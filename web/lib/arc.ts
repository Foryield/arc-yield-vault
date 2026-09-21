// Arc testnet access: network definition, on-chain reads, and the two write flows (deposit,
// redemption) signed by the visitor's browser wallet. Amounts are bigint base units end to end;
// conversions go through viem's parseUnits / formatUnits only.

import {
  BaseError,
  ContractFunctionRevertedError,
  UserRejectedRequestError,
  createPublicClient,
  createWalletClient,
  custom,
  defineChain,
  http,
  parseAbi,
  type Address,
  type EIP1193Provider,
  type Hash,
} from "viem";
import type { VaultConfig } from "./vaults";

const RPC_URL = process.env.NEXT_PUBLIC_ARC_RPC_URL || "https://rpc.testnet.arc.io";
const EXPLORER = "https://explorer.testnet.arc.io";

export const arcTestnet = defineChain({
  id: 5042002,
  name: "Arc Testnet",
  // USDC is Arc's native gas token; the native balance uses 18 decimals.
  nativeCurrency: { name: "USDC", symbol: "USDC", decimals: 18 },
  rpcUrls: { default: { http: [RPC_URL] } },
  blockExplorers: { default: { name: "Arc Testnet Explorer", url: EXPLORER } },
  testnet: true,
});

export const NETWORK_LABEL = "Arc Testnet";
export const FAUCET_URL = "https://faucet.circle.com/";
export const explorerTx = (hash: Hash) => `${EXPLORER}/tx/${hash}`;
export const explorerAddress = (address: Address) => `${EXPLORER}/address/${address}`;

/// Kept aside from a USDC balance so the visitor can still pay the fees of the next steps.
export const USDC_GAS_RESERVE = 50_000n; // 0.05 USDC in 6-decimal units

const erc20Abi = parseAbi([
  "function balanceOf(address) view returns (uint256)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function approve(address spender, uint256 value) returns (bool)",
]);

const vaultAbi = parseAbi([
  "function balanceOf(address) view returns (uint256)",
  "function convertToAssets(uint256 shares) view returns (uint256)",
  "function totalAssets() view returns (uint256)",
  "function paused() view returns (bool)",
  "function deposit(uint256 assets, address receiver) returns (uint256)",
  "function withdraw(uint256 assets, address receiver, address owner) returns (uint256)",
  "function redeem(uint256 shares, address receiver, address owner) returns (uint256)",
  "error ERC4626ExceededMaxDeposit(address receiver, uint256 assets, uint256 max)",
  "error ERC4626ExceededMaxWithdraw(address owner, uint256 assets, uint256 max)",
  "error ERC4626ExceededMaxRedeem(address owner, uint256 shares, uint256 max)",
  "error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed)",
  "error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed)",
  "error AllowanceNotConsumed(uint256 remaining)",
  "error ShortWithdrawal(uint256 requested, uint256 received)",
]);

export const publicClient = createPublicClient({ chain: arcTestnet, transport: http(RPC_URL) });

declare global {
  interface Window {
    ethereum?: EIP1193Provider;
  }
}

function provider(): EIP1193Provider {
  if (!window.ethereum) throw new Error("No browser wallet found. Install MetaMask to continue.");
  return window.ethereum;
}

function walletClient(account: Address) {
  return createWalletClient({ account, chain: arcTestnet, transport: custom(provider()) });
}

/// Puts the wallet on Arc testnet, adding the network first if the wallet does not know it.
async function ensureArcTestnet(): Promise<void> {
  const chainId = `0x${arcTestnet.id.toString(16)}` as const;
  try {
    await provider().request({ method: "wallet_switchEthereumChain", params: [{ chainId }] });
  } catch (error) {
    if ((error as { code?: number }).code !== 4902) throw error;
    await provider().request({
      method: "wallet_addEthereumChain",
      params: [
        {
          chainId,
          chainName: arcTestnet.name,
          nativeCurrency: arcTestnet.nativeCurrency,
          rpcUrls: [RPC_URL],
          blockExplorerUrls: [EXPLORER],
        },
      ],
    });
  }
}

export async function connectWallet(): Promise<Address> {
  const [account] = await provider().request({ method: "eth_requestAccounts" });
  if (!account) throw new Error("The wallet returned no account.");
  await ensureArcTestnet();
  return account;
}

/// Silent: returns the already-authorised account, if any, without prompting.
export async function reconnectWallet(): Promise<Address | null> {
  if (!window.ethereum) return null;
  const [account] = await window.ethereum.request({ method: "eth_accounts" });
  return account ?? null;
}

