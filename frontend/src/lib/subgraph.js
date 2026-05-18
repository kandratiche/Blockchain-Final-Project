const SUBGRAPH_URL = import.meta.env.VITE_SUBGRAPH_URL;

/** Minimal GraphQL POST helper for the RealmForge subgraph. */
async function query(gql, variables) {
  const res = await fetch(SUBGRAPH_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ query: gql, variables }),
  });
  if (!res.ok) throw new Error(`Subgraph HTTP ${res.status}`);
  const json = await res.json();
  if (json.errors) throw new Error(json.errors[0]?.message || "Subgraph error");
  return json.data;
}

/** Fetch governance proposals with their tallies — indexed by The Graph. */
export async function fetchProposals() {
  const data = await query(`
    {
      proposals(orderBy: voteStart, orderDirection: desc, first: 25) {
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
  `);
  return data.proposals;
}

/** Fetch the most recent swaps for the activity feed. */
export async function fetchRecentSwaps() {
  const data = await query(`
    {
      swaps(first: 10, orderBy: timestamp, orderDirection: desc) {
        id
        tokenIn
        amountIn
        amountOut
        timestamp
        trader { id }
      }
    }
  `);
  return data.swaps;
}
