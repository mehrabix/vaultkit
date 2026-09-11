# apps/web — not implemented yet

Reserved for the Next.js dashboard (milestone **M5**).

Planned screens:

1. `/` — landing: one verdict, one chart, one CTA
2. `/dashboard` — the connected wallet's schedules, one **Claim** button per row
3. `/schedule/[address]` — live vesting curve, cliff marker, claim history
4. `/create` — step wizard with a projected unlock table before signing
5. `/verify/[address]` — read-only, no-connect public verification page

Everything it needs already exists: [`@vaultkit/sdk`](../../packages/sdk) for reads/writes/curve math
and [`@vaultkit/react`](../../packages/react) for the wagmi-aware hooks.
