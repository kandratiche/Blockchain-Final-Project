// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./Guild.sol";

/// @title GuildFactory
/// @notice Deploys Guild contracts using BOTH deployment opcodes:
///           - createGuild              → CREATE  (nonce-derived address)
///           - createGuildDeterministic → CREATE2 (salt-derived address)
/// @dev    Design pattern: Factory. CREATE2 lets callers reserve a guild
///         address in advance — see predictGuildAddress.
contract GuildFactory {
    /// @notice Every guild ever deployed by this factory.
    address[] public allGuilds;

    /// @notice Salt-derived guilds, looked up by their deterministic salt.
    mapping(bytes32 => address) public guildBySalt;

    event GuildCreated(address indexed guild, address indexed leader, bool deterministic);

    error SaltAlreadyUsed();

    /// @notice Deploy a guild via CREATE — address depends on the factory nonce.
    function createGuild(string calldata name, address leader)
        external
        returns (address guild)
    {
        guild = address(new Guild(name, leader));
        allGuilds.push(guild);
        emit GuildCreated(guild, leader, false);
    }

    /// @notice Deploy a guild via CREATE2 — address is fully deterministic from
    ///         (factory, salt, bytecode + constructor args).
    function createGuildDeterministic(string calldata name, address leader, bytes32 salt)
        external
        returns (address guild)
    {
        if (guildBySalt[salt] != address(0)) revert SaltAlreadyUsed();
        guild = address(new Guild{salt: salt}(name, leader));
        guildBySalt[salt] = guild;
        allGuilds.push(guild);
        emit GuildCreated(guild, leader, true);
    }

    /// @notice Predict the CREATE2 address of a guild before it is deployed.
    /// @dev    Constructor args are part of the init code, so they must be
    ///         included in the hash exactly as createGuildDeterministic uses them.
    function predictGuildAddress(string calldata name, address leader, bytes32 salt)
        external
        view
        returns (address predicted)
    {
        bytes memory initCode =
            abi.encodePacked(type(Guild).creationCode, abi.encode(name, leader));
        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(initCode))
        );
        predicted = address(uint160(uint256(hash)));
    }

    function guildCount() external view returns (uint256) {
        return allGuilds.length;
    }
}
