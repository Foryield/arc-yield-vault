# A2: USDC from Base Sepolia to Arc testnet with CCTP v2

Route: Base Sepolia (CCTP domain 6, chain id 84532) to Arc testnet (CCTP domain 26, chain id
5042002). Script: `scripts/cctp/base-sepolia-to-arc.ts`. Contracts, identical on both chains:
TokenMessengerV2 `0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA`, MessageTransmitterV2
`0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275`. Attestation service: Circle Iris sandbox.

Account: `arc-depositor` `0x91405144F7ac4E9CcC26C32fbc475535d6110837`, sender on Base Sepolia and
recipient on Arc testnet.

## 2026-09-21: burn on Base Sepolia, mint pending on a Circle outage

- **What it proves (so far)**: the burn half of a CCTP v2 Fast Transfer to Arc, with an exact
  approval fully consumed by the burn. The mint half is blocked on Circle's side, see below.
- **Approve 1 USDC** to TokenMessengerV2:
  [`0xeddb858f…8696`](https://base-sepolia.blockscout.com/tx/0xeddb858f79182519029e3b6d7892f284f5e8676255cbe801691fc62ec74b8696)
  (block 47116433, 14:32:34 UTC).
- **depositForBurn 1 USDC** to domain 26, recipient `arc-depositor`, `maxFee` 0.000130 USDC
  (1.3 basis points, the Fast Transfer fee published by Iris for this route),
  `minFinalityThreshold` 1000:
  [`0xe9137539…75d7`](https://base-sepolia.blockscout.com/tx/0xe913753935d3286a361f930e89688f81190d3d3fbb54f8fb13cd72057a1675d7)
  (block 47116434, 14:32:36 UTC, 109,103 gas).
- **Emitted message**, decoded from the `MessageSent` log: version 1, source domain 6,
  destination domain 26, minimum finality threshold 1000.
- **Post-state on Base Sepolia**: allowance of `arc-depositor` to TokenMessengerV2 back to `0`,
  USDC balance down by exactly 1 USDC.
- **Attestation not issued**: Iris sandbox answered `Message not found` for this burn for over
  ten minutes, and equally for two other users' Base Sepolia burns from 14:00 and 14:09 UTC.
  Circle's status page reported "Circle CCTP - Sandbox" and "Circle Cross-Chain Transfer
  Protocol" in major outage at 14:44 UTC. The burn remains mintable once attested:
  `BURN_TX=0xe913…75d7 node scripts/cctp/base-sepolia-to-arc.ts` resumes at the attestation
  step and relays `receiveMessage` on Arc.
