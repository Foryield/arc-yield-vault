---
name: mainnet-evidence
description: Writes docs/evidence/a3-vault-mainnet.md and updates the README and evidence index from the real outputs of the mainnet run, then has them checked on chain and for public-repo safety. Use once the mainnet deployment, signatures and CCTP transfer are done.
---
Source of truth: the saved outputs of `/mainnet-preflight`, `/mainnet-rehearsal`, `/mainnet-postdeploy`,
the broadcast JSON and the transaction hashes. Never write a value that was not read on chain.

1. `docs/evidence/a3-vault-mainnet.md`, same format as `a1-vault-testnet.md` (UTC date, "What it proves",
   hash + explorer link, block, gas in USDC): pre-flight, rehearsal, deployment (commit of `src/` and of
   the script, constructor-args keccak), verification, post-deploy state, guardian drill, 1 USDC round trip,
   100 USDC deposit and redeem (amounts in 6 and 18 decimals, shares in 12), CCTP burn and mint,
   bytecode fingerprint (`cast code <vault> | shasum -a 256`), final state. Roles named by function only.
2. `docs/evidence/README.md`: a3 row, mainnet explorer link, remove "testnet only".
3. README: mainnet deployment section; fix every sentence that says nothing is on mainnet; rewrite the
   target-gating risk with the exit-gate abdication facts (keep the general case); state that mainnet
   roles are management EOAs for an own-capital demo and that production puts the owner behind a
   multi-party custody quorum; cite the review that covers `OWNER_ONLY_DEPOSITS`; update
   "Circle products used" and the roadmap.
4. `grep -n "testnet only\|nothing is deployed on mainnet" README.md docs/evidence/README.md` must be empty.
5. Launch `evidence-verifier`, then `public-repo-guard` on the staged diff. Any KO or BLOCK: fix, re-run.
6. One documentation commit, diff read in full before committing.
