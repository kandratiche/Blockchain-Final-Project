// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/GuildFactory.sol";
import "../src/Guild.sol";

/// @notice Tests for GuildFactory (CREATE + CREATE2 deployment) and the Guild
///         membership lifecycle.
contract GuildFactoryTest is Test {
    GuildFactory factory;

    address leader = address(0xA1);
    address member = address(0xA2);
    address member2 = address(0xA3);

    function setUp() public {
        factory = new GuildFactory();
    }

    // ─── CREATE ───────────────────────────────────────────────────────────────
    function test_createGuild_create() public {
        address g = factory.createGuild("Iron Wolves", leader);
        assertTrue(g != address(0));
        assertEq(factory.guildCount(), 1);
        assertEq(factory.allGuilds(0), g);

        Guild guild = Guild(g);
        assertEq(guild.name(), "Iron Wolves");
        assertEq(guild.leader(), leader);
        assertEq(guild.factory(), address(factory));
        assertTrue(guild.isMember(leader));
        assertEq(guild.memberCount(), 1);
    }

    function test_createGuild_distinctAddresses() public {
        address g1 = factory.createGuild("A", leader);
        address g2 = factory.createGuild("B", leader);
        assertTrue(g1 != g2);
        assertEq(factory.guildCount(), 2);
    }

    // ─── CREATE2 ──────────────────────────────────────────────────────────────
    function test_createGuildDeterministic_matchesPrediction() public {
        bytes32 salt = keccak256("guild-salt-1");
        address predicted = factory.predictGuildAddress("Shadow Clan", leader, salt);

        address actual = factory.createGuildDeterministic("Shadow Clan", leader, salt);
        assertEq(actual, predicted, "CREATE2 address must match prediction");
        assertEq(factory.guildBySalt(salt), actual);
    }

    function test_createGuildDeterministic_revertsOnSaltReuse() public {
        bytes32 salt = keccak256("dup");
        factory.createGuildDeterministic("First", leader, salt);
        vm.expectRevert(GuildFactory.SaltAlreadyUsed.selector);
        factory.createGuildDeterministic("Second", leader, salt);
    }

    function test_predict_differsBySalt() public view {
        address p1 = factory.predictGuildAddress("X", leader, keccak256("s1"));
        address p2 = factory.predictGuildAddress("X", leader, keccak256("s2"));
        assertTrue(p1 != p2);
    }

    // ─── Guild membership ─────────────────────────────────────────────────────
    function test_join_addsMember() public {
        Guild guild = Guild(factory.createGuild("G", leader));
        vm.prank(member);
        guild.join();
        assertTrue(guild.isMember(member));
        assertEq(guild.memberCount(), 2);
    }

    function test_join_revertsIfAlreadyMember() public {
        Guild guild = Guild(factory.createGuild("G", leader));
        vm.prank(member);
        guild.join();
        vm.prank(member);
        vm.expectRevert(Guild.AlreadyMember.selector);
        guild.join();
    }

    function test_leave_removesMember() public {
        Guild guild = Guild(factory.createGuild("G", leader));
        vm.startPrank(member);
        guild.join();
        guild.leave();
        vm.stopPrank();
        assertFalse(guild.isMember(member));
        assertEq(guild.memberCount(), 1);
    }

    function test_leave_leaderCannotLeave() public {
        Guild guild = Guild(factory.createGuild("G", leader));
        vm.prank(leader);
        vm.expectRevert(Guild.LeaderCannotLeave.selector);
        guild.leave();
    }

    function test_transferLeadership() public {
        Guild guild = Guild(factory.createGuild("G", leader));
        vm.prank(member);
        guild.join();

        vm.prank(leader);
        guild.transferLeadership(member);
        assertEq(guild.leader(), member);
    }

    function test_transferLeadership_onlyLeader() public {
        Guild guild = Guild(factory.createGuild("G", leader));
        vm.prank(member);
        vm.expectRevert(Guild.NotLeader.selector);
        guild.transferLeadership(member);
    }

    function test_transferLeadership_targetMustBeMember() public {
        Guild guild = Guild(factory.createGuild("G", leader));
        vm.prank(leader);
        vm.expectRevert(Guild.NotMember.selector);
        guild.transferLeadership(member2);
    }
}
