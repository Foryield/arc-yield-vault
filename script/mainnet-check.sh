#!/usr/bin/env bash
# Read-only checks of the Arc mainnet deployment. Only `cast` reads: nothing is signed or sent.
# Prints key=value lines for the evidence log and exits non-zero on the first mismatch.
#
#   PHASE=preflight    OWNER=… GUARDIAN=… RECOVERY=… DEPLOYER=…      script/mainnet-check.sh
#   PHASE=post-deploy  OWNER=… GUARDIAN=… RECOVERY=… USDC_VAULT=… EURC_VAULT=… script/mainnet-check.sh
#   PHASE=post-deposit OWNER=… USDC_VAULT=… AMOUNT=100000000          script/mainnet-check.sh
#   PHASE=post-redeem  OWNER=… USDC_VAULT=…                           script/mainnet-check.sh
#
# ARC_RPC_URL defaults to the public mainnet RPC; point it at a local arc-anvil fork to rehearse.
# EXPECTED_CODE_KECCAK_USDC / _EURC (post-deploy): the rehearsal's code fingerprints, compared if set.
# SKIP_LIQUIDITY=1 (preflight): proceed when Morpho's API is down; recorded in the output.
#
# Every on-chain read is assigned to a variable before use, so that `set -e` stops the script
# when a read fails instead of logging an empty value. Values above 2^63 (wei balances, target
# totals) are only printed or compared as strings, never in shell arithmetic.
set -euo pipefail

RPC="${ARC_RPC_URL:-https://rpc.mainnet.arc.io}"
PHASE="${PHASE:?PHASE must be preflight, post-deploy, post-deposit or post-redeem}"
USDC=0x3600000000000000000000000000000000000000
EURC=0xbEf5f6d51CB62b58e6A8f77868681825C6fe21c1
GALAXY_USDC=0x8E357432CC12ff425c36432F312968aEb16112AF
GALAXY_EURC=0x389abDf4355e0cF4f19298179991705a98f21c18
MAX_UINT=115792089237316195423570985008687907853269984665640564039457584007913129639935
MIN_LIQUIDITY_USD=1000000

fail() { echo "NO-GO: $*" >&2; exit 1; }
out() { echo "$1=$2"; }
# cast prints large numbers as "100000000000000 [1e14]": keep the first field only.
call() { cast call "$@" --rpc-url "$RPC" | awk '{print $1}'; }
lower() { tr '[:upper:]' '[:lower:]' <<<"$1"; }
expect() { # name actual expected
  out "$1" "$2"
  [[ "$(lower "$2")" == "$(lower "$3")" ]] || fail "$1 is $2, expected $3"
}
selector() { cast sig "$1"; }

chain=$(cast chain-id --rpc-url "$RPC")
expect chain_id "$chain" 5042
block=$(cast block-number --rpc-url "$RPC")
out block "$block"
out checked_at_utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

read_into() { # var args...: a failed read stops the script (set -e applies to assignments).
  # printf -v rather than a nameref: macOS ships bash 3.2.
  local read_value
  read_value=$(call "${@:2}")
  [[ -n "$read_value" ]] || fail "empty read: ${*:2}"
  printf -v "$1" '%s' "$read_value"
}

target_state() { # label target asset
  local label=$1 target=$2 asset=$3 v sel
  read_into v "$target" 'asset()(address)'; expect "${label}_asset" "$v" "$asset"
  for gate in receiveSharesGate sendSharesGate receiveAssetsGate sendAssetsGate; do
    read_into v "$target" "${gate}()(address)"
    expect "${label}_${gate}" "$v" 0x0000000000000000000000000000000000000000
  done
  for setter in setReceiveSharesGate setSendSharesGate setReceiveAssetsGate; do
    sel=$(selector "${setter}(address)")
    read_into v "$target" 'abdicated(bytes4)(bool)' "$sel"
    expect "${label}_abdicated_${setter}" "$v" true
  done
  read_into v "$target" 'totalAssets()(uint256)'; out "${label}_total_assets" "$v"
  read_into v "$target" 'performanceFee()(uint96)'; out "${label}_performance_fee" "$v"
  read_into v "$target" 'managementFee()(uint96)'; out "${label}_management_fee" "$v"
}

