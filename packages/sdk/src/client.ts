import {
  createPublicClient,
  createWalletClient,
  parseEventLogs,
  type Account,
  type Address,
  type Chain,
  type Hash,
  type PublicClient,
  type Transport,
} from 'viem'

import { vaultKitFactoryAbi, vestingWalletAbi } from './abis/index.js'
import { getDeployment } from './deployments.js'
import { parseDuration } from './duration.js'
import { ConfigurationError, IndexerUnavailableError, VaultKitError } from './errors.js'
import { IndexerClient } from './indexer.js'
import { nowSeconds, toScheduleView, vestedAmountAt } from './math.js'
import type {
  CreateScheduleParams,
  CreateScheduleResult,
  ListSchedulesQuery,
  Schedule,
  ScheduleView,
} from './types.js'

export interface VaultKitOptions {
  chain: Chain
  transport: Transport
  /** Required for writes: a local account or a JSON-RPC account address. */
  account?: Account | Address
  /** Overrides the built-in deployment lookup for this chain. */
  factoryAddress?: Address
  registryAddress?: Address
  /** Base URL of the Ponder indexer. Without it, list queries throw `IndexerUnavailableError`. */
  indexerUrl?: string
  /** Injectable fetch, for tests and non-standard runtimes. */
  fetch?: typeof globalThis.fetch
}

export type VaultKitPublicClient = PublicClient<Transport, Chain>
export type VaultKitWalletClient = ReturnType<
  typeof createWalletClient<Transport, Chain, Account | Address>
>

interface RawSchedule {
  token: Address
  beneficiary: Address
  creator: Address
  start: bigint
  cliff: bigint
  duration: bigint
  totalAmount: bigint
  claimed: bigint
  revocable: boolean
  revoked: boolean
  revokedAt: bigint
}

/**
 * Framework-free entry point. Read methods work with nothing but a transport; write methods need an
 * `account`; list methods need an `indexerUrl`.
 */
export class VaultKit {
  readonly chain: Chain
  readonly publicClient: VaultKitPublicClient
  readonly walletClient?: VaultKitWalletClient
  readonly indexer?: IndexerClient

  private readonly factoryAddress?: Address

  constructor(options: VaultKitOptions) {
    const deployment = getDeployment(options.chain.id)

    this.chain = options.chain
    this.factoryAddress = options.factoryAddress ?? deployment?.factory
    this.publicClient = createPublicClient({ chain: options.chain, transport: options.transport })

    if (options.account) {
      this.walletClient = createWalletClient({
        chain: options.chain,
        transport: options.transport,
        account: options.account,
      })
    }

    if (options.indexerUrl) {
      this.indexer = new IndexerClient({ url: options.indexerUrl, fetch: options.fetch })
    }
  }

  // -------------------------------------------------------------------
  // Reads — no indexer, no wallet required
  // -------------------------------------------------------------------

  /** Raw on-chain schedule state for one wallet. */
  async getSchedule(address: Address): Promise<Schedule> {
    const raw = (await this.publicClient.readContract({
      address,
      abi: vestingWalletAbi,
      functionName: 'schedule',
    })) as unknown as RawSchedule

    return mapSchedule(address, this.chain.id, raw)
  }

  /** The schedule plus every derived display value (claimable, percent vested, next unlock, …). */
  async getScheduleView(address: Address, at: number = nowSeconds()): Promise<ScheduleView> {
    return toScheduleView(await this.getSchedule(address), at)
  }

  /** Authoritative on-chain `claimableAmount()`. */
  async claimableAmount(address: Address): Promise<bigint> {
    return this.publicClient.readContract({
      address,
      abi: vestingWalletAbi,
      functionName: 'claimableAmount',
    })
  }

  /** Vested amount at `at` (defaults to now), computed with the same math as the contract. */
  async vestedAmount(address: Address, at: number = nowSeconds()): Promise<bigint> {
    return vestedAmountAt(await this.getSchedule(address), at)
  }

  // -------------------------------------------------------------------
  // Writes — simulated first, so the caller gets a revert reason, not a failed tx
  // -------------------------------------------------------------------

