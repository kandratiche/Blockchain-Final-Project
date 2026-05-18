// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "../src/PriceOracle.sol";

interface IUniswapV2Router {
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
}

/// @notice Fork tests against live Ethereum mainnet protocols. They require a
///         mainnet RPC in the MAINNET_RPC env var; without it each test marks
///         itself skipped instead of failing.
///
///   MAINNET_RPC=https://eth.llamarpc.com forge test --match-path test/Fork.t.sol
contract ForkTest is Test {
    // Mainnet addresses.
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant UNIV2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant ETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    /// @dev Selects a mainnet fork, or skips the calling test if no RPC is set.
    function _fork() internal returns (bool) {
        string memory rpc = vm.envOr("MAINNET_RPC", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return false;
        }
        vm.createSelectFork(rpc);
        return true;
    }

    // ─── Real USDC token ──────────────────────────────────────────────────────
    function test_fork_usdcMetadata() public {
        if (!_fork()) return;
        IERC20Metadata usdc = IERC20Metadata(USDC);
        assertEq(usdc.decimals(), 6, "USDC has 6 decimals");
        assertGt(usdc.totalSupply(), 0, "USDC supply non-zero");
    }

    // ─── Real Uniswap V2 router ───────────────────────────────────────────────
    function test_fork_uniswapV2Quote() public {
        if (!_fork()) return;
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = USDC;
        uint256[] memory amounts = IUniswapV2Router(UNIV2_ROUTER).getAmountsOut(1 ether, path);
        assertEq(amounts.length, 2);
        assertGt(amounts[1], 0, "1 WETH must quote to some USDC");
    }

    // ─── Real Chainlink ETH/USD feed via our PriceOracle ──────────────────────
    function test_fork_priceOracleAgainstLiveFeed() public {
        if (!_fork()) return;
        // 24h staleness window — the live feed updates well within that.
        PriceOracle oracle = new PriceOracle(ETH_USD_FEED, 1 days, address(this));
        (uint256 price, uint8 dec) = oracle.getPrice();
        assertEq(dec, 8, "ETH/USD feed uses 8 decimals");
        assertGt(price, 0, "live ETH price must be positive");
    }
}
