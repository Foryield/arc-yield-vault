# ForYield Arc YieldVault

Open-source ERC-4626 vault for **ForYield**, a DeFi yield vault built for EU
regulatory requirements, on [Arc](https://arc.io), Circle's stablecoin-native
chain. Deposits of USDC or EURC are supplied to a Morpho Vault V2 in the same
transaction. This repository is the public demonstration submitted to the
Circle Developer Grants Program.

ForYield is not an authorised crypto-asset service provider. Nothing here is an
offer of a financial service; the deployments below are testnet only.

> Work in progress. The design and execution plan is in
> [docs/plans/2026-09-21-arc-morpho-vault-design.md](./docs/plans/2026-09-21-arc-morpho-vault-design.md).

## Build & test

```bash
git clone --recurse-submodules https://github.com/Foryield/arc-yield-vault.git
forge build
forge test
```

## Contributions

This repository is published read-only: issues and pull requests from outside
the ForYield team are not accepted.

## License

[MIT](./LICENSE)
