---
name: mainnet-preflight
description: Read-only pre-flight on Arc mainnet before deploying or signing. Re-reads chain id, Morpho target state (asset, gates, exit-gate abdication, fees, liquidity), role addresses and deployer nonce, and predicts the vault addresses. Use within one hour before any mainnet deployment or owner signature.
---
Read-only. Only read-only `cast` subcommands (`call code nonce balance chain-id block-number compute-address sig`) and the Morpho API.
The Bash environment of Claude only sees variables exported before `claude` was launched.

Inputs from the environment (never from a committed file): `DEPLOYER OWNER GUARDIAN RECOVERY`.
Targets are the constants pinned in `script/Deploy.s.sol`.

1. Run `ARC_RPC_URL=https://rpc.mainnet.arc.io PHASE=preflight script/mainnet-check.sh`.
2. If the script does not exist yet, run the checks by hand:
   - `cast chain-id` = 5042.
   - For each target: `asset()`; the four gates `receiveSharesGate() sendSharesGate() receiveAssetsGate() sendAssetsGate()` = `0x0`;
     `abdicated(bytes4)` = true for the selectors of `setReceiveSharesGate(address)`, `setSendSharesGate(address)`,
     `setReceiveAssetsGate(address)` (`cast sig`); `performanceFee()`, `managementFee()`.
   - Liquidity and net APY: `https://blue-api.morpho.org/graphql`, `vaultV2s(where:{chainId_in:[5042]})`, fields
     `address name liquidity liquidityUsd totalAssetsUsd netApy`, filtered by address.
   - Roles: three distinct addresses, none equal to `DEPLOYER`; `cast code` of each (empty for an EOA);
     `cast balance` of deployer, owner and guardian > 0.
   - `cast nonce $DEPLOYER` = N; predicted vaults: `cast compute-address $DEPLOYER --nonce N` and `N+1`.
3. Output a `key=value` block, with the block number and UTC time, ready for the evidence log.

NO-GO, say it first and stop: any gate set, any exit-gate abdication false, target liquidity < 1 M$,
a role equal to the deployer, a zero gas balance, chain id ≠ 5042.
