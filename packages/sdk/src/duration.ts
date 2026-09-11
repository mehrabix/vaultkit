import { InvalidDurationError } from './errors.js'
import type { DurationInput } from './types.js'

const SECOND = 1
const MINUTE = 60 * SECOND
const HOUR = 60 * MINUTE
const DAY = 24 * HOUR
const WEEK = 7 * DAY
const MONTH = 30 * DAY
const YEAR = 365 * DAY

/** `m` is *minutes*; use `mo` for months. */
const UNITS: Record<string, number> = {
  s: SECOND,
  sec: SECOND,
  secs: SECOND,
  second: SECOND,
  seconds: SECOND,
  m: MINUTE,
  min: MINUTE,
  mins: MINUTE,
  minute: MINUTE,
  minutes: MINUTE,
  h: HOUR,
  hr: HOUR,
  hrs: HOUR,
  hour: HOUR,
  hours: HOUR,
  d: DAY,
  day: DAY,
  days: DAY,
  w: WEEK,
  week: WEEK,
  weeks: WEEK,
  mo: MONTH,
  month: MONTH,
  months: MONTH,
  y: YEAR,
  yr: YEAR,
  yrs: YEAR,
  year: YEAR,
  years: YEAR,
}

const PART = /(\d+(?:\.\d+)?)\s*([a-z]+)/g

/**
 * Parses a human duration into whole seconds.
 *
 * Supported inputs: `'6 months'`, `'18w'`, `'90d'`, `'1y 6mo'`, `'36h'`, `90` (seconds),
 * `604800n` (seconds as a bigint). Whitespace between parts is required.
 */
export function parseDuration(input: DurationInput): number {
  if (typeof input === 'bigint') return check(Number(input), input)

  if (typeof input === 'number') return check(Math.round(input), input)

  const text = input.trim().toLowerCase()
  if (text === '') throw new InvalidDurationError('Duration is empty')

  // A bare number is seconds.
  if (/^\d+(?:\.\d+)?$/.test(text)) return check(Math.round(Number(text)), input)

  let total = 0
  let cursor = 0
  let parts = 0

  for (const match of text.matchAll(PART)) {
    const index = match.index ?? 0
    if (text.slice(cursor, index).trim() !== '') {
      throw new InvalidDurationError(`Could not parse duration: "${input}"`)
    }
    cursor = index + match[0].length

    const value = Number(match[1])
    const unit = match[2]!
    const multiplier = UNITS[unit]
    if (multiplier === undefined) {
      throw new InvalidDurationError(`Unknown duration unit "${unit}" in "${input}"`)
    }

    total += value * multiplier
    parts += 1
  }

  if (parts === 0 || text.slice(cursor).trim() !== '') {
    throw new InvalidDurationError(`Could not parse duration: "${input}"`)
  }

  return check(Math.round(total), input)
}

function check(seconds: number, input: DurationInput): number {
  if (!Number.isFinite(seconds) || seconds <= 0) {
    throw new InvalidDurationError(`Duration must be a positive number of seconds: "${input}"`)
  }
  return seconds
}
