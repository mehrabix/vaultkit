# VaultKit Contracts — Specification

This document is the source of truth for the on-chain behavior of VaultKit. It defines the vesting
math, the state machine, the security properties the tests enforce, and the design decisions behind
the implementation.

---

## 1. System

Three contracts, one impl:

| Contract | Role | Deployed how |
| --- | --- | --- |
| `VestingWallet` | One schedule. Holds exactly one token. | Deployed once as an implementation; every schedule is an EIP-1167 minimal proxy (`Clones.clone`) of it. |
| `VaultKitFactory` | Creates and funds wallets, emits canonical events. | Deployed once per chain, `Ownable2Step` + `Pausable`. |
| `VaultKitRegistry` | Append-only list of factory versions. | Deployed once per chain, `Ownable`. |

**Non-upgradeable by design.** The `VestingWallet` implementation is never replaced. A schedule's
terms are fixed at initialization; only the beneficiary can move (`reassignBeneficiary`) and only
before revocation.

---

## 2. Vesting math

Linear vesting with a cliff. `t` is a Unix timestamp in seconds.

```
if      t <  start + cliff        vested = 0
else if t >= start + duration     vested = total
else                              vested = total * (t - start) / duration
```

Key properties:

- **The cliff gates when vesting *begins*, not what has accrued.** At `t = start + cliff` the
  beneficiary immediately has a claim on `total * cliff / duration` — the standard investor-cliff
  behavior.
- **Floor division.** `total * (t - start) / duration` truncates toward zero, computed with
  OpenZeppelin's `Math.mulDiv` so the intermediate product can never overflow.
- **Monotonic.** `vested` is non-decreasing in `t` until a revoke, after which it is frozen.
- `claimable = vested - claimed`.

Validation at initialization:

| Rejected | Error |
| --- | --- |
| `token`, `beneficiary`, or `creator` is zero | `ZeroAddress` |
| `totalAmount == 0` | `ZeroAmount` |
| `duration == 0` | `InvalidDuration` |
| `cliff > duration` | `CliffExceedsDuration` |

`start` may be in the past (retroactive schedules are legitimate) or the future. There is no
sub-minute precision anywhere in the contract; validator drift of a few seconds is tolerated.

---

## 3. State machine

```
                 initialize()             claim()  (beneficiary, any time)
   UNINITIALIZED ─────────────▶ ACTIVE ─────────────────────────────▶ ACTIVE
                                  │
                                  │ revoke()  (creator, if revocable)
                                  ▼
                              REVOKED ─── claim() still allowed for the vested remainder
                                  ▲
                                  └── reassignBeneficiary() is blocked once revoked
```

`initialize()` is callable exactly once (OpenZeppelin `Initializable`). The implementation contract
is `_disableInitializers()`-ed in its constructor, so the un-cloned implementation can never be
initialized or used to hijack a clone.

---

## 4. Function reference

### `VestingWallet`

| Function | Access | Effect |
| --- | --- | --- |
| `initialize(...)` | anyone, once | Stores the schedule. Called by the factory in the same tx as funding. |
| `schedule()` | view | Full `Schedule` struct. |
| `vestedAmount(uint64 t)` | view | Vested at `t` (capped at `revokedAt` if revoked). |
| `vestedAmount()` | view | Vested at `block.timestamp`. |
| `claimableAmount()` | view | `vested - claimed`. |
| `claim()` | beneficiary | Transfers `claimableAmount()`, then adds it to `claimed`. |
| `revoke()` | creator, revocable, once | Freezes vesting, returns `total - vested` to the creator. |
| `reassignBeneficiary(address)` | creator, pre-revoke | Moves the beneficiary position. |
| `token() / beneficiary() / creator()` | view | Convenience getters for indexers and SDKs. |

`claim()` reverts with `NothingToClaim` when `claimable == 0`. `revoke()` reverts with
`NotCreator`, `NotRevocable`, or `AlreadyRevoked`.

### `VaultKitFactory`

| Function | Access | Effect |
| --- | --- | --- |
| `createVestingSchedule(token, beneficiary, start, cliff, duration, amount, revocable)` | anyone | Clones, initializes, pulls `amount` from the caller, and verifies the wallet was funded by exactly `amount`. Emits `ScheduleCreated`. |
| `pause() / unpause()` | owner | Stops/starts **new** schedules only. |
| `implementation()` | view | The implementation all clones point at. |
| `isSchedule(address)` | view | True for wallets this factory created. |
| `scheduleCount()` | view | Number of schedules created. |