morpho_liquidity() { # label target: liquidity and APY from Morpho's public API
  local label=$1 target=$2 body
  body=$(curl -sf https://blue-api.morpho.org/graphql -H 'content-type: application/json' -d \
    '{"query":"{ vaultV2s(where:{chainId_in:[5042]}) { items { address liquidityUsd netApy } } }"}') \
    || body=""
  local item="" liquidity=""
  [[ -z "$body" ]] || item=$(jq -c --arg a "$(lower "$target")" \
    '.data.vaultV2s.items[]? | select((.address | ascii_downcase) == $a)' <<<"$body")
  [[ -z "$item" ]] || liquidity=$(jq -r '.liquidityUsd | floor' <<<"$item")
  if [[ ! "$liquidity" =~ ^[0-9]+$ ]]; then
    out "${label}_liquidity_usd" unavailable
    [[ "${SKIP_LIQUIDITY:-}" == 1 ]] || fail "Morpho API unavailable: check liquidity by hand, then rerun with SKIP_LIQUIDITY=1"
    out "${label}_liquidity_check" "skipped by operator"
    return
  fi
  out "${label}_liquidity_usd" "$liquidity"
  out "${label}_net_apy" "$(jq -r '.netApy' <<<"$item")"
  ((liquidity >= MIN_LIQUIDITY_USD)) || fail "${label} liquidity ${liquidity} USD below ${MIN_LIQUIDITY_USD}"
}

roles() {
  local owner=${OWNER:?} guardian=${GUARDIAN:?} recovery=${RECOVERY:?}
  local set
  set=$(printf '%s\n' "$(lower "$owner")" "$(lower "$guardian")" "$(lower "$recovery")" | sort -u | wc -l)
  ((set == 3)) || fail "owner, guardian and recovery must be three distinct addresses"
  out owner "$owner"
  out guardian "$guardian"
  out recovery "$recovery"
}

vault_state() { # label vault asset target expected_keccak
  local label=$1 vault=$2 asset=$3 target=$4 expected_keccak=$5 v code
  read_into v "$vault" 'owner()(address)'; expect "${label}_owner" "$v" "$OWNER"
  read_into v "$vault" 'pendingOwner()(address)'
  expect "${label}_pending_owner" "$v" 0x0000000000000000000000000000000000000000
  read_into v "$vault" 'guardian()(address)'; expect "${label}_guardian" "$v" "$GUARDIAN"
  read_into v "$vault" 'RECOVERY_ADDRESS()(address)'; expect "${label}_recovery" "$v" "$RECOVERY"
  read_into v "$vault" 'OWNER_ONLY_DEPOSITS()(bool)'; expect "${label}_owner_only_deposits" "$v" true
  read_into v "$vault" 'MORPHO_VAULT()(address)'; expect "${label}_morpho_vault" "$v" "$target"
  read_into v "$vault" 'asset()(address)'; expect "${label}_asset" "$v" "$asset"
  read_into v "$vault" 'decimals()(uint8)'; expect "${label}_decimals" "$v" 12
  read_into v "$vault" 'paused()(bool)'; expect "${label}_paused" "$v" false
  read_into v "$vault" 'terminated()(bool)'; expect "${label}_terminated" "$v" false
  read_into v "$vault" 'totalSupply()(uint256)'; expect "${label}_total_supply" "$v" 0
  read_into v "$vault" 'maxDeposit(address)(uint256)' 0x000000000000000000000000000000000000dEaD
  expect "${label}_max_deposit_stranger" "$v" 0
  read_into v "$vault" 'maxDeposit(address)(uint256)' "$OWNER"
  expect "${label}_max_deposit_owner" "$v" "$MAX_UINT"
  code=$(cast code "$vault" --rpc-url "$RPC")
  v=$(cast keccak "$code")
  if [[ -n "$expected_keccak" ]]; then expect "${label}_code_keccak" "$v" "$expected_keccak"; else out "${label}_code_keccak" "$v"; fi
}

