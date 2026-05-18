// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Minimal Chainlink aggregator interface — the subset PriceOracle uses.
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/// @title PriceOracle
/// @notice Adapter around a Chainlink price feed that enforces a freshness
///         (staleness) check and rejects non-positive prices. Used to value
///         in-game assets against an external reference price.
/// @dev    Design pattern: Oracle adapter / interface abstraction. The concrete
///         feed is swappable by the owner; tests inject a MockAggregator.
contract PriceOracle is Ownable {
    /// @notice The underlying Chainlink aggregator.
    AggregatorV3Interface public feed;

    /// @notice Maximum age (seconds) a feed answer may have before it is stale.
    uint256 public maxStaleness;

    event FeedUpdated(address indexed newFeed);
    event MaxStalenessUpdated(uint256 newMaxStaleness);

    error InvalidPrice(int256 answer);
    error StalePrice(uint256 updatedAt, uint256 blockTimestamp, uint256 maxStaleness);
    error ZeroAddress();

    constructor(address feed_, uint256 maxStaleness_, address admin_) Ownable(admin_) {
        if (feed_ == address(0)) revert ZeroAddress();
        require(maxStaleness_ > 0, "Oracle: zero staleness");
        feed = AggregatorV3Interface(feed_);
        maxStaleness = maxStaleness_;
    }

    /// @notice Latest price with its decimals. Reverts on a stale or bad answer.
    function getPrice() public view returns (uint256 price, uint8 priceDecimals) {
        (, int256 answer,, uint256 updatedAt,) = feed.latestRoundData();

        if (answer <= 0) revert InvalidPrice(answer);
        if (block.timestamp - updatedAt > maxStaleness) {
            revert StalePrice(updatedAt, block.timestamp, maxStaleness);
        }
        return (uint256(answer), feed.decimals());
    }

    /// @notice Convert a token amount into reference-currency value.
    /// @param  amount token amount, assumed to share the feed's decimals base.
    function valueOf(uint256 amount) external view returns (uint256) {
        (uint256 price, uint8 dec) = getPrice();
        return (amount * price) / (10 ** dec);
    }

    // ─── Owner config ─────────────────────────────────────────────────────────
    function setFeed(address newFeed) external onlyOwner {
        if (newFeed == address(0)) revert ZeroAddress();
        feed = AggregatorV3Interface(newFeed);
        emit FeedUpdated(newFeed);
    }

    function setMaxStaleness(uint256 newMaxStaleness) external onlyOwner {
        require(newMaxStaleness > 0, "Oracle: zero staleness");
        maxStaleness = newMaxStaleness;
        emit MaxStalenessUpdated(newMaxStaleness);
    }
}
