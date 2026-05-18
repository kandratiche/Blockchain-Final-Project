import { useQuery } from "@tanstack/react-query";
import { useAccount, useWriteContract } from "wagmi";
import { formatEther } from "viem";
import { ADDRESSES, gameDaoAbi } from "../contracts.js";
import { fetchProposals } from "../lib/subgraph.js";
import { readableError } from "../lib/errors.js";

/**
 * Proposal list — data is pulled from THE SUBGRAPH (The Graph), not the
 * contract. Each active proposal exposes a vote button. Write transaction #3.
 */
export function Governance() {
  const { isConnected } = useAccount();
  const { writeContract, isPending, error } = useWriteContract();

  const {
    data: proposals,
    isLoading,
    isError,
    error: queryError,
  } = useQuery({
    queryKey: ["proposals"],
    queryFn: fetchProposals,
    refetchInterval: 15_000,
  });

  function vote(proposalId, support) {
    writeContract({
      address: ADDRESSES.gameDao,
      abi: gameDaoAbi,
      functionName: "castVote",
      args: [BigInt(proposalId), support],
    });
  }

  /** Derive a display state from the subgraph fields (no contract call). */
  function displayState(p) {
    if (p.executed) return "Executed";
    const now = Math.floor(Date.now() / 1000);
    if (now < Number(p.voteStart)) return "Pending";
    if (now <= Number(p.voteEnd)) return "Active";
    return Number(p.forVotes) > Number(p.againstVotes) ? "Succeeded" : "Defeated";
  }

  return (
    <section className="card">
      <h2>Governance proposals</h2>
      <p className="muted">Indexed via The Graph subgraph.</p>

      {isLoading && <p>Loading proposals…</p>}
      {isError && <p className="error">Subgraph unavailable: {queryError.message}</p>}
      {proposals && proposals.length === 0 && <p>No proposals yet.</p>}

      {proposals?.map((p) => {
        const state = displayState(p);
        const active = state === "Active";
        return (
          <article key={p.id} className="proposal">
            <header>
              <span className={`pill pill-${state.toLowerCase()}`}>{state}</span>
              <code>#{p.id.slice(0, 10)}…</code>
            </header>
            <p>{p.description || "(no description)"}</p>
            <p className="muted">
              For {formatEther(BigInt(p.forVotes))} · Against{" "}
              {formatEther(BigInt(p.againstVotes))} · Abstain{" "}
              {formatEther(BigInt(p.abstainVotes))}
            </p>
            <div className="wallet-row">
              <button
                disabled={!isConnected || !active || isPending}
                onClick={() => vote(p.id, 1)}
              >
                Vote For
              </button>
              <button
                disabled={!isConnected || !active || isPending}
                onClick={() => vote(p.id, 0)}
              >
                Vote Against
              </button>
            </div>
          </article>
        );
      })}

      {error && <p className="error">{readableError(error)}</p>}
    </section>
  );
}
