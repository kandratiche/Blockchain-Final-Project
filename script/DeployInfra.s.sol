// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../src/GameRegistryV1.sol";
import "../src/GuildFactory.sol";
import "../src/SumBench.sol";
import "../src/RealmStakeVault.sol";
import "../src/PriceOracle.sol";

/// @notice Deploys the RealmForge infrastructure layer: the UUPS-upgradeable
///         GameRegistry (behind an ERC-1967 proxy), the GuildFactory, the
///         SumBench gas-benchmark contract, the ERC-4626 RealmStakeVault, and
///         the Chainlink PriceOracle adapter.
///
/// Usage:
///   forge script script/DeployInfra.s.sol --rpc-url $ARBITRUM_SEPOLIA_RPC \
///     --broadcast --verify -vvvv
///
/// Required env vars:
///   ADMIN_ADDRESS – admin / proxy owner (intended: the DAO Timelock)
///   RLM_TOKEN     – RealmToken address (ERC-4626 vault underlying asset)
///   PRICE_FEED    – Chainlink aggregator address for the PriceOracle
contract DeployInfra is Script {
    uint256 constant XP_PER_LEVEL = 1000; // GameRegistry progression curve
    uint256 constant MAX_STALENESS = 1 hours; // PriceOracle freshness window

    function run() external {
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address rlmToken = vm.envAddress("RLM_TOKEN");
        address feed = vm.envAddress("PRICE_FEED");

        vm.startBroadcast();

        // 1. UUPS GameRegistry — implementation + ERC-1967 proxy.
        GameRegistryV1 registryImpl = new GameRegistryV1();
        bytes memory initData = abi.encodeCall(GameRegistryV1.initialize, (admin, XP_PER_LEVEL));
        ERC1967Proxy registryProxy = new ERC1967Proxy(address(registryImpl), initData);

        // 2. Guild factory (CREATE + CREATE2).
        GuildFactory guildFactory = new GuildFactory();

        // 3. Yul gas-benchmark contract.
        SumBench sumBench = new SumBench();

        // 4. ERC-4626 staking vault over $RLM.
        RealmStakeVault stakeVault = new RealmStakeVault(IERC20(rlmToken));

        // 5. Chainlink price-oracle adapter.
        PriceOracle priceOracle = new PriceOracle(feed, MAX_STALENESS, admin);

        vm.stopBroadcast();

        // ─── Summary ──────────────────────────────────────────────────────────
        console.log("=== RealmForge Infrastructure Deployment ===");
        console.log("GameRegistry impl  :", address(registryImpl));
        console.log("GameRegistry proxy :", address(registryProxy));
        console.log("GuildFactory       :", address(guildFactory));
        console.log("SumBench           :", address(sumBench));
        console.log("RealmStakeVault    :", address(stakeVault));
        console.log("PriceOracle        :", address(priceOracle));
    }
}
