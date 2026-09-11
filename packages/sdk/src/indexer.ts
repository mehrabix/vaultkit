import type { Address } from 'viem'

import { IndexerUnavailableError } from './errors.js'
import type { ListSchedulesQuery, Schedule } from './types.js'

export interface IndexerClientOptions {
  /** Base URL of the Ponder API, e.g. `https://indexer.vaultkit.xyz`. */
  url: string
  /** Injectable fetch, for tests and non-standard runtimes. */
  fetch?: typeof globalThis.fetch
  timeoutMs?: number
}

interface RawIndexerSchedule {
  address: string
  chainId: number | string
  token: string
  beneficiary: string
  creator: string
  start: number | string
  cliff: number | string
  duration: number | string
  totalAmount: string
  claimed: string
  revocable: boolean
  revoked: boolean
  revokedAt: number | string | null
}

/**
 * Thin client over the Ponder indexer. The indexer is the only thing that can answer
 * "every schedule for beneficiary X" — single-schedule reads never need it.
 */
export class IndexerClient {
  private readonly url: string
  private readonly fetchImpl: typeof globalThis.fetch
  private readonly timeoutMs: number

  constructor(options: IndexerClientOptions) {
    this.url = options.url.replace(/\/+$/, '')

    const fetchImpl = options.fetch ?? globalThis.fetch
    if (typeof fetchImpl !== 'function') {
      throw new IndexerUnavailableError('No fetch implementation is available in this runtime.')
    }

    this.fetchImpl = fetchImpl
    this.timeoutMs = options.timeoutMs ?? 10_000
  }

  async listSchedules(query: ListSchedulesQuery = {}): Promise<Schedule[]> {
    const params = new URLSearchParams()
    if (query.beneficiary) params.set('beneficiary', query.beneficiary)
    if (query.creator) params.set('creator', query.creator)
    if (query.token) params.set('token', query.token)
    if (query.chainId !== undefined) params.set('chain', String(query.chainId))

    const search = params.toString()
    const endpoint = `${this.url}/schedules${search ? `?${search}` : ''}`

    let response: Response
    try {
      response = await this.fetchImpl(endpoint, {
        headers: { accept: 'application/json' },
        signal: AbortSignal.timeout(this.timeoutMs),
      })
    } catch (cause) {
      throw new IndexerUnavailableError(`Could not reach the indexer at ${this.url}.`, { cause })
    }

    if (!response.ok) {
      throw new IndexerUnavailableError(`Indexer responded ${response.status} for ${endpoint}.`)
    }

    const payload: unknown = await response.json()
    const rows = Array.isArray(payload)
      ? payload
      : ((payload as { schedules?: unknown[] }).schedules ?? [])

    return rows.map((row) => mapIndexerSchedule(row as RawIndexerSchedule))
  }

  async isAvailable(): Promise<boolean> {
    try {
      const response = await this.fetchImpl(`${this.url}/health`, {
        signal: AbortSignal.timeout(this.timeoutMs),
      })
      return response.ok
    } catch {
      return false
    }
  }
}

function toSeconds(value: number | string | null): number | null {
  if (value === null) return null
  const seconds = typeof value === 'number' ? value : Number(value)
  return Number.isFinite(seconds) ? Math.floor(seconds) : 0
}

function mapIndexerSchedule(raw: RawIndexerSchedule): Schedule {
  const revokedAt = toSeconds(raw.revokedAt)

  return {
    address: raw.address as Address,
    chainId: Number(raw.chainId),
    token: raw.token as Address,
    beneficiary: raw.beneficiary as Address,
    creator: raw.creator as Address,
    start: toSeconds(raw.start) ?? 0,
    cliff: toSeconds(raw.cliff) ?? 0,
    duration: toSeconds(raw.duration) ?? 0,
    totalAmount: BigInt(raw.totalAmount),
    claimed: BigInt(raw.claimed),
    revocable: Boolean(raw.revocable),
    revoked: Boolean(raw.revoked),
    revokedAt: revokedAt === 0 ? null : revokedAt,
  }
}
