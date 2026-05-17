// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/GameRegistryV1.sol";
import "../src/GameRegistryV2.sol";

/// @notice Tests for the UUPS-upgradeable GameRegistry: V1 behaviour behind an
///         ERC-1967 proxy, the V1 -> V2 upgrade, and storage preservation
///         across the upgrade (no slot collision).
contract GameRegistryTest is Test {
    GameRegistryV1 registry; // proxy, typed as V1
    address proxy;

    address owner   = address(0xA0);
    address player  = address(0xB0);
    address player2 = address(0xB1);

    function setUp() public {
        GameRegistryV1 impl = new GameRegistryV1();
        bytes memory initData =
            abi.encodeCall(GameRegistryV1.initialize, (owner, 100));
        proxy = address(new ERC1967Proxy(address(impl), initData));
        registry = GameRegistryV1(proxy);
    }

    // ─── V1 behaviour ─────────────────────────────────────────────────────────
    function test_initialize_setsState() public view {
        assertEq(registry.owner(), owner);
        assertEq(registry.xpPerLevel(), 100);
        assertEq(registry.version(), "V1");
    }

    function test_initialize_cannotRunTwice() public {
        vm.expectRevert();
        registry.initialize(owner, 1);
    }

    function test_implementation_cannotInitialize() public {
        GameRegistryV1 impl = new GameRegistryV1();
        vm.expectRevert(); // _disableInitializers() locked it
        impl.initialize(owner, 1);
    }

    function test_grantXP_andLevel() public {
        vm.prank(owner);
        registry.grantXP(player, 250);
        assertEq(registry.xpOf(player), 250);
        assertEq(registry.levelOf(player), 2); // 250 / 100
    }

    function test_grantXP_onlyOwner() public {
        vm.prank(player);
        vm.expectRevert(GameRegistryV1.NotOwner.selector);
        registry.grantXP(player, 1);
    }

    function test_transferOwnership() public {
        vm.prank(owner);
        registry.transferOwnership(player);
        assertEq(registry.owner(), player);
    }

    // ─── Upgrade authorization ────────────────────────────────────────────────
    function test_upgrade_onlyOwner() public {
        GameRegistryV2 v2 = new GameRegistryV2();
        vm.prank(player);
        vm.expectRevert(GameRegistryV1.NotOwner.selector);
        registry.upgradeToAndCall(address(v2), "");
    }

    // ─── V1 -> V2 upgrade ─────────────────────────────────────────────────────
    function test_upgradeToV2_preservesStorage() public {
        // Seed V1 state.
        vm.startPrank(owner);
        registry.grantXP(player, 500);
        registry.grantXP(player2, 120);
        vm.stopPrank();

        // Upgrade the proxy implementation to V2.
        GameRegistryV2 v2impl = new GameRegistryV2();
        vm.prank(owner);
        registry.upgradeToAndCall(address(v2impl), "");

        GameRegistryV2 r2 = GameRegistryV2(proxy);

        // V1 storage survived the upgrade.
        assertEq(r2.version(), "V2");
        assertEq(r2.owner(), owner);
        assertEq(r2.xpPerLevel(), 100);
        assertEq(r2.xpOf(player), 500);
        assertEq(r2.levelOf(player), 5);
        assertEq(r2.xpOf(player2), 120);

        // New V2 feature works on top of preserved state.
        vm.prank(owner);
        r2.unlockAchievement(player, 7);
        assertTrue(r2.hasAchievement(player, 7));
        assertFalse(r2.hasAchievement(player, 8));
        assertFalse(r2.hasAchievement(player2, 7));
    }

    function test_v2_grantXpStillWorks() public {
        GameRegistryV2 v2impl = new GameRegistryV2();
        vm.prank(owner);
        registry.upgradeToAndCall(address(v2impl), "");

        GameRegistryV2 r2 = GameRegistryV2(proxy);
        vm.prank(owner);
        r2.grantXP(player, 333);
        assertEq(r2.xpOf(player), 333);
    }

    function test_v2_achievementOutOfRangeReverts() public {
        GameRegistryV2 v2impl = new GameRegistryV2();
        vm.prank(owner);
        registry.upgradeToAndCall(address(v2impl), "");

        vm.prank(owner);
        vm.expectRevert(GameRegistryV2.AchievementOutOfRange.selector);
        GameRegistryV2(proxy).unlockAchievement(player, 256);
    }
}
