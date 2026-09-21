# A1: MorphoYieldVault on Arc testnet

Network: Arc testnet, chain id 5042002. Explorer: <https://explorer.testnet.arc.io>.

Accounts (local encrypted keystores, testnet only):

- `arc-admin` (deployer, vault owner, owner of the Morpho targets): `0xEBe5beF060F54e8a0c1d222f3712ABF1C6639080`
- `arc-guardian` (pause and evacuation): `0xf99953774DA1da824553BD7c998605D2ABd0FE61`
- `arc-recovery` (immutable evacuation destination): `0xB5cDdFbC11FF36E3533b045D8beAe6cA99d1DbCc`
- `arc-depositor` (demonstration depositor, distinct from every role): `0x91405144F7ac4E9CcC26C32fbc475535d6110837`

## 2026-09-21: Morpho Vault V2 allocation targets

- **What it proves**: real Morpho Vault V2 contracts run on Arc testnet and hold the Circle
  assets the vaults will supply. Morpho has no deployment on Arc testnet (no code at the Morpho
  core address, and Morpho's API rejects chain id 5042002), so these two targets were deployed
  from `morpho-org/vault-v2` at commit `a0ba9df0ea697a080c0de69c18b84738cfb3bef7` with
  `script/deploy-morpho-target.sh`.
- **These are not curated Morpho vaults**: no adapter, no market, no curator. Deposits stay idle
  inside them and earn nothing. Real Morpho yield is shown by the mainnet fork test instead
  (`test/fork/MorphoArcMainnet.fork.t.sol`, against Galaxy USDC).
- **USDC target**: `0x76b022B083F00e094feB1DFf5a89E60cF1c52e27`
  ([explorer](https://explorer.testnet.arc.io/address/0x76b022B083F00e094feB1DFf5a89E60cF1c52e27)),
  asset USDC `0x3600000000000000000000000000000000000000`, source verified (VaultV2,
  solc 0.8.28).
  Deploy: [`0x0af0bb33…0d15`](https://explorer.testnet.arc.io/tx/0x0af0bb33038a2d65797631a6cfd59cfad080950fd21013a39c4b352b1f660d15)
  (block 63261912, 13:36:17 UTC, 4,802,716 gas).
- **EURC target**: `0x046CE778D030B0Bb348dd8fDa4751B2281081AE4`
  ([explorer](https://explorer.testnet.arc.io/address/0x046CE778D030B0Bb348dd8fDa4751B2281081AE4)),
  asset EURC `0x89B50855Aa3bE2F677cD6303Cec089B5F319D72a`, source verified (VaultV2,
  solc 0.8.28).
  Deploy: [`0x1514b0d9…8283`](https://explorer.testnet.arc.io/tx/0x1514b0d9a6565bd186e79edd2e66aa03d9f946b94b62a49f2c65d0b552318283)
  (block 63262072, 13:38:14 UTC, 4,802,899 gas).
- **Post-state read on chain**: both targets have `owner = arc-admin`, zero adapters, no
  liquidity adapter, and all four gates (`receiveSharesGate`, `sendSharesGate`,
  `receiveAssetsGate`, `sendAssetsGate`) at `address(0)`: any contract can deposit and exit.
- Gas for both deployments: 0.240141 USDC, paid in USDC as Arc's native gas token.

## 2026-09-21: USDC and EURC vaults deployed and source-verified

- **What it proves**: the same MorphoYieldVault bytecode runs on Arc testnet for both of
  Circle's stablecoins, with three distinct role holders and the Morpho targets above.
- **Built from**: `src/` as of commit `d1fcbdc`, with `script/Deploy.s.sol`.
- **Deploy transactions** (block 63262532, 13:43:50 UTC, signed by `arc-admin`):
  USDC vault [`0xc190a997…c9e9`](https://explorer.testnet.arc.io/tx/0xc190a9971b1c940dd5a90db4d78918aabb3615b27168026c8792ced5f11fc9e9)
  (2,066,413 gas), EURC vault [`0x52d459bb…b5d2`](https://explorer.testnet.arc.io/tx/0x52d459bbf1957fbbb48b2f9c17e8ea5b7e489f57b73dfd625004e1a9e164b5d2)
  (2,066,596 gas).
- **USDC vault** "ForYield Arc USDC" (fyUSDC): `0xBbc099E29069e71C1A52C2e9d74328096Fc4e4a7`
  ([explorer](https://explorer.testnet.arc.io/address/0xBbc099E29069e71C1A52C2e9d74328096Fc4e4a7)),
  asset USDC `0x3600…0000`, target `0x76b022B083F00e094feB1DFf5a89E60cF1c52e27`.
- **EURC vault** "ForYield Arc EURC" (fyEURC): `0x623B4e264CB217763dDD71a1ec597c0926Cb902c`
  ([explorer](https://explorer.testnet.arc.io/address/0x623B4e264CB217763dDD71a1ec597c0926Cb902c)),
  asset EURC `0x89B5…D72a`, target `0x046CE778D030B0Bb348dd8fDa4751B2281081AE4`.
- **Source verification**: both pass on the Arc testnet Blockscout (`MorphoYieldVault`,
  solc 0.8.28). The EURC submission was first rejected by the explorer's rate limit
  ("Too many requests") and succeeded on resubmission the same day. A verified match means the
  on-chain bytecode compiles from this repository's sources; the runtime code hashes differ
  between the two instances only through their immutables (asset, Morpho target, recovery).
- **Post-state read on chain**: `owner = arc-admin`, `guardian = arc-guardian`,
  `RECOVERY_ADDRESS = arc-recovery`, `MORPHO_VAULT` and `asset` as above, `totalSupply = 0`.

## 2026-09-21: deposit and redemption, USDC and EURC

- **What it proves**: a depositor distinct from the owner deposits a Circle stablecoin, the
  vault supplies all of it to Morpho in the same transaction with an exact, fully consumed
  approval, and the depositor redeems half of the shares back into the stablecoin.
- **Funding of the depositor** by `arc-admin`: 8 USDC
  [`0xbd33a4bd…b422`](https://explorer.testnet.arc.io/tx/0xbd33a4bd17d78fdc660b122449410ca484acf461ed1ca2da110d5cccbc09b422)
  (block 63265304, 14:11:26 UTC); 10 EURC
  [`0xdf716954…be22`](https://explorer.testnet.arc.io/tx/0xdf716954241b230f3bc2b0d0d92a49d8ea2f882ace5eb421f46df65b894bbe22)
  (block 63265334, 14:11:45 UTC). The USDC transfer emits two `Transfer` logs: one from the
  native-balance system address `0xffff…fffe` for 8e18 (18 decimals) and one from the USDC
  ERC-20 `0x3600…0000` for 8e6 (6 decimals), the same movement seen through both interfaces.
- **USDC flow** (`script/DemoFlow.s.sol`, block 63265375, 14:12:18 UTC, in this order within
  the block):
  approve 5 USDC [`0x6f1dfa2c…0ba8`](https://explorer.testnet.arc.io/tx/0x6f1dfa2cdfabe164b9262b46cf34eecd4b05edc4bac5dedc19abd8a48fe30ba8),
  deposit 5 USDC for 5,000,000,000,000 fyUSDC shares [`0x200c9635…6e88`](https://explorer.testnet.arc.io/tx/0x200c9635f567da9a31cdcbeb8de8e75de5fcba2ae6b9944bb43dea4ccd006e88) (213,590 gas),
  redeem 2,500,000,000,000 shares for 2.5 USDC [`0x992e3502…c81b`](https://explorer.testnet.arc.io/tx/0x992e3502de6f2fb9eb9fbf090f51458ea3888ff51811811adb35aed2b213c81b) (135,310 gas).
- **EURC flow** (block 63265415, 14:12:47 UTC, same order):
  approve 5 EURC [`0x1fa17e36…cbfe`](https://explorer.testnet.arc.io/tx/0x1fa17e36d5acb6ae1316fe0b04257b445714a7e678fa0ed1ceb6712bbc59cfbe),
  deposit 5 EURC [`0x3f30e905…c14c`](https://explorer.testnet.arc.io/tx/0x3f30e9050fc69c616eed8f10d6c9ccd625ade5eb1f3bdcd342c448c498a1c14c) (221,683 gas),
  redeem half the shares for 2.5 EURC [`0x7b069d6c…9e3f`](https://explorer.testnet.arc.io/tx/0x7b069d6ca9bcf0995d7e1a8b0f68617e7247db9976c8f1dae92e78d168ce9e3f) (126,672 gas).
- **Post-state read on chain, both vaults**: `totalAssets = 2500000` for
  `totalSupply = 2500000000000` (all held by the depositor), idle balance `0`, Morpho target
  shares `2500000000000000000` valued at `2500000`, allowance vault to Morpho `0`, allowance
  depositor to vault `0`.
- Gas for the two flows: 0.022526897 USDC in total. Depositor balance afterwards: 5.477473 USDC
  and 7.5 EURC.
- Transaction records: `broadcast/Deploy.s.sol/5042002/` and `broadcast/DemoFlow.s.sol/5042002/`.
