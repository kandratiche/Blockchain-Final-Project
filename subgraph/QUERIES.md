# RealmForge Subgraph — Documented Queries

The subgraph indexes the RealmForge protocol on Arbitrum Sepolia. It exposes
**7 entities** — `Player`, `Pool`, `Swap`, `Craft`, `Rental`, `Proposal`,
`Vote` — and the queries below cover the data the dApp reads.

GraphQL endpoint (after `graph deploy`):
`https://api.studio.thegraph.com/query/<id>/realmforge/<version>`

---

## 1. Recent swaps with pool and trader

Used by the frontend "Activity" feed.

```graphql
{
  swaps(first: 20, orderBy: timestamp, orderDirection: desc) {
    id
    tokenIn
    amountIn
    amountOut
    timestamp
    trader { id }
    pool { id tokenA tokenB }
  }
}
```

## 2. AMM pools with live reserves

Drives the swap UI's price quote and reserve display.

```graphql
{
  pools(orderBy: swapCount, orderDirection: desc) {
    id
    tokenA
    tokenB
    reserveA
    reserveB
    totalShares
    swapCount
  }
}
```

## 3. A player's full activity

```graphql
query Player($addr: ID!) {
  player(id: $addr) {
    id
    totalSwaps
    totalCrafts
    swaps(first: 10, orderBy: timestamp, orderDirection: desc) {
      amountIn
      amountOut
    }
    crafts(first: 10) {
      recipeId
      equipmentTokenId
    }
    rentalsAsOwner {
      equipmentId
      active
    }
  }
}
```

## 4. Governance proposals with running tallies

Powers the proposal list and vote panel. The dApp reads proposal data from
**this query, not the contract**.

```graphql
{
  proposals(orderBy: voteStart, orderDirection: desc) {
    id
    description
    proposer { id }
    voteStart
    voteEnd
    forVotes
    againstVotes
    abstainVotes
    executed
  }
}
```

## 5. Votes cast on a single proposal

```graphql
query ProposalVotes($id: ID!) {
  proposal(id: $id) {
    id
    description
    votes(orderBy: timestamp, orderDirection: desc) {
      voter
      support
      weight
      timestamp
    }
  }
}
```

## 6. Active equipment rentals

```graphql
{
  rentals(where: { active: true }, orderBy: timestamp, orderDirection: desc) {
    equipmentId
    owner { id }
    renter
    pricePaid
    expires
  }
}
```
