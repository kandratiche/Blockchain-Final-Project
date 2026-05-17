// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MockAggregator
/// @notice Test double for a Chainlink AggregatorV3 feed. Lets tests drive the
///         answer and its `updatedAt` timestamp to exercise PriceOracle's
///         staleness and invalid-price checks.
contract MockAggregator {
    uint8  public decimals;
    string public description = "MOCK / USD";

    int256  private _answer;
    uint256 private _updatedAt;
    uint80  private _roundId;

    constructor(uint8 decimals_, int256 initialAnswer) {
        decimals   = decimals_;
        _answer    = initialAnswer;
        _updatedAt = block.timestamp;
        _roundId   = 1;
    }

    /// @notice Set a fresh answer (updatedAt = now).
    function setAnswer(int256 newAnswer) external {
        _answer    = newAnswer;
        _updatedAt = block.timestamp;
        _roundId  += 1;
    }

    /// @notice Override only the answer's age — used to simulate a stale feed.
    function setUpdatedAt(uint256 timestamp) external {
        _updatedAt = timestamp;
    }

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (_roundId, _answer, _updatedAt, _updatedAt, _roundId);
    }
}
