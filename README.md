# VaultKit

> **Vesting that anyone can verify.**

Token vesting and escrow infrastructure. One Solidity wallet per schedule, a typed SDK, and a
dashboard that makes a vesting curve legible in five seconds.

---

## The problem

Every token project needs vesting, and almost nobody builds it well.

- **Hand-rolled contracts** copy-paste a 2021 `TokenVesting.sol`, ship without cliff-math tests, and
  hold every schedule's funds in a single address — one bug drains all of it.
- **Spreadsheets and multisigs** require trusting an operator to send the right amount on the right
  date. Beneficiaries have zero visibility.
- **Beneficiaries are blind.** They cannot answer "how much can I claim right now?" without asking
  the team.
- **Integrators have no API.** Wallets, launchpads, and DAOs that want to show vesting have to write
  their own indexer.

VaultKit standardizes the primitive: **isolation of funds, verifiable math, and a typed interface.**

---

## The guarantees

Four properties define the product. Each one is enforced by tests, not copy.

1. **Isolation.** Every schedule is its own contract with its own token balance. A failure in one
   schedule cannot touch another's funds.
2. **Provable math.** Fuzz and invariant tests assert `claimable <= vested <= total` for all inputs.
3. **No privileged key.** The creator can revoke *only* the unvested remainder. Vested tokens are
   untouchable, forever.
4. **Typed interface.** Generated ABIs, `bigint` amounts, discriminated results — no `any` at the
   boundary.

---

## Architecture

```
                          createVestingSchedule()
   Founder ───────────────────────────────────────▶ VaultKitFactory
                                                          │
                                            Clones.clone()│  (EIP-1167 minimal proxy)
                                                          ▼
                            ┌─────────────────── VestingWallet (one per schedule) ───────────────┐
                            │  holds exactly one token, one beneficiary, one cliff/duration      │
                            └────────────────────────────────────────────────────────────────────┘
                                                          │
                                              claim() / revoke() / reassignBeneficiary()
                                                          ▼
                                              Beneficiary  /  Creator

   VestingWallet events ──▶ Ponder indexer ──▶ Postgres ──▶ SDK .listSchedules()
                                                                  │
                                                                  ▼
                                                        @vaultkit/react ──▶ Dashboard
```

**Why clones?** Each schedule gets its own address and its own token balance. Isolation is a
security property, not a nicety. The implementation is deployed once, never upgraded, and clones are
cheap.

**Why an indexer?** On-chain enumeration of "everything for this beneficiary" is not feasible with a
factory + clones. Ponder subscribes to events, which is also the integration surface for wallets and
launchpads. The SDK's read path works without it — the indexer only powers *list* queries.

---

## Vesting math

Linear vesting with a cliff. `t` is a Unix timestamp in seconds.

```
if      t <  start + cliff        vested = 0
else if t >= start + duration     vested = total
else                              vested = total * (t - start) / duration
```

`claimable = vested - claimed`.

The cliff gates *when vesting begins*, not what has accrued. At `t = start + cliff` the beneficiary
immediately holds a claim on `total * cliff / duration` — the standard investor-cliff behavior.
Division floors toward zero and is computed with `Math.mulDiv` so the intermediate product can never
overflow.

---

## Repository layout

```
vaultkit/
├── apps/
│   └── web/                 # Next.js dashboard (planned, M5)
├── packages/
│   ├── contracts/           # Foundry project — the product
│   ├── sdk/                 # @vaultkit/sdk   — viem-based, framework-free
│   ├── react/               # @vaultkit/react — wagmi hooks on top of the SDK
│   ├── indexer/             # Ponder indexer + API (planned, M4)
│   └── config/              # shared tsconfig / prettier
├── examples/
│   └── create-schedule/     # ~40-line script showing SDK usage
└── .github/workflows/ci.yml
```

---

## Quickstart

### Contracts

```bash
cd packages/contracts
forge build
forge test
```

