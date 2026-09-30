# ForYield Arc YieldVault

Open-source ERC-4626 vault for **ForYield**, a DeFi yield vault built for EU
regulatory requirements, on [Arc](https://arc.io), Circle's stablecoin-native
chain. Every deposit of USDC or EURC is supplied to a Morpho Vault V2 in the same
transaction. This repository is the public demonstration submitted to the
Circle Developer Grants Program.

ForYield is not an authorised crypto-asset service provider (MiCA CASP applicant). Nothing
here is an offer of a financial service: the mainnet vaults hold ForYield's own capital only,
and their deposits are reserved to ForYield on chain.

> **Scope.** A base vault (`YieldVault`: proportional ERC-4626 shares, first-depositor
> inflation protection, owner / guardian / recovery roles held by three distinct
> addresses, emergency pause and a fixed-destination evacuation) and its Morpho
> subclass (`MorphoYieldVault`: one immutable Morpho Vault V2 target per vault). Live on
> Arc mainnet for USDC and EURC against curated Galaxy vaults, and on Arc testnet with
> deposit and redemption evidence, plus a CCTP v2 script that moves USDC from Base to Arc. StableFX, Gateway, an Aave V4 adapter
> and a compliance event schema are planned milestones, not part of this code.

## Live demo

**[arc.for-yield.com](https://arc.for-yield.com)**: connect a browser wallet on Arc testnet,
deposit USDC or EURC and redeem it. The page adds Arc testnet to the wallet, approves the exact
amount, and links every transaction to the explorer. `?vault=eurc` opens the EURC instance.
Testnet USDC and EURC come from [Circle's faucet](https://faucet.circle.com). The page is a
static Next.js export in [`web/`](./web/), deployed on Render from
[`render.yaml`](./render.yaml).

## Mainnet deployment

Network: Arc **mainnet**, chain id 5042, explorer [arc.etherscan.io](https://arc.etherscan.io).
Deployed on 2026-09-29 (block 23338354) from this repository's `main` with
[`script/Deploy.s.sol`](./script/Deploy.s.sol); both sources are verified (Exact Match).

| Component | Address | Morpho target |
|---|---|---|
| MorphoYieldVault "ForYield Arc USDC" (fyUSDC) | [`0x007977235da099E1B29cc63b0D842472B5ecef28`](https://arc.etherscan.io/address/0x007977235da099E1B29cc63b0D842472B5ecef28#code) | Galaxy USDC [`0x8E357432CC12ff425c36432F312968aEb16112AF`](https://arc.etherscan.io/address/0x8E357432CC12ff425c36432F312968aEb16112AF) |
| MorphoYieldVault "ForYield Arc EURC" (fyEURC) | [`0x0fD1f8f3dbc4F78e34F85aE5592a3C873d9512d9`](https://arc.etherscan.io/address/0x0fD1f8f3dbc4F78e34F85aE5592a3C873d9512d9#code) | Galaxy EURC [`0x389abDf4355e0cF4f19298179991705a98f21c18`](https://arc.etherscan.io/address/0x389abDf4355e0cF4f19298179991705a98f21c18) |

Deployment transactions: USDC vault
[`0x055424fd…2bc11`](https://arc.etherscan.io/tx/0x055424fd23e4a3862fbdb9aca01ac400ed48c2ecb0aaee492ac761a13cb2bc11),
EURC vault
[`0xfeae6251…b5cf9`](https://arc.etherscan.io/tx/0xfeae625121b09f260ecce1855d3af4ac5f6c43b9eb64b421439b99dc77eb5cf9).

- **Own capital only.** `OWNER_ONLY_DEPOSITS` is `true` on both vaults: any other depositor is
  refused on chain (`ERC4626ExceededMaxDeposit`, or `DepositNotAllowed` when depositing for
  the owner). The USDC vault holds a position of ForYield's own capital in Galaxy USDC.
- **No curator can lock the exits.** On both Galaxy targets the three setters that could gate
  an exit (`setReceiveSharesGate`, `setSendSharesGate`, `setReceiveAssetsGate`) are abdicated
  for good; the deployment script refuses any mainnet target that is not pinned or whose exit
  gates are not abdicated, and the weekly fork test checks it against the live contracts.
- **Checks.** [`script/mainnet-check.sh`](./script/mainnet-check.sh) re-reads every role,
  flag and target on chain, read-only.

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
(see [Tests](#tests)) and live on mainnet (see [Mainnet deployment](#mainnet-deployment)).

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
- **Owner-only deposits.** `OWNER_ONLY_DEPOSITS`, fixed at deployment, reserves entries to
  the owner: `maxDeposit` and `maxMint` return 0 for any other receiver, and a deposit from any
  other caller reverts with `DepositNotAllowed`. Exits stay open to share holders. The testnet
  instances are open; a mainnet instance is always restricted, so it only ever holds
  ForYield's own capital.
- **Arc specifics.** USDC is both Arc's native gas token (18 decimals) and an ERC-20 at
  `0x3600…0000` (6 decimals) over the same balance. The vault only uses the ERC-20 interface.

## Contract interface

| Function | Access | Description |
|---|---|---|
| `deposit` / `mint` | anyone (ERC-4626), or the owner only when `OWNER_ONLY_DEPOSITS` | Standard ERC-4626 entry points; the supply to Morpho happens inside. |
| `withdraw` / `redeem` | any share holder (ERC-4626) | Standard ERC-4626 exit points; the recall from Morpho happens inside. |
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
- **Keys.** The testnet roles are local keystores; the mainnet roles are three distinct keys
  held by ForYield's management, for an own-capital demonstration. A production deployment
  puts the owner behind a multi-party custody quorum and the recovery address on a multisig.

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
- `test/script/Deploy.t.sol`: every guard of the deployment script (expected chain, deployer
  without a role, pinned mainnet targets, gates set, exit gates not abdicated), on mocks etched
  at the real addresses.
- `test/fork/DeployMainnet.fork.t.sol`: dress rehearsal on a fork of Arc mainnet through the
  deployment script: both vaults as configured on mainnet, the owner's 100 USDC round trip, the
  guardian's pause and evacuation to the recovery address against the real Morpho Vault V2,
  refused third-party entries, and the Galaxy targets' abdicated exit gates. `OWNER`,
  `GUARDIAN` and `RECOVERY` may be exported to rehearse with the real role addresses.
- `test/fork/MorphoArcMainnet.fork.t.sol`: the vault against the real Galaxy USDC Morpho
  Vault V2 on a local fork of Arc mainnet, configured as on mainnet (owner-only deposits), with
  a year of real interest and a refused third-party deposit. It needs
  [Arc Foundry](https://github.com/circlefin/arc-foundry), which implements Arc's USDC
  precompile, and `--isolate`, because a Morpho Vault V2 freezes its valuation for the rest of
  a transaction:

  ```bash
  arc-forge test --isolate --match-path 'test/fork/*' --fork-url https://rpc.mainnet.arc.io
  ```

CI enforces formatting, the test suite, 95 % line and branch coverage of `src/` (currently
100 %), a clean Slither run, and a type-checked build of the web demo. The mainnet fork tests
run weekly in a separate workflow.

## Deploy

Scripts run with Arc Foundry (`arc-forge`) and sign with Foundry keystores.
[`script/Deploy.s.sol`](./script/Deploy.s.sol) deploys the USDC vault, and the EURC vault when
`EURC_MORPHO_TARGET` is set, from a deployment key that holds no role: the constructor sets
owner, guardian and recovery. It refuses to run on any chain but `EXPECTED_CHAIN_ID`, from a key
that holds a role, or against a Morpho target with any access gate set. On Arc mainnet it always
restricts deposits to the owner, deploys both vaults, accepts only the two pinned Galaxy targets
(several test vaults share their names), and requires the three gates that could block an exit
to be abdicated for good, so no curator can ever lock the vaults' exits after a deposit. It
prints every parameter and the ABI-encoded constructor arguments before broadcasting.

### Testnet

```bash
# 1. A Morpho Vault V2 target per asset (USDC shown)
ASSET=0x3600000000000000000000000000000000000000 OWNER=<owner> script/deploy-morpho-target.sh

# 2. Both vaults, same bytecode
EXPECTED_CHAIN_ID=5042002 OWNER=<owner> GUARDIAN=<guardian> RECOVERY=<recovery> \
USDC_MORPHO_TARGET=<usdc target> EURC_MORPHO_TARGET=<eurc target> \
arc-forge script script/Deploy.s.sol --rpc-url arc_testnet --account <deployer keystore> \
  --sender <deployer> --broadcast --verify --verifier blockscout \
  --verifier-url https://explorer.testnet.arc.io/api/

# 3. Deposit and redeem half, from a depositor
DEPOSITOR=<depositor> VAULT=<vault> AMOUNT=5000000 \
arc-forge script script/DemoFlow.s.sol --rpc-url arc_testnet --account <depositor keystore> \
  --sender <depositor> --broadcast
```

### Mainnet

Morpho runs curated Vault V2 instances on Arc mainnet, so no target is deployed. The owner
key is held by ForYield's management; the deployment key only needs a little USDC for gas (about
5.5 M gas for both vaults). Every step is checked by
[`script/mainnet-check.sh`](./script/mainnet-check.sh), read-only, which prints `key=value`
lines for the evidence log and stops at the first mismatch; point `ARC_RPC_URL` at a local
`arc-anvil` fork to rehearse the whole sequence first.

```bash
# 0. Pre-flight, within the hour: targets, gates, abdications, liquidity, roles, gas, and the
#    vault addresses predicted from the deployer's nonce
PHASE=preflight OWNER=<owner> GUARDIAN=<guardian> RECOVERY=<recovery> DEPLOYER=<deployer> \
  script/mainnet-check.sh

# 1. Both vaults, owner-only deposits. Run once without --broadcast: the simulation must
#    return the predicted addresses.
EXPECTED_CHAIN_ID=5042 OWNER=<owner> GUARDIAN=<guardian> RECOVERY=<recovery> \
USDC_MORPHO_TARGET=0x8E357432CC12ff425c36432F312968aEb16112AF \
EURC_MORPHO_TARGET=0x389abDf4355e0cF4f19298179991705a98f21c18 \
arc-forge script script/Deploy.s.sol --rpc-url arc_mainnet --account <deployer keystore> \
  --sender <deployer> --broadcast

# 1b. Before any owner signature
PHASE=post-deploy OWNER=<owner> GUARDIAN=<guardian> RECOVERY=<recovery> \
  USDC_VAULT=<usdc vault> EURC_VAULT=<eurc vault> script/mainnet-check.sh

# 2. Source verification: the Blockscout API of explorer.arc.io sits behind a bot challenge,
#    so publish on Sourcify, then upload the standard JSON input on explorer.arc.io by hand
ARGS=$(cast abi-encode "constructor(address,string,string,address,address,address,bool,address)" \
  0x3600000000000000000000000000000000000000 "ForYield Arc USDC" fyUSDC \
  <owner> <guardian> <recovery> true <usdc target>)
arc-forge verify-contract <vault> src/MorphoYieldVault.sol:MorphoYieldVault --chain 5042 \
  --verifier sourcify --constructor-args "$ARGS"
arc-forge verify-contract <vault> src/MorphoYieldVault.sol:MorphoYieldVault --chain 5042 \
  --constructor-args "$ARGS" --show-standard-json-input > standard-input.json

# 3. Calldata for the three owner signatures, to compare with the wallet's raw data.
#    Assets have 6 decimals (100 USDC = 100000000); vault shares have 12. Redeem the exact
#    balanceOf(owner), first field only: cast appends "[1e14]".
cast calldata "approve(address,uint256)" <vault> <amount>   # to the asset
cast calldata "deposit(uint256,address)" <amount> <owner>   # to the vault
cast calldata "redeem(uint256,address,address)" <shares> <owner> <owner>
PHASE=post-deposit OWNER=<owner> USDC_VAULT=<usdc vault> AMOUNT=<amount> script/mainnet-check.sh
PHASE=post-redeem OWNER=<owner> USDC_VAULT=<usdc vault> script/mainnet-check.sh
```

## CCTP v2: USDC from Base to Arc

[`scripts/cctp/base-sepolia-to-arc.ts`](./scripts/cctp/base-sepolia-to-arc.ts) approves the
exact amount, burns it on Base with `depositForBurn` to Arc (CCTP domain 26, Fast Transfer),
waits for Circle's attestation and relays `receiveMessage` on Arc. It runs on Node 24 with no
dependency and signs through `cast` and a keystore. Base Sepolia to Arc testnet by default;
`NETWORK=mainnet` moves real USDC from Base to Arc mainnet. The keystore relays the mint on
Arc, so it needs a little USDC there for gas; the recipient can be any address. On mainnet
nothing has a default: `RECIPIENT`, `AMOUNT` and `ACCOUNT` are required, addresses must carry
their EIP-55 checksum, `SENDER` must be the keystore's address, the fee is capped at 10 bps,
and the operator types the recipient's last four characters before anything is sent. Every
hash is printed as soon as its transaction is sent: before re-running after an error, look for
a `depositForBurn` from the sender on Basescan and resume with `BURN_TX`.

```bash
SENDER=<address> node scripts/cctp/base-sepolia-to-arc.ts
# mainnet
NETWORK=mainnet SENDER=<keystore address> RECIPIENT=<address> AMOUNT=<units> \
  ACCOUNT=<keystore> node scripts/cctp/base-sepolia-to-arc.ts
# resume an interrupted transfer from its burn
SENDER=<address> BURN_TX=<burn tx hash> node scripts/cctp/base-sepolia-to-arc.ts
```

## Circle products used

- **Arc**: the vaults run on Arc mainnet against curated Morpho vaults, and on Arc testnet
  with all evidence transactions, with USDC as the gas token.
- **USDC** and **EURC**: the two vault assets, Circle's official tokens on Arc.
- **CCTP v2**: moves USDC from Base (Base Sepolia on testnet) to Arc.

## Roadmap

- **Delivered (this repository)**: base vault, Morpho Vault V2 subclass, USDC and EURC
  instances on Arc testnet and Arc mainnet (own capital, curated Galaxy vaults), CCTP v2
  funding script, mainnet fork tests.
- **Next**: owner behind a multi-party custody quorum and an external audit; StableFX for USDC and EURC conversion; Gateway for unified USDC
  balances across chains; an Aave V4 adapter (Aave runs V4 on Arc, whose hub-and-spoke
  interface differs from Aave V3's `IPool`); a compliance event schema for EU reporting.

## Contributions

This repository is published read-only: issues and pull requests from outside the ForYield
team are not accepted.

## License

[MIT](./LICENSE)
