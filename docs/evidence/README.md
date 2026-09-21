# Reviewer evidence log

One file per deliverable. Every proof is recorded **the day it is produced**, not
reconstructed at submission time. Entries are append-only: a later redeployment gets a new
dated entry, and earlier entries stay as dated records.

| File | Deliverable |
|---|---|
| `a1-vault-testnet.md` | MorphoYieldVault on Arc testnet: USDC and EURC instances, deposit and redemption |
| `a2-cctp.md` | USDC moved from Base Sepolia to Arc testnet with CCTP v2 |
| `screenshots/` | PNG captures per Circle product, for the grant video |

Each entry records:

- **Date** (UTC)
- **What it proves** (one line)
- **Transaction hash** + [Arc testnet explorer](https://explorer.testnet.arc.io) link, when on-chain
- **Contract address**, when a (re)deployment, with its source verification status
- **Commit** of this repository the bytecode was built from
- **Media** (screenshot) path, when visual

Nothing sensitive belongs here: testnet only, public addresses only.
