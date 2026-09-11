import { describe, expect, it, vi } from 'vitest'

import { IndexerUnavailableError } from '../src/errors.js'
import { IndexerClient } from '../src/indexer.js'

const BENEFICIARY = '0x1111111111111111111111111111111111111111'
const TOKEN = '0x2222222222222222222222222222222222222222'
const CREATOR = '0x3333333333333333333333333333333333333333'
const WALLET = '0x4444444444444444444444444444444444444444'

const row = {
  address: WALLET,
  chainId: 8453,
  token: TOKEN,
  beneficiary: BENEFICIARY,
  creator: CREATOR,
  start: 1_700_000_000,
  cliff: 15_552_000,
  duration: 63_072_000,
  totalAmount: '1000000000000000000000',
  claimed: '250000000000000000000',
  revocable: true,
  revoked: false,
  revokedAt: null,
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  })
}

describe('IndexerClient', () => {
  it('maps indexer rows into typed schedules', async () => {
    const fetchImpl = vi.fn(async () => jsonResponse([row]))
    const client = new IndexerClient({
      url: 'https://indexer.test/',
      fetch: fetchImpl as unknown as typeof globalThis.fetch,
    })

    const schedules = await client.listSchedules({ beneficiary: BENEFICIARY, chainId: 8453 })

    expect(schedules).toHaveLength(1)
    expect(schedules[0]).toMatchObject({
      address: WALLET,
      chainId: 8453,
      totalAmount: 1_000_000_000_000_000_000_000n,
      claimed: 250_000_000_000_000_000_000n,
      revokedAt: null,
    })
    expect(fetchImpl).toHaveBeenCalledWith(
      `https://indexer.test/schedules?beneficiary=${BENEFICIARY}&chain=8453`,
      expect.objectContaining({ headers: { accept: 'application/json' } }),
    )
  })

  it('accepts a `{ schedules: [...] }` envelope', async () => {
    const fetchImpl = vi.fn(async () => jsonResponse({ schedules: [row] }))
    const client = new IndexerClient({
      url: 'https://indexer.test',
      fetch: fetchImpl as unknown as typeof globalThis.fetch,
    })

    await expect(client.listSchedules()).resolves.toHaveLength(1)
  })

  it('throws IndexerUnavailableError when it cannot reach the indexer', async () => {
    const fetchImpl = vi.fn(async () => {
      throw new Error('ECONNREFUSED')
    })
    const client = new IndexerClient({
      url: 'https://indexer.test',
      fetch: fetchImpl as unknown as typeof globalThis.fetch,
    })

    await expect(client.listSchedules()).rejects.toBeInstanceOf(IndexerUnavailableError)
  })

  it('throws IndexerUnavailableError on a non-2xx response', async () => {
    const fetchImpl = vi.fn(async () => jsonResponse({ error: 'nope' }, 500))
    const client = new IndexerClient({
      url: 'https://indexer.test',
      fetch: fetchImpl as unknown as typeof globalThis.fetch,
    })

    await expect(client.listSchedules()).rejects.toBeInstanceOf(IndexerUnavailableError)
  })

  it('reports availability from /health', async () => {
    const ok = new IndexerClient({
      url: 'https://indexer.test',
      fetch: vi.fn(async () => jsonResponse({ ok: true })) as unknown as typeof globalThis.fetch,
    })
    const down = new IndexerClient({
      url: 'https://indexer.test',
      fetch: vi.fn(async () => {
        throw new Error('offline')
      }) as unknown as typeof globalThis.fetch,
    })

    await expect(ok.isAvailable()).resolves.toBe(true)
    await expect(down.isAvailable()).resolves.toBe(false)
  })
})
