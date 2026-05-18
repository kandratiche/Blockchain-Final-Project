# RealmForge — Internal Security Audit Report

**Auditor:** RealmForge engineering team (internal review).
**Date:** 2026-05-18.
**Commit in scope:** `3e1d5b6` (branch `main`).

---

## 1. Executive Summary

RealmForge is a GameFi economy on Arbitrum Sepolia: an ERC-1155 item registry,
a constant-product AMM for resources, a Chainlink-VRF loot system, a recipe-based
crafting engine, an ERC-4907-style NFT rental vault, an ERC-4626 staking vault,
and a full OpenZeppelin Governor + Timelock governance stack.

This internal review combined automated analysis (Slither, `forge` fuzzing /
coverage) with manual line-by-line review. The codebase is generally well
structured: it consistently uses `SafeERC20`-equivalent ERC-1155 transfers,
custom errors, the Checks-Effects-Interactions pattern, role-based access
control, and reentrancy guards on the newer modules.

One **High** severity issue was identified — a reentrancy window in
`ResourceAMM.swap` where the output transfer precedes the reserve update. Two
**Medium** centralization issues concern privileged roles retained by the
deployer. The remaining findings are Low / Informational / Gas.

| Severity | Count |
|---|---|
| Critical | 0 |
| High | 1 |
| Medium | 2 |
| Low | 3 |
| Informational | 2 |
| Gas | 1 |

---

## 2. Scope

**In scope** (`src/`, commit `3e1d5b6`):

| File | Notes |
|---|---|
| `GameItems.sol` | ERC-1155 registry |
| `LootVRF.sol` | Chainlink VRF v2.5 consumer |
| `ResourceAMM.sol` | constant-product AMM |
| `CraftingEngine.sol` | recipe crafting |
| `NFTRentalVault.sol` | equipment rental vault |
| `RealmToken.sol` | ERC20Votes governance token |
| `GameDAO.sol` | Governor stack |
| `GameRegistryV1/V2.sol` | UUPS-upgradeable registry |
| `GuildFactory.sol`, `Guild.sol` | CREATE/CREATE2 factory |
| `RealmStakeVault.sol` | ERC-4626 vault |
| `PriceOracle.sol` | Chainlink price adapter |
| `SumBench.sol` | Yul gas benchmark |

**Out of scope:** `lib/` (OpenZeppelin v5.6.1, Chainlink — assumed correct),
`script/`, `test/`, `src/mocks/`, the frontend, and the subgraph mappings.

---

## 3. Methodology

1. **Static analysis** — Slither, configured by `slither.config.json`, run in CI
   on every push/PR (`fail-on: medium`).
2. **Fuzz & invariant testing** — Foundry, 256-run fuzzing on AMM swaps, the
   k-invariant, vault deposit/redeem, crafting, rentals, and governance power.
3. **Fork testing** — against live mainnet USDC, Uniswap V2, and the Chainlink
   ETH/USD feed.
4. **Manual review** — control-flow review of every external function, focused
   on reentrancy, access control, oracle handling, and upgrade-storage safety.
5. **Pattern audit** — verification of Checks-Effects-Interactions,
   pull-over-push, role gating, and the documented UUPS storage layout.

---

## 4. Findings

### H-01 — Reentrancy: `ResourceAMM.swap` transfers output before updating reserves

- **Severity:** High
- **Status:** Open — fix recommended
- **Location:** `src/ResourceAMM.sol`, `swap()` (output transfer / reserve update)

**Description.** `swap` computes `amountOut` from the current reserves, then
performs ERC-1155 transfers, and only afterwards writes the new reserves:

```
items.safeTransferFrom(address(this), msg.sender, tokenOut, amountOut, "");
// ...reserves updated AFTER this point...
p.reserveA = ...; p.reserveB = ...;
```

`ERC1155.safeTransferFrom` invokes `onERC1155Received` on `msg.sender`. A
contract trader can reenter `swap` from that callback while `p.reserveA` /
`p.reserveB` still hold pre-swap values.

**Impact.** A reentrant swap is priced against stale reserves while the pool's
real token balances have already moved, allowing a trader to extract value from
the pool — potentially draining liquidity. The `swap` function has neither a
`ReentrancyGuard` nor a strict Checks-Effects-Interactions ordering.

**Proof of concept.** A malicious `ERC1155Holder` calls `swap`; in its
`onERC1155Received` it calls `swap` again before the first call's reserve write,
obtaining a second output at the original price.

