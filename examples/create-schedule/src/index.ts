/**
 * Create a VaultKit vesting schedule from the command line.
 *
 *   PRIVATE_KEY=0x…            (required)
 *   FACTORY_ADDRESS=0x…        (required)
 *   TOKEN_ADDRESS=0x…          (required)
 *   BENEFICIARY=0x…            (required)
 *   AMOUNT=100000              (optional, whole tokens — defaults to 100000)
 *   RPC_URL=https://…          (optional, defaults to Base Sepolia)
 *   INDEXER_URL=https://…      (optional; enables the "all my schedules" listing)
 *
 * Run with: pnpm --filter @vaultkit/example-create-schedule start
 */
import { VaultKit } from '@vaultkit/sdk'
import type { Address } from 'viem'
import { formatUnits, http, parseUnits } from 'viem'
import { privateKeyToAccount } from 'viem/accounts'
import { baseSepolia } from 'viem/chains'

const DECIMALS = 18

async function main() {
  const privateKey = required('PRIVATE_KEY') as `0x${string}`
  const factoryAddress = required('FACTORY_ADDRESS') as Address
  const token = required('TOKEN_ADDRESS') as Address
  const beneficiary = required('BENEFICIARY') as Address

  const vk = new VaultKit({
    chain: baseSepolia,
    transport: http(process.env.RPC_URL ?? 'https://sepolia.base.org'),
    account: privateKeyToAccount(privateKey),
    factoryAddress,
    indexerUrl: process.env.INDEXER_URL,
  })

  const amount = parseUnits(process.env.AMOUNT ?? '100000', DECIMALS)

  const { wallet, hash } = await vk.createSchedule({
    token,
    beneficiary,
    start: new Date(),
    cliff: '6 months',
    duration: '2 years',
    amount,
    revocable: true,
  })

  console.log(`created ${wallet} in ${hash}`)

  const view = await vk.getScheduleView(wallet)
  console.log(
    `total ${formatUnits(view.totalAmount, DECIMALS)} | ` +
      `vested ${view.percentVested.toFixed(2)}% | ` +
      `claimable ${formatUnits(view.claimableAmount, DECIMALS)} | ` +
      `cliff ${new Date(view.cliffAt * 1000).toISOString()} | ` +
      `fully vested ${new Date(view.fullyVestedAt * 1000).toISOString()}`,
  )
}

function required(name: string): string {
  const value = process.env[name]
  if (!value) throw new Error(`Missing required environment variable ${name}`)
  return value
}

main().catch((error: unknown) => {
  console.error(error)
  process.exitCode = 1
})
