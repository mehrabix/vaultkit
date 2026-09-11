import {
  toScheduleView,
  type CreateScheduleParams,
  type CreateScheduleResult,
  type ListSchedulesQuery,
  type ScheduleView,
} from '@vaultkit/sdk'
import {
  useMutation,
  useQuery,
  useQueryClient,
  type UseMutationResult,
  type UseQueryResult,
} from '@tanstack/react-query'
import type { Address, Hash } from 'viem'

import { useVaultKit } from './context.js'

const ROOT_KEY = ['vaultkit'] as const

export interface QueryOptions {
  enabled?: boolean
  /** Defaults to 12s, roughly one block on Base. */
  refetchInterval?: number
}

/** Every schedule the indexer knows about for the given filter. Disabled without an indexer. */
export function useSchedules(
  query: ListSchedulesQuery = {},
  options: QueryOptions = {},
): UseQueryResult<ScheduleView[]> {
  const vk = useVaultKit()

  return useQuery({
    queryKey: [...ROOT_KEY, 'schedules', vk.chain.id, query],
    queryFn: async () => {
      const schedules = await vk.listSchedules(query)
      return schedules.map((schedule) => toScheduleView(schedule))
    },
    enabled: (options.enabled ?? true) && vk.indexer !== undefined,
    refetchInterval: options.refetchInterval ?? 15_000,
  })
}

/** A single schedule with derived display values. Polls so the curve and claimable stay live. */
export function useSchedule(
  address?: Address,
  options: QueryOptions = {},
): UseQueryResult<ScheduleView> {
  const vk = useVaultKit()

  return useQuery({
    queryKey: [...ROOT_KEY, 'schedule', vk.chain.id, address],
    queryFn: () => vk.getScheduleView(address as Address),
    enabled: (options.enabled ?? true) && Boolean(address),
    refetchInterval: options.refetchInterval ?? 12_000,
  })
}

/** Authoritative on-chain `claimableAmount()` for one schedule. */
export function useClaimable(
  address?: Address,
  options: QueryOptions = {},
): UseQueryResult<bigint> {
  const vk = useVaultKit()

  return useQuery({
    queryKey: [...ROOT_KEY, 'claimable', vk.chain.id, address],
    queryFn: () => vk.claimableAmount(address as Address),
    enabled: (options.enabled ?? true) && Boolean(address),
    refetchInterval: options.refetchInterval ?? 12_000,
  })
}

/** Simulates, then sends. Polling queries are invalidated on success. */
export function useCreateSchedule(): UseMutationResult<
  CreateScheduleResult,
  Error,
  CreateScheduleParams
> {
  const vk = useVaultKit()
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (params: CreateScheduleParams) => vk.createSchedule(params),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ROOT_KEY })
    },
  })
}

export function useClaim(): UseMutationResult<Hash, Error, Address> {
  const vk = useVaultKit()
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (address: Address) => vk.claim(address),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ROOT_KEY })
    },
  })
}

export function useRevoke(): UseMutationResult<Hash, Error, Address> {
  const vk = useVaultKit()
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (address: Address) => vk.revoke(address),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ROOT_KEY })
    },
  })
}
