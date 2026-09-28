// Moves USDC from Base to Arc with Circle's CCTP v2 (Fast Transfer): Base Sepolia to Arc testnet
// by default, Base to Arc mainnet with NETWORK=mainnet.
//
//   1. Base: approve TokenMessengerV2 for the exact amount.
//   2. Base: depositForBurn to Arc (CCTP domain 26); the USDC is burned.
//   3. Circle's attestation service (Iris) signs the burn message.
//   4. Arc: MessageTransmitterV2.receiveMessage mints native USDC to the recipient.
//
// Signing goes through Foundry's `cast` and an encrypted keystore: no private key ever reaches
// this process or its environment. Amounts are bigint base units (USDC has 6 decimals).
//
// Usage (Node 24+, no dependency):
//   SENDER=0x… [RECIPIENT=0x…] [AMOUNT=1000000] [ACCOUNT=arc-depositor] \
//     node scripts/cctp/base-sepolia-to-arc.ts
//
// On mainnet nothing has a default: RECIPIENT, AMOUNT and ACCOUNT are required, addresses must be
// EIP-55 checksummed, SENDER must be the keystore's own address, the relaying key must already
// hold USDC for gas on Arc, and the transfer waits for the operator to type the last four
// characters of the recipient:
//   NETWORK=mainnet SENDER=0x… RECIPIENT=0x… AMOUNT=5000000 ACCOUNT=<keystore> \
//     node scripts/cctp/base-sepolia-to-arc.ts
//
// The same keystore signs the burn on Base and relays the mint on Arc: on Arc it needs a little
// USDC for gas, since the recipient may be a custody wallet that cannot sign through cast.
//
// Resuming after an interruption (e.g. an attestation outage): a burn stays mintable once
// Circle attests it, so pass its hash to skip straight to steps 3 and 4:
//   SENDER=0x… BURN_TX=0x… node scripts/cctp/base-sepolia-to-arc.ts
// Every transaction hash is printed as soon as it is sent. Before re-running after an error, look
// for a depositForBurn from the sender on the Base explorer: if one exists, resume with BURN_TX
// instead of burning twice.

import { execFileSync } from "node:child_process";
import { createInterface } from "node:readline/promises";

// CCTP v2 contracts share their addresses across the chains of one network (deterministic
// deployment). Mainnet addresses checked on chain on 2026-09-23 (localDomain 6 on Base, 26 on Arc).
const NETWORKS = {
  testnet: {
    base: { name: "Base Sepolia", chainId: 84532n, domain: 6, rpc: "https://sepolia.base.org" },
    arc: { name: "Arc testnet", chainId: 5042002n, domain: 26, rpc: "https://rpc.testnet.arc.io" },
    tokenMessenger: "0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA",
    messageTransmitter: "0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275",
    usdcBase: "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
    iris: "https://iris-api-sandbox.circle.com",
  },
  mainnet: {
    base: { name: "Base", chainId: 8453n, domain: 6, rpc: "https://mainnet.base.org" },
    arc: { name: "Arc mainnet", chainId: 5042n, domain: 26, rpc: "https://rpc.mainnet.arc.io" },
    tokenMessenger: "0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d",
    messageTransmitter: "0x81D40F21F12A8F0E3252Bccb954D722d4c464B64",
    usdcBase: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
    iris: "https://iris-api.circle.com",
  },
} as const;
const networkName = process.env.NETWORK ?? "testnet";
if (networkName !== "testnet" && networkName !== "mainnet") {
  throw new Error("NETWORK must be testnet or mainnet");
}
const NETWORK = NETWORKS[networkName];
const BASE = NETWORK.base;
const ARC = NETWORK.arc;
const TOKEN_MESSENGER_V2 = NETWORK.tokenMessenger;
const MESSAGE_TRANSMITTER_V2 = NETWORK.messageTransmitter;
const USDC_BASE = NETWORK.usdcBase;
const USDC_ARC = "0x3600000000000000000000000000000000000000";
const IRIS = NETWORK.iris;
const FAST_FINALITY = 1000; // Fast Transfer; 2000 would wait for Base finality at no fee.
const POLL_INTERVAL_MS = 5_000;
const POLL_TIMEOUT_MS = 30 * 60_000;
const HTTP_TIMEOUT_MS = 15_000;
// Hard cap on the Fast Transfer fee, whatever the fee API answers: 10 basis points.
const MAX_FEE_BPS = 10n;
const MAINNET = networkName === "mainnet";

