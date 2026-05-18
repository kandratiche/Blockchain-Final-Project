/**
 * Map any wallet / RPC / contract error to a short, human-readable message.
 * No raw RPC blobs reach the UI.
 */
export function readableError(err) {
  if (!err) return "";
  const name = err.name || "";
  const msg = (err.shortMessage || err.details || err.message || "").toLowerCase();

  if (name === "UserRejectedRequestError" || msg.includes("user rejected")) {
    return "Transaction rejected in your wallet.";
  }
  if (msg.includes("insufficient funds")) {
    return "Insufficient ETH to cover gas.";
  }
  if (msg.includes("insufficient balance") || msg.includes("erc20insufficientbalance")) {
    return "Insufficient token balance for this action.";
  }
  if (msg.includes("chain") && msg.includes("mismatch")) {
    return "Wrong network — switch to Arbitrum Sepolia.";
  }
  if (msg.includes("slippage")) {
    return "Price moved too much — increase slippage or retry.";
  }
  // Fall back to the wallet's own short message, never the raw payload.
  return err.shortMessage || "Transaction failed. Check your inputs and retry.";
}
