// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/SumBench.sol";

/// @notice Correctness + gas benchmark for SumBench: the inline-Yul array sum
///         must return identical results to the pure-Solidity version while
///         consuming less gas. Run with -vv to see the before/after numbers.
contract SumBenchTest is Test {
    SumBench bench;

    function setUp() public {
        bench = new SumBench();
    }

    function _data(uint256 n) internal pure returns (uint256[] memory d) {
        d = new uint256[](n);
        for (uint256 i = 0; i < n; ++i) {
            d[i] = (i + 1) * 1e16;
        }
    }

    // ─── Correctness ──────────────────────────────────────────────────────────
    function test_bothImplementationsAgree() public view {
        uint256[] memory d = _data(64);
        assertEq(bench.sumSolidity(d), bench.sumAssembly(d));
    }

    function test_emptyArray() public view {
        uint256[] memory d = new uint256[](0);
        assertEq(bench.sumSolidity(d), 0);
        assertEq(bench.sumAssembly(d), 0);
    }

    function testFuzz_implementationsAgree(uint64[] calldata raw) public view {
        uint256[] memory d = new uint256[](raw.length);
        for (uint256 i = 0; i < raw.length; ++i) {
            d[i] = raw[i];
        }
        assertEq(bench.sumSolidity(d), bench.sumAssembly(d));
    }

    // ─── Gas benchmark (before / after) ───────────────────────────────────────
    function test_gasBenchmark() public {
        uint256[] memory d = _data(128);

        uint256 g0 = gasleft();
        uint256 sumSol = bench.sumSolidity(d);
        uint256 gasSolidity = g0 - gasleft();

        uint256 g1 = gasleft();
        uint256 sumAsm = bench.sumAssembly(d);
        uint256 gasAssembly = g1 - gasleft();

        assertEq(sumSol, sumAsm);

        emit log_named_uint("gas: pure Solidity ", gasSolidity);
        emit log_named_uint("gas: inline Yul    ", gasAssembly);
        emit log_named_uint("gas saved          ", gasSolidity - gasAssembly);

        // The assembly path must not be more expensive than the Solidity path.
        assertLe(gasAssembly, gasSolidity);
    }
}
