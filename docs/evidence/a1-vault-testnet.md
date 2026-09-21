# A1: MorphoYieldVault on Arc testnet

Network: Arc testnet, chain id 5042002. Explorer: <https://explorer.testnet.arc.io>.

Accounts (local encrypted keystores, testnet only):

- `arc-admin` (deployer, vault owner, owner of the Morpho targets): `0xEBe5beF060F54e8a0c1d222f3712ABF1C6639080`
- `arc-recovery` (immutable evacuation destination): `0xB5cDdFbC11FF36E3533b045D8beAe6cA99d1DbCc`

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
