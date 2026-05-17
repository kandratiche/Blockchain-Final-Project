// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/PriceOracle.sol";
import "../src/mocks/MockAggregator.sol";

/// @notice Unit tests for PriceOracle: a fresh price reads back correctly, a
///         stale or non-positive answer reverts, and the owner-only config
///         setters are guarded.
contract PriceOracleTest is Test {
    PriceOracle oracle;
    MockAggregator feed;

    address admin    = address(0xA0);
    address outsider = address(0xB0);

    uint256 constant MAX_STALENESS = 1 hours;
    int256  constant PRICE         = 2000e8; // $2000, 8 decimals

    function setUp() public {
        vm.warp(1_000_000);
        feed   = new MockAggregator(8, PRICE);
        oracle = new PriceOracle(address(feed), MAX_STALENESS, admin);
    }

    // ─── Happy path ───────────────────────────────────────────────────────────
    function test_getPrice_returnsFreshAnswer() public view {
        (uint256 price, uint8 dec) = oracle.getPrice();
        assertEq(price, uint256(PRICE));
        assertEq(dec, 8);
    }

    function test_valueOf_scalesByDecimals() public view {
        // 3 units valued at $2000 each = $6000, expressed with 8 decimals.
        assertEq(oracle.valueOf(3 * 1e8), 6000e8);
    }

    // ─── Staleness check ──────────────────────────────────────────────────────
    function test_getPrice_revertsOnStalePrice() public {
        // Move time past the staleness window without refreshing the feed.
        vm.warp(block.timestamp + MAX_STALENESS + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                PriceOracle.StalePrice.selector,
                block.timestamp - MAX_STALENESS - 1,
                block.timestamp,
                MAX_STALENESS
            )
        );
        oracle.getPrice();
    }

    function test_getPrice_freshAgainAfterUpdate() public {
        vm.warp(block.timestamp + MAX_STALENESS + 1);
        feed.setAnswer(2100e8); // refreshes updatedAt to now
        (uint256 price,) = oracle.getPrice();
        assertEq(price, 2100e8);
    }

    function test_getPrice_acceptsAnswerAtStalenessEdge() public {
        vm.warp(block.timestamp + MAX_STALENESS); // exactly at the limit
        (uint256 price,) = oracle.getPrice();
        assertEq(price, uint256(PRICE));
    }

    // ─── Invalid price ────────────────────────────────────────────────────────
    function test_getPrice_revertsOnZeroPrice() public {
        feed.setAnswer(0);
        vm.expectRevert(abi.encodeWithSelector(PriceOracle.InvalidPrice.selector, int256(0)));
        oracle.getPrice();
    }

    function test_getPrice_revertsOnNegativePrice() public {
        feed.setAnswer(-5);
        vm.expectRevert(abi.encodeWithSelector(PriceOracle.InvalidPrice.selector, int256(-5)));
        oracle.getPrice();
    }

    // ─── Owner config ─────────────────────────────────────────────────────────
    function test_setFeed_onlyOwner() public {
        MockAggregator feed2 = new MockAggregator(8, 1e8);
        vm.prank(outsider);
        vm.expectRevert();
        oracle.setFeed(address(feed2));

        vm.prank(admin);
        oracle.setFeed(address(feed2));
        assertEq(address(oracle.feed()), address(feed2));
    }

    function test_setMaxStaleness_onlyOwner() public {
        vm.prank(outsider);
        vm.expectRevert();
        oracle.setMaxStaleness(2 hours);

        vm.prank(admin);
        oracle.setMaxStaleness(2 hours);
        assertEq(oracle.maxStaleness(), 2 hours);
    }
}