const ADDRESS = /^0x[0-9a-fA-F]{40}$/;

function requireAddress(name: string, value: string | undefined): string {
  if (!value || !ADDRESS.test(value)) throw new Error(`${name} must be a 0x-prefixed address`);
  return value;
}

function requireOnMainnet(name: string): string | undefined {
  const value = process.env[name];
  if (MAINNET && !value) throw new Error(`${name} is required on mainnet: no default applies`);
  return value;
}

const sender = requireAddress("SENDER", process.env.SENDER);
const recipient = requireAddress("RECIPIENT", requireOnMainnet("RECIPIENT") ?? sender);
const account = requireOnMainnet("ACCOUNT") ?? "arc-depositor";
const amountInput = requireOnMainnet("AMOUNT") ?? "1000000";
if (!/^[0-9]+$/.test(amountInput)) throw new Error("AMOUNT must be an integer in USDC base units (6 decimals)");
const amount = BigInt(amountInput);
if (amount <= 0n) throw new Error("AMOUNT must be positive");
const resumeBurnTx = process.env.BURN_TX;
if (resumeBurnTx !== undefined && !/^0x[0-9a-fA-F]{64}$/.test(resumeBurnTx)) {
  throw new Error("BURN_TX must be a 0x-prefixed transaction hash");
}

function cast(args: string[]): string {
  // stdin and stderr stay on the terminal so cast can prompt for the keystore password.
  // CAST_ASYNC from the environment would make `cast receipt` give up on a pending transaction.
  const env = { ...process.env };
  delete env.CAST_ASYNC;
  return execFileSync("cast", args, { stdio: ["inherit", "pipe", "inherit"], encoding: "utf8", env }).trim();
}

function read(rpc: string, to: string, signature: string, ...args: string[]): bigint {
  return BigInt(cast(["call", to, signature, ...args, "--rpc-url", rpc]).split(" ")[0]);
}

function send(rpc: string, to: string, signature: string, ...args: string[]): string {
  // --async returns the hash as soon as the transaction is sent: it is printed before waiting,
  // so a receipt timeout never hides a burn that went through.
  const hash = cast(["send", to, signature, ...args, "--rpc-url", rpc, "--account", account, "--async"]);
  console.log(`Sent ${signature.split("(")[0]}: ${hash}`);
  const receipt = JSON.parse(cast(["receipt", hash, "--rpc-url", rpc, "--json"]));
  if (receipt.status !== "0x1") throw new Error(`transaction ${hash} reverted`);
  return hash;
}

function checksummed(name: string, address: string): void {
  if (cast(["to-check-sum-address", address]) !== address) {
    throw new Error(`${name} must be written with its EIP-55 checksum`);
  }
}

// Mainnet only: the checks that stand between a typo and USDC minted to nobody.
async function confirmMainnet(): Promise<void> {
  checksummed("SENDER", sender);
  checksummed("RECIPIENT", recipient);
  const signer = cast(["wallet", "address", "--account", account]);
  if (signer.toLowerCase() !== sender.toLowerCase()) {
    throw new Error(`SENDER ${sender} is not the address of keystore ${account} (${signer})`);
  }
  if (BigInt(cast(["balance", sender, "--rpc-url", ARC.rpc])) === 0n) {
    throw new Error(`${sender} holds no USDC on ${ARC.name} to pay for relaying the mint`);
  }
  console.log(`Network:   ${BASE.name} -> ${ARC.name}`);
  console.log(`Amount:    ${formatUsdc(amount)}`);
  console.log(`Recipient: ${recipient}`);
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  const typed = await rl.question("Type the last 4 characters of the recipient to proceed: ");
  rl.close();
  if (typed.trim().toLowerCase() !== recipient.slice(-4).toLowerCase()) {
    throw new Error("confirmation did not match the recipient: nothing was sent");
  }
}

