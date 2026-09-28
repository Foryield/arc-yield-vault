---
name: mainnet-postdeploy
description: Read-only checks on the freshly deployed mainnet vaults before the owner signs anything, then the exact calldata and wallet checklist for approve, deposit and redeem, and the post-deposit and post-redeem checks. Use right after the human broadcasts the mainnet deployment.
---
Read-only. Input: the two vault addresses, taken from BOTH `broadcast/Deploy.s.sol/5042/run-latest.json`
and the contract-creation transactions of the deployer on the explorer. If they differ, stop.

1. `PHASE=post-deploy script/mainnet-check.sh`, or by hand for each vault: `owner()`, `pendingOwner()` = 0,
   `guardian()`, `RECOVERY_ADDRESS()`, `OWNER_ONLY_DEPOSITS()` = true, `MORPHO_VAULT()` = pinned target,
   `asset()`, `decimals()` = 12, `paused()` = false, `terminated()` = false, `totalSupply()` = 0,
   `maxDeposit(<any stranger>)` = 0; `cast call --from <stranger> <vault> "deposit(uint256,address)" 1 <stranger>`
   must revert `ERC4626ExceededMaxDeposit`, and `… 1 <owner>` from the stranger must revert `DepositNotAllowed`; code fingerprint = rehearsal fingerprint. Any mismatch: NO-GO.
2. Source verification status (Sourcify `match`, explorer "Verified") before any signature.
3. For the owner, print a signing sheet:
   | Step | Contract | Function | Arguments | Expected calldata (`cast calldata`) |
   with selectors `approve 0x095ea7b3`, `deposit 0x6e553f65`, `redeem 0xba087652`.
   Amounts: USDC 6 decimals (1 USDC = 1000000, 100 USDC = 100000000). Shares are 12 decimals:
   `redeem` uses the exact `balanceOf(owner)` read just before (first field only: `cast` appends `[1e14]`),
   after a `previewRedeem`.
   Remind: wallet on chain id 5042, explorer from a bookmark, receiver/owner pasted from the wallet
   and compared character by character, never the whole balance, 1 USDC round trip first.
4. After deposit: `totalSupply == balanceOf(owner)`, `USDC.balanceOf(vault) == 0`,
   `allowance(vault, target) == 0`, `allowance(owner, vault) == 0`, `target.balanceOf(vault) > 0`,
   `totalAssets` within 2 units of the deposit.
5. After redeem: `totalSupply == 0`, residue ≤ 2 units, recorded.
If redeem reverts: check target liquidity; `forceDeallocate` on the target is permissionless; the
guardian path (pause → emergencyDeallocate → emergencyWithdraw) is the last resort, decided by a human.
