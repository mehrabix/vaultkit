export { VaultKit } from './client.js'
export type { VaultKitOptions, VaultKitPublicClient, VaultKitWalletClient } from './client.js'

export { IndexerClient } from './indexer.js'
export type { IndexerClientOptions } from './indexer.js'

export { parseDuration } from './duration.js'

export {
  nextUnlockAt,
  nowSeconds,
  percentVested,
  scheduleStatus,
  toScheduleView,
  vestedAmountAt,
} from './math.js'
export type { VestingTerms } from './math.js'

export { DEPLOYMENTS, getDeployment } from './deployments.js'
export type { Deployment } from './deployments.js'

export {
  ConfigurationError,
  IndexerUnavailableError,
  InvalidDurationError,
  VaultKitError,
} from './errors.js'

export { vaultKitFactoryAbi, vaultKitRegistryAbi, vestingWalletAbi } from './abis/index.js'

export type {
  CreateScheduleParams,
  CreateScheduleResult,
  DurationInput,
  ListSchedulesQuery,
  Schedule,
  ScheduleStatus,
  ScheduleView,
} from './types.js'
