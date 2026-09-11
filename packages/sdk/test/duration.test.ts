import { describe, expect, it } from 'vitest'

import { parseDuration } from '../src/duration.js'
import { InvalidDurationError } from '../src/errors.js'

const SECOND = 1
const MINUTE = 60 * SECOND
const HOUR = 60 * MINUTE
const DAY = 24 * HOUR
const WEEK = 7 * DAY
const MONTH = 30 * DAY
const YEAR = 365 * DAY

describe('parseDuration', () => {
  it('parses single units', () => {
    expect(parseDuration('60s')).toBe(60 * SECOND)
    expect(parseDuration('45m')).toBe(45 * MINUTE)
    expect(parseDuration('36h')).toBe(36 * HOUR)
    expect(parseDuration('90d')).toBe(90 * DAY)
    expect(parseDuration('18w')).toBe(18 * WEEK)
    expect(parseDuration('6 months')).toBe(6 * MONTH)
    expect(parseDuration('2 years')).toBe(2 * YEAR)
  })

  it('treats `m` as minutes and `mo` as months', () => {
    expect(parseDuration('1m')).toBe(MINUTE)
    expect(parseDuration('1mo')).toBe(MONTH)
  })

  it('parses compound durations', () => {
    expect(parseDuration('1y 6mo')).toBe(YEAR + 6 * MONTH)
    expect(parseDuration('1d 12h 30m')).toBe(DAY + 12 * HOUR + 30 * MINUTE)
  })

  it('accepts numbers and bigints as seconds', () => {
    expect(parseDuration(120)).toBe(120)
    expect(parseDuration('120')).toBe(120)
    expect(parseDuration(604800n)).toBe(604800)
  })

  it('rounds fractional units to whole seconds', () => {
    expect(parseDuration('1.5d')).toBe(Math.round(1.5 * DAY))
  })

  it('rejects unparseable and non-positive input', () => {
    expect(() => parseDuration('soon')).toThrow(InvalidDurationError)
    expect(() => parseDuration('6 fortnights')).toThrow(InvalidDurationError)
    expect(() => parseDuration('')).toThrow(InvalidDurationError)
    expect(() => parseDuration('0')).toThrow(InvalidDurationError)
    expect(() => parseDuration(0)).toThrow(InvalidDurationError)
    expect(() => parseDuration(-1)).toThrow(InvalidDurationError)
    expect(() => parseDuration(Number.NaN)).toThrow(InvalidDurationError)
  })
})
