import { describe, expect, it } from 'vitest'

import { nextUnlockAt, percentVested, scheduleStatus, toScheduleView, vestedAmountAt } from '../src/math.js'
import type { Schedule } from '../src/types.js'

const ZERO = '0x0000000000000000000000000000000000000000' as const
const START = 1_000_000
const CLIFF = 30 * 86_400
const DURATION = 365 * 86_400
const TOTAL = 1_000_000n * 10n ** 18n

const schedule: Schedule = {
  address: ZERO,
  chainId: 8453,
  token: ZERO,
  beneficiary: ZERO,
  creator: ZERO,
  start: START,
  cliff: CLIFF,
  duration: DURATION,
  totalAmount: TOTAL,
  claimed: 0n,
  revocable: true,
  revoked: false,
  revokedAt: null,
}

describe('vestedAmountAt', () => {
  it('is zero before the schedule starts', () => {
    expect(vestedAmountAt(schedule, START - 1)).toBe(0n)
  })

  it('is zero through the cliff', () => {
    expect(vestedAmountAt(schedule, START + CLIFF - 1)).toBe(0n)
  })

  it('credits elapsed time once the cliff passes', () => {
    expect(vestedAmountAt(schedule, START + CLIFF)).toBe((TOTAL * BigInt(CLIFF)) / BigInt(DURATION))
  })

  it('is half at the midpoint and full at the end', () => {
    expect(vestedAmountAt(schedule, START + DURATION / 2)).toBe(TOTAL / 2n)
    expect(vestedAmountAt(schedule, START + DURATION)).toBe(TOTAL)
    expect(vestedAmountAt(schedule, START + DURATION * 10)).toBe(TOTAL)
  })

  it('freezes at the revoke time', () => {
    const revokedAt = START + DURATION / 2
    expect(vestedAmountAt({ ...schedule, revokedAt }, START + DURATION)).toBe(TOTAL / 2n)
  })

  it('is monotonic', () => {
    let previous = 0n
    for (let elapsed = 0; elapsed <= DURATION; elapsed += 7 * 86_400) {
      const vested = vestedAmountAt(schedule, START + elapsed)
      expect(vested >= previous).toBe(true)
      previous = vested
    }
  })
})

describe('percentVested', () => {
  it('reports 0, 50 and 100 at the obvious points', () => {
    expect(percentVested(0n, TOTAL)).toBe(0)
    expect(percentVested(TOTAL / 2n, TOTAL)).toBe(50)
    expect(percentVested(TOTAL, TOTAL)).toBe(100)
  })

  it('keeps two decimals', () => {
    expect(percentVested(TOTAL / 8n, TOTAL)).toBe(12.5)
  })

  it('is zero when the total is zero', () => {
    expect(percentVested(0n, 0n)).toBe(0)
  })
})

describe('toScheduleView', () => {
  it('derives claimable, remaining and dates', () => {
    const at = START + DURATION / 2
    const view = toScheduleView(schedule, at)

    expect(view.vestedAmount).toBe(TOTAL / 2n)
    expect(view.claimableAmount).toBe(TOTAL / 2n)
    expect(view.remainingAmount).toBe(TOTAL - TOTAL / 2n)
    expect(view.percentVested).toBe(50)
    expect(view.cliffAt).toBe(START + CLIFF)
    expect(view.fullyVestedAt).toBe(START + DURATION)
    expect(view.status).toBe('vesting')
    expect(view.nextUnlockAt).toBe(START + DURATION)
  })

  it('subtracts what has already been claimed', () => {
    const at = START + DURATION
    const view = toScheduleView({ ...schedule, claimed: TOTAL / 4n }, at)
    expect(view.vestedAmount).toBe(TOTAL)
    expect(view.claimableAmount).toBe(TOTAL - TOTAL / 4n)
  })
})

describe('scheduleStatus', () => {
  it('walks through pending -> cliff -> vesting -> fully-vested', () => {
    expect(scheduleStatus(schedule, START - 1)).toBe('pending')
    expect(scheduleStatus(schedule, START + 1)).toBe('cliff')
    expect(scheduleStatus(schedule, START + CLIFF + 1)).toBe('vesting')
    expect(scheduleStatus(schedule, START + DURATION)).toBe('fully-vested')
  })

  it('reports revoked regardless of time', () => {
    expect(scheduleStatus({ ...schedule, revoked: true }, START + CLIFF + 1)).toBe('revoked')
  })
})

describe('nextUnlockAt', () => {
  it('points at the cliff first, then the end, then nothing', () => {
    expect(nextUnlockAt(schedule, START)).toBe(START + CLIFF)
    expect(nextUnlockAt(schedule, START + CLIFF + 1)).toBe(START + DURATION)
    expect(nextUnlockAt(schedule, START + DURATION)).toBeNull()
    expect(nextUnlockAt({ ...schedule, revoked: true }, START)).toBeNull()
  })
})
