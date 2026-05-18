import { http, createConfig } from "wagmi";
import { arbitrumSepolia } from "wagmi/chains";
import { injected, walletConnect } from "wagmi/connectors";

/** The single chain this dApp targets. */
export const TARGET_CHAIN = arbitrumSepolia;

const wcProjectId = import.meta.env.VITE_WALLETCONNECT_PROJECT_ID;

/**
 * wagmi config — MetaMask (injected) is the primary connector; WalletConnect is
 * wired in as a second connector when a project id is provided.
 */
export const wagmiConfig = createConfig({
  chains: [arbitrumSepolia],
  connectors: [
    injected(),
    ...(wcProjectId ? [walletConnect({ projectId: wcProjectId })] : []),
  ],
  transports: {
    [arbitrumSepolia.id]: http(),
  },
});
