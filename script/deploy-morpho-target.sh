#!/usr/bin/env bash
# Deploys a Morpho Vault V2 on Arc testnet, to serve as the allocation target of MorphoYieldVault.
#
# Morpho is not deployed on Arc testnet (checked 2026-09-21), so the Vault V2 contract is deployed
# here from morpho-org/vault-v2 at a pinned commit. That code is GPL-2.0-or-later: it is cloned,
# compiled and deployed from its own repository, never vendored nor imported by this repository's
# MIT sources. The instance has no adapter, so deposits stay idle inside it and earn nothing: it is
# real Morpho code, not a curated Morpho vault.
#
# Usage: ASSET=<token address> [ACCOUNT=arc-admin] script/deploy-morpho-target.sh
set -euo pipefail

VAULT_V2_COMMIT=a0ba9df0ea697a080c0de69c18b84738cfb3bef7
ARC_TESTNET_CHAIN_ID=5042002
RPC_URL="${ARC_TESTNET_RPC_URL:-https://rpc.testnet.arc.io}"
EXPLORER_API="https://explorer.testnet.arc.io/api/"
ACCOUNT="${ACCOUNT:-arc-admin}"
: "${ASSET:?ASSET (the token held by the Morpho vault) is required}"

chain_id="$(cast chain-id --rpc-url "$RPC_URL")"
if [[ "$chain_id" != "$ARC_TESTNET_CHAIN_ID" ]]; then
  echo "Refusing to deploy: chain id $chain_id is not Arc testnet ($ARC_TESTNET_CHAIN_ID)." >&2
  exit 1
fi

owner="$(cast wallet address --account "$ACCOUNT")"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

git clone --quiet https://github.com/morpho-org/vault-v2.git "$workdir/vault-v2"
git -C "$workdir/vault-v2" checkout --quiet "$VAULT_V2_COMMIT"
git -C "$workdir/vault-v2" submodule update --init --recursive --quiet

forge create --root "$workdir/vault-v2" src/VaultV2.sol:VaultV2 \
  --rpc-url "$RPC_URL" --account "$ACCOUNT" --broadcast \
  --verify --verifier blockscout --verifier-url "$EXPLORER_API" \
  --constructor-args "$owner" "$ASSET"
