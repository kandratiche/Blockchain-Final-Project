// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/// @title GameRegistryV1
/// @notice Upgradeable on-chain registry of player progression (XP and level).
///         Deployed behind an ERC-1967 proxy; upgrades follow the UUPS pattern
///         and are gated by `owner` (intended to be the DAO Timelock).
/// @dev    Storage layout (V1) — APPEND-ONLY across upgrades:
///           slot 0: owner       (address)
///           slot 1: _xp         (mapping address => uint256)
///           slot 2: xpPerLevel  (uint256)
///         A V2 implementation may ONLY append new storage after slot 2.
///         GameRegistryV2 inherits this contract, so its new mapping lands at
///         slot 3 — a collision is structurally impossible. See GameRegistryV2.
contract GameRegistryV1 is Initializable, UUPSUpgradeable {
    // ─── Storage (V1) ─────────────────────────────────────────────────────────
    address public owner;
    mapping(address => uint256) internal _xp;
    uint256 public xpPerLevel;

    // ─── Events ───────────────────────────────────────────────────────────────
    event XPGranted(address indexed player, uint256 amount, uint256 newTotal);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ─── Errors ───────────────────────────────────────────────────────────────
    error NotOwner();
    error ZeroAddress();
    error ZeroValue();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // Lock the implementation contract — it must only run behind a proxy.
        _disableInitializers();
    }

    /// @notice Proxy initializer — replaces the constructor for upgradeable use.
    function initialize(address owner_, uint256 xpPerLevel_) external initializer {
        if (owner_ == address(0)) revert ZeroAddress();
        if (xpPerLevel_ == 0) revert ZeroValue();
        owner = owner_;
        xpPerLevel = xpPerLevel_;
    }

    // ─── Progression ──────────────────────────────────────────────────────────
    /// @notice Award XP to a player. Restricted to the owner (game / DAO).
    function grantXP(address player, uint256 amount) external onlyOwner {
        uint256 total = _xp[player] + amount;
        _xp[player] = total;
        emit XPGranted(player, amount, total);
    }

    function xpOf(address player) external view returns (uint256) {
        return _xp[player];
    }

    /// @notice Player level derived from XP.
    function levelOf(address player) external view returns (uint256) {
        return _xp[player] / xpPerLevel;
    }

    // ─── Ownership ────────────────────────────────────────────────────────────
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    /// @notice Implementation version tag — overridden by V2.
    function version() external pure virtual returns (string memory) {
        return "V1";
    }

    // ─── UUPS authorization ───────────────────────────────────────────────────
    /// @dev Only the owner may authorize an implementation upgrade.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
