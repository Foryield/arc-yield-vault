# arc-yield-vault: rules for Claude Code

Public MIT repository. ERC-4626 vault on Arc (Circle's L1, gas paid in USDC) that supplies every
deposit to one immutable Morpho Vault V2. Testnet (5042002) is live; Arc mainnet (5042) holds
ForYield's own capital only, deposits reserved to the owner on chain (`OWNER_ONLY_DEPOSITS`).

## Hard rules
- **Claude prepares, a human signs.** Never broadcast, never sign, never handle a key: print the
  exact command instead. The real barrier is the keys: the owner key is held by a human, the
  deployer keystore is encrypted, and its password is never typed in the conversation, never
  written to a file, never passed with `--password`/`--password-file`. The hook
  `.claude/hooks/block-mainnet-broadcast.sh` is a seat belt on top (fails closed; regression
  suite run by a human: `bash .claude/hooks/test-guard.sh`; the hook blocks it for Claude since
  it contains the forbidden commands). Never try to work around it.
- **`src/` is frozen** after the 2026-09-28 review. A change there needs a written reason, new
  tests, and a `vault-auditor` pass before any commit.
- **Public repo**: no personal names, emails, custody configuration, internal URLs, or code from
  other ForYield repositories. Public on-chain addresses are fine, labelled by role only.
  Run `public-repo-guard` on every staged diff before committing.
- **Wording**: "MiCA CASP applicant", "own capital", "not an authorised crypto-asset service
  provider". Never an invitation to deposit or a yield promise.
- **Amounts**: USDC and EURC are 6 decimals through the ERC-20 interface; native gas is
  18 decimals on the same balance; vault shares are 12 decimals (offset 6). Integers only,
  never floats. Never deposit a wallet's whole balance.
- **Targets by address, never by name.** Mainnet targets are pinned in `script/Deploy.s.sol`.

## Tooling
- Vanilla forge cannot run the USDC precompile at `0x3600…0000`: fork tests and scripts use
  Arc Foundry (`arc-forge`, `arc-anvil`, version pinned in `.github/workflows/fork.yml`).
- Fork tests need `--isolate` (Morpho V2 freezes its valuation within a transaction).
- `forge clean` before concluding on any test summary (a cached suite was once skipped).
- Rehearsals on `arc-anvil` keep chain id 5042: their broadcast files never enter the repo.

## Done means
`forge fmt --check`, `forge test`, coverage ≥ 95 %, Slither clean, fork tests green under
`arc-forge --isolate`, diff reviewed by `vault-auditor` (code) or `evidence-verifier` (evidence),
`public-repo-guard` OK, and every on-chain claim re-read with `cast`.

## Mainnet runbook
Skills, in order: `/mainnet-preflight` → `/mainnet-rehearsal` → (human deploys) →
`/mainnet-postdeploy` → (owner signs) → `/mainnet-evidence`.
