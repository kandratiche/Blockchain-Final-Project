// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Nonces.sol";

/// @title RealmToken ($RLM)
/// @notice Governance token for the RealmForge DAO.
///         - ERC20Votes  — checkpointed voting power consumed by the Governor.
///         - ERC20Permit — gasless (EIP-2612) approvals.
///         The token uses a TIMESTAMP-based clock so the Governor's voting delay
///         and voting period are expressed in seconds (1 day / 1 week).
/// @dev    Minting is gated behind MINTER_ROLE (held by the deployer initially,
///         then transferable to the Timelock).
contract RealmToken is ERC20, ERC20Permit, ERC20Votes, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(address admin)
        ERC20("RealmForge Governance", "RLM")
        ERC20Permit("RealmForge Governance")
    {
        require(admin != address(0), "RLM: zero admin");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    /// @notice Mint new governance tokens. Restricted to MINTER_ROLE.
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    // ─── Timestamp-based clock (ERC-6372) ─────────────────────────────────────
    /// @dev Makes Governor delays/periods second-denominated instead of blocks.
    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    // ─── Required multiple-inheritance overrides ──────────────────────────────
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}
