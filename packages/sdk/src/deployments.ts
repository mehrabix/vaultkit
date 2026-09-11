import type { Address } from 'viem'

export interface Deployment {
  readonly implementation: Address
  readonly factory: Address
  readonly registry: Address
}

/**
 * Canonical deployments, keyed by chain id. Filled in after a testnet/mainnet deploy; until then
 * write operations require an explicit `factoryAddress` in the SDK constructor.
 */
export const DEPLOYMENTS: Readonly<Record<number, Deployment>> = {}

export function getDeployment(chainId: number): Deployment | undefined {
  return DEPLOYMENTS[chainId]
}
