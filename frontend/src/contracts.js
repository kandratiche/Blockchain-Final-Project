import { parseAbi } from "viem";

/** Deployed addresses, injected via Vite env vars. */
export const ADDRESSES = {
  gameItems: import.meta.env.VITE_GAME_ITEMS,
  resourceAmm: import.meta.env.VITE_RESOURCE_AMM,
  craftingEngine: import.meta.env.VITE_CRAFTING_ENGINE,
  realmToken: import.meta.env.VITE_REALM_TOKEN,
  gameDao: import.meta.env.VITE_GAME_DAO,
};

/** GameItems token IDs for the fungible resources. */
export const RESOURCE = { IRON: 1n, WOOD: 2n, MANA: 3n };

// ─── Human-readable ABIs (only the members the dApp uses) ────────────────────

export const realmTokenAbi = parseAbi([
  "function balanceOf(address) view returns (uint256)",
  "function getVotes(address) view returns (uint256)",
  "function delegates(address) view returns (address)",
  "function delegate(address delegatee)",
]);

export const gameItemsAbi = parseAbi([
  "function balanceOf(address account, uint256 id) view returns (uint256)",
  "function isApprovedForAll(address account, address operator) view returns (bool)",
  "function setApprovalForAll(address operator, bool approved)",
]);

export const resourceAmmAbi = parseAbi([
  "function getReserves(uint256 tA, uint256 tB) view returns (uint256 rA, uint256 rB)",
  "function quoteOut(uint256 tokenIn, uint256 tokenOut, uint256 amountIn) view returns (uint256)",
  "function swap(uint256 tokenIn, uint256 tokenOut, uint256 amountIn, uint256 minAmountOut) returns (uint256)",
]);

export const craftingEngineAbi = parseAbi([
  "function manaFee() view returns (uint256)",
  "function recipeExists(uint256 recipeId) view returns (bool)",
  "function craft(uint256 recipeId) returns (uint256)",
]);

export const gameDaoAbi = parseAbi([
  "function state(uint256 proposalId) view returns (uint8)",
  "function castVote(uint256 proposalId, uint8 support) returns (uint256)",
]);

/** Governor proposal states, indexed by the uint8 the contract returns. */
export const PROPOSAL_STATES = [
  "Pending",
  "Active",
  "Canceled",
  "Defeated",
  "Succeeded",
  "Queued",
  "Expired",
  "Executed",
];
