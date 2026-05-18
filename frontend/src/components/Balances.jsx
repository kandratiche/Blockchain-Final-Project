import { useAccount, useReadContract, useWriteContract } from "wagmi";
import { formatEther } from "viem";
import {
  ADDRESSES,
  RESOURCE,
  realmTokenAbi,
  gameItemsAbi,
  resourceAmmAbi,
} from "../contracts.js";
import { readableError } from "../lib/errors.js";

/** Reads on-chain state: RLM balance, voting power, delegate, and pool reserves. */
export function Balances() {
  const { address, isConnected } = useAccount();
  const { writeContract, isPending, error } = useWriteContract();

  const rlm = { address: ADDRESSES.realmToken, abi: realmTokenAbi };

  const { data: balance } = useReadContract({
    ...rlm,
    functionName: "balanceOf",
    args: [address],
    query: { enabled: isConnected },
  });
  const { data: votes } = useReadContract({
    ...rlm,
    functionName: "getVotes",
    args: [address],
    query: { enabled: isConnected },
  });
  const { data: delegate } = useReadContract({
    ...rlm,
    functionName: "delegates",
    args: [address],
    query: { enabled: isConnected },
  });

  // Protocol-specific state: the IRON/WOOD AMM pool reserves.
  const { data: reserves } = useReadContract({
    address: ADDRESSES.resourceAmm,
    abi: resourceAmmAbi,
    functionName: "getReserves",
    args: [RESOURCE.IRON, RESOURCE.WOOD],
  });

  const { data: manaBalance } = useReadContract({
    address: ADDRESSES.gameItems,
    abi: gameItemsAbi,
    functionName: "balanceOf",
    args: [address, RESOURCE.MANA],
    query: { enabled: isConnected },
  });

  if (!isConnected) return <section className="card">Connect a wallet to view balances.</section>;

  const notDelegated =
    delegate && delegate === "0x0000000000000000000000000000000000000000";

  return (
    <section className="card">
      <h2>Your position</h2>
      <dl className="grid">
        <dt>RLM balance</dt>
        <dd>{balance != null ? formatEther(balance) : "…"}</dd>
        <dt>Voting power</dt>
        <dd>{votes != null ? formatEther(votes) : "…"}</dd>
        <dt>Delegate</dt>
        <dd>{notDelegated ? "none" : delegate ? `${delegate.slice(0, 10)}…` : "…"}</dd>
        <dt>MANA</dt>
        <dd>{manaBalance != null ? manaBalance.toString() : "…"}</dd>
        <dt>IRON/WOOD reserves</dt>
        <dd>{reserves ? `${reserves[0]} / ${reserves[1]}` : "…"}</dd>
      </dl>

      {notDelegated && (
        <button
          disabled={isPending}
          onClick={() =>
            writeContract({
              ...rlm,
              functionName: "delegate",
              args: [address],
            })
          }
        >
          {isPending ? "Delegating…" : "Activate voting power (self-delegate)"}
        </button>
      )}
      {error && <p className="error">{readableError(error)}</p>}
    </section>
  );
}