  async createSchedule(params: CreateScheduleParams): Promise<CreateScheduleResult> {
    const factory = this.requireFactory()
    const walletClient = this.requireWalletClient()
    const account = walletClient.account

    const start = toUnixSeconds(params.start ?? nowSeconds())
    const cliff = params.cliff === undefined ? 0 : parseDuration(params.cliff)
    const duration = parseDuration(params.duration)

    if (params.amount <= 0n) throw new ConfigurationError('`amount` must be greater than zero.')
    if (cliff > duration) throw new ConfigurationError('`cliff` cannot exceed `duration`.')

    const { request } = await this.publicClient.simulateContract({
      address: factory,
      abi: vaultKitFactoryAbi,
      functionName: 'createVestingSchedule',
      args: [
        params.token,
        params.beneficiary,
        BigInt(start),
        BigInt(cliff),
        BigInt(duration),
        params.amount,
        params.revocable ?? false,
      ],
      account,
    })

    const hash = await walletClient.writeContract(request)
    const receipt = await this.publicClient.waitForTransactionReceipt({ hash })

    const [created] = parseEventLogs({
      abi: vaultKitFactoryAbi,
      eventName: 'ScheduleCreated',
      logs: receipt.logs,
    })

    if (!created) throw new VaultKitError('ScheduleCreated event missing from the transaction receipt.')

    const wallet = created.args.wallet
    return { wallet, hash, schedule: await this.getSchedule(wallet) }
  }

  /** Simulation-only variant of `claim`, for UIs that want a revert reason before sending. */
  simulateClaim(address: Address) {
    return this.publicClient.simulateContract({
      address,
      abi: vestingWalletAbi,
      functionName: 'claim',
      account: this.requireWalletClient().account,
    })
  }

  async claim(address: Address): Promise<Hash> {
    const walletClient = this.requireWalletClient()
    const { request } = await this.publicClient.simulateContract({
      address,
      abi: vestingWalletAbi,
      functionName: 'claim',
      account: walletClient.account,
    })
    return walletClient.writeContract(request)
  }

  async revoke(address: Address): Promise<Hash> {
    const walletClient = this.requireWalletClient()
    const { request } = await this.publicClient.simulateContract({
      address,
      abi: vestingWalletAbi,
      functionName: 'revoke',
      account: walletClient.account,
    })
    return walletClient.writeContract(request)
  }

  async reassignBeneficiary(address: Address, newBeneficiary: Address): Promise<Hash> {
    const walletClient = this.requireWalletClient()
    const { request } = await this.publicClient.simulateContract({
      address,
      abi: vestingWalletAbi,
      functionName: 'reassignBeneficiary',
      args: [newBeneficiary],
      account: walletClient.account,
    })
    return walletClient.writeContract(request)
  }

  // -------------------------------------------------------------------
  // Lists — indexer-backed; degrades to a typed error, never a silent empty result
  // -------------------------------------------------------------------

  async listSchedules(query: ListSchedulesQuery = {}): Promise<Schedule[]> {
    if (!this.indexer) throw new IndexerUnavailableError()
    return this.indexer.listSchedules({ chainId: this.chain.id, ...query })
  }

  async listScheduleViews(
    query: ListSchedulesQuery = {},
    at: number = nowSeconds(),
  ): Promise<ScheduleView[]> {
    const schedules = await this.listSchedules(query)
    return schedules.map((schedule) => toScheduleView(schedule, at))
  }

  // -------------------------------------------------------------------

  private requireFactory(): Address {
    if (!this.factoryAddress) {
      throw new ConfigurationError(
        `No VaultKitFactory is known for chain ${this.chain.id}. Pass \`factoryAddress\`.`,
      )
    }
    return this.factoryAddress
  }

  private requireWalletClient(): VaultKitWalletClient {
    if (!this.walletClient) {
      throw new ConfigurationError(
        'A wallet account is required for write operations. Pass `account` to the VaultKit constructor.',
      )
    }
    return this.walletClient
  }
}

function toUnixSeconds(input: Date | number): number {
  return input instanceof Date ? Math.floor(input.getTime() / 1000) : Math.floor(input)
}

function mapSchedule(address: Address, chainId: number, raw: RawSchedule): Schedule {
  return {
    address,
    chainId,
    token: raw.token,
    beneficiary: raw.beneficiary,
    creator: raw.creator,
    start: Number(raw.start),
    cliff: Number(raw.cliff),
    duration: Number(raw.duration),
    totalAmount: raw.totalAmount,
    claimed: raw.claimed,
    revocable: raw.revocable,
    revoked: raw.revoked,
    revokedAt: raw.revokedAt === 0n ? null : Number(raw.revokedAt),
  }
}
