# Screenshots for the grant video

One or two PNG files per Circle product, named by product, showing where it lives in the code
and where it shows up on chain. Files land in this folder; each row below says what to frame.

| File | Product | What to frame |
|---|---|---|
| `arc-usdc-code.png` | USDC on Arc | `script/Deploy.s.sol`: the `USDC` constant `0x3600…0000` passed as the vault asset |
| `arc-usdc-deposit.png` | USDC on Arc | Explorer, deposit tx [`0x200c9635…6e88`](https://explorer.testnet.arc.io/tx/0x200c9635f567da9a31cdcbeb8de8e75de5fcba2ae6b9944bb43dea4ccd006e88): USDC moving from the depositor to the vault, then to the Morpho target |
| `arc-usdc-gas.png` | Arc (USDC as gas) | Explorer, same tx: the fee field denominated in USDC |
| `arc-eurc-code.png` | EURC on Arc | `script/Deploy.s.sol`: the `EURC` constant and the fyEURC instance |
| `arc-eurc-deposit.png` | EURC on Arc | Explorer, deposit tx [`0x3f30e905…c14c`](https://explorer.testnet.arc.io/tx/0x3f30e9050fc69c616eed8f10d6c9ccd625ade5eb1f3bdcd342c448c498a1c14c) |
| `cctp-code.png` | CCTP v2 | `scripts/cctp/base-sepolia-to-arc.ts`: `depositForBurn` to domain 26 and `receiveMessage` on Arc |
| `cctp-burn.png` | CCTP v2 | Base Sepolia explorer, burn tx [`0xe9137539…75d7`](https://base-sepolia.blockscout.com/tx/0xe913753935d3286a361f930e89688f81190d3d3fbb54f8fb13cd72057a1675d7) |
| `cctp-mint.png` | CCTP v2 | Arc explorer, mint tx [`0x761c159a…57b2`](https://explorer.testnet.arc.io/tx/0x761c159a0ee845c36b94dcdbe18f3a6a6bafec62a04e3d6fbe56f69affe757b2): 0.999870 USDC minted to the depositor |
| `morpho-code.png` | Morpho on Arc | `src/MorphoYieldVault.sol`: `_transferIn` supplying the exact amount to the Morpho Vault V2 |
| `vault-verified.png` | Arc | Explorer page of the USDC vault showing the verified source |
| `mainnet-fork-test.png` | Morpho on Arc mainnet | Terminal output of the fork test against Galaxy USDC, passing |

Planned products (StableFX, Gateway) have no code yet: the video shows them on an
architecture slide, not here. The Stellar EURC vault lives in `Foryield/soroban-yield-vault`
and is captured from that repository.
