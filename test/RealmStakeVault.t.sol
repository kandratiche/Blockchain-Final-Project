// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../src/RealmStakeVault.sol";
import "../src/RealmToken.sol";

/// @notice Unit + fuzz tests for the ERC-4626 RealmStakeVault: deposit / mint /
///         withdraw / redeem, the rounding invariants (every conversion rounds
///         in the vault's favour), pro-rata yield, and inflation-attack defence.
contract RealmStakeVaultTest is Test {
    RealmToken asset;
    RealmStakeVault vault;

    address alice = address(0xA1);
    address bob   = address(0xB1);

    function setUp() public {
        asset = new RealmToken(address(this));
        vault = new RealmStakeVault(IERC20(address(asset)));

        asset.mint(alice, 1_000_000e18);
        asset.mint(bob, 1_000_000e18);

        vm.prank(alice);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        asset.approve(address(vault), type(uint256).max);
    }

    // ─── Metadata ─────────────────────────────────────────────────────────────
    function test_decimals_includeOffset() public view {
        // ERC-4626 share decimals = asset decimals (18) + offset (3).
        assertEq(vault.decimals(), 21);
        assertEq(vault.asset(), address(asset));
    }

    // ─── deposit / withdraw ───────────────────────────────────────────────────
    function test_deposit_mintsShares() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(100e18, alice);
        assertGt(shares, 0);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.totalAssets(), 100e18);
    }

    function test_withdraw_returnsAssets() public {
        vm.startPrank(alice);
        vault.deposit(100e18, alice);
        uint256 balBefore = asset.balanceOf(alice);
        vault.withdraw(40e18, alice, alice);
        vm.stopPrank();
        assertEq(asset.balanceOf(alice) - balBefore, 40e18);
    }

    function test_mint_and_redeem() public {
        vm.startPrank(alice);
        uint256 assetsIn = vault.mint(50e21, alice); // mint 50e21 shares
        uint256 assetsOut = vault.redeem(vault.balanceOf(alice), alice, alice);
        vm.stopPrank();
        // Redeeming everything must never return more than was put in.
        assertLe(assetsOut, assetsIn);
    }

    // ─── Rounding invariants ──────────────────────────────────────────────────
    function test_roundTrip_neverFavoursUser() public {
        vm.startPrank(alice);
        uint256 shares = vault.deposit(123_456e18, alice);
        uint256 assetsBack = vault.redeem(shares, alice, alice);
        vm.stopPrank();
        // Deposit -> redeem must not create assets out of thin air.
        assertLe(assetsBack, 123_456e18);
    }

    function testFuzz_convertInvariant(uint256 amount) public view {
        amount = bound(amount, 0, 1e30);
        // convertToAssets(convertToShares(x)) <= x  — rounds toward the vault.
        uint256 shares = vault.convertToShares(amount);
        assertLe(vault.convertToAssets(shares), amount);
    }

    function testFuzz_depositRedeem(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000e18);
        vm.startPrank(alice);
        uint256 shares = vault.deposit(amount, alice);
        uint256 back = vault.redeem(shares, alice, alice);
        vm.stopPrank();
        assertLe(back, amount);
        assertApproxEqAbs(back, amount, 1); // at most 1 wei lost to rounding
    }

    // ─── Yield sharing ────────────────────────────────────────────────────────
    function test_yield_sharedProRata() public {
        vm.prank(alice);
        vault.deposit(100e18, alice);

        // Simulate staking rewards: extra asset transferred straight in.
        asset.mint(address(vault), 100e18);

        // Alice owns 100% of shares, so her position now reflects 200 assets.
        assertEq(vault.totalAssets(), 200e18);
        assertApproxEqAbs(vault.maxWithdraw(alice), 200e18, 1);
    }

    // ─── Inflation attack ─────────────────────────────────────────────────────
    function testFuzz_inflationAttackDefence(uint256 donation) public {
        // Griefing donation up to 100x the victim's deposit.
        donation = bound(donation, 1e18, 1000e18);
        uint256 victimDeposit = 10e18;

        // Attacker seeds 1 wei of shares, then donates directly to the vault.
        vm.prank(bob);
        uint256 attackerShares = vault.deposit(1, bob);
        asset.mint(address(vault), donation);
        uint256 attackerCost = 1 + donation;

        // Victim deposits after the donation — virtual shares + the decimals
        // offset keep the victim's position non-trivial.
        vm.prank(alice);
        uint256 victimShares = vault.deposit(victimDeposit, alice);
        assertGt(victimShares, 0, "victim must receive shares");

        // The attack must never be profitable: the attacker can never redeem
        // more than the assets they sank into the vault.
        assertLe(
            vault.previewRedeem(attackerShares),
            attackerCost,
            "inflation attack must not profit"
        );
    }
}
