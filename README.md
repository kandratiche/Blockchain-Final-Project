# RealmForge — Phase 1

**GameFi Economy on L2** | Foundry · Solidity 0.8.24 · Arbitrum Sepolia

This repo contains the first half (3 of 6 contracts) of the RealmForge GameFi economy.

---

## Contracts

| Contract | Description |
|---|---|
| `GameItems.sol` | ERC-1155 registry. Token IDs 1–3 are fungible resources ($IRON, $WOOD, $MANA). IDs ≥1000 are equipment NFTs. Role-gated minting and burning. |
| `LootVRF.sol` | Chainlink VRF v2.5 consumer. Player burns $MANA → random loot minted. Drop table weights controlled by owner (DAO). |
| `ResourceAMM.sol` | Constant-product AMM (x·y=k) for resource pairs. LP shares, fee accrual to treasury, swap fee settable by owner (DAO). |

---

## Phase 2 (not yet implemented)

| Contract | Description |
|---|---|
| `CraftingEngine.sol` | Burns resource inputs per recipe, mints output equipment NFT via GameItems. Recipes updated by DAO. |
| `NFTRentalVault.sol` | ERC-4907-compatible vault. Owner deposits NFT, sets daily price and max duration. Renter pays $MANA, receives timed user rights. |
| `GameDAO.sol` | OpenZeppelin Governor + TimelockController. Voting token = $MANA. Governs drop rates, crafting recipes, AMM fee. |

---

## Setup

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash && foundryup

# Install dependencies
forge install OpenZeppelin/openzeppelin-contracts
forge install smartcontractkit/chainlink

# Run tests
forge test -vv

# Fuzz tests only
forge test --match-test testFuzz -vv
```

---

## Deploy (Arbitrum Sepolia)

```bash
cp .env.example .env
# Fill in all env vars

forge script script/Deploy.s.sol \
  --rpc-url $ARBITRUM_SEPOLIA_RPC \
  --broadcast \
  --verify \
  -vvvv
```

### Required env vars

| Variable | Description |
|---|---|
| `ADMIN_ADDRESS` | Deployer wallet |
| `VRF_COORDINATOR` | `0x5CE8D5A2BC84be...` (Arbitrum Sepolia) |
| `VRF_SUBSCRIPTION_ID` | Your Chainlink subscription ID |
| `VRF_KEY_HASH` | Gas lane key hash |
| `TREASURY_ADDRESS` | Receives AMM swap fees |
| `BASE_URI` | Metadata base URI, e.g. `https://api.realmforge.io/meta/` |

Chainlink VRF addresses: https://docs.chain.link/vrf/v2-5/supported-networks

---

## Architecture

```
         ┌─────────────┐
         │  GameItems  │  ERC-1155 (resources + equipment)
         └──────┬──────┘
         ┌──────┼──────┐
         │             │
  ┌──────▼──────┐  ┌───▼──────────┐
  │   LootVRF   │  │ ResourceAMM  │
  │ Chainlink   │  │  x · y = k   │
  │    VRF      │  │  LP + fees   │
  └─────────────┘  └──────────────┘
  (Phase 2 → CraftingEngine, RentalVault, GameDAO)
```

---

## Tests

```
RealmForge.t.sol
├── GameItemsTest
│   ├── test_mintResource_iron
│   ├── test_mintResource_revertsOnInvalidId
│   ├── test_mintEquipment
│   ├── test_burn
│   ├── test_unauthorizedMintReverts
│   └── testFuzz_mintResource          (fuzz, 256 runs)
└── ResourceAMMTest
    ├── test_addLiquidity_firstDeposit
    ├── test_swap_ironForWood
    ├── test_swap_rejectsSlippage
    ├── test_removeLiquidity
    ├── test_setFeeBps_onlyOwner
    ├── testFuzz_swap                  (fuzz, 256 runs)
    └── testFuzz_kInvariant            (fuzz, 256 runs)
```

---

## License

MIT
