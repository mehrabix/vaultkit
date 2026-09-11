# packages/indexer — not implemented yet

Reserved for the Ponder indexer (milestone **M4**).

Planned surface:

- **Events indexed:** `ScheduleCreated`, `Claimed`, `Revoked`, `BeneficiaryReassigned`
- **Tables:** `schedules`, `claims`, `beneficiaries`, `tokens`
- **API:** `GET /schedules?beneficiary=0x…&chain=8453` — the exact contract
  [`IndexerClient`](../sdk/src/indexer.ts) in the SDK already speaks and is tested against.

Until this exists, `VaultKit.listSchedules` throws `IndexerUnavailableError`; single-schedule reads
(`getSchedule`, `getScheduleView`, `claimableAmount`) work entirely from RPC and need no indexer.

The factory emits everything the indexer needs — the event ABI is available today via
`@vaultkit/sdk`'s generated `vaultKitFactoryAbi`.
