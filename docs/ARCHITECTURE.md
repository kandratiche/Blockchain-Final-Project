# RealmForge — Architecture & Design Document

**Scenario:** Option B — GameFi Economy.
**Network:** Arbitrum Sepolia (L2).
**Toolchain:** Foundry · Solidity 0.8.24 · OpenZeppelin v5.6.1 · Chainlink VRF v2.5.

---

## 1. System Context (C4 Level 1)

```
                ┌──────────────────────────────────────────────┐
                │                  PLAYER                      │
                │  (browser wallet — MetaMask / WalletConnect)  │
                └───────────────┬──────────────────────────────┘
                                │ signs transactions / reads state
                ┌───────────────▼──────────────┐
                │        RealmForge dApp        │  React + Wagmi + Viem
                └───────┬───────────────┬───────┘
            reads via   │               │  writes via JSON-RPC
        ┌───────────────▼───┐   ┌───────▼──────────────────────┐
        │  The Graph         │   │   RealmForge contracts        │
        │  (subgraph index)  │◄──┤   on Arbitrum Sepolia (L2)    │
        └────────────────────┘   └───────┬──────────────────────┘
                  events                 │ requests randomness
                                 ┌───────▼────────┐
                                 │  Chainlink VRF  │  external oracle
                                 │  + price feeds  │
                                 └─────────────────┘
```

External dependencies: **Chainlink** (VRF randomness, price feeds), **The Graph**
(event indexing), the **Arbitrum Sepolia** L2 sequencer.

---

## 2. Container / Component Diagram

```
                         ┌───────────────────────────┐
                         │   GameDAO (Governor)       │
                         │   + TimelockController     │  governance
                         │   votes: RealmToken (RLM)  │
                         └────────────┬───────────────┘
                       owns / privileged-setter caller
   ┌──────────────┬───────────────┬───┴───────────┬────────────────┐
   ▼              ▼               ▼               ▼                ▼
┌────────┐  ┌────────────┐  ┌──────────────┐ ┌───────────────┐ ┌──────────────┐
│LootVRF │  │ResourceAMM │  │CraftingEngine│ │NFTRentalVault │ │ PriceOracle  │
│VRF v2.5│  │ x·y=k AMM  │  │ recipes      │ │ ERC-4907-style│ │ Chainlink    │
└───┬────┘  └─────┬──────┘  └──────┬───────┘ └──────┬────────┘ └──────────────┘
    │ MINTER/BURNER│ ERC1155 xfer  │ MINTER/BURNER  │ custody
    └──────────────┴───────┬───────┴────────────────┘
                           ▼
                  ┌──────────────────┐
                  │    GameItems     │  ERC-1155 (resources 1-3, equipment ≥1000)
                  └──────────────────┘

   Infrastructure layer (not DAO-critical):
   ┌────────────────┐  ┌──────────────┐  ┌───────────────┐  ┌──────────┐
   │ GameRegistry   │  │ GuildFactory │  │ RealmStakeVault│ │ SumBench │
   │ UUPS proxy V1/V2│ │ CREATE/CREATE2│ │ ERC-4626 (RLM)│  │ Yul bench│
   └────────────────┘  └──────────────┘  └───────────────┘  └──────────┘
```

### Access-control roles

| Contract | Role / owner | Holder (production) |
|---|---|---|
| GameItems | `DEFAULT_ADMIN_ROLE` | Deployer (role manager) |
| GameItems | `MINTER_ROLE`, `BURNER_ROLE` | LootVRF, CraftingEngine |
| LootVRF | `owner` (ConfirmedOwner) | Timelock |
| ResourceAMM | `owner` (Ownable) | Timelock |
| CraftingEngine | `DAO_ROLE`, `PAUSER_ROLE` | Timelock |
| NFTRentalVault | `owner` (Ownable, pause only) | Timelock |
| GameRegistry | `owner` (UUPS upgrade auth) | Timelock |
| TimelockController | `PROPOSER`, `CANCELLER` | GameDAO |
| TimelockController | `EXECUTOR` | `address(0)` (open) |
| RealmToken | `MINTER_ROLE` | Deployer → Timelock |

