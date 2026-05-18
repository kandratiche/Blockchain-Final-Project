// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/GameItems.sol";
import "../src/ResourceAMM.sol";

/// @notice Unit + fuzz tests for GameItems and ResourceAMM.
///         LootVRF requires a live VRF coordinator mock — see test/LootVRFMock.t.sol.
contract GameItemsTest is Test {
    GameItems items;
    address admin = address(0xA0);
    address alice = address(0xA1);
    address minter = address(0xA2);

    uint256 IRON;
    uint256 WOOD;
    uint256 MANA;

    function setUp() public {
        vm.startPrank(admin);
        items = new GameItems(admin, "https://api.realmforge.io/meta/");
        items.grantRole(items.MINTER_ROLE(), minter);
        items.grantRole(items.BURNER_ROLE(), minter);
        vm.stopPrank();

        IRON = items.IRON();
        WOOD = items.WOOD();
        MANA = items.MANA();
    }

    // ── Basic mint ────────────────────────────────────────────────────────────
    function test_mintResource_iron() public {
        vm.prank(minter);
        items.mintResource(alice, IRON, 100);
        assertEq(items.balanceOf(alice, IRON), 100);
    }

    function test_mintResource_revertsOnInvalidId() public {
        vm.prank(minter);
        vm.expectRevert("GameItems: not a resource");
        items.mintResource(alice, 99, 1);
    }

    function test_mintEquipment() public {
        vm.prank(minter);
        uint256 id = items.mintEquipment(alice, "Iron Sword", 1, 50);
        assertGe(id, 1000);
        assertEq(items.balanceOf(alice, id), 1);
        (string memory n, uint8 t, uint256 p) = items.equipment(id);
        assertEq(n, "Iron Sword");
        assertEq(t, 1);
        assertEq(p, 50);
    }

    // ── Burn ──────────────────────────────────────────────────────────────────
    function test_burn() public {
        vm.startPrank(minter);
        items.mintResource(alice, WOOD, 50);
        items.burn(alice, WOOD, 20);
        vm.stopPrank();
        assertEq(items.balanceOf(alice, WOOD), 30);
    }

    // ── Access control ────────────────────────────────────────────────────────
    function test_unauthorizedMintReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        items.mintResource(alice, IRON, 1);
    }

    // ── Fuzz: mint any valid amount ───────────────────────────────────────────
    function testFuzz_mintResource(uint64 amount) public {
        vm.assume(amount > 0 && amount < 1e18);
        vm.prank(minter);
        items.mintResource(alice, MANA, amount);
        assertEq(items.balanceOf(alice, MANA), amount);
    }
}

contract ResourceAMMTest is Test {
    GameItems items;
    ResourceAMM amm;

    address admin = address(0xB0);
    address treasury = address(0xB1);
    address lp = address(0xB2);
    address trader = address(0xB3);

    uint256 IRON;
    uint256 WOOD;

    function setUp() public {
        vm.startPrank(admin);
        items = new GameItems(admin, "https://api.realmforge.io/meta/");
        amm = new ResourceAMM(address(items), treasury, admin);

        items.grantRole(items.MINTER_ROLE(), admin);
        items.grantRole(items.BURNER_ROLE(), address(amm));

        IRON = items.IRON();
        WOOD = items.WOOD();

        items.mintResource(lp, IRON, 10_000);
        items.mintResource(lp, WOOD, 10_000);
        items.mintResource(trader, IRON, 1_000);
        vm.stopPrank();

        vm.prank(lp);
        items.setApprovalForAll(address(amm), true);
        vm.prank(trader);
        items.setApprovalForAll(address(amm), true);
    }

    // ── Seed liquidity ────────────────────────────────────────────────────────
    function test_addLiquidity_firstDeposit() public {
        vm.prank(lp);
        uint256 shares = amm.addLiquidity(IRON, 1000, WOOD, 1000);
        assertGt(shares, 0);

        (uint256 rA, uint256 rB) = amm.getReserves(IRON, WOOD);
        assertEq(rA, 1000);
        assertEq(rB, 1000);
    }

    // ── Swap ─────────────────────────────────────────────────────────────────
    function test_swap_ironForWood() public {
        vm.prank(lp);
        amm.addLiquidity(IRON, 5000, WOOD, 5000);

        uint256 ironBefore = items.balanceOf(trader, IRON);
        uint256 woodBefore = items.balanceOf(trader, WOOD);

        vm.prank(trader);
        uint256 out = amm.swap(IRON, WOOD, 100, 1);

        assertGt(out, 0);
        assertEq(items.balanceOf(trader, IRON), ironBefore - 100);
        assertEq(items.balanceOf(trader, WOOD), woodBefore + out);
    }

    // ── Slippage guard ────────────────────────────────────────────────────────
    function test_swap_rejectsSlippage() public {
        vm.prank(lp);
        amm.addLiquidity(IRON, 5000, WOOD, 5000);

        vm.prank(trader);
        vm.expectRevert("AMM: slippage");
        amm.swap(IRON, WOOD, 100, 99999);
    }

    // ── Remove liquidity ──────────────────────────────────────────────────────
    function test_removeLiquidity() public {
        vm.startPrank(lp);
        uint256 shares = amm.addLiquidity(IRON, 2000, WOOD, 2000);
        uint256 ironPre = items.balanceOf(lp, IRON);
        uint256 woodPre = items.balanceOf(lp, WOOD);
        amm.removeLiquidity(IRON, WOOD, shares);
        vm.stopPrank();

        assertGt(items.balanceOf(lp, IRON), ironPre);
        assertGt(items.balanceOf(lp, WOOD), woodPre);
    }

    // ── Fee update (DAO) ──────────────────────────────────────────────────────
    function test_setFeeBps_onlyOwner() public {
        vm.prank(admin);
        amm.setFeeBps(50);
        assertEq(amm.feeBps(), 50);

        vm.prank(trader);
        vm.expectRevert();
        amm.setFeeBps(10);
    }

    // ── Fuzz: any in-range swap amount ────────────────────────────────────────
    function testFuzz_swap(uint64 amountIn) public {
        vm.assume(amountIn > 10 && amountIn < 500);
        vm.prank(lp);
        amm.addLiquidity(IRON, 5000, WOOD, 5000);

        vm.prank(trader);
        uint256 out = amm.swap(IRON, WOOD, amountIn, 0);
        assertGt(out, 0);
    }

    // ── k must not decrease after swap ────────────────────────────────────────
    function testFuzz_kInvariant(uint64 amountIn) public {
        vm.assume(amountIn > 10 && amountIn < 400);
        vm.prank(lp);
        amm.addLiquidity(IRON, 5000, WOOD, 5000);

        (uint256 rA0, uint256 rB0) = amm.getReserves(IRON, WOOD);
        uint256 k0 = rA0 * rB0;

        vm.prank(trader);
        amm.swap(IRON, WOOD, amountIn, 0);

        (uint256 rA1, uint256 rB1) = amm.getReserves(IRON, WOOD);
        uint256 k1 = rA1 * rB1;
        assertGe(k1, k0);
    }
}
