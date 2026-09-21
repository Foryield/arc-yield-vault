// Moves USDC from Base Sepolia to Arc testnet with Circle's CCTP v2 (Fast Transfer).
//
//   1. Base Sepolia: approve TokenMessengerV2 for the exact amount.
//   2. Base Sepolia: depositForBurn to Arc (CCTP domain 26); the USDC is burned.
//   3. Circle's attestation service (Iris, sandbox) signs the burn message.
//   4. Arc testnet: MessageTransmitterV2.receiveMessage mints native USDC to the recipient.
//
// Signing goes through Foundry's `cast` and an encrypted keystore: no private key ever reaches
// this process or its environment. Amounts are bigint base units (USDC has 6 decimals).
//
// Usage (Node 24+, no dependency):
//   SENDER=0x… [RECIPIENT=0x…] [AMOUNT=1000000] [ACCOUNT=arc-depositor] \
//     node scripts/cctp/base-sepolia-to-arc.ts

import { execFileSync } from "node:child_process";

const BASE_SEPOLIA = { chainId: 84532n, domain: 6, rpc: "https://sepolia.base.org" };
const ARC_TESTNET = { chainId: 5042002n, domain: 26, rpc: "https://rpc.testnet.arc.io" };
// CCTP v2 contracts share their addresses across both testnets (deterministic deployment).
const TOKEN_MESSENGER_V2 = "0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA";
const MESSAGE_TRANSMITTER_V2 = "0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275";
const USDC_BASE_SEPOLIA = "0x036CbD53842c5426634e7929541eC2318f3dCF7e";
const USDC_ARC = "0x3600000000000000000000000000000000000000";
const IRIS = "https://iris-api-sandbox.circle.com";
const FAST_FINALITY = 1000; // Fast Transfer; 2000 would wait for Base finality at no fee.
const POLL_INTERVAL_MS = 5_000;
const POLL_TIMEOUT_MS = 30 * 60_000;

const ADDRESS = /^0x[0-9a-fA-F]{40}$/;

function requireAddress(name: string, value: string | undefined): string {
  if (!value || !ADDRESS.test(value)) throw new Error(`${name} must be a 0x-prefixed address`);
  return value;
}

const sender = requireAddress("SENDER", process.env.SENDER);
const recipient = requireAddress("RECIPIENT", process.env.RECIPIENT ?? sender);
const account = process.env.ACCOUNT ?? "arc-depositor";
const amount = BigInt(process.env.AMOUNT ?? "1000000");
if (amount <= 0n) throw new Error("AMOUNT must be positive");

function cast(args: string[]): string {
  // stdin and stderr stay on the terminal so cast can prompt for the keystore password.
  return execFileSync("cast", args, { stdio: ["inherit", "pipe", "inherit"], encoding: "utf8" }).trim();
}

function read(rpc: string, to: string, signature: string, ...args: string[]): bigint {
  return BigInt(cast(["call", to, signature, ...args, "--rpc-url", rpc]).split(" ")[0]);
}

function send(rpc: string, to: string, signature: string, ...args: string[]): string {
  const receipt = JSON.parse(
    cast(["send", to, signature, ...args, "--rpc-url", rpc, "--account", account, "--json"]),
  );
  if (receipt.status !== "0x1") throw new Error(`transaction ${receipt.transactionHash} reverted`);
  return receipt.transactionHash;
}

function toBytes32(address: string): string {
  return `0x${address.slice(2).toLowerCase().padStart(64, "0")}`;
}

function formatUsdc(units: bigint): string {
  const sign = units < 0n ? "-" : "";
  const abs = units < 0n ? -units : units;
  return `${sign}${abs / 1_000_000n}.${(abs % 1_000_000n).toString().padStart(6, "0")} USDC`;
}

async function fastTransferMaxFee(): Promise<bigint> {
  const response = await fetch(
    `${IRIS}/v2/burn/USDC/fees/${BASE_SEPOLIA.domain}/${ARC_TESTNET.domain}`,
  );
  if (!response.ok) throw new Error(`fee lookup failed: HTTP ${response.status}`);
  const tiers: { finalityThreshold: number; minimumFee: number }[] = await response.json();
  const fast = tiers.find((tier) => tier.finalityThreshold === FAST_FINALITY);
  if (!fast) throw new Error("no Fast Transfer fee tier for Base Sepolia to Arc");
  // minimumFee is in basis points (e.g. 1.3). Scale to hundredths of a basis point to stay in
  // integers, then round the fee up so the burn is never rejected for an underpaid fee.
  const hundredthsOfBps = BigInt(Math.round(fast.minimumFee * 100));
  return (amount * hundredthsOfBps + 999_999n) / 1_000_000n;
}

