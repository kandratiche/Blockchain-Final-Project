# Gas Optimization Report

Numbers below come from `forge test --gas-report` on the committed test suite
(`solc 0.8.24`, `optimizer = true`, `runs = 200`, `via_ir = true`).

---

## 1. Headline before/after — inline Yul vs pure Solidity

`SumBench` sums a `uint256` calldata array two ways. The Yul path reads straight
from calldata and skips the per-element bounds check the Solidity loop emits.

| Implementation | Avg gas | Median | Max |
|---|---|---|---|
| `sumSolidity` (before) | 13,452 | 12,969 | 27,039 |
| `sumAssembly` (after)  | 9,607  | 9,267  | 19,183 |
| **Saving**             | **−3,845 (−28.6%)** | **−28.5%** | **−29.0%** |

Verified by `test_gasBenchmark` and `testFuzz_implementationsAgree`: both
implementations return identical results for every input, fuzzed over 256 runs.

**Trade-off.** The Yul version drops Solidity's automatic array-bounds check.
This is safe here because the loop bound is `data.length` itself — it can never
read past the array — and the function is `pure`. The pure-Solidity version is
kept in the codebase as the readable reference and the differential test oracle.

---

## 2. Key operation gas costs

| Contract | Function | Avg gas |
|---|---|---|
| ResourceAMM | `swap` | 96,225 |
| RealmStakeVault | `deposit` | 99,665 |
| CraftingEngine | `craft` | 174,761 |
| NFTRentalVault | `rent` | 104,020 |
| GameDAO | `castVote` | 82,904 |
| GameDAO | `propose` | 66,609 |
| GameRegistryV1 | `grantXP` | 20,349 |
| GuildFactory | `createGuild` (CREATE) | 424,543 |
| PriceOracle | `getPrice` | 14,937 |

---

## 3. Optimization log

| # | Change | Rationale | Effect |
|---|---|---|---|
| 1 | Inline-Yul array sum (`SumBench`) | Skip bounds check + memory expansion | −28.6% on the hot path |
| 2 | `via_ir = true` | IR pipeline yields better stack scheduling | Lower cost on multi-variable functions; enables crafting/governance code without "stack too deep" |
| 3 | `immutable` for `items`, `MANA`, `factory`, asset refs | Immutables are inlined into bytecode, no SLOAD | ~2,100 gas saved per access vs a storage read |
| 4 | Custom errors instead of `require` strings | 4-byte selector vs ABI-encoded string | ~50 gas + smaller bytecode per revert (CraftingEngine, Guild, GameRegistry, PriceOracle) |
| 5 | Pull-over-push earnings in `NFTRentalVault` | One SSTORE on `rent`, payout deferred | Removes a token transfer from the rent path; renter pays a flat cost |
| 6 | `Pool` packed into one struct, single mapping | Related slots co-located | Fewer SLOADs per swap/liquidity action |

---

## 4. L1 vs L2 cost projection

The gas **units** above are EVM-identical on L1 and any L2. The cost difference
is the gas price. Using representative prices (L1 ≈ 12 gwei, Arbitrum Sepolia
≈ 0.1 gwei) for six operations:

| Operation | Gas | L1 @ 12 gwei | L2 @ 0.1 gwei |
|---|---|---|---|
| `swap` | 96,225 | ~0.001155 ETH | ~0.0000096 ETH |
| `deposit` (vault) | 99,665 | ~0.001196 ETH | ~0.0000100 ETH |
| `craft` | 174,761 | ~0.002097 ETH | ~0.0000175 ETH |
| `rent` | 104,020 | ~0.001248 ETH | ~0.0000104 ETH |
| `castVote` | 82,904 | ~0.000995 ETH | ~0.0000083 ETH |
| `grantXP` | 20,349 | ~0.000244 ETH | ~0.0000020 ETH |

> The L1/L2 figures are projections from local gas units. They will be replaced
> with measured on-chain numbers once the contracts are deployed and verified on
> Arbitrum Sepolia.

## Reproduce

```bash
forge test --match-path 'test/*.t.sol' --gas-report
```
