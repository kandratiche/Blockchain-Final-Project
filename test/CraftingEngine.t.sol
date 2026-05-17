// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/GameItems.sol";
import "../src/CraftingEngine.sol";

/// @notice Unit + fuzz tests for CraftingEngine: recipe management, crafting
///         flow (burn resources + fee, mint equipment), access control, and the
///         pausable circuit breaker.
contract CraftingEngineTest is Test {
    GameItems items;
    CraftingEngine crafting;

    address dao    = address(0xDA0);
    address player = address(0xC1);
    address outsider = address(0xC2);

    uint256 IRON;
    uint256 WOOD;
    uint256 MANA;

    uint256 constant RECIPE_ID = 1;
    uint256 constant MANA_FEE  = 5;

    function setUp() public {
        // GameItems admin = this test contract, so it can grant roles.
        items = new GameItems(address(this), "https://api.realmforge.io/meta/");
        crafting = new CraftingEngine(address(items), dao, MANA_FEE);

        // CraftingEngine needs to burn resources and mint equipment.
        items.grantRole(items.MINTER_ROLE(), address(crafting));
        items.grantRole(items.BURNER_ROLE(), address(crafting));
        // Also keep mint rights for the test harness to fund players.
        items.grantRole(items.MINTER_ROLE(), address(this));

        IRON = items.IRON();
        WOOD = items.WOOD();
        MANA = items.MANA();

        _createDefaultRecipe();
    }

    function _createDefaultRecipe() internal {
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amts = new uint256[](2);
        ids[0] = IRON; amts[0] = 10;
        ids[1] = WOOD; amts[1] = 5;
        vm.prank(dao);
        crafting.createRecipe(RECIPE_ID, ids, amts, "Iron Sword", 2, 120);
    }

    function _fundPlayer(uint256 ironAmt, uint256 woodAmt, uint256 manaAmt) internal {
        items.mintResource(player, IRON, ironAmt);
        items.mintResource(player, WOOD, woodAmt);
        items.mintResource(player, MANA, manaAmt);
    }

    // ─── Recipe creation ──────────────────────────────────────────────────────
    function test_createRecipe_storesRecipe() public {
        CraftingEngine.Recipe memory r = crafting.getRecipe(RECIPE_ID);
        assertTrue(r.exists);
        assertEq(r.outputName, "Iron Sword");
        assertEq(r.outputTier, 2);
        assertEq(r.resourceIds.length, 2);
    }

    function test_createRecipe_revertsOnDuplicate() public {
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amts = new uint256[](1);
        ids[0] = IRON; amts[0] = 1;
        vm.prank(dao);
        vm.expectRevert("Crafting: recipe exists");
        crafting.createRecipe(RECIPE_ID, ids, amts, "Dup", 1, 1);
    }

    function test_createRecipe_revertsOnLengthMismatch() public {
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amts = new uint256[](1);
        vm.prank(dao);
        vm.expectRevert("Crafting: length mismatch");
        crafting.createRecipe(2, ids, amts, "Bad", 1, 1);
    }

    function test_createRecipe_revertsOnBadTier() public {
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amts = new uint256[](1);
        ids[0] = IRON; amts[0] = 1;
        vm.prank(dao);
        vm.expectRevert("Crafting: bad tier");
        crafting.createRecipe(2, ids, amts, "Bad", 6, 1);
    }

    function test_createRecipe_revertsOnNonResource() public {
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amts = new uint256[](1);
        ids[0] = 1000; amts[0] = 1;
        vm.prank(dao);
        vm.expectRevert("Crafting: not a resource");
        crafting.createRecipe(2, ids, amts, "Bad", 1, 1);
    }

    function test_createRecipe_onlyDao() public {
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amts = new uint256[](1);
        ids[0] = IRON; amts[0] = 1;
        vm.prank(outsider);
        vm.expectRevert();
        crafting.createRecipe(2, ids, amts, "X", 1, 1);
    }

    // ─── Recipe update / remove ───────────────────────────────────────────────
    function test_updateRecipe_changesOutput() public {
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amts = new uint256[](1);
        ids[0] = MANA; amts[0] = 3;
        vm.prank(dao);
        crafting.updateRecipe(RECIPE_ID, ids, amts, "Mana Staff", 4, 300);

        CraftingEngine.Recipe memory r = crafting.getRecipe(RECIPE_ID);
        assertEq(r.outputName, "Mana Staff");
        assertEq(r.outputTier, 4);
    }

    function test_updateRecipe_revertsIfMissing() public {
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amts = new uint256[](1);
        ids[0] = IRON; amts[0] = 1;
        vm.prank(dao);
        vm.expectRevert("Crafting: no recipe");
        crafting.updateRecipe(999, ids, amts, "X", 1, 1);
    }

    function test_removeRecipe_deletesIt() public {
        vm.prank(dao);
        crafting.removeRecipe(RECIPE_ID);
        assertFalse(crafting.recipeExists(RECIPE_ID));
    }

    function test_removeRecipe_revertsIfMissing() public {
        vm.prank(dao);
        vm.expectRevert("Crafting: no recipe");
        crafting.removeRecipe(999);
    }

    // ─── Crafting flow ────────────────────────────────────────────────────────
    function test_craft_burnsInputsAndMintsEquipment() public {
        _fundPlayer(100, 100, 100);

        vm.prank(player);
        uint256 equipId = crafting.craft(RECIPE_ID);

        // Inputs burned: 10 IRON, 5 WOOD, 5 MANA fee.
        assertEq(items.balanceOf(player, IRON), 90);
        assertEq(items.balanceOf(player, WOOD), 95);
        assertEq(items.balanceOf(player, MANA), 95);
        // Equipment minted.
        assertGe(equipId, 1000);
        assertEq(items.balanceOf(player, equipId), 1);
        (string memory n, uint8 t,) = items.equipment(equipId);
        assertEq(n, "Iron Sword");
        assertEq(t, 2);
    }

    function test_craft_revertsOnInvalidRecipe() public {
        vm.prank(player);
        vm.expectRevert("Crafting: invalid recipe");
        crafting.craft(999);
    }

    function test_craft_revertsWithoutResources() public {
        _fundPlayer(0, 0, 100); // no IRON/WOOD
        vm.prank(player);
        vm.expectRevert();
        crafting.craft(RECIPE_ID);
    }

    function test_craft_zeroFeeSkipsManaBurn() public {
        vm.prank(dao);
        crafting.setManaFee(0);
        _fundPlayer(100, 100, 0); // no MANA at all

        vm.prank(player);
        crafting.craft(RECIPE_ID);
        assertEq(items.balanceOf(player, IRON), 90);
    }

    // ─── DAO fee ──────────────────────────────────────────────────────────────
    function test_setManaFee_updates() public {
        vm.prank(dao);
        crafting.setManaFee(42);
        assertEq(crafting.manaFee(), 42);
    }

    function test_setManaFee_onlyDao() public {
        vm.prank(outsider);
        vm.expectRevert();
        crafting.setManaFee(1);
    }

    // ─── Circuit breaker ──────────────────────────────────────────────────────
    function test_pause_blocksCrafting() public {
        _fundPlayer(100, 100, 100);
        vm.prank(dao);
        crafting.pause();

        vm.prank(player);
        vm.expectRevert();
        crafting.craft(RECIPE_ID);

        vm.prank(dao);
        crafting.unpause();
        vm.prank(player);
        crafting.craft(RECIPE_ID); // succeeds again
    }

    function test_pause_onlyPauser() public {
        vm.prank(outsider);
        vm.expectRevert();
        crafting.pause();
    }

    // ─── Fuzz ─────────────────────────────────────────────────────────────────
    function testFuzz_craft_anyResourceAmount(uint64 ironReq, uint64 woodReq) public {
        ironReq = uint64(bound(ironReq, 1, 1_000_000));
        woodReq = uint64(bound(woodReq, 1, 1_000_000));

        uint256[] memory ids = new uint256[](2);
        uint256[] memory amts = new uint256[](2);
        ids[0] = IRON; amts[0] = ironReq;
        ids[1] = WOOD; amts[1] = woodReq;
        vm.prank(dao);
        crafting.createRecipe(7, ids, amts, "Fuzzed", 3, 50);

        _fundPlayer(ironReq, woodReq, MANA_FEE);
        vm.prank(player);
        crafting.craft(7);

        assertEq(items.balanceOf(player, IRON), 0);
        assertEq(items.balanceOf(player, WOOD), 0);
    }
}
