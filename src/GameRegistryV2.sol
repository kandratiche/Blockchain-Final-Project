// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./GameRegistryV1.sol";

/// @title GameRegistryV2
/// @notice V2 upgrade of GameRegistry. Adds a per-player achievement bitmap
///         while preserving the entire V1 storage layout.
/// @dev    Storage layout (V2) — V1 slots 0-2 are inherited UNCHANGED:
///           slot 0: owner            (from V1)
///           slot 1: _xp              (from V1)
///           slot 2: xpPerLevel       (from V1)
///           slot 3: _achievements    (NEW — appended, no collision)
///         Upgrade path: deploy GameRegistryV2, then call
///         `proxy.upgradeToAndCall(v2, "")`. No re-initialization is required
///         because V2 introduces no new init-time state.
contract GameRegistryV2 is GameRegistryV1 {
    // ─── Storage (V2 — appended after all V1 slots) ───────────────────────────
    /// @dev Bitmap of unlocked achievement IDs, keyed by player.
    mapping(address => uint256) internal _achievements;

    event AchievementUnlocked(address indexed player, uint256 indexed achievementId);

    error AchievementOutOfRange();

    /// @notice Unlock an achievement for a player (achievementId 0-255).
    function unlockAchievement(address player, uint256 achievementId) external onlyOwner {
        if (achievementId > 255) revert AchievementOutOfRange();
        _achievements[player] |= (uint256(1) << achievementId);
        emit AchievementUnlocked(player, achievementId);
    }

    function hasAchievement(address player, uint256 achievementId)
        external
        view
        returns (bool)
    {
        return _achievements[player] & (uint256(1) << achievementId) != 0;
    }

    function version() external pure override returns (string memory) {
        return "V2";
    }
}
