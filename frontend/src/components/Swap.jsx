import { useState } from "react";
import { useAccount, useReadContract, useWriteContract } from "wagmi";
import { ADDRESSES, RESOURCE, resourceAmmAbi, gameItemsAbi } from "../contracts.js";
import { readableError } from "../lib/errors.js";

/** Swap IRON -> WOOD on the ResourceAMM. Write transaction #1. */
export function Swap() {
  const { address, isConnected } = useAccount();
  const [amount, setAmount] = useState("100");
  const { writeContract, isPending, error, isSuccess } = useWriteContract();

  const amountIn = amount && /^\d+$/.test(amount) ? BigInt(amount) : 0n;

  const { data: quote } = useReadContract({
    address: ADDRESSES.resourceAmm,
    abi: resourceAmmAbi,
    functionName: "quoteOut",
    args: [RESOURCE.IRON, RESOURCE.WOOD, amountIn],
    query: { enabled: amountIn > 0n },
  });

  const { data: approved } = useReadContract({
    address: ADDRESSES.gameItems,
    abi: gameItemsAbi,
    functionName: "isApprovedForAll",
    args: [address, ADDRESSES.resourceAmm],
    query: { enabled: isConnected },
  });

  function approve() {
    writeContract({
      address: ADDRESSES.gameItems,
      abi: gameItemsAbi,
      functionName: "setApprovalForAll",
      args: [ADDRESSES.resourceAmm, true],
    });
  }

  function swap() {
    // 1% slippage floor on the quoted output.
    const minOut = quote ? (quote * 99n) / 100n : 0n;
    writeContract({
      address: ADDRESSES.resourceAmm,
      abi: resourceAmmAbi,
      functionName: "swap",
      args: [RESOURCE.IRON, RESOURCE.WOOD, amountIn, minOut],
    });
  }

  return (
    <section className="card">
      <h2>Swap IRON → WOOD</h2>
      <label>
        IRON in
        <input
          value={amount}
          onChange={(e) => setAmount(e.target.value.trim())}
          inputMode="numeric"
        />
      </label>
      <p className="muted">
        Estimated WOOD out: <strong>{quote != null ? quote.toString() : "—"}</strong>
      </p>

      {!isConnected ? (
        <p className="muted">Connect a wallet to swap.</p>
      ) : approved === false ? (
        <button disabled={isPending} onClick={approve}>
          {isPending ? "Approving…" : "Approve AMM"}
        </button>
      ) : (
        <button disabled={isPending || amountIn === 0n} onClick={swap}>
          {isPending ? "Swapping…" : "Swap"}
        </button>
      )}

      {error && <p className="error">{readableError(error)}</p>}
      {isSuccess && <p className="ok">Transaction submitted.</p>}
    </section>
  );
}