Requires [Foundry](https://book.getfoundry.sh/getting-started/installation). Dependencies are git
submodules — after a fresh clone run `git submodule update --init --recursive`.

### JavaScript

```bash
pnpm install
pnpm build
pnpm test
```

### Create a schedule

```ts
import { VaultKit } from '@vaultkit/sdk'
import { base } from 'viem/chains'
import { http, parseUnits } from 'viem'

const vk = new VaultKit({
  chain: base,
  transport: http(),
  account: '0xYourAddress',
  factoryAddress: '0x…',
  indexerUrl: 'https://indexer.vaultkit.xyz', // only needed for list queries
})

const { wallet, hash } = await vk.createSchedule({
  token: '0x…',
  beneficiary: '0x…',
  start: new Date(),
  cliff: '6 months',
  duration: '2 years',
  amount: parseUnits('100000', 18),
  revocable: true,
})

const view = await vk.getScheduleView(wallet)
view.claimableAmount // 1234567890000000000n
view.percentVested // 12.5
view.nextUnlockAt // 1751328000 | null
```

A runnable version lives in [`examples/create-schedule`](./examples/create-schedule).

---

## Security model

| Property | Guarantee |
| --- | --- |
| Fund isolation | One clone per schedule; balance never shared |
| Revocation | Returns `total - vested` to the creator only; vested stays claimable forever |
| Reentrancy | `claim` / `revoke` guarded; `claimed` written before transfer |
| Fee-on-transfer / rebasing | Rejected at funding time — wallet balance must increase by exactly `amount` |
| Clone hijack | Implementation is init-disabled in its constructor; clones initialize exactly once |
| Factory pause | Stops *new* schedules only — existing schedules are unstoppable by design |
| Timestamps | No sub-minute-dependent logic; validator drift is documented and tolerated |

**Trust assumptions.** The creator trusts no one — they retain revoke/reassign rights and their
unvested remainder is always reclaimable. The beneficiary trusts no one — the math is deterministic,
the funds sit in the schedule's own contract, and no admin key can move vested tokens. The factory
owner can pause new schedule creation and nothing else.

Full write-up, including deviations and known limitations:
[`packages/contracts/SPEC.md`](./packages/contracts/SPEC.md).

---

## Status

| Milestone | Scope | State |
| --- | --- | --- |
| **M0** | Monorepo, shared config, CI skeleton, license | ✅ done |
| **M1** | `VestingWallet` + unit/fuzz/invariant suite, gas snapshot, SPEC | ✅ done |
| **M2** | `VaultKitFactory`, `VaultKitRegistry`, clones, deploy script | ✅ done |
| **M3** | `@vaultkit/sdk` — codegen, duration parser, simulate, indexer fallback | ✅ done |
| **M4** | Ponder indexer + public API | ⬜ planned |
| **M5** | Dashboard (landing, dashboard, detail, create wizard, verify page) | ⬜ planned |
| **M6** | Slither/Aderyn clean, docs site, public testnet deploy | ⬜ planned |

62 contract tests (unit + fuzz + invariants) and 25 SDK tests pass today.

---

## Commands

| Command | What it does |
| --- | --- |
| `pnpm build` | Build every package (Turborepo, cached) |
| `pnpm test` | `forge test` + `vitest` across the workspace |
| `pnpm typecheck` | `tsc --noEmit` in every TypeScript package |
| `pnpm lint` | Lint checks across the workspace |
| `pnpm --filter @vaultkit/sdk codegen` | Regenerate ABIs from the Foundry artifacts |
| `forge test --fuzz-runs 4096` | Heavier fuzzing |

CI runs `forge fmt --check`, the full contract suite, ABI-drift detection, typecheck, tests and
build on every push and pull request.

---

## Contributing

The contract is the product; everything else is packaging. Changes to `packages/contracts` should
come with tests at the appropriate level (unit for boundaries, fuzz for math, invariant for
accounting) and a re-run of `forge snapshot`.

---

## License

MIT for the contracts, SDK, and indexer — this is the adoption engine. The hosted dashboard is a
separate, commercial offering. See [LICENSE](./LICENSE).
