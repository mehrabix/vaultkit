import type { Schedule, ScheduleStatus, ScheduleView } from './types.js'

/** The minimal terms needed to evaluate vesting — matches the Solidity contract exactly. */
export interface VestingTerms {
  totalAmount: bigint
  /** Unix seconds. */
  start: number
  /** Seconds. */
  cliff: number
  /** Seconds. */
  duration: number
  /** Unix seconds, or `null`/`undefined` when not revoked. */
  revokedAt?: number | null
}

export function nowSeconds(): number {
  return Math.floor(Date.now() / 1000)
}

/**
 * Mirrors `VestingWallet.vestedAmount(t)`: linear, cliff-gated, floored, and frozen at `revokedAt`
 * once revoked. Kept in lockstep with the Solidity by the math tests.
 */
export function vestedAmountAt(terms: VestingTerms, at: number): bigint {
  const time = Math.floor(at)
  const capped =
    terms.revokedAt != null && time > terms.revokedAt ? Math.floor(terms.revokedAt) : time

  if (capped < terms.start + terms.cliff) return 0n
  if (capped >= terms.start + terms.duration) return terms.totalAmount

  return (terms.totalAmount * BigInt(capped - terms.start)) / BigInt(terms.duration)
}

/** Vested share as a percentage (0–100) with two decimals of precision. */
export function percentVested(vested: bigint, total: bigint): number {
  if (total <= 0n) return 0
  return Number((vested * 1_000_000n) / total) / 10_000
}

export function scheduleStatus(schedule: Schedule, at: number): ScheduleStatus {
  if (schedule.revoked) return 'revoked'
  if (at < schedule.start) return 'pending'
  if (at < schedule.start + schedule.cliff) return 'cliff'
  if (at < schedule.start + schedule.duration) return 'vesting'
  return 'fully-vested'
}

export function nextUnlockAt(schedule: Schedule, at: number): number | null {
  if (schedule.revoked) return null
  if (at < schedule.start + schedule.cliff) return schedule.start + schedule.cliff
  if (at < schedule.start + schedule.duration) return schedule.start + schedule.duration
  return null
}

/** Derives every display value a dashboard needs from raw on-chain state. */
export function toScheduleView(schedule: Schedule, at: number = nowSeconds()): ScheduleView {
  const vested = vestedAmountAt(schedule, at)
  const claimable = vested > schedule.claimed ? vested - schedule.claimed : 0n

  return {
    ...schedule,
    vestedAmount: vested,
    claimableAmount: claimable,
    remainingAmount: schedule.totalAmount - vested,
    percentVested: percentVested(vested, schedule.totalAmount),
    cliffAt: schedule.start + schedule.cliff,
    fullyVestedAt: schedule.start + schedule.duration,
    nextUnlockAt: nextUnlockAt(schedule, at),
    status: scheduleStatus(schedule, at),
  }
}
