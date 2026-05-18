// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

/// @title RealmStakeVault
/// @notice ERC-4626 tokenized vault: stake $RLM, receive xRLM shares. Any $RLM
///         transferred into the vault (e.g. staking rewards routed by the DAO)
///         is shared pro-rata across all shareholders.
/// @dev    Built on OpenZeppelin's ERC4626, which applies virtual shares /
///         assets so every conversion rounds in the vault's favour — this is
///         what makes the ERC-4626 rounding invariants hold and neutralises the
///         classic first-depositor inflation attack. A non-zero decimals offset
///         hardens that further.
contract RealmStakeVault is ERC4626 {
    constructor(IERC20 asset_) ERC20("Staked RealmForge", "xRLM") ERC4626(asset_) {}

    /// @dev Virtual decimals offset — strengthens inflation-attack resistance.
    function _decimalsOffset() internal pure override returns (uint8) {
        return 3;
    }
}
