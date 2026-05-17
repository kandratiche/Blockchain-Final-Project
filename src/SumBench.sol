// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title SumBench
/// @notice Two implementations of the same routine — summing a uint256 calldata
///         array — one in pure Solidity, one in inline Yul. Used to benchmark
///         the assembly path against the high-level equivalent (see
///         test/SumBench.t.sol for the before/after gas comparison).
/// @dev    The Yul version skips the per-element bounds check and the implicit
///         memory expansion of the Solidity loop, reading straight from
///         calldata. Both MUST return identical results for any input.
contract SumBench {
    /// @notice Pure-Solidity reference implementation.
    function sumSolidity(uint256[] calldata data) external pure returns (uint256 total) {
        uint256 len = data.length;
        for (uint256 i = 0; i < len; ++i) {
            total += data[i];
        }
    }

    /// @notice Inline-Yul implementation reading the array directly from calldata.
    function sumAssembly(uint256[] calldata data) external pure returns (uint256 total) {
        assembly {
            // `data.offset` is the calldata offset of the first element;
            // `data.length` is the element count.
            let len := data.length
            let ptr := data.offset
            for { let i := 0 } lt(i, len) { i := add(i, 1) } {
                total := add(total, calldataload(add(ptr, mul(i, 0x20))))
            }
        }
    }
}