### `VaultKitRegistry`

`registerFactory(address, string label)` (owner only, one-way), plus `factoryCount()`,
`factoryAt(uint256)`, `latestFactory()`, `allFactories()`, `isFactory(address)`.

---

## 5. Security properties (what the tests assert)

1. **Fund isolation.** Each schedule has its own address and its own balance. Revoking schedule A
   leaves schedule B's balance and vesting untouched (`test_SchedulesAreIsolated`).
2. **Solvency.** `walletBalance + claimed + returnedToCreator == total`, across arbitrary
   claim / revoke / reassign / time sequences (`invariant_Solvency`).
3. **Bounds.** `claimable <= vested <= total` always (`invariant_VestedWithinBounds`,
   `testFuzz_Claimable_NeverExceedsVested`).
4. **No privileged drain.** The creator can only ever receive `total - vested` at revoke time.
   Vested-but-unclaimed tokens remain claimable by the beneficiary forever
   (`test_Revoke_VestedStaysClaimableForever`).
5. **Reentrancy.** `claim` and `revoke` are `nonReentrant` and update `claimed` **before** any
   transfer; a token that tries to re-enter `claim()` is rejected
   (`test_Claim_ReentrantCallIsRejected`).
6. **No under-funding.** Fee-on-transfer / rebasing tokens that deliver less than `amount` are
   rejected at funding time: the transaction reverts and no schedule exists
   (`test_Create_RevertsOnFeeOnTransferToken`).
7. **Clone hijack resistance.** The implementation cannot be initialized; a clone can be
   initialized exactly once (`test_Implementation_IsInitDisabled`, `test_Initialize_CannotRunTwice`).
8. **Pausing is limited.** `pause()` blocks new schedules and cannot touch existing ones
   (`test_Pause_DoesNotBlockExistingSchedules`).

### Trust assumptions

- The **creator** trusts no one: they retain revoke/reassign rights and their unvested remainder is
  always reclaimable.
- The **beneficiary** trusts no one: the vesting math is deterministic, the balance is held by the
  schedule's own contract, and no admin key can move vested tokens.
- The **implementation and factory owner** can only pause *new* schedule creation. They cannot
  touch funds, alter terms, or block claims.

---

## 6. Deployment order

```
1. VestingWallet (implementation)      ← constructor disables initializers
2. VaultKitFactory(implementation, owner)
3. VaultKitRegistry(owner)
4. registry.registerFactory(factory, "v1")
```

See [`script/Deploy.s.sol`](./script/Deploy.s.sol).

---

## 7. Design decisions and deviations

| Change | Why |
| --- | --- |
| `Schedule` has an extra `uint64 revokedAt` field | Needed to freeze `vested` at the revoke instant. Without it, tokens already returned to the creator would keep accruing as vested and become claimable — a real bug. |
| `cliff > duration` is rejected | Makes the linear branch unreachable and the accounting ambiguous. |
| Uses OZ `ReentrancyGuard` (not `ReentrancyGuardUpgradeable`) | OZ ≥ 5.5 made `ReentrancyGuard` stateless (ERC-7201 slot) and removed the upgradeable variant; it is clone-safe as-is. |
| `Initializable` imported from `@openzeppelin/contracts` | In OZ 5.7 the upgradeable package only re-exports it; the real contract lives in the base package. This drops a whole git subtree dependency. |
| No `Ownable` on `VestingWallet` | Creator-only actions are a direct `creator` address check — cheaper than an ownership module and it keeps the creator role explicit in the `Schedule` struct. |

---

## 8. Known limitations

- **Enumeration is off-chain.** A factory + clones cannot enumerate "all schedules for beneficiary
  X" on-chain. That is the indexer's job; the SDK degrades to single-address reads.
- **Single token per schedule.** Multi-token portfolios are a non-goal for v1.
- **No upgrade path.** Terms are immutable; a mistake requires a new schedule.
- **Rebasing tokens.** The funding check guarantees the wallet receives exactly `amount` at creation.
  A token that later rebases changes the wallet's balance; claims are still capped at `total`, but
  the final claims from a rebasing token are not guaranteed to succeed. Such tokens should be
  excluded by policy.
