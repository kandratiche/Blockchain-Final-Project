// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "../src/GameItems.sol";
import "../src/LootVRF.sol";
import "../src/ResourceAMM.sol";
import "../src/CraftingEngine.sol";
import "../src/NFTRentalVault.sol";
import "../src/RealmToken.sol";
import "../src/GameDAO.sol";

/// @notice Deploys the full RealmForge GameFi economy to an L2 testnet and wires
///         every privileged role to the DAO Timelock.
///
/// Usage (Arbitrum Sepolia):
///   forge script script/Deploy.s.sol \
///     --rpc-url $ARBITRUM_SEPOLIA_RPC \
///     --broadcast --verify -vvvv
///
/// Required env vars:
///   ADMIN_ADDRESS       – deployer / initial admin wallet
///   VRF_COORDINATOR     – Chainlink VRF Coordinator address on target network
///   VRF_SUBSCRIPTION_ID – Chainlink subscription ID (uint256)
///   VRF_KEY_HASH        – Chainlink gas-lane key hash (bytes32)
///   TREASURY_ADDRESS    – address receiving AMM swap fees
///   BASE_URI            – base URI for item metadata
contract Deploy is Script {
    // ─── Protocol constants ───────────────────────────────────────────────────
    uint256 constant MANA_COST_PER_LOOT = 10; // MANA burned per loot roll
    uint256 constant MANA_FEE_PER_CRAFT = 5; // MANA burned per craft
    uint256 constant TIMELOCK_DELAY = 2 days; // governance execution delay
    uint256 constant GOV_SUPPLY = 1_000_000e18; // RLM minted to admin

    function run() external {
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address vrfCoord = vm.envAddress("VRF_COORDINATOR");
        uint256 subId = vm.envUint("VRF_SUBSCRIPTION_ID");
        bytes32 keyHash = vm.envBytes32("VRF_KEY_HASH");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        string memory baseUri = vm.envString("BASE_URI");

        vm.startBroadcast();

        // 1. ERC-1155 item registry.
        GameItems items = new GameItems(admin, baseUri);

        // 2. Governance token + Timelock + Governor.
        RealmToken token = new RealmToken(admin);
        address[] memory empty = new address[](0);
        TimelockController timelock = new TimelockController(TIMELOCK_DELAY, empty, empty, admin);
        GameDAO dao = new GameDAO(IVotes(address(token)), timelock);

        // 3. Game systems — privileged setters owned by the Timelock (the DAO).
        LootVRF loot = new LootVRF(vrfCoord, address(items), subId, keyHash, MANA_COST_PER_LOOT, address(timelock));
        ResourceAMM amm = new ResourceAMM(address(items), treasury, address(timelock));
        CraftingEngine crafting = new CraftingEngine(address(items), address(timelock), MANA_FEE_PER_CRAFT);
        NFTRentalVault rental = new NFTRentalVault(address(items), address(timelock));

        // 4. Wire GameItems roles: LootVRF + CraftingEngine mint/burn items.
        items.grantRole(items.MINTER_ROLE(), address(loot));
        items.grantRole(items.BURNER_ROLE(), address(loot));
        items.grantRole(items.MINTER_ROLE(), address(crafting));
        items.grantRole(items.BURNER_ROLE(), address(crafting));

        // 5. Wire Timelock roles: Governor proposes & cancels, anyone executes.
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(dao));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(dao));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
        // Drop the deployer's temporary Timelock admin — no governance backdoor.
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), msg.sender);

        // 6. Seed governance voting supply to the admin for initial distribution.
        token.mint(admin, GOV_SUPPLY);

        vm.stopBroadcast();

        // ─── Summary ──────────────────────────────────────────────────────────
        console.log("=== RealmForge Deployment ===");
        console.log("GameItems     :", address(items));
        console.log("RealmToken    :", address(token));
        console.log("TimelockCtrl  :", address(timelock));
        console.log("GameDAO       :", address(dao));
        console.log("LootVRF       :", address(loot));
        console.log("ResourceAMM   :", address(amm));
        console.log("CraftingEngine:", address(crafting));
        console.log("NFTRentalVault:", address(rental));
        console.log("Treasury      :", treasury);
        console.log("Admin         :", admin);
    }
}
