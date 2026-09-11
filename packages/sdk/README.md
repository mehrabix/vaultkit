# @vaultkit/sdk

Framework-free, [viem](https://viem.sh)-based SDK for VaultKit. No React dependency — hooks live in
`@vaultkit/react`.

- **Typed end to end.** ABIs are generated from the Foundry artifacts (`pnpm codegen`); token
  amounts are always `bigint`; times are always Unix seconds.
- **Reads need nothing but an RPC.** `getSchedule`, `getScheduleView`, `claimableAmount`.
- **Writes simulate first.** `createSchedule`, `claim`, `revoke` run `simulateContract` before
  sending, so you get a revert reason instead of a failed transaction.
- **Lists are indexer-backed and fail loudly.** `listSchedules` throws `IndexerUnavailableError`
  rather than silently returning `[]` when the indexer is missing.

## Install

```bash
pnpm add @vaultkit/sdk viem
```

## Usage

```ts
import { VaultKit, parseDuration } from '@vaultkit/sdk'
import { base } from 'viem/chains'
import { http, parseUnits } from 'viem'

const vk = new VaultKit({
  chain: base,
  transport: http(),
  account: '0xYourAddress', // required only for writes
  factoryAddress: '0x…',
  indexerUrl: 'https://indexer.vaultkit.xyz', // required only for lists
})

// Write
const { wallet, hash, schedule } = await vk.createSchedule({
  token: '0x…',
  beneficiary: '0x…',
  start: new Date(),
  cliff: '6 months',
  duration: '2 years',
  amount: parseUnits('100000', 18),
  revocable: true,
})

// Read
const view = await vk.getScheduleView(wallet)
view.claimableAmount // 1234567890000000000n
view.percentVested // 12.5
view.nextUnlockAt // 1751328000 (Unix seconds) | null
view.status // 'pending' | 'cliff' | 'vesting' | 'fully-vested' | 'revoked'

// List (indexer)
const mine = await vk.listSchedules({ beneficiary: '0x…' })

// Act
await vk.claim(wallet)
```

## Durations

`parseDuration` accepts single units, compounds, and raw seconds:

```ts
parseDuration('18w') // 10886400
parseDuration('6 months') // 15552000
parseDuration('1y 6mo') // 47304000
parseDuration(604800) // 604800
```

`m` is **minutes**; use `mo` for months. A month is 30 days and a year is 365 days — the same
convention the dashboard presets use.

## API

| Method | Needs | Returns |
| --- | --- | --- |
| `getSchedule(address)` | RPC | `Promise<Schedule>` |
| `getScheduleView(address, at?)` | RPC | `Promise<ScheduleView>` |
| `claimableAmount(address)` | RPC | `Promise<bigint>` (on-chain read) |
| `vestedAmount(address, at?)` | RPC | `Promise<bigint>` (mirrored math) |
| `createSchedule(params)` | account + factory | `Promise<{ wallet, hash, schedule }>` |
| `simulateClaim(address)` | account | simulation result |
| `claim(address)` | account | `Promise<Hash>` |
| `revoke(address)` | account | `Promise<Hash>` |
| `reassignBeneficiary(address, newBeneficiary)` | account | `Promise<Hash>` |
| `listSchedules(query)` | indexer | `Promise<Schedule[]>` |
| `listScheduleViews(query, at?)` | indexer | `Promise<ScheduleView[]>` |

Pure helpers (`vestedAmountAt`, `percentVested`, `scheduleStatus`, `nextUnlockAt`, `toScheduleView`)
are exported too, so a chart can compute a curve without touching the network.

## Time convention

Every `Schedule` / `ScheduleView` field that represents a moment is **Unix seconds** (`number`), not
a `Date`. This keeps the objects JSON-friendly and indexer-compatible; convert at the edge with
`new Date(seconds * 1000)`.

## Development

```bash
pnpm --filter @vaultkit/contracts build   # produce artifacts first
pnpm --filter @vaultkit/sdk codegen       # regenerate ABIs from out/
pnpm --filter @vaultkit/sdk test
pnpm --filter @vaultkit/sdk build
```
