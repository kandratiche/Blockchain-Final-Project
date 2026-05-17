// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Guild
/// @notice A player guild — a lightweight membership contract deployed once per
///         guild by GuildFactory (via CREATE or CREATE2).
contract Guild {
    string  public name;
    address public leader;
    address public immutable factory;
    uint256 public memberCount;

    mapping(address => bool) public isMember;

    event MemberJoined(address indexed member);
    event MemberLeft(address indexed member);
    event LeaderChanged(address indexed previousLeader, address indexed newLeader);

    error AlreadyMember();
    error NotMember();
    error NotLeader();
    error LeaderCannotLeave();

    constructor(string memory name_, address leader_) {
        require(leader_ != address(0), "Guild: zero leader");
        name    = name_;
        leader  = leader_;
        factory = msg.sender;
        isMember[leader_] = true;
        memberCount = 1;
    }

    /// @notice Join the guild.
    function join() external {
        if (isMember[msg.sender]) revert AlreadyMember();
        isMember[msg.sender] = true;
        memberCount++;
        emit MemberJoined(msg.sender);
    }

    /// @notice Leave the guild. The leader must hand over leadership first.
    function leave() external {
        if (!isMember[msg.sender]) revert NotMember();
        if (msg.sender == leader) revert LeaderCannotLeave();
        isMember[msg.sender] = false;
        memberCount--;
        emit MemberLeft(msg.sender);
    }

    /// @notice Transfer leadership to another member.
    function transferLeadership(address newLeader) external {
        if (msg.sender != leader) revert NotLeader();
        if (!isMember[newLeader]) revert NotMember();
        emit LeaderChanged(leader, newLeader);
        leader = newLeader;
    }
}
