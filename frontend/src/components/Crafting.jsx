import { useState } from "react";
import { useAccount, useReadContract, useWriteContract } from "wagmi";
import { ADDRESSES, craftingEngineAbi } from "../contracts.js";
import { readableError } from "../lib/errors.js";

/** Craft an item from a recipe on the CraftingEngine. Write transaction #2. */
export function Crafting() {
  const { isConnected } = useAccount();
  const [recipeId, setRecipeId] = useState("1");
  const { writeContract, isPending, error, isSuccess } = useWriteContract();

  const id = recipeId && /^\d+$/.test(recipeId) ? BigInt(recipeId) : 0n;

  const { data: manaFee } = useReadContract({
    address: ADDRESSES.craftingEngine,
    abi: craftingEngineAbi,
    functionName: "manaFee",
  });
  const { data: exists } = useReadContract({
    address: ADDRESSES.craftingEngine,
    abi: craftingEngineAbi,
    functionName: "recipeExists",
    args: [id],
    query: { enabled: id > 0n },
  });

  function craft() {
    writeContract({
      address: ADDRESSES.craftingEngine,
      abi: craftingEngineAbi,
      functionName: "craft",
      args: [id],
    });
  }

  return (
    <section className="card">
      <h2>Craft equipment</h2>
      <label>
        Recipe ID
        <input
          value={recipeId}
          onChange={(e) => setRecipeId(e.target.value.trim())}
          inputMode="numeric"
        />
      </label>
      <p className="muted">
        MANA fee per craft: <strong>{manaFee != null ? manaFee.toString() : "…"}</strong>
        {id > 0n && exists === false && " · recipe does not exist"}
      </p>

      <button
        disabled={!isConnected || isPending || id === 0n || exists === false}
        onClick={craft}
      >
        {isPending ? "Crafting…" : "Craft"}
      </button>

      {error && <p className="error">{readableError(error)}</p>}
      {isSuccess && <p className="ok">Craft transaction submitted.</p>}
    </section>
  );
}
