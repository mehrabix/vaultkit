import type { Address, Hash } from 'viem'

/** A human duration: `'6 months'`, `'18w'`, `'90d'`, or a raw number of seconds. */
export type DurationInput = string | number | bigint

/** Raw on-chain schedule state. All times are Unix seconds. */
export interface Schedule {
  /** Address of the VestingWallet clone. */
  readonly address: Address
  readonly chainId: number
  readonly token: Address
  readonly beneficiary: Address
  readonly creator: Address
  /** Vesting start, Unix seconds. */
  readonly start: number
  /** Seconds after `start` before anything vests. */
  readonly cliff: number
  /** Seconds after `start` until fully vested. */
  readonly duration: number
  readonly totalAmount: bigint
  readonly claimed: bigint
  readonly revocable: boolean
  readonly revoked: boolean
  /** Revocation time in Unix seconds, or `null` if not revoked. */
  readonly revokedAt: number | null
}

export type ScheduleStatus = 'pending' | 'cliff' | 'vesting' | 'fully-vested' | 'revoked'

/** A `Schedule` enriched with derived, display-ready values. */
export interface ScheduleView extends Schedule {
  readonly vestedAmount: bigint
  readonly claimableAmount: bigint
  /** `totalAmount - vestedAmount`; what the creator reclaims on revoke. */
  readonly remainingAmount: bigint
  /** 0–100, to two decimal places. */
  readonly percentVested: number
  /** `start + cliff`, Unix seconds. */
  readonly cliffAt: number
  /** `start + duration`, Unix seconds. */
  readonly fullyVestedAt: number
  /** Next date worth showing a user, Unix seconds, or `null` if there is none. */
  readonly nextUnlockAt: number | null
  readonly status: ScheduleStatus
}

export interface CreateScheduleParams {
  token: Address
  beneficiary: Address
  /** Unix seconds. Defaults to now. */
  start?: Date | number
  /** Defaults to 0 (no cliff). */
  cliff?: DurationInput
  duration: DurationInput
  amount: bigint
  /** Defaults to `false`. */
  revocable?: boolean
}

export interface CreateScheduleResult {
  /** Address of the newly deployed VestingWallet clone. */
  wallet: Address
  hash: Hash
  schedule: Schedule
}

export interface ListSchedulesQuery {
  beneficiary?: Address
  creator?: Address
  token?: Address
  chainId?: number
}
