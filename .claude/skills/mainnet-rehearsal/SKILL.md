---
name: mainnet-rehearsal
description: Full dress rehearsal of the mainnet sequence on an arc-anvil fork of Arc mainnet (deploy, post-deploy checks, approve, deposit, redeem, stranger revert) with the real addresses and real deployer nonce. Use after /mainnet-preflight and before the real deployment.
---
Everything runs against a local fork. Nothing touches mainnet. Broadcast files go outside the repo.

Prerequisites: `arc-anvil` and `arc-forge` installed; `DEPLOYER OWNER GUARDIAN RECOVERY` exported;
predicted addresses from `/mainnet-preflight`.

Print these commands for the human to run in a second terminal (the hook blocks `--broadcast`
and `cast send` for Claude, including against the fork, on purpose):

```bash
B=$(cast block-number --rpc-url https://rpc.mainnet.arc.io)
arc-anvil --network arc --fork-url https://rpc.mainnet.arc.io --fork-block-number $B --port 8545
# second terminal
export SCRATCH=$(mktemp -d); export FOUNDRY_BROADCAST=$SCRATCH/broadcast
L=http://127.0.0.1:8545
cast rpc anvil_impersonateAccount $DEPLOYER --rpc-url $L
cast rpc anvil_impersonateAccount $OWNER --rpc-url $L
cast rpc anvil_setBalance $OWNER $(cast to-hex 101000000000000000000) --rpc-url $L   # 101 USDC native, 18 dec
EXPECTED_CHAIN_ID=5042 USDC_MORPHO_TARGET=0x8E357432CC12ff425c36432F312968aEb16112AF \
  EURC_MORPHO_TARGET=0x389abDf4355e0cF4f19298179991705a98f21c18 \
  arc-forge script script/Deploy.s.sol --rpc-url $L --sender $DEPLOYER --unlocked --broadcast
VAULT=$(jq -r '.receipts[0].contractAddress' $FOUNDRY_BROADCAST/Deploy.s.sol/5042/run-latest.json)   # [1] = EURC vault
ARC_RPC_URL=$L PHASE=post-deploy script/mainnet-check.sh
cast send 0x3600000000000000000000000000000000000000 "approve(address,uint256)" $VAULT 100000000 --from $OWNER --unlocked --rpc-url $L
cast send $VAULT "deposit(uint256,address)" 100000000 $OWNER --from $OWNER --unlocked --rpc-url $L
ARC_RPC_URL=$L PHASE=post-deposit script/mainnet-check.sh
SHARES=$(cast call $VAULT "balanceOf(address)(uint256)" $OWNER --rpc-url $L | awk '{print $1}')   # cast prints "1e14" after the value
cast send $VAULT "redeem(uint256,address,address)" $SHARES $OWNER $OWNER --from $OWNER --unlocked --rpc-url $L
ARC_RPC_URL=$L PHASE=post-redeem script/mainnet-check.sh
```

Then Claude, read-only on `$L`:
- vault addresses = predicted addresses (same nonce);
- `cast keccak $(cast code $VAULT --rpc-url $L)` recorded as the reference fingerprint;
- `cast receipt` status 1 and `gasUsed` of each step;
- a funded stranger: `deposit(1, stranger)` must revert `ERC4626ExceededMaxDeposit` (maxDeposit is 0 for any receiver
  but the owner), and `deposit(1, owner)` must revert `DepositNotAllowed(stranger)` (`cast call --from`);
- the calldata table (`cast calldata`) the owner will compare in the wallet.

Afterwards: `ls broadcast/Deploy.s.sol/5042/ 2>/dev/null` must be empty (`git status` is blind: the path is
gitignored). If `FOUNDRY_BROADCAST` was not honoured, the human deletes that folder before the real deployment,
otherwise fork hashes would be read later as mainnet evidence. A failure: retry once on a fresh
fork (a spurious first-deposit failure was seen on arc-anvil in the spikes); a second failure stops the run.