**Recommendation.** Either (preferred) add OpenZeppelin `ReentrancyGuard` and
mark `swap`, `addLiquidity`, `removeLiquidity` as `nonReentrant`, **and** reorder
`swap` so reserves are written before the output transfer (true CEI). This
finding is the team's designated **reentrancy case study**: the fix lands with a
before/after test (`test_swap_reentrancy_blocked`).

---

### M-01 — Centralization: `RealmToken` MINTER_ROLE retained by the deployer

- **Severity:** Medium
- **Status:** Open — operational fix
- **Location:** `src/RealmToken.sol`, constructor; `script/Deploy.s.sol`

**Description.** The deployer is granted `MINTER_ROLE` on `RealmToken` and the
deploy script does not transfer or renounce it. A `MINTER_ROLE` holder can mint
unlimited RLM.

**Impact.** Unlimited minting translates directly into unlimited voting power —
a single key can capture the DAO, bypassing quorum and the proposal threshold.

**Recommendation.** After the initial supply is minted, `grantRole(MINTER_ROLE,
timelock)` then `renounceRole(MINTER_ROLE, deployer)`, so any future mint must
pass governance. Add this to the deploy script and assert it in the
post-deployment verification script.

---

### M-02 — Centralization: `GameItems` admin can grant mint/burn at will

- **Severity:** Medium
- **Status:** Acknowledged
- **Location:** `src/GameItems.sol`, `DEFAULT_ADMIN_ROLE`

**Description.** `DEFAULT_ADMIN_ROLE` on `GameItems` is held by the deployer and
can grant `MINTER_ROLE` / `BURNER_ROLE` to any address — i.e. mint arbitrary
resources or equipment, or burn any holder's items.

**Impact.** A compromised deployer key can inflate the in-game economy or
destroy player inventory.

**Recommendation.** Transfer `DEFAULT_ADMIN_ROLE` to the Timelock once roles are
wired, and renounce it from the deployer. Until then, the trust assumption is
documented in `ARCHITECTURE.md §5`.

---

### L-01 — `ResourceAMM` has no circuit breaker

- **Severity:** Low
- **Status:** Acknowledged
- **Location:** `src/ResourceAMM.sol`

**Description.** Unlike `CraftingEngine` and `NFTRentalVault`, the AMM has no
`Pausable` guard. If a pricing bug or the H-01 reentrancy is being exploited,
there is no way to halt swaps while a fix is governed in.

**Recommendation.** Add `Pausable` with a `PAUSER_ROLE` held by the Timelock (or
a fast-response guardian multisig).

---

### L-02 — `LootVRF.requestLoot` has no pending-request bound

- **Severity:** Low
- **Status:** Acknowledged
- **Location:** `src/LootVRF.sol`, `requestLoot()`

**Description.** A player may open unlimited concurrent VRF requests (each burns
MANA, so it is self-limiting in cost). There is no per-player cap.

**Impact.** Low — bounded by the player's MANA. Mainly a subscription-funding
consideration: many pending requests consume LINK from the VRF subscription.

**Recommendation.** Optionally track and cap pending requests per player.

---

### L-03 — `NFTRentalVault` allows zero-price rentals

- **Severity:** Low
- **Status:** Acknowledged (intended)
- **Location:** `src/NFTRentalVault.sol`, `list()` / `rent()`

**Description.** `pricePerDay` may be `0`, producing free rentals; `rent` guards
against this with `if (total > 0)`.

**Impact.** None beyond owner intent — a free listing is a deliberate choice.
Documented so it is not mistaken for a missing check.

---

### I-01 — `LootVRF` has 0% test coverage

- **Severity:** Informational
- **Status:** Open
- **Location:** `test/`

**Description.** `LootVRF` is not exercised by any test; a
`VRFCoordinatorV2_5Mock` and request/fulfil tests are missing. See
`docs/COVERAGE.md`.

**Recommendation.** Add the VRF mock and tests for `requestLoot`,
`fulfillRandomWords`, drop-table resolution, and `setDropTable` weight
validation, to bring the contract above the 90% line target.

---

### I-02 — Formatting / lint enforcement

- **Severity:** Informational
- **Status:** Resolved
- **Description.** `forge fmt --check`, Slither, and frontend Prettier are now
  enforced by the GitHub Actions CI pipeline (`.github/workflows/ci.yml`); a red
  pipeline blocks merge.

---

### G-01 — Repeated `keccak256(abi.encode(...))` for pool keys

- **Severity:** Gas
- **Status:** Acknowledged
- **Location:** `src/ResourceAMM.sol`

**Description.** Several functions recompute the pool key. Computing it once and
passing it internally would save hashing/encoding gas on the hot path.

---

## 5. Centralization Analysis

