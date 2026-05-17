# RealmForge — GameFi Economy

**ERC-1155 in-game item economy on L2** | Foundry · Solidity 0.8.24 · Arbitrum Sepolia

RealmForge is a GameFi protocol: a fungible-resource economy with crafting, an
AMM marketplace, VRF loot drops, an NFT rental market, all governed by a DAO.

---

## Contracts

| Contract | Standard / role | Description |
|---|---|---|
| `GameItems.sol` | ERC-1155 + AccessControl | Item registry. IDs 1–3 are fungible resources ($IRON, $WOOD, $MANA); IDs ≥1000 are equipment NFTs. Role-gated mint/burn. |
| `LootVRF.sol` | Chainlink VRF v2.5 | Player burns $MANA → random loot. Drop-table weights are DAO-governed. |
| `ResourceAMM.sol` | Constant-product AMM | `x·y=k` pools for resource pairs. LP shares, 0.3% fee to treasury. DAO sets the fee. |
| `CraftingEngine.sol` | AccessControl + Pausable | Burns recipe resource inputs + a flat MANA fee, mints an equipment NFT. Recipes & fee are DAO-governed. |
| `NFTRentalVault.sol` | Custodial vault (ERC-4907-style) | Owner deposits an equipment NFT, sets a daily MANA price; renter pays MANA and receives time-bound `user` rights. Pull-based earnings. |
| `RealmToken.sol` | ERC20Votes + ERC20Permit | $RLM governance token. Timestamp clock (ERC-6372). |
| `GameDAO.sol` | OZ Governor + Timelock | Governs drop rates, crafting recipes/costs, AMM fee. 1-day delay, 1-week period, 4% quorum, 1% proposal threshold, 2-day timelock. |

---

## Architecture

```
                       ┌──────────────┐
                       │   GameDAO    │  Governor + TimelockController
                       │  ($RLM votes)│
                       └──────┬───────┘
                  governs (Timelock owns setters)
        ┌─────────────┬───────┼────────┬───────────────┐
        ▼             ▼       ▼        ▼               ▼
   ┌─────────┐  ┌──────────┐ ┌──────────────┐  ┌────────────────┐
   │ LootVRF │  │ResourceAMM│ │CraftingEngine│  │ NFTRentalVault │
   └────┬────┘  └────┬─────┘ └──────┬───────┘  └───────┬────────┘
        │  mint/burn │              │ mint/burn        │ custody
        └────────────┴──────┬───────┴──────────────────┘
                             ▼
                       ┌───────────┐
                       │ GameItems │  ERC-1155 (resources + equipment)
                       └───────────┘
```

---

## Setup

```bash
curl -L https://foundry.paradigm.xyz | bash && foundryup
forge install
forge build
forge test
```

---

## Tests

59 tests across 4 suites — all passing.

```
test/RealmForge.t.sol       GameItems (6) + ResourceAMM (7)
test/CraftingEngine.t.sol   recipes, crafting flow, access control, pause (19)
test/NFTRentalVault.t.sol   list/rent/delist, ERC-4907 rights, earnings (20)
test/GameDAO.t.sol          token votes + full propose→vote→queue→execute (7)
```

```bash
forge test --match-path 'test/*.t.sol' -vv
```

---

## Deploy (Arbitrum Sepolia)

```bash
cp .env.example .env   # fill in all vars

forge script script/Deploy.s.sol \
  --rpc-url $ARBITRUM_SEPOLIA_RPC \
  --broadcast --verify -vvvv
```

The deploy script deploys all 7 contracts, wires every privileged role to the
DAO Timelock, and renounces the deployer's temporary Timelock admin.

### Required env vars

| Variable | Description |
|---|---|
| `ADMIN_ADDRESS` | Deployer / initial admin wallet |
| `VRF_COORDINATOR` | Chainlink VRF Coordinator (Arbitrum Sepolia) |
| `VRF_SUBSCRIPTION_ID` | Chainlink subscription ID |
| `VRF_KEY_HASH` | Gas-lane key hash |
| `TREASURY_ADDRESS` | Receives AMM swap fees |
| `BASE_URI` | Item metadata base URI |

Chainlink VRF addresses: https://docs.chain.link/vrf/v2-5/supported-networks

---

## Governance parameters

| Parameter | Value |
|---|---|
| Voting delay | 1 day |
| Voting period | 1 week |
| Quorum | 4% of supply |
| Proposal threshold | 10,000 RLM (1% of 1,000,000 supply) |
| Timelock delay | 2 days |

---

## License

MIT