case "$PHASE" in
  preflight)
    roles
    deployer=${DEPLOYER:?}
    for r in "$OWNER" "$GUARDIAN" "$RECOVERY"; do
      [[ "$(lower "$r")" != "$(lower "$deployer")" ]] || fail "the deployer must hold no role"
      code=$(cast code "$r" --rpc-url "$RPC")
      [[ "$code" == 0x ]] || out "code_at_$r" present
    done
    target_state galaxy_usdc "$GALAXY_USDC" "$USDC"
    target_state galaxy_eurc "$GALAXY_EURC" "$EURC"
    morpho_liquidity galaxy_usdc "$GALAXY_USDC"
    for who in deployer:"$deployer" owner:"$OWNER" guardian:"$GUARDIAN"; do
      balance=$(cast balance "${who#*:}" --rpc-url "$RPC")
      [[ -n "$balance" ]] || fail "empty balance read"

      out "${who%%:*}_native_balance_wei" "$balance"
      [[ "$balance" != 0 ]] || fail "${who%%:*} has no USDC for gas on Arc"
    done
    nonce=$(cast nonce "$deployer" --rpc-url "$RPC")
    out deployer "$deployer"
    out deployer_nonce "$nonce"
    [[ "$nonce" =~ ^[0-9]+$ ]] || fail "unreadable deployer nonce"
    predicted=$(cast compute-address "$deployer" --nonce "$nonce" | awk '{print $NF}')
    out predicted_usdc_vault "$predicted"
    predicted=$(cast compute-address "$deployer" --nonce $((nonce + 1)) | awk '{print $NF}')
    out predicted_eurc_vault "$predicted"
    ;;
  post-deploy)
    roles
    vault_state usdc_vault "${USDC_VAULT:?}" "$USDC" "$GALAXY_USDC" "${EXPECTED_CODE_KECCAK_USDC:-}"
    vault_state eurc_vault "${EURC_VAULT:?}" "$EURC" "$GALAXY_EURC" "${EXPECTED_CODE_KECCAK_EURC:-}"
    target_state galaxy_usdc "$GALAXY_USDC" "$USDC"
    target_state galaxy_eurc "$GALAXY_EURC" "$EURC"
    ;;
  post-deposit)
    vault=${USDC_VAULT:?} owner=${OWNER:?} amount=${AMOUNT:?}
    [[ "$amount" =~ ^[0-9]+$ ]] || fail "AMOUNT must be an integer in USDC base units"
    read_into supply "$vault" 'totalSupply()(uint256)'
    read_into v "$vault" 'balanceOf(address)(uint256)' "$owner"; expect owner_shares "$v" "$supply"
    read_into v "$USDC" 'balanceOf(address)(uint256)' "$vault"; expect vault_idle_usdc "$v" 0
    read_into v "$USDC" 'allowance(address,address)(uint256)' "$vault" "$GALAXY_USDC"
    expect allowance_vault_to_target "$v" 0
    read_into v "$USDC" 'allowance(address,address)(uint256)' "$owner" "$vault"
    expect allowance_owner_to_vault "$v" 0
    read_into position "$GALAXY_USDC" 'balanceOf(address)(uint256)' "$vault"
    out vault_morpho_shares "$position"
    [[ "$position" != 0 ]] || fail "the deposit did not reach Morpho"
    read_into assets "$vault" 'totalAssets()(uint256)'
    out total_assets "$assets"
    # Morpho interest accrues between the signature and this check: allow 0.1 % above the
    # deposit, and 2 units of rounding below it.
    ((assets + 2 >= amount && assets <= amount + amount / 1000)) \
      || fail "totalAssets $assets not within [-2 units, +0.1 %] of $amount"
    read_into v "$vault" 'previewRedeem(uint256)(uint256)' "$supply"; out preview_redeem_all "$v"
    ;;
  post-redeem)
    vault=${USDC_VAULT:?} owner=${OWNER:?}
    read_into v "$vault" 'totalSupply()(uint256)'; expect total_supply "$v" 0
    read_into v "$vault" 'balanceOf(address)(uint256)' "$owner"; expect owner_shares "$v" 0
    read_into v "$vault" 'totalAssets()(uint256)'; out residual_total_assets "$v"
    read_into v "$USDC" 'balanceOf(address)(uint256)' "$owner"; out owner_usdc "$v"
    ;;
  *) fail "unknown PHASE $PHASE" ;;
esac
echo "GO: $PHASE"
