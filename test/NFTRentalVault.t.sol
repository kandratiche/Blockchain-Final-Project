// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/GameItems.sol";
import "../src/NFTRentalVault.sol";

/// @notice Unit + fuzz tests for NFTRentalVault: listing equipment, renting it
///         with MANA, ERC-4907-style user rights, pull-based earnings, delist
///         guards, and the pausable circuit breaker.
contract NFTRentalVaultTest is Test {
    GameItems items;
    NFTRentalVault vault;

    address admin  = address(0xA0);
    address owner  = address(0xE1);
    address renter = address(0xE2);

    uint256 MANA;
    uint256 equipId;

    uint256 constant PRICE_PER_DAY = 100;
    uint64  constant MAX_DURATION  = 30;

    function setUp() public {
        items = new GameItems(address(this), "https://api.realmforge.io/meta/");
        vault = new NFTRentalVault(address(items), admin);

        items.grantRole(items.MINTER_ROLE(), address(this));
        MANA = items.MANA();

        // Mint an equipment NFT to the owner.
        equipId = items.mintEquipment(owner, "Dragon Blade", 5, 999);
        // Fund the renter with MANA.
        items.mintResource(renter, MANA, 10_000);

        // Approvals for the vault to move tokens.
        vm.prank(owner);
        items.setApprovalForAll(address(vault), true);
        vm.prank(renter);
        items.setApprovalForAll(address(vault), true);
    }

    function _list() internal {
        vm.prank(owner);
        vault.list(equipId, PRICE_PER_DAY, MAX_DURATION);
    }

    // ─── Listing ──────────────────────────────────────────────────────────────
    function test_list_movesNftToVault() public {
        _list();
        assertEq(items.balanceOf(address(vault), equipId), 1);
        assertEq(items.balanceOf(owner, equipId), 0);

        (address o, uint256 p,, , , bool active) = vault.listings(equipId);
        assertEq(o, owner);
        assertEq(p, PRICE_PER_DAY);
        assertTrue(active);
    }

    function test_list_revertsOnNonEquipment() public {
        vm.prank(owner);
        vm.expectRevert("Rental: not equipment");
        vault.list(MANA, PRICE_PER_DAY, MAX_DURATION);
    }

    function test_list_revertsOnZeroDuration() public {
        vm.prank(owner);
        vm.expectRevert("Rental: zero duration");
        vault.list(equipId, PRICE_PER_DAY, 0);
    }

    function test_list_revertsOnDoubleList() public {
        _list();
        vm.prank(owner);
        vm.expectRevert(); // NFT already in vault -> transfer fails
        vault.list(equipId, PRICE_PER_DAY, MAX_DURATION);
    }

    // ─── Renting ──────────────────────────────────────────────────────────────
    function test_rent_chargesManaAndSetsUser() public {
        _list();
        uint64 dur = 5;

        vm.prank(renter);
        vault.rent(equipId, dur);

        // 5 days * 100 = 500 MANA pulled into the vault.
        assertEq(items.balanceOf(renter, MANA), 10_000 - 500);
        assertEq(items.balanceOf(address(vault), MANA), 500);
        assertEq(vault.earnings(owner), 500);

        // ERC-4907-style rights.
        assertEq(vault.userOf(equipId), renter);
        assertEq(vault.userExpires(equipId), block.timestamp + uint256(dur) * 1 days);
    }

    function test_rent_revertsIfNotListed() public {
        vm.prank(renter);
        vm.expectRevert("Rental: not listed");
        vault.rent(equipId, 1);
    }

    function test_rent_revertsOnBadDuration() public {
        _list();
        vm.prank(renter);
        vm.expectRevert("Rental: bad duration");
        vault.rent(equipId, MAX_DURATION + 1);
    }

    function test_rent_revertsWhileActive() public {
        _list();
        vm.prank(renter);
        vault.rent(equipId, 5);

        vm.prank(renter);
        vm.expectRevert("Rental: currently rented");
        vault.rent(equipId, 1);
    }

    function test_rent_revertsForOwner() public {
        _list();
        items.mintResource(owner, MANA, 1000);
        vm.prank(owner);
        vm.expectRevert("Rental: owner cannot rent");
        vault.rent(equipId, 1);
    }

    function test_userOf_expiresAfterDuration() public {
        _list();
        vm.prank(renter);
        vault.rent(equipId, 3);

        assertEq(vault.userOf(equipId), renter);
        vm.warp(block.timestamp + 3 days + 1);
        assertEq(vault.userOf(equipId), address(0));
    }

    function test_rent_relistableAfterExpiry() public {
        _list();
        vm.prank(renter);
        vault.rent(equipId, 2);
        vm.warp(block.timestamp + 2 days + 1);

        // A second renter can now rent again.
        items.mintResource(address(0xE3), MANA, 1000);
        vm.prank(address(0xE3));
        items.setApprovalForAll(address(vault), true);
        vm.prank(address(0xE3));
        vault.rent(equipId, 1);
        assertEq(vault.userOf(equipId), address(0xE3));
    }

    // ─── Earnings (pull-over-push) ────────────────────────────────────────────
    function test_claimEarnings_paysOwner() public {
        _list();
        vm.prank(renter);
        vault.rent(equipId, 4); // 400 MANA

        vm.prank(owner);
        vault.claimEarnings();

        assertEq(items.balanceOf(owner, MANA), 400);
        assertEq(vault.earnings(owner), 0);
    }

    function test_claimEarnings_revertsIfNothing() public {
        vm.prank(owner);
        vm.expectRevert("Rental: nothing to claim");
        vault.claimEarnings();
    }

    // ─── Delist ───────────────────────────────────────────────────────────────
    function test_delist_returnsNft() public {
        _list();
        vm.prank(owner);
        vault.delist(equipId);
        assertEq(items.balanceOf(owner, equipId), 1);

        (, , , , , bool active) = vault.listings(equipId);
        assertFalse(active);
    }

    function test_delist_revertsDuringRental() public {
        _list();
        vm.prank(renter);
        vault.rent(equipId, 5);

        vm.prank(owner);
        vm.expectRevert("Rental: active rental");
        vault.delist(equipId);
    }

    function test_delist_onlyOwner() public {
        _list();
        vm.prank(renter);
        vm.expectRevert("Rental: not owner");
        vault.delist(equipId);
    }

    function test_delist_succeedsAfterRentalExpires() public {
        _list();
        vm.prank(renter);
        vault.rent(equipId, 5);
        vm.warp(block.timestamp + 5 days + 1);

        vm.prank(owner);
        vault.delist(equipId);
        assertEq(items.balanceOf(owner, equipId), 1);
    }

    // ─── Circuit breaker ──────────────────────────────────────────────────────
    function test_pause_blocksRent() public {
        _list();
        vm.prank(admin);
        vault.pause();

        vm.prank(renter);
        vm.expectRevert();
        vault.rent(equipId, 1);
    }

    function test_pause_onlyOwner() public {
        vm.prank(renter);
        vm.expectRevert();
        vault.pause();
    }

    // ─── Fuzz ─────────────────────────────────────────────────────────────────
    function testFuzz_rent_anyDuration(uint64 durationDays) public {
        durationDays = uint64(bound(durationDays, 1, MAX_DURATION));
        _list();

        uint256 expected = uint256(PRICE_PER_DAY) * durationDays;
        items.mintResource(renter, MANA, expected); // top-up to be safe

        uint256 balBefore = items.balanceOf(renter, MANA);
        vm.prank(renter);
        vault.rent(equipId, durationDays);

        assertEq(balBefore - items.balanceOf(renter, MANA), expected);
        assertEq(vault.earnings(owner), expected);
    }
}
