# ForYield Arc YieldVault

Open-source ERC-4626 vault for **ForYield**, a DeFi yield vault built for EU
regulatory requirements, on [Arc](https://arc.io), Circle's stablecoin-native
chain. Every deposit of USDC or EURC is supplied to a Morpho Vault V2 in the same
transaction. This repository is the public demonstration submitted to the
Circle Developer Grants Program.

ForYield is not an authorised crypto-asset service provider. Nothing here is an
offer of a financial service; the deployments below are testnet only.

> **Scope.** A base vault (`YieldVault`: proportional ERC-4626 shares, first-depositor
> inflation protection, owner / guardian / recovery roles held by three distinct
> addresses, emergency pause and a fixed-destination evacuation) and its Morpho
> subclass (`MorphoYieldVault`: one immutable Morpho Vault V2 target per vault). Deployed
> on Arc testnet for USDC and EURC, with deposit and redemption evidence, plus a CCTP v2
> script that moves USDC from Base Sepolia to Arc. StableFX, Gateway, an Aave V4 adapter
> and a compliance event schema are planned milestones, not part of this code.

## Live demo

**[arc.for-yield.com](https://arc.for-yield.com)**: connect a browser wallet on Arc testnet,
deposit USDC or EURC and redeem it. The page adds Arc testnet to the wallet, approves the exact
amount, and links every transaction to the explorer. `?vault=eurc` opens the EURC instance.
Testnet USDC and EURC come from [Circle's faucet](https://faucet.circle.com). The page is a
static Next.js export in [`web/`](./web/), deployed on Render from
[`render.yaml`](./render.yaml).

## Testnet deployments

Network: Arc **testnet**, chain id 5042002, explorer
[explorer.testnet.arc.io](https://explorer.testnet.arc.io). All four contracts are
source-verified on the explorer.

| Component | Address | Asset |
|---|---|---|
| MorphoYieldVault "ForYield Arc USDC" (fyUSDC) | [`0xBbc099E29069e71C1A52C2e9d74328096Fc4e4a7`](https://explorer.testnet.arc.io/address/0xBbc099E29069e71C1A52C2e9d74328096Fc4e4a7) | USDC `0x3600000000000000000000000000000000000000` |
| MorphoYieldVault "ForYield Arc EURC" (fyEURC) | [`0x623B4e264CB217763dDD71a1ec597c0926Cb902c`](https://explorer.testnet.arc.io/address/0x623B4e264CB217763dDD71a1ec597c0926Cb902c) | EURC `0x89B50855Aa3bE2F677cD6303Cec089B5F319D72a` |
| Morpho Vault V2, USDC target | [`0x76b022B083F00e094feB1DFf5a89E60cF1c52e27`](https://explorer.testnet.arc.io/address/0x76b022B083F00e094feB1DFf5a89E60cF1c52e27) | USDC |
| Morpho Vault V2, EURC target | [`0x046CE778D030B0Bb348dd8fDa4751B2281081AE4`](https://explorer.testnet.arc.io/address/0x046CE778D030B0Bb348dd8fDa4751B2281081AE4) | EURC |
| Owner / guardian / recovery | `0xEBe5…9080` / `0xf999…FE61` / `0xB5cD…DbCc` | |

Morpho has no deployment on Arc testnet, so the two targets are real Morpho Vault V2
contracts deployed by us from [`morpho-org/vault-v2`](https://github.com/morpho-org/vault-v2)
(pinned commit, see [`script/deploy-morpho-target.sh`](./script/deploy-morpho-target.sh)).
They have no adapter and no curator: deposits sit idle inside them and earn nothing. Real
Morpho yield is demonstrated against a curated vault on Arc mainnet in a local fork test
(see [Tests](#tests)); nothing is deployed on mainnet.

Evidence, with every transaction hash, block and post-state read on chain:

- [docs/evidence/a1-vault-testnet.md](./docs/evidence/a1-vault-testnet.md): Morpho targets,
  vault deployments, deposit and redemption of USDC and EURC by a depositor distinct from
  every role.
- [docs/evidence/a2-cctp.md](./docs/evidence/a2-cctp.md): USDC moved from Base Sepolia to Arc
  testnet with CCTP v2.

Screenshots per Circle product are in [docs/evidence/screenshots/](./docs/evidence/screenshots/).
A step-by-step walkthrough to reproduce the demo from a browser wallet, with no command line,
is in [docs/demo/fil-rouge-testeur.md](./docs/demo/fil-rouge-testeur.md) (French).

## How it works

- **Deposit.** The vault pulls the assets from the caller (never from any other address),
  mints its shares, approves the Morpho vault for the exact amount, supplies all of it in the
  same transaction, and checks that the approval was fully consumed. If Morpho refuses the
  deposit, the whole transaction reverts: no deposit is ever left idle silently.
- **Withdrawal.** Shares are burned first, then the vault pays from its idle balance and
  recalls any shortfall from Morpho, checking the amount actually received.
- **Valuation.** `totalAssets()` is the Morpho position valued with Morpho's own
  `convertToAssets` (net of Morpho's fees, rounded down) plus idle assets. Rounding always
  favors the vault.
- **Morpho Vault V2's `max*` functions always return 0** by design (its access gates cannot
  be evaluated revert-free), so this vault never reads them.
- **Arc specifics.** USDC is both Arc's native gas token (18 decimals) and an ERC-20 at
  `0x3600…0000` (6 decimals) over the same balance. The vault only uses the ERC-20 interface.

## Contract interface

| Function | Access | Description |
|---|---|---|
| `deposit` / `mint` / `withdraw` / `redeem` | anyone (ERC-4626) | Standard ERC-4626 entry and exit points; supply to and recall from Morpho happen inside. |
| `totalAssets()` | view | Morpho position plus idle assets. |
| `pause()` | owner or guardian | Closes every entry and exit (`max*` return 0). |
| `unpause()` | owner | Reopens the vault, unless it was terminated. |
| `emergencyDeallocate()` | owner or guardian | Redeems the whole Morpho position into idle assets held by the vault. |
| `emergencyWithdraw()` | owner or guardian, paused only | Sends every idle asset to `RECOVERY_ADDRESS` and terminates the vault for good. Callable again to sweep assets recalled later. |
| `setGuardian(address)` | owner | Replaces the guardian; refuses any address holding another role. |
| `transferOwnership` / `acceptOwnership` | owner / pending owner | Two-step ownership transfer; the new owner cannot be the guardian or the recovery address. `renounceOwnership` is disabled. |

## Risks and deviations

- **Target gating.** A Morpho Vault V2 curator can gate addresses (`sendSharesGate`,
  `receiveAssetsGate`). If the target gates this vault after deposits, every exit reverts,
  Morpho's own `forceDeallocate` included, and nothing in this contract can route around it.
  Choosing and monitoring an ungated target is an operational requirement. Funds are not
  lost (transactions revert without effect), but they stay locked while the gate is in place.
- **Illiquidity.** If Morpho lacks liquidity, withdrawals revert without effect. Anyone can
  call Morpho's permissionless `forceDeallocate` to bring liquidity back, then retry.
- **ERC-4626 deviation.** While unpaused, `maxDeposit` and `maxMint` report no limit even
  though Morpho may refuse a deposit; such a deposit reverts as a whole.
- **Evacuation.** After `emergencyWithdraw`, the vault is terminal: shares can no longer be
  redeemed on chain, and holders are made whole off chain from the recovery address.
- **Testnet keys.** The testnet roles are local keystores. A production deployment would put
  the owner behind a multi-party custody quorum and the recovery address on a multisig.

A security review of the contracts found no fund-theft, share-price manipulation, approval
or reentrancy issue; its one medium finding is the target-gating risk above.

## Build & test

```bash
git clone --recurse-submodules https://github.com/Foryield/arc-yield-vault.git
cd arc-yield-vault
forge build
forge test
```

### Tests

- `test/YieldVault.t.sol`: roles, pause, evacuation, inflation attack, third-party calls
  (sender, receiver and share owner are always distinct addresses).
- `test/MorphoYieldVault.t.sol`: against a mock reproducing Morpho Vault V2 (zero `max*`,
  refused deposits, limited liquidity, short payments).
- `test/MorphoYieldVault.fuzz.t.sol`: solvency and fairness under random deposits, yield
  and withdrawals.
- `test/fork/MorphoArcMainnet.fork.t.sol`: the vault against the real Galaxy USDC Morpho
  Vault V2 on a local fork of Arc mainnet, with a year of real interest. It needs
  [Arc Foundry](https://github.com/circlefin/arc-foundry), which implements Arc's USDC
  precompile, and `--isolate`, because a Morpho Vault V2 freezes its valuation for the rest of
  a transaction:

  ```bash
  arc-forge test --isolate --match-path test/fork/MorphoArcMainnet.fork.t.sol \
    --fork-url https://rpc.mainnet.arc.io
  ```

CI enforces formatting, the test suite, 95 % line and branch coverage of `src/` (currently
100 %), a clean Slither run, and a type-checked build of the web demo. The mainnet fork test runs weekly in a separate workflow.

## Deploy (testnet)

Scripts run with Arc Foundry (`arc-forge`) and sign with Foundry keystores.

```bash
# 1. A Morpho Vault V2 target per asset (USDC shown)
ASSET=0x3600000000000000000000000000000000000000 OWNER=<owner> script/deploy-morpho-target.sh

# 2. Both vaults, same bytecode
OWNER=<owner> GUARDIAN=<guardian> RECOVERY=<recovery> \
USDC_MORPHO_TARGET=<usdc target> EURC_MORPHO_TARGET=<eurc target> \
arc-forge script script/Deploy.s.sol --rpc-url arc_testnet --account <owner keystore> \
  --sender <owner> --broadcast --verify --verifier blockscout \
  --verifier-url https://explorer.testnet.arc.io/api/

# 3. Deposit and redeem half, from a depositor
DEPOSITOR=<depositor> VAULT=<vault> AMOUNT=5000000 \
arc-forge script script/DemoFlow.s.sol --rpc-url arc_testnet --account <depositor keystore> \
  --sender <depositor> --broadcast
```

## CCTP v2: USDC from Base Sepolia to Arc

[`scripts/cctp/base-sepolia-to-arc.ts`](./scripts/cctp/base-sepolia-to-arc.ts) approves the
exact amount, burns it on Base Sepolia with `depositForBurn` to Arc (CCTP domain 26, Fast
Transfer), waits for Circle's attestation and relays `receiveMessage` on Arc. It runs on
Node 24 with no dependency and signs through `cast` and a keystore.

```bash
SENDER=<address> node scripts/cctp/base-sepolia-to-arc.ts
# resume an interrupted transfer from its burn
SENDER=<address> BURN_TX=<burn tx hash> node scripts/cctp/base-sepolia-to-arc.ts
```

## Circle products used

- **Arc**: the vaults, their Morpho targets and all evidence transactions run on Arc testnet,
  with USDC as the gas token.
- **USDC** and **EURC**: the two vault assets, Circle's official testnet tokens on Arc.
- **CCTP v2**: moves USDC from Base Sepolia to Arc.

## Roadmap

- **Delivered (this repository)**: base vault, Morpho Vault V2 subclass, USDC and EURC
  instances on Arc testnet, CCTP v2 funding script, mainnet fork test against a curated
  Morpho vault.
- **Next**: Arc mainnet deployment behind a custody quorum; EURC and USDC instances on
  curated Morpho vaults; StableFX for USDC and EURC conversion; Gateway for unified USDC
  balances across chains; an Aave V4 adapter (Aave runs V4 on Arc, whose hub-and-spoke
  interface differs from Aave V3's `IPool`); a compliance event schema for EU reporting.

## Contributions

This repository is published read-only: issues and pull requests from outside the ForYield
team are not accepted.

## License

[MIT](./LICENSE)
