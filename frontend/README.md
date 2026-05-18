# RealmForge dApp

React + Vite frontend for the RealmForge GameFi protocol, built on **Wagmi v2**
and **Viem**.

## Features

- **Wallet** — MetaMask (injected) connector; WalletConnect as an optional
  second connector when `VITE_WALLETCONNECT_PROJECT_ID` is set.
- **Network detection** — detects the wrong chain and prompts a one-click
  switch to Arbitrum Sepolia.
- **Reads** — RLM balance, voting power, delegate address, MANA balance, and the
  IRON/WOOD AMM pool reserves (protocol-specific state).
- **Writes** — four state-changing transactions from the UI:
  1. `swap` IRON → WOOD on the ResourceAMM (with a 1% slippage floor)
  2. `craft` an item on the CraftingEngine
  3. `castVote` on a governance proposal
  4. `delegate` to self to activate voting power
- **Governance** — proposal list with derived state
  (Pending / Active / Succeeded / Defeated / Executed) and vote buttons. This
  section reads from **The Graph subgraph**, not directly from the contract.
- **Error handling** — wallet rejections, wrong network, and insufficient
  balances surface as readable messages (`src/lib/errors.js`); no raw RPC blobs.

## Setup

```bash
cd frontend
npm install
cp .env.example .env   # fill in deployed addresses + subgraph URL
npm run dev
```

## Structure

```
src/
  config.js            wagmi config (chain, connectors, transport)
  contracts.js         addresses + human-readable ABIs
  lib/errors.js        RPC error -> readable message
  lib/subgraph.js      The Graph query helpers
  components/
    Wallet.jsx         connect / disconnect / network switch
    Balances.jsx       on-chain reads + self-delegate
    Swap.jsx           AMM swap
    Crafting.jsx       crafting
    Governance.jsx     subgraph-backed proposal list + voting
```