---

## 3. Sequence Diagrams — Critical Flows

### 3.1 AMM swap

```
Player        GameItems            ResourceAMM
  │ setApprovalForAll(amm,true)        │
  ├───────────────►│                   │
  │ swap(IRON,WOOD,amtIn,minOut)        │
  ├────────────────────────────────────►│
  │                │  checks reserves   │
  │                │  computes amountOut (fee 0.3%)
  │                │  require out >= minOut  (slippage guard)
  │   safeTransferFrom(player→treasury, fee)
  │                │◄──────────────────┤
  │   safeTransferFrom(player→amm, amtIn-fee)
  │                │◄──────────────────┤
  │   safeTransferFrom(amm→player, amountOut)
  │                │◄──────────────────┤
  │                │  update reserves   │
  │◄───────────────────────────────────┤ amountOut
```

### 3.2 Governance — propose → vote → queue → execute

```
Proposer    GameDAO         TimelockController   Target (e.g. CraftingEngine)
  │ propose(targets,values,calldatas,desc)  │             │
  ├──────────►│ state = Pending             │             │
  │           │ ...voting delay (1 day)...  │             │
  │ castVote(id, support)                   │             │
  ├──────────►│ tally; state = Active        │            │
  │           │ ...voting period (1 week)... │            │
  │           │ state = Succeeded            │            │
  │ queue(...)│                              │            │
  ├──────────►│ scheduleBatch ──────────────►│ (2-day delay)│
  │           │ state = Queued               │             │
  │           │ ...timelock delay...         │             │
  │ execute(...)                             │             │
  ├──────────►│ executeBatch ───────────────►│ call ───────►│ setManaFee(x)
  │           │ state = Executed             │             │
```

### 3.3 Loot drop via Chainlink VRF

```
Player      LootVRF        VRF Coordinator      GameItems
  │ requestLoot()              │                    │
  ├──────────►│ burn(MANA cost) ──────────────────►  │
  │           │ requestRandomWords() ──────►│        │
  │◄──────────┤ requestId                   │        │
  │           │       ...VRF callback...    │        │
  │           │◄── fulfillRandomWords(id,words)       │
  │           │ resolve drop table          │        │
  │           │ mintResource / mintEquipment ──────► │
```

---

## 4. Data Model — Storage Layouts

Non-upgradeable contracts use standard sequential storage. The **upgradeable**
`GameRegistry` requires an explicit, collision-proof layout.

### GameRegistryV1 (behind an ERC-1967 proxy)

| Slot | Variable | Type |
|---|---|---|
| 0 | `owner` | `address` |
| 1 | `_xp` | `mapping(address => uint256)` |
| 2 | `xpPerLevel` | `uint256` |

### GameRegistryV2 (`is GameRegistryV1`)

| Slot | Variable | Origin |
|---|---|---|
| 0–2 | `owner`, `_xp`, `xpPerLevel` | inherited from V1, **unchanged** |
| 3 | `_achievements` | **new — appended** |

**Collision proof.** V2 inherits V1 and declares its new mapping *after* every
V1 variable. Solidity assigns inherited storage first, in declaration order, so
V1 slots 0–2 keep their meaning and `_achievements` can only land at slot 3. No
V1 variable is reordered, retyped, or removed. `Initializable` /
`UUPSUpgradeable` from OZ's main package are stateless (no storage), so they add
no slots. Confirmed by `test_upgradeToV2_preservesStorage`.

### Pool storage (ResourceAMM)

`mapping(bytes32 => Pool)` where `Pool { reserveA, reserveB, totalShares }` and
the key is `keccak256(abi.encode(loToken, hiToken))` with `loToken < hiToken`,
so each unordered pair maps to exactly one pool.

