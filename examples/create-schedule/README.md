# create-schedule example

Creates one revocable vesting schedule (6-month cliff, 2-year duration) and prints the resulting
claimable amount and dates.

```bash
PRIVATE_KEY=0x… \
FACTORY_ADDRESS=0x… \
TOKEN_ADDRESS=0x… \
BENEFICIARY=0x… \
AMOUNT=100000 \
pnpm --filter @vaultkit/example-create-schedule start
```

Optional env: `RPC_URL` (defaults to Base Sepolia), `INDEXER_URL`.

The token holder must approve the factory for `AMOUNT` first — the factory pulls the tokens and
funds the new wallet in the same transaction.
