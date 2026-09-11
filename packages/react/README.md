# @vaultkit/react

React hooks for VaultKit — wagmi-aware, with loading/error state via
[TanStack Query](https://tanstack.com/query). Everything is a thin layer over [`@vaultkit/sdk`](../sdk).

## Setup

```tsx
import { WagmiVaultKitProvider } from '@vaultkit/react'

export function App() {
  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <WagmiVaultKitProvider indexerUrl="https://indexer.vaultkit.xyz">
          <Dashboard />
        </WagmiVaultKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  )
}
```

`WagmiVaultKitProvider` derives the SDK's chain, transport and account from wagmi, so switching
networks or accounts in the wallet is picked up automatically. If you already own a viem transport,
use `<VaultKitProvider client={vk}>` instead.

## Hooks

| Hook | Kind | Returns |
| --- | --- | --- |
| `useSchedules(query?, options?)` | query | `ScheduleView[]` — indexer-backed, disabled without `indexerUrl` |
| `useSchedule(address?, options?)` | query | `ScheduleView` — polls every 12s |
| `useClaimable(address?, options?)` | query | `bigint` — on-chain `claimableAmount()` |
| `useCreateSchedule()` | mutation | `{ wallet, hash, schedule }` |
| `useClaim()` | mutation | `Hash` |
| `useRevoke()` | mutation | `Hash` |

Every query accepts `{ enabled, refetchInterval }`; every mutation exposes TanStack's
`isPending` / `isError` / `error`, and invalidates all `['vaultkit', …]` queries on success.

Writes go through the SDK, which runs `simulateContract` before sending — so a revert shows up as a
mutation error rather than a wasted transaction.

## Example

```tsx
function Row({ address }: { address: Address }) {
  const { data: view } = useSchedule(address)
  const claim = useClaim()

  return (
    <button disabled={!view?.claimableAmount || claim.isPending} onClick={() => claim.mutate(address)}>
      Claim {view ? formatUnits(view.claimableAmount, 18) : '…'}
    </button>
  )
}
```

## Development

```bash
pnpm --filter @vaultkit/sdk build
pnpm --filter @vaultkit/react typecheck
pnpm --filter @vaultkit/react build
```