export type VaultState = {
  walletBalance: bigint;
  shares: bigint;
  position: bigint;
  totalAssets: bigint;
  inMorpho: bigint;
  paused: boolean;
};

export async function readVault(vault: VaultConfig, account: Address | null): Promise<VaultState> {
  const asset = { address: vault.asset.address, abi: erc20Abi } as const;
  const self = { address: vault.address, abi: vaultAbi } as const;
  const [totalAssets, idle, paused, walletBalance, shares] = await Promise.all([
    publicClient.readContract({ ...self, functionName: "totalAssets" }),
    publicClient.readContract({ ...asset, functionName: "balanceOf", args: [vault.address] }),
    publicClient.readContract({ ...self, functionName: "paused" }),
    account
      ? publicClient.readContract({ ...asset, functionName: "balanceOf", args: [account] })
      : Promise.resolve(0n),
    account
      ? publicClient.readContract({ ...self, functionName: "balanceOf", args: [account] })
      : Promise.resolve(0n),
  ]);
  const position =
    shares === 0n
      ? 0n
      : await publicClient.readContract({ ...self, functionName: "convertToAssets", args: [shares] });
  return { walletBalance, shares, position, totalAssets, inMorpho: totalAssets - idle, paused };
}

async function confirmed(hash: Hash): Promise<Hash> {
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  if (receipt.status !== "success") throw new Error(`Transaction ${hash} reverted.`);
  return hash;
}

/// Approves the vault for exactly `assets` (skipped if an allowance already covers it), then
/// deposits. Two signatures at most; `onStep` reports progress to the page.
export async function deposit(
  vault: VaultConfig,
  account: Address,
  assets: bigint,
  onStep: (step: "approve" | "deposit") => void,
): Promise<Hash> {
  await ensureArcTestnet();
  const wallet = walletClient(account);
  const allowance = await publicClient.readContract({
    address: vault.asset.address,
    abi: erc20Abi,
    functionName: "allowance",
    args: [account, vault.address],
  });
  if (allowance < assets) {
    onStep("approve");
    const { request } = await publicClient.simulateContract({
      account,
      address: vault.asset.address,
      abi: erc20Abi,
      functionName: "approve",
      args: [vault.address, assets],
    });
    await confirmed(await wallet.writeContract(request));
  }
  onStep("deposit");
  const { request } = await publicClient.simulateContract({
    account,
    address: vault.address,
    abi: vaultAbi,
    functionName: "deposit",
    args: [assets, account],
  });
  return confirmed(await wallet.writeContract(request));
}

/// Withdraws an exact amount of the asset, or redeems every share when `all` is set, so a full
/// exit never leaves dust shares behind.
export async function exit(
  vault: VaultConfig,
  account: Address,
  request: { all: true; shares: bigint } | { all: false; assets: bigint },
): Promise<Hash> {
  await ensureArcTestnet();
  const wallet = walletClient(account);
  if (request.all) {
    const { request: tx } = await publicClient.simulateContract({
      account,
      address: vault.address,
      abi: vaultAbi,
      functionName: "redeem",
      args: [request.shares, account, account],
    });
    return confirmed(await wallet.writeContract(tx));
  }
  const { request: tx } = await publicClient.simulateContract({
    account,
    address: vault.address,
    abi: vaultAbi,
    functionName: "withdraw",
    args: [request.assets, account, account],
  });
  return confirmed(await wallet.writeContract(tx));
}

export function friendlyError(error: unknown): string {
  if (error instanceof BaseError) {
    if (error.walk((e) => e instanceof UserRejectedRequestError)) {
      return "Request rejected in the wallet.";
    }
    const revert = error.walk((e) => e instanceof ContractFunctionRevertedError);
    if (revert instanceof ContractFunctionRevertedError) {
      const name = revert.data?.errorName;
      if (name?.startsWith("ERC4626ExceededMax")) return "The vault is paused or the amount exceeds your position.";
      if (name === "ERC20InsufficientBalance") return "Balance too low for this amount.";
      if (revert.reason) return `The transaction would fail: ${revert.reason}.`;
      if (name) return `The transaction would fail: ${name}.`;
    }
    return error.shortMessage;
  }
  if ((error as { code?: number })?.code === 4001) return "Request rejected in the wallet.";
  return error instanceof Error ? error.message : "Unexpected error.";
}
