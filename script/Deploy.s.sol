// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/GameItems.sol";
import "../src/LootVRF.sol";
import "../src/ResourceAMM.sol";

/// @notice Deploy GameItems, LootVRF, and ResourceAMM to an L2 testnet.
///
/// Usage (Arbitrum Sepolia):
///   forge script script/Deploy.s.sol \
///     --rpc-url $ARBITRUM_SEPOLIA_RPC \
///     --broadcast \
///     --verify \
///     -vvvv
///
/// Required env vars:
///   ADMIN_ADDRESS       – deployer / admin wallet
///   VRF_COORDINATOR     – Chainlink VRF Coordinator address on target network
///   VRF_SUBSCRIPTION_ID – Chainlink subscription ID (uint256)
///   VRF_KEY_HASH        – Chainlink gas-lane key hash (bytes32)
///   TREASURY_ADDRESS    – address receiving swap fees
///   BASE_URI            – base URI for item metadata (e.g. https://api.realmforge.io/meta/)
contract Deploy is Script {

    function run() external {
        address admin       = vm.envAddress("ADMIN_ADDRESS");
        address vrfCoord    = vm.envAddress("VRF_COORDINATOR");
        uint256 subId       = vm.envUint("VRF_SUBSCRIPTION_ID");
        bytes32 keyHash     = vm.envBytes32("VRF_KEY_HASH");
        address treasury    = vm.envAddress("TREASURY_ADDRESS");
        string memory uri   = vm.envString("BASE_URI");

        vm.startBroadcast();

        // 1. Deploy ERC-1155 item registry
        GameItems items = new GameItems(admin, uri);
        console.log("GameItems deployed at:", address(items));

        // 2. Deploy LootVRF (costs 10 MANA per roll by default)
        uint256 manaCost = 10 * 1e0; // 10 MANA (no decimals in ERC-1155)
        LootVRF loot = new LootVRF(vrfCoord, address(items), subId, keyHash, manaCost, admin);
        console.log("LootVRF deployed at:", address(loot));

        // 3. Deploy ResourceAMM
        ResourceAMM amm = new ResourceAMM(address(items), treasury, admin);
        console.log("ResourceAMM deployed at:", address(amm));

        // 4. Wire up roles
        //    LootVRF needs MINTER (to mint loot) and BURNER (to burn MANA cost)
        items.grantRole(items.MINTER_ROLE(), address(loot));
        items.grantRole(items.BURNER_ROLE(), address(loot));
        //    AMM needs BURNER role to handle token transfers inside swap
        //    (actually uses safeTransferFrom, not burn — no extra role needed)
        console.log("Roles granted.");

        vm.stopBroadcast();

        // Print summary
        console.log("\n=== RealmForge Phase 1 Deployment ===");
        console.log("GameItems  :", address(items));
        console.log("LootVRF    :", address(loot));
        console.log("ResourceAMM:", address(amm));
        console.log("Treasury   :", treasury);
        console.log("Admin      :", admin);
    }
}
