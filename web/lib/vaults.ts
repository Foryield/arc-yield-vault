// Vault instances served by the page, one per Circle stablecoin. The choice lives in the UI
// and in the URL (`?vault=eurc`), so a link opens the instance to show.
//
// Asset addresses are network constants. Vault addresses change with each redeployment, so
// the environment can override them; the defaults are the instances recorded in
// docs/evidence/a1-vault-testnet.md.

import type { Address } from "viem";

export type VaultKey = "usdc" | "eurc";

export type VaultConfig = {
  key: VaultKey;
  tab: string;
  address: Address;
  asset: { symbol: string; address: Address; decimals: number };
  morphoTarget: Address;
  subtitle: string;
  /// USDC is also Arc's gas token: part of the balance must stay aside to pay fees.
  paysGas: boolean;
};

const ADDRESS = /^0x[0-9a-fA-F]{40}$/;

function fromEnv(value: string | undefined, fallback: Address): Address {
  return value && ADDRESS.test(value) ? (value as Address) : fallback;
}

export const VAULTS: VaultConfig[] = [
  {
    key: "usdc",
    tab: "USDC",
    address: fromEnv(
      process.env.NEXT_PUBLIC_USDC_VAULT,
      "0xBbc099E29069e71C1A52C2e9d74328096Fc4e4a7",
    ),
    asset: { symbol: "USDC", address: "0x3600000000000000000000000000000000000000", decimals: 6 },
    morphoTarget: "0x76b022B083F00e094feB1DFf5a89E60cF1c52e27",
    subtitle:
      "Deposit USDC into the ForYield vault. Every deposit is supplied to a Morpho Vault V2 in the same transaction, on Arc, Circle's stablecoin-native chain.",
    paysGas: true,
  },
  {
    key: "eurc",
    tab: "EURC",
    address: fromEnv(
      process.env.NEXT_PUBLIC_EURC_VAULT,
      "0x623B4e264CB217763dDD71a1ec597c0926Cb902c",
    ),
    asset: { symbol: "EURC", address: "0x89B50855Aa3bE2F677cD6303Cec089B5F319D72a", decimals: 6 },
    morphoTarget: "0x046CE778D030B0Bb348dd8fDa4751B2281081AE4",
    subtitle:
      "Deposit EURC, Circle's euro stablecoin, into the same vault contract. It is supplied to a Morpho Vault V2 in the same transaction; fees are still paid in USDC.",
    paysGas: false,
  },
];

export const DEFAULT_VAULT = VAULTS[0];

/// Unknown keys fall back to the default rather than to an empty page.
export function vaultFromKey(key: string | null): VaultConfig {
  return VAULTS.find((v) => v.key === key?.toLowerCase()) ?? DEFAULT_VAULT;
}
