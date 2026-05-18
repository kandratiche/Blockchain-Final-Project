// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "./GameItems.sol";

/// @title ResourceAMM
/// @notice Constant-product AMM (x * y = k) for pairs of GameItems fungible
///         resources ($IRON=1, $WOOD=2, $MANA=3).
///         Each pool is identified by (tokenA, tokenB) where tokenA < tokenB.
///         Liquidity providers earn LP shares stored as a plain mapping.
///         Swap fees accrue to a DAO treasury address.
///         Fee rate and treasury are DAO-settable (owner).
contract ResourceAMM is Ownable, ERC1155Holder {
    // ─── External contracts ───────────────────────────────────────────────────
    GameItems public immutable items;

    // ─── Fee config ───────────────────────────────────────────────────────────
    uint256 public feeBps = 30; // 0.30 % default
    address public treasury;

    // ─── Pool storage ─────────────────────────────────────────────────────────
    struct Pool {
        uint256 reserveA;
        uint256 reserveB;
        uint256 totalShares;
    }
    /// @dev key = keccak256(abi.encode(tokenA, tokenB)), tokenA < tokenB
    mapping(bytes32 => Pool) public pools;
    /// @dev LP balances: poolKey => (provider => shares)
    mapping(bytes32 => mapping(address => uint256)) public lpBalance;

    // ─── Events ───────────────────────────────────────────────────────────────
    event PoolCreated(uint256 tokenA, uint256 tokenB);
    event LiquidityAdded(bytes32 indexed key, address indexed provider, uint256 amtA, uint256 amtB, uint256 shares);
    event LiquidityRemoved(bytes32 indexed key, address indexed provider, uint256 amtA, uint256 amtB);
    event Swapped(bytes32 indexed key, address indexed trader, uint256 tokenIn, uint256 amountIn, uint256 amountOut);
    event FeeUpdated(uint256 newFeeBps);

    constructor(address itemsContract_, address treasury_, address admin_) Ownable(admin_) {
        items = GameItems(itemsContract_);
        treasury = treasury_;
    }

    // ─── View helpers ─────────────────────────────────────────────────────────
    function poolKey(uint256 tA, uint256 tB) public pure returns (bytes32) {
        require(tA != tB, "AMM: same token");
        return tA < tB ? keccak256(abi.encode(tA, tB)) : keccak256(abi.encode(tB, tA));
    }

    function getReserves(uint256 tA, uint256 tB) external view returns (uint256 rA, uint256 rB) {
        (uint256 lo, uint256 hi) = tA < tB ? (tA, tB) : (tB, tA);
        Pool storage p = pools[keccak256(abi.encode(lo, hi))];
        (rA, rB) = (p.reserveA, p.reserveB);
    }

    // ─── Add liquidity ────────────────────────────────────────────────────────
    /// @notice Deposit amtA of tokenA and amtB of tokenB into the pool.
    ///         On first deposit the ratio is set freely.
    ///         On subsequent deposits amtB is adjusted to maintain current ratio.
    function addLiquidity(uint256 tokenA, uint256 amtA, uint256 tokenB, uint256 amtB)
        external
        returns (uint256 shares)
    {
        (uint256 lo, uint256 hi, uint256 loAmt, uint256 hiAmt) =
            tokenA < tokenB ? (tokenA, tokenB, amtA, amtB) : (tokenB, tokenA, amtB, amtA);

        bytes32 key = keccak256(abi.encode(lo, hi));
        Pool storage p = pools[key];

        if (p.totalShares == 0) {
            // First deposit — seed the pool
            shares = _sqrt(loAmt * hiAmt);
            p.reserveA += loAmt;
            p.reserveB += hiAmt;
            emit PoolCreated(lo, hi);
        } else {
            // Proportional deposit
            uint256 sharesFromA = (loAmt * p.totalShares) / p.reserveA;
            uint256 sharesFromB = (hiAmt * p.totalShares) / p.reserveB;
            shares = sharesFromA < sharesFromB ? sharesFromA : sharesFromB;

            // Recalculate actual amounts from the binding side
            loAmt = (shares * p.reserveA) / p.totalShares;
            hiAmt = (shares * p.reserveB) / p.totalShares;

            p.reserveA += loAmt;
            p.reserveB += hiAmt;
        }

        require(shares > 0, "AMM: zero shares");
        p.totalShares += shares;
        lpBalance[key][msg.sender] += shares;

        // Transfer tokens in
        items.safeTransferFrom(msg.sender, address(this), lo, loAmt, "");
        items.safeTransferFrom(msg.sender, address(this), hi, hiAmt, "");

        emit LiquidityAdded(key, msg.sender, loAmt, hiAmt, shares);
    }

    // ─── Remove liquidity ─────────────────────────────────────────────────────
    function removeLiquidity(uint256 tokenA, uint256 tokenB, uint256 shares)
        external
        returns (uint256 amtA, uint256 amtB)
    {
        (uint256 lo, uint256 hi) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        bytes32 key = keccak256(abi.encode(lo, hi));
        Pool storage p = pools[key];

        require(lpBalance[key][msg.sender] >= shares, "AMM: insufficient LP");
        require(p.totalShares > 0, "AMM: empty pool");

        amtA = (shares * p.reserveA) / p.totalShares;
        amtB = (shares * p.reserveB) / p.totalShares;

        p.reserveA -= amtA;
        p.reserveB -= amtB;
        p.totalShares -= shares;
        lpBalance[key][msg.sender] -= shares;

        items.safeTransferFrom(address(this), msg.sender, lo, amtA, "");
        items.safeTransferFrom(address(this), msg.sender, hi, amtB, "");

        emit LiquidityRemoved(key, msg.sender, amtA, amtB);
    }

    // ─── Swap ─────────────────────────────────────────────────────────────────
    /// @notice Swap `amountIn` of `tokenIn` for the other token in the pair.
    function swap(uint256 tokenIn, uint256 tokenOut, uint256 amountIn, uint256 minAmountOut)
        external
        returns (uint256 amountOut)
    {
        (uint256 lo, uint256 hi) = tokenIn < tokenOut ? (tokenIn, tokenOut) : (tokenOut, tokenIn);
        bytes32 key = keccak256(abi.encode(lo, hi));
        Pool storage p = pools[key];
        require(p.reserveA > 0 && p.reserveB > 0, "AMM: empty pool");

        bool inIsLo = tokenIn == lo;
        (uint256 rIn, uint256 rOut) = inIsLo ? (p.reserveA, p.reserveB) : (p.reserveB, p.reserveA);

        // Apply fee: amountInWithFee = amountIn * (10000 - feeBps)
        uint256 amountInAfterFee = amountIn * (10_000 - feeBps);
        amountOut = (amountInAfterFee * rOut) / (rIn * 10_000 + amountInAfterFee);
        require(amountOut >= minAmountOut, "AMM: slippage");

        // Fee portion goes to treasury
        uint256 fee = (amountIn * feeBps) / 10_000;
        if (fee > 0) {
            items.safeTransferFrom(msg.sender, treasury, tokenIn, fee, "");
        }

        // Transfer amountIn (minus fee) from trader
        items.safeTransferFrom(msg.sender, address(this), tokenIn, amountIn - fee, "");
        // Transfer amountOut to trader
        items.safeTransferFrom(address(this), msg.sender, tokenOut, amountOut, "");

        // Update reserves
        if (inIsLo) {
            p.reserveA = p.reserveA + (amountIn - fee);
            p.reserveB = p.reserveB - amountOut;
        } else {
            p.reserveA = p.reserveA - amountOut;
            p.reserveB = p.reserveB + (amountIn - fee);
        }

        emit Swapped(key, msg.sender, tokenIn, amountIn, amountOut);
    }

    // ─── Quote helper ─────────────────────────────────────────────────────────
    function quoteOut(uint256 tokenIn, uint256 tokenOut, uint256 amountIn) external view returns (uint256 amountOut) {
        (uint256 lo, uint256 hi) = tokenIn < tokenOut ? (tokenIn, tokenOut) : (tokenOut, tokenIn);
        Pool storage p = pools[keccak256(abi.encode(lo, hi))];
        bool inIsLo = tokenIn == lo;
        (uint256 rIn, uint256 rOut) = inIsLo ? (p.reserveA, p.reserveB) : (p.reserveB, p.reserveA);
        if (rIn == 0) return 0;
        uint256 inAfterFee = amountIn * (10_000 - feeBps);
        amountOut = (inAfterFee * rOut) / (rIn * 10_000 + inAfterFee);
    }

    // ─── DAO setters ──────────────────────────────────────────────────────────
    function setFeeBps(uint256 newFee) external onlyOwner {
        require(newFee <= 1000, "AMM: fee too high"); // max 10 %
        feeBps = newFee;
        emit FeeUpdated(newFee);
    }

    function setTreasury(address newTreasury) external onlyOwner {
        treasury = newTreasury;
    }

    // ─── ERC1155Holder override ───────────────────────────────────────────────
    function supportsInterface(bytes4 interfaceId) public view override(ERC1155Holder) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // ─── Math ─────────────────────────────────────────────────────────────────
    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) z = x;
            x = (y / x + x) / 2;
        } else if (y != 0) {
            z = 1;
        }
    }
}