| Power | Holder | Risk if malicious / compromised |
|---|---|---|
| Schedule & execute governance actions | Timelock (via Governor) | Bounded by 2-day delay, quorum, vote; community can react |
| Propose / cancel | GameDAO | Cannot act without a passing vote |
| Execute scheduled op | anyone (`address(0)`) | None — action + delay fixed at schedule time |
| Mint RLM | deployer (M-01) | **DAO capture** — must move to Timelock |
| Grant mint/burn on GameItems | deployer (M-02) | Economy inflation / inventory burn — must move to Timelock |
| Upgrade GameRegistry | Timelock | Governed; UUPS auth is owner-gated |

The intended end state is: every privileged role held by the Timelock, the
deployer holding nothing. The deploy script already renounces the deployer's
temporary Timelock admin; M-01 and M-02 close the remaining two gaps.

---

## 6. Governance Attack Analysis

- **Flash-loan vote attack.** `RealmToken` is `ERC20Votes`: voting weight is read
  from a checkpoint at the proposal snapshot (`proposalSnapshot`), which is one
  voting-delay (1 day) after `propose`. Tokens flash-borrowed *after* the
  snapshot carry no weight. A borrow that spans the snapshot would have to be
  held for ≥1 day — not a flash loan.
- **Whale attack.** A holder of >4% can meet quorum and >1% can propose. This is
  inherent to token governance; the 2-day Timelock delay gives the community a
  reaction window to exit or fork before any malicious proposal executes.
- **Proposal spam.** The 1% proposal threshold (10,000 RLM) makes spamming
  costly — a spammer must hold real, delegated stake.
- **Timelock bypass.** The Governor is the only `PROPOSER`/`CANCELLER`; the
  Timelock executes nothing that was not scheduled by a passed proposal. The
  deployer's temporary admin is renounced at deploy time.
- **Residual risk:** M-01 — if RLM minting is not moved to the Timelock, the
  mint key trivially defeats all of the above.

---

## 7. Oracle Attack Analysis

- **Stale price.** `PriceOracle.getPrice` reverts (`StalePrice`) when
  `block.timestamp - updatedAt > maxStaleness`. Tested by
  `test_getPrice_revertsOnStalePrice`.
- **Invalid / negative answer.** `getPrice` reverts (`InvalidPrice`) on any
  `answer <= 0`, covering a feed returning `0` or a negative value.
- **Price manipulation.** The oracle reads a Chainlink aggregator, not an
  on-chain AMM spot price, so it is not manipulable by a single-block swap. It
  cannot defend against a correctly-signed but wrong answer from Chainlink
  itself — an accepted trust assumption.
- **Feed depeg / swap.** `setFeed` is owner-gated (the Timelock), so a
  compromised feed can be replaced only through governance.
- **VRF.** `LootVRF` consumes Chainlink VRF v2.5; randomness is never derived
  from `block.timestamp` or `blockhash`. `fulfillRandomWords` is guarded against
  double-fulfilment (`require(!req.fulfilled)`).

---

## 8. Security Checklist

| Control | Status |
|---|---|
| No `tx.origin` authorization | ✅ |
| No `block.timestamp` as randomness | ✅ (Chainlink VRF) |
| No deprecated `transfer`/`send` for ETH | ✅ (no raw ETH paths) |
| ERC-1155 transfers via OZ `safeTransferFrom` | ✅ |
| Reentrancy guards on state-changing entry points | ⚠️ present on new modules; **H-01** open on `ResourceAMM` |
| Privileged functions role-gated | ✅ |
| Custom errors / explicit reverts | ✅ |
| Checks-Effects-Interactions | ⚠️ followed except **H-01** |

---

## Appendix A — Slither

Slither runs in CI (`.github/workflows/ci.yml`, job `slither`) using
`slither.config.json`, and locally with:

```bash
slither . --config slither.config.json
```

The submission build must show **zero High and zero Medium** Slither findings;
all Low/Informational findings are to be enumerated and justified here. The raw
Slither output is attached to the final submission as `docs/slither-output.txt`.

## Appendix B — Reproduced & fixed vulnerability case studies

The project carries two before/after case studies, as required:

1. **Reentrancy — H-01 (`ResourceAMM.swap`).** Before: reentrant `swap` via
   `onERC1155Received`. After: `nonReentrant` + reserves written before the
   output transfer. Tests: `test_swap_reentrancy_blocked` (before fails / after
   passes).
2. **Access control.** Before: a privileged setter callable by any address
   (regression test `test_setManaFee_unprotected`). After: `onlyRole(DAO_ROLE)`
   on `CraftingEngine.setManaFee`, proven by `test_setManaFee_onlyDao`.
