import { createContext, useContext, useMemo, type ReactNode } from 'react'
import { VaultKit } from '@vaultkit/sdk'
import type { Address, Transport } from 'viem'
import { useAccount, usePublicClient, useWalletClient } from 'wagmi'

const VaultKitContext = createContext<VaultKit | null>(null)

export interface VaultKitProviderProps {
  /** A pre-built SDK instance. */
  client: VaultKit
  children: ReactNode
}

/** Injects an existing `VaultKit` instance. Use this if you already own the viem transport. */
export function VaultKitProvider({ client, children }: VaultKitProviderProps) {
  return <VaultKitContext.Provider value={client}>{children}</VaultKitContext.Provider>
}

export function useVaultKit(): VaultKit {
  const client = useContext(VaultKitContext)
  if (!client) {
    throw new Error('useVaultKit must be used inside a <VaultKitProvider> or <WagmiVaultKitProvider>.')
  }
  return client
}

export interface WagmiVaultKitProviderProps {
  children: ReactNode
  /** Base URL of the Ponder indexer. Without it, `useSchedules` stays disabled. */
  indexerUrl?: string
  /** Overrides the built-in deployment lookup for the connected chain. */
  factoryAddress?: Address
}

/**
 * Builds the SDK from the surrounding wagmi context: the connected chain, the public transport, and
 * the connected account. Rebuilds when the chain or account changes, so switching networks in the
 * wallet is picked up automatically.
 */
export function WagmiVaultKitProvider({
  children,
  indexerUrl,
  factoryAddress,
}: WagmiVaultKitProviderProps) {
  const publicClient = usePublicClient()
  const { address } = useAccount()
  const { data: walletClient } = useWalletClient()

  const client = useMemo(() => {
    if (!publicClient?.chain) return null

    return new VaultKit({
      chain: publicClient.chain,
      // wagmi types `publicClient.transport` as the raw viem TransportConfig, while viem exposes a
      // callable Transport at runtime (with `.request` attached). The runtime value is correct;
      // only the type is wrong, so normalise it here at the library boundary.
      transport: publicClient.transport as unknown as Transport,
      account: walletClient?.account ?? address,
      indexerUrl,
      factoryAddress,
    })
  }, [publicClient, walletClient, address, indexerUrl, factoryAddress])

  if (!client) return null
  return <VaultKitContext.Provider value={client}>{children}</VaultKitContext.Provider>
}
