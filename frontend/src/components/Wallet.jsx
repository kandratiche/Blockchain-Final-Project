import { useAccount, useConnect, useDisconnect, useChainId, useSwitchChain } from "wagmi";
import { TARGET_CHAIN } from "../config.js";

/** Connect / disconnect controls plus a wrong-network banner + switch prompt. */
export function Wallet() {
  const { address, isConnected } = useAccount();
  const { connect, connectors, error: connectError } = useConnect();
  const { disconnect } = useDisconnect();
  const chainId = useChainId();
  const { switchChain } = useSwitchChain();

  const wrongNetwork = isConnected && chainId !== TARGET_CHAIN.id;

  return (
    <div className="wallet">
      <div className="wallet-row">
        {isConnected ? (
          <>
            <span className="addr">
              {address.slice(0, 6)}…{address.slice(-4)}
            </span>
            <button onClick={() => disconnect()}>Disconnect</button>
          </>
        ) : (
          connectors.map((c) => (
            <button key={c.uid} onClick={() => connect({ connector: c })}>
              Connect {c.name}
            </button>
          ))
        )}
      </div>

      {connectError && <p className="error">{connectError.message}</p>}

      {wrongNetwork && (
        <div className="banner banner-warn">
          Wrong network. RealmForge runs on {TARGET_CHAIN.name}.
          <button onClick={() => switchChain({ chainId: TARGET_CHAIN.id })}>
            Switch network
          </button>
        </div>
      )}
    </div>
  );
}
