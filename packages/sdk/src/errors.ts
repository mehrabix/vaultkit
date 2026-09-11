/** Base class for every error the SDK raises deliberately. */
export class VaultKitError extends Error {
  constructor(message: string, options?: { cause?: unknown }) {
    super(message, options)
    this.name = 'VaultKitError'
  }
}

/** Thrown when the SDK is constructed or used without the configuration an operation needs. */
export class ConfigurationError extends VaultKitError {
  constructor(message: string) {
    super(message)
    this.name = 'ConfigurationError'
  }
}

/** Thrown by list/aggregate queries when no indexer is configured or it cannot be reached. */
export class IndexerUnavailableError extends VaultKitError {
  constructor(message = 'The VaultKit indexer is not configured or unreachable.', options?: { cause?: unknown }) {
    super(message, options)
    this.name = 'IndexerUnavailableError'
  }
}

/** Thrown when a duration string cannot be parsed. */
export class InvalidDurationError extends VaultKitError {
  constructor(message: string) {
    super(message)
    this.name = 'InvalidDurationError'
  }
}
