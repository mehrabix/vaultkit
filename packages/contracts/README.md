# @vaultkit/contracts

Foundry project for the VaultKit on-chain primitive.

- `VestingWallet.sol` — one schedule, one address, one token balance (EIP-1167 clone target)
- `VaultKitFactory.sol` — creates and funds clones atomically
- `VaultKitRegistry.sol` — append-only factory version registry

Behavior is specified in [`SPEC.md`](./SPEC.md).

## Commands

```bash
forge build
forge test
forge test --fuzz-runs 4096                 # heavier fuzz
FOUNDRY_PROFILE=ci forge test               # CI settings
forge coverage --report summary
forge snapshot
forge fmt
```

## Deploy

```bash
export PRIVATE_KEY=0x…
export BASE_SEPOLIA_RPC_URL=https://…
export BASESCAN_API_KEY=…

forge script script/Deploy.s.sol \
  --rpc-url base_sepolia \
  --broadcast \
  --verify
```

## Test layout

| File | Covers |
| --- | --- |
| `test/VestingWallet.t.sol` | Initialization, cliff/duration boundaries, claim, revoke, reassign, reentrancy |
| `test/VestingWallet.fuzz.t.sol` | Closed-form math, monotonicity, `claimable <= vested <= total` |
| `test/VestingWallet.invariant.t.sol` | Solvency and bounds across arbitrary call sequences |
| `test/VaultKitFactory.t.sol` | Clone + fund-in-one-tx, fee-on-transfer rejection, pause, isolation |
| `test/VaultKitRegistry.t.sol` | Append-only registration, owner gating |

## Dependencies (git submodules)

```bash
forge install    # after a fresh clone, or: git submodule update --init --recursive
```

- `foundry-rs/forge-std`
- `OpenZeppelin/openzeppelin-contracts` (v5.7)