---

## 5. Trust Assumptions

- **TimelockController** is the root of authority. It owns the privileged setters
  of every protocol contract and the UUPS upgrade authorization of GameRegistry.
  It can only act on operations that the Governor has scheduled, after the 2-day
  delay. It cannot mint RLM or move user funds directly.
- **GameDAO (Governor)** is the only `PROPOSER`/`CANCELLER` on the Timelock. It
  cannot act without a proposal that clears quorum (4%) and the vote.
- **Deployer** retains `DEFAULT_ADMIN_ROLE` on GameItems (to manage mint/burn
  roles) and initially `MINTER_ROLE` on RealmToken. Production hardening:
  transfer both to the Timelock and renounce. The deploy script already
  renounces the deployer's temporary Timelock admin.
- **`EXECUTOR_ROLE` is open (`address(0)`)** — anyone may execute an already
  scheduled operation. This is safe: the action and its delay are fixed at
  schedule time; an open executor only improves liveness.
- **Chainlink** is trusted for randomness (VRF) and price (feeds). PriceOracle
  defends against a stale or non-positive feed answer; it cannot defend against
  a correctly-signed but manipulated answer.
- **If the deployer key is compromised before role hand-off:** the attacker
  could grant itself mint/burn on GameItems. Mitigation: hand roles to the
  Timelock immediately post-deploy; the post-deployment verification script
  checks that no deployer backdoor remains.

---

## 6. Design Decisions (ADRs)

### ADR-1 — ERC-1155 for both resources and equipment
*Context:* the economy needs fungible resources and unique equipment.
*Options:* separate ERC-20s + ERC-721; one ERC-1155.
*Decision:* a single ERC-1155 (`GameItems`) — IDs 1–3 fungible, IDs ≥1000 unique.
*Consequences:* one approval surface, one mint/burn role set; the rental vault
adapts ERC-4907 semantics to ERC-1155 since 1155 has no native `user` role.

### ADR-2 — Separate ERC20Votes governance token
*Context:* the spec mandates an `ERC20Votes + ERC20Permit` governance token; the
in-game currency MANA is an ERC-1155 id and cannot provide checkpointed votes.
*Decision:* a dedicated `RealmToken` ($RLM) for governance only.
*Consequences:* clean separation of game economy from political power; RLM uses
a timestamp clock (ERC-6372) so Governor delays are second-denominated.

### ADR-3 — Timelock owns every privileged setter
*Context:* DAO must govern drop rates, recipes, crafting cost, AMM fee.
*Decision:* deploy with the Timelock as `owner`/`DAO_ROLE` of LootVRF,
ResourceAMM, CraftingEngine, NFTRentalVault, GameRegistry.
*Consequences:* every parameter change goes through the full governance lifecycle
plus a 2-day delay; no admin can change parameters unilaterally.

### ADR-4 — UUPS over Transparent proxy for GameRegistry
*Context:* one upgradeable contract is required.
*Decision:* UUPS — upgrade logic lives in the implementation, authorized by
`_authorizeUpgrade` (owner-gated).
*Consequences:* cheaper proxy, no `ProxyAdmin` contract; the V2 upgrade path is
tested and the storage layout is documented append-only.

### ADR-5 — Pull-over-push for rental earnings
*Context:* a renter's MANA payment must reach the NFT owner.
*Decision:* credit `earnings[owner]`; the owner withdraws via `claimEarnings`.
*Consequences:* the `rent` path makes no transfer to an arbitrary owner address,
removing a reentrancy/gas-griefing surface; the owner pays their own claim gas.

### ADR-6 — Inline Yul only where it is measured
*Context:* the spec requires benchmarked assembly.
*Decision:* `SumBench` keeps a pure-Solidity reference and a Yul variant, with a
differential fuzz test and a gas benchmark.
*Consequences:* a 28.6% saving on the hot path, provably equivalent; assembly is
confined to one audited function rather than scattered across the codebase.
