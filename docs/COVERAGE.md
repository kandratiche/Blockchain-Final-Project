# Test Coverage Report

Generated with `forge coverage --match-path 'test/*.t.sol' --ir-minimum --report summary`.

Test suite: **106 tests** (103 passing, 3 fork tests skipped without an RPC) across
11 suites — unit, fuzz, invariant-style, and fork.

## Line coverage by contract

| Contract | % Lines | % Statements | % Funcs |
|---|---|---|---|
| `src/CraftingEngine.sol` | 95.65% (44/46) | 94.59% | 100.00% |
| `src/GameDAO.sol` | 80.00% (16/20) | 78.95% | 80.00% |
| `src/GameItems.sol` | 75.00% (18/24) | 76.47% | 62.50% |
| `src/GameRegistryV1.sol` | 95.83% (23/24) | 80.95% | 100.00% |
| `src/GameRegistryV2.sol` | 100.00% (8/8) | 100.00% | 100.00% |
| `src/Guild.sol` | 100.00% (23/23) | 95.65% | 100.00% |
| `src/GuildFactory.sol` | 100.00% (17/17) | 100.00% | 100.00% |
| `src/LootVRF.sol` | 0.00% (0/67) | 0.00% | 0.00% |
| `src/NFTRentalVault.sol` | 77.59% (45/58) | 78.43% | 72.73% |
| `src/PriceOracle.sol` | 100.00% (22/22) | 91.67% | 100.00% |
| `src/RealmStakeVault.sol` | 100.00% (2/2) | 100.00% | 100.00% |
| `src/RealmToken.sol` | 100.00% (14/14) | 100.00% | 100.00% |
| `src/ResourceAMM.sol` | 71.74% (66/92) | 69.90% | 63.64% |

## Status against the ≥90% target

The newer modules (CraftingEngine, GameRegistry, Guild/GuildFactory, PriceOracle,
RealmToken, RealmStakeVault) meet or exceed the 90% line target. Three contracts
are **open coverage gaps** still being closed:

1. **`LootVRF.sol` — 0%.** Exercising the VRF consumer requires a
   `VRFCoordinatorV2_5Mock`; the mock and the request/fulfil tests are the next
   work item. This is the single largest gap.
2. **`ResourceAMM.sol` — 71.74%.** `removeLiquidity` edge cases, `quoteOut`, and
   proportional `addLiquidity` re-deposits need direct coverage.
3. **`NFTRentalVault.sol` — 77.59%** and **`GameItems.sol` — 75%.** Remaining
   view/branch paths (`updateListing`, `quoteRent`, `burnBatch`, `setBaseURI`).

Branch percentages reported by `forge coverage` are low across the board because
the tool counts each `require`/custom-error path as a branch; the revert paths are
tested via `vm.expectRevert`, which `--ir-minimum` coverage under-attributes.

## Reproduce

```bash
forge coverage --match-path 'test/*.t.sol' --ir-minimum --report summary
forge coverage --match-path 'test/*.t.sol' --ir-minimum --report lcov   # lcov.info
```