async function fetchWithTimeout(url: string): Promise<Response> {
  return fetch(url, { signal: AbortSignal.timeout(HTTP_TIMEOUT_MS) });
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
  const response = await fetchWithTimeout(
    `${IRIS}/v2/burn/USDC/fees/${BASE.domain}/${ARC.domain}`,
  );
  if (!response.ok) throw new Error(`fee lookup failed: HTTP ${response.status}`);
  const tiers: { finalityThreshold: number; minimumFee: number }[] = await response.json();
  const fast = tiers.find((tier) => tier.finalityThreshold === FAST_FINALITY);
  if (!fast) throw new Error(`no Fast Transfer fee tier for ${BASE.name} to ${ARC.name}`);
  // minimumFee is in basis points (e.g. 1.3). Scale to hundredths of a basis point to stay in
  // integers, then round the fee up so the burn is never rejected for an underpaid fee.
  // Round to 1e-4 bps first, so that float noise (1.1 * 100 = 110.00000000000001) is not rounded up.
  const hundredthsOfBps = BigInt(Math.ceil(Math.round(fast.minimumFee * 10_000) / 100));
  const fee = (amount * hundredthsOfBps + 999_999n) / 1_000_000n;
  const cap = (amount * MAX_FEE_BPS) / 10_000n;
  if (fee > cap) throw new Error(`fee ${formatUsdc(fee)} exceeds the ${MAX_FEE_BPS} bps cap`);
  return fee;
}

async function waitForAttestation(burnHash: string): Promise<{ message: string; attestation: string }> {
  const url = `${IRIS}/v2/messages/${BASE.domain}?transactionHash=${burnHash}`;
  const deadline = Date.now() + POLL_TIMEOUT_MS;
  while (Date.now() < deadline) {
    const response = await fetchWithTimeout(url).catch(() => undefined);
    if (response === undefined || response.status === 429 || response.status >= 500) {
      // Transient: the burn stays attestable, keep polling until the deadline.
    } else if (response.ok) {
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
  for (const chain of [BASE, ARC]) {
    const chainId = BigInt(cast(["chain-id", "--rpc-url", chain.rpc]));
    if (chainId !== chain.chainId) throw new Error(`${chain.rpc} is chain ${chainId}, not ${chain.chainId}`);
  }
  if (MAINNET) await confirmMainnet();

  const arcBefore = read(ARC.rpc, USDC_ARC, "balanceOf(address)(uint256)", recipient);
  if (!resumeBurnTx) console.log(`Base nonce of ${sender}: ${cast(["nonce", sender, "--rpc-url", BASE.rpc])}`);
  const started = Date.now();
  const burn = resumeBurnTx ? { burnHash: resumeBurnTx } : await approveAndBurn();
  console.log(`Burned: ${burn.burnHash}. Waiting for Circle's attestation…`);

  const { message, attestation } = await waitForAttestation(burn.burnHash);
  const mintHash = send(ARC.rpc, MESSAGE_TRANSMITTER_V2, "receiveMessage(bytes,bytes)", message, attestation);
  const arcAfter = read(ARC.rpc, USDC_ARC, "balanceOf(address)(uint256)", recipient);

  // The recipient pays the mint's gas in USDC when it also relays it, so the net change
  // understates the minted amount by that gas; the Mint event on Arc carries the exact figure.
  console.log(JSON.stringify({
    route: `${BASE.name} (domain ${BASE.domain}) -> ${ARC.name} (domain ${ARC.domain})`,
    ...burn,
    mintTx: mintHash,
    recipient,
    arcBalanceChange: formatUsdc(arcAfter - arcBefore),
    elapsedSeconds: Math.round((Date.now() - started) / 1000),
  }, null, 2));
}

async function approveAndBurn() {
  const balance = read(BASE.rpc, USDC_BASE, "balanceOf(address)(uint256)", sender);
  if (balance < amount) throw new Error(`sender holds ${formatUsdc(balance)} on ${BASE.name}`);
  const maxFee = await fastTransferMaxFee();
  console.log(`Burning ${formatUsdc(amount)} on ${BASE.name}, max fee ${formatUsdc(maxFee)}`);

  const approveHash = send(
    BASE.rpc, USDC_BASE, "approve(address,uint256)", TOKEN_MESSENGER_V2, amount.toString(),
  );
  const burnHash = send(
    BASE.rpc,
    TOKEN_MESSENGER_V2,
    "depositForBurn(uint256,uint32,bytes32,address,bytes32,uint256,uint32)",
    amount.toString(),
    String(ARC.domain),
    toBytes32(recipient),
    USDC_BASE,
    toBytes32("0x0000000000000000000000000000000000000000"), // any caller may relay the mint
    maxFee.toString(),
    String(FAST_FINALITY),
  );
  const allowanceLeft = read(
    BASE.rpc, USDC_BASE, "allowance(address,address)(uint256)", sender, TOKEN_MESSENGER_V2,
  );
  return {
    amount: formatUsdc(amount),
    maxFee: formatUsdc(maxFee),
    approveTx: approveHash,
    burnHash,
    allowanceLeftAfterBurn: allowanceLeft.toString(),
  };
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
