import { Wallet } from "./components/Wallet.jsx";
import { Balances } from "./components/Balances.jsx";
import { Swap } from "./components/Swap.jsx";
import { Crafting } from "./components/Crafting.jsx";
import { Governance } from "./components/Governance.jsx";

/** RealmForge dApp shell. */
export default function App() {
  return (
    <div className="app">
      <header className="topbar">
        <h1>⚒️ RealmForge</h1>
        <Wallet />
      </header>

      <main className="layout">
        <Balances />
        <Swap />
        <Crafting />
        <Governance />
      </main>

      <footer className="footer">
        GameFi economy · ERC-1155 · AMM · VRF loot · DAO governance · Arbitrum Sepolia
      </footer>
    </div>
  );
}
