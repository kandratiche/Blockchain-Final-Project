import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import {
  PoolCreated,
  Swapped,
  LiquidityAdded,
} from "../generated/ResourceAMM/ResourceAMM";
import { Crafted } from "../generated/CraftingEngine/CraftingEngine";
import { Listed, Rented } from "../generated/NFTRentalVault/NFTRentalVault";
import {
  ProposalCreated,
  VoteCast,
  ProposalExecuted,
} from "../generated/GameDAO/GameDAO";
import {
  Player,
  Pool,
  Swap,
  Craft,
  Rental,
  Proposal,
  Vote,
} from "../generated/schema";

// ─── Helpers ─────────────────────────────────────────────────────────────────

/** Load a Player, creating it with zeroed counters on first sight. */
function loadPlayer(address: string): Player {
  let player = Player.load(address);
  if (player == null) {
    player = new Player(address);
    player.totalSwaps = BigInt.zero();
    player.totalCrafts = BigInt.zero();
    player.save();
  }
  return player as Player;
}

// ─── ResourceAMM ─────────────────────────────────────────────────────────────

export function handlePoolCreated(event: PoolCreated): void {
  // Pool key is derived the same way the contract does: keccak(abi.encode(a,b)).
  let id = event.transaction.hash.toHex() + "-pool";
  let pool = new Pool(id);
  pool.tokenA = event.params.tokenA;
  pool.tokenB = event.params.tokenB;
  pool.reserveA = BigInt.zero();
  pool.reserveB = BigInt.zero();
  pool.totalShares = BigInt.zero();
  pool.swapCount = BigInt.zero();
  pool.save();
}

export function handleLiquidityAdded(event: LiquidityAdded): void {
  let id = event.params.key.toHex();
  let pool = Pool.load(id);
  if (pool == null) {
    pool = new Pool(id);
    pool.tokenA = BigInt.zero();
    pool.tokenB = BigInt.zero();
    pool.reserveA = BigInt.zero();
    pool.reserveB = BigInt.zero();
    pool.totalShares = BigInt.zero();
    pool.swapCount = BigInt.zero();
  }
  pool.reserveA = pool.reserveA.plus(event.params.amtA);
  pool.reserveB = pool.reserveB.plus(event.params.amtB);
  pool.totalShares = pool.totalShares.plus(event.params.shares);
  pool.save();
}

export function handleSwapped(event: Swapped): void {
  let trader = loadPlayer(event.params.trader.toHex());
  trader.totalSwaps = trader.totalSwaps.plus(BigInt.fromI32(1));
  trader.save();

  let poolId = event.params.key.toHex();
  let pool = Pool.load(poolId);
  if (pool == null) {
    pool = new Pool(poolId);
    pool.tokenA = BigInt.zero();
    pool.tokenB = BigInt.zero();
    pool.reserveA = BigInt.zero();
    pool.reserveB = BigInt.zero();
    pool.totalShares = BigInt.zero();
    pool.swapCount = BigInt.zero();
  }
  pool.swapCount = pool.swapCount.plus(BigInt.fromI32(1));
  pool.save();

  let swap = new Swap(
    event.transaction.hash.toHex() + "-" + event.logIndex.toString()
  );
  swap.pool = poolId;
  swap.trader = trader.id;
  swap.tokenIn = event.params.tokenIn;
  swap.amountIn = event.params.amountIn;
  swap.amountOut = event.params.amountOut;
  swap.blockNumber = event.block.number;
  swap.timestamp = event.block.timestamp;
  swap.txHash = event.transaction.hash;
  swap.save();
}

// ─── CraftingEngine ──────────────────────────────────────────────────────────

export function handleCrafted(event: Crafted): void {
  let player = loadPlayer(event.params.player.toHex());
  player.totalCrafts = player.totalCrafts.plus(BigInt.fromI32(1));
  player.save();

  let craft = new Craft(
    event.transaction.hash.toHex() + "-" + event.logIndex.toString()
  );
  craft.player = player.id;
  craft.recipeId = event.params.recipeId;
  craft.equipmentTokenId = event.params.equipmentTokenId;
  craft.timestamp = event.block.timestamp;
  craft.txHash = event.transaction.hash;
  craft.save();
}

// ─── NFTRentalVault ──────────────────────────────────────────────────────────

export function handleListed(event: Listed): void {
  let owner = loadPlayer(event.params.owner.toHex());
  let id = event.params.equipmentId.toString();
  let rental = new Rental(id);
  rental.equipmentId = event.params.equipmentId;
  rental.owner = owner.id;
  rental.renter = null;
  rental.pricePaid = BigInt.zero();
  rental.expires = BigInt.zero();
  rental.active = true;
  rental.timestamp = event.block.timestamp;
  rental.save();
}

export function handleRented(event: Rented): void {
  let id = event.params.equipmentId.toString();
  let rental = Rental.load(id);
  if (rental == null) return;
  rental.renter = event.params.renter;
  rental.pricePaid = event.params.paid;
  rental.expires = BigInt.fromI32(event.params.expires);
  rental.timestamp = event.block.timestamp;
  rental.save();
}

// ─── GameDAO ─────────────────────────────────────────────────────────────────

export function handleProposalCreated(event: ProposalCreated): void {
  let proposer = loadPlayer(event.params.proposer.toHex());
  let proposal = new Proposal(event.params.proposalId.toString());
  proposal.proposer = proposer.id;
  proposal.description = event.params.description;
  proposal.voteStart = event.params.voteStart;
  proposal.voteEnd = event.params.voteEnd;
  proposal.forVotes = BigInt.zero();
  proposal.againstVotes = BigInt.zero();
  proposal.abstainVotes = BigInt.zero();
  proposal.executed = false;
  proposal.save();
}

export function handleVoteCast(event: VoteCast): void {
  let proposal = Proposal.load(event.params.proposalId.toString());
  if (proposal == null) return;

  let support = event.params.support;
  let weight = event.params.weight;
  if (support == 0) {
    proposal.againstVotes = proposal.againstVotes.plus(weight);
  } else if (support == 1) {
    proposal.forVotes = proposal.forVotes.plus(weight);
  } else {
    proposal.abstainVotes = proposal.abstainVotes.plus(weight);
  }
  proposal.save();

  let vote = new Vote(
    event.transaction.hash.toHex() + "-" + event.logIndex.toString()
  );
  vote.proposal = proposal.id;
  vote.voter = event.params.voter;
  vote.support = support;
  vote.weight = weight;
  vote.timestamp = event.block.timestamp;
  vote.save();
}

export function handleProposalExecuted(event: ProposalExecuted): void {
  let proposal = Proposal.load(event.params.proposalId.toString());
  if (proposal == null) return;
  proposal.executed = true;
  proposal.save();
}