async function waitForAttestation(burnHash: string): Promise<{ message: string; attestation: string }> {
  const url = `${IRIS}/v2/messages/${BASE_SEPOLIA.domain}?transactionHash=${burnHash}`;
  const deadline = Date.now() + POLL_TIMEOUT_MS;
  while (Date.now() < deadline) {
    const response = await fetch(url);
    if (response.ok) {
      const body: { messages?: { status: string; message: string; attestation: string }[] } =
        await response.json();
      const entry = body.messages?.[0];
      if (entry?.status === "complete") return { message: entry.message, attestation: entry.attestation };
    } else if (response.status !== 404) {
      throw new Error(`attestation lookup failed: HTTP ${response.status}`);
    }
    await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL_MS));
  }
  throw new Error(`no attestation for ${burnHash} after ${POLL_TIMEOUT_MS / 60_000} minutes`);
}

async function main(): Promise<void> {
  for (const chain of [BASE_SEPOLIA, ARC_TESTNET]) {
    const chainId = BigInt(cast(["chain-id", "--rpc-url", chain.rpc]));
    if (chainId !== chain.chainId) throw new Error(`${chain.rpc} is chain ${chainId}, not ${chain.chainId}`);
  }

  const balance = read(BASE_SEPOLIA.rpc, USDC_BASE_SEPOLIA, "balanceOf(address)(uint256)", sender);
  if (balance < amount) throw new Error(`sender holds ${formatUsdc(balance)} on Base Sepolia`);
  const maxFee = await fastTransferMaxFee();
  const arcBefore = read(ARC_TESTNET.rpc, USDC_ARC, "balanceOf(address)(uint256)", recipient);
  console.log(`Burning ${formatUsdc(amount)} on Base Sepolia, max fee ${formatUsdc(maxFee)}`);

  const started = Date.now();
  const approveHash = send(
    BASE_SEPOLIA.rpc, USDC_BASE_SEPOLIA, "approve(address,uint256)", TOKEN_MESSENGER_V2, amount.toString(),
  );
  const burnHash = send(
    BASE_SEPOLIA.rpc,
    TOKEN_MESSENGER_V2,
    "depositForBurn(uint256,uint32,bytes32,address,bytes32,uint256,uint32)",
    amount.toString(),
    String(ARC_TESTNET.domain),
    toBytes32(recipient),
    USDC_BASE_SEPOLIA,
    toBytes32("0x0000000000000000000000000000000000000000"), // any caller may relay the mint
    maxFee.toString(),
    String(FAST_FINALITY),
  );
  const allowanceLeft = read(
    BASE_SEPOLIA.rpc, USDC_BASE_SEPOLIA, "allowance(address,address)(uint256)", sender, TOKEN_MESSENGER_V2,
  );
  console.log(`Burned: ${burnHash}. Waiting for Circle's attestation…`);

  const { message, attestation } = await waitForAttestation(burnHash);
  const mintHash = send(ARC_TESTNET.rpc, MESSAGE_TRANSMITTER_V2, "receiveMessage(bytes,bytes)", message, attestation);
  const arcAfter = read(ARC_TESTNET.rpc, USDC_ARC, "balanceOf(address)(uint256)", recipient);

  // The recipient pays the mint's gas in USDC when it also relays it, so the net change
  // understates the minted amount by that gas; the Mint event on Arc carries the exact figure.
  console.log(JSON.stringify({
    route: "Base Sepolia (domain 6) -> Arc testnet (domain 26)",
    amount: formatUsdc(amount),
    maxFee: formatUsdc(maxFee),
    approveTx: approveHash,
    burnTx: burnHash,
    mintTx: mintHash,
    allowanceLeftAfterBurn: allowanceLeft.toString(),
    recipient,
    arcBalanceChange: formatUsdc(arcAfter - arcBefore),
    elapsedSeconds: Math.round((Date.now() - started) / 1000),
  }, null, 2));
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
