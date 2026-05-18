// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "@openzeppelin/contracts/governance/IGovernor.sol";
import "../src/RealmToken.sol";
import "../src/GameDAO.sol";
import "../src/GameItems.sol";
import "../src/CraftingEngine.sol";

/// @notice Governance tests for the full OZ Governor stack: RealmToken voting
///         power, Governor parameters (delay / period / quorum / threshold),
///         and the end-to-end propose -> vote -> queue -> execute lifecycle
///         driving a real protocol setter (CraftingEngine.setManaFee).
contract GameDAOTest is Test {
    RealmToken token;
    TimelockController timelock;
    GameDAO dao;
    GameItems items;
    CraftingEngine crafting;

    address voter = address(0xF1);
    address voter2 = address(0xF2);

    uint256 constant SUPPLY = 1_000_000e18; // total RLM minted
    uint256 constant TL_DELAY = 2 days; // timelock minimum delay

    function setUp() public {
        vm.warp(1_000_000); // sane starting timestamp for the token clock

        // ── Governance token ──────────────────────────────────────────────
        token = new RealmToken(address(this));

        // ── Timelock (this contract is temporary admin to wire roles) ─────
        address[] memory empty = new address[](0);
        timelock = new TimelockController(TL_DELAY, empty, empty, address(this));

        // ── Governor ──────────────────────────────────────────────────────
        dao = new GameDAO(IVotes(address(token)), timelock);

        // Governor may propose & cancel; anyone may execute a ready operation.
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(dao));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(dao));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
        // Drop the temporary admin — no backdoor remains.
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), address(this));

        // ── Protocol contract governed by the DAO ─────────────────────────
        items = new GameItems(address(this), "https://api.realmforge.io/meta/");
        crafting = new CraftingEngine(address(items), address(timelock), 5);

        // ── Distribute voting power ───────────────────────────────────────
        token.mint(voter, SUPPLY);
        vm.prank(voter);
        token.delegate(voter); // self-delegate to activate checkpoints

        // Advance past the delegation checkpoint so it counts as "past".
        vm.warp(block.timestamp + 1);
    }

    // ─── Token / voting power ─────────────────────────────────────────────────
    function test_token_isERC20VotesAndPermit() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.getVotes(voter), SUPPLY);
        assertEq(token.nonces(voter), 0); // ERC20Permit nonce starts at 0
        assertEq(keccak256(bytes(token.CLOCK_MODE())), keccak256("mode=timestamp"));
    }

    function test_votingPower_requiresDelegation() public {
        token.mint(voter2, 100e18);
        assertEq(token.getVotes(voter2), 0); // not delegated yet
        vm.prank(voter2);
        token.delegate(voter2);
        assertEq(token.getVotes(voter2), 100e18);
    }

    // ─── Governor parameters (spec) ───────────────────────────────────────────
    function test_governorParameters_matchSpec() public view {
        assertEq(dao.votingDelay(), 1 days);
        assertEq(dao.votingPeriod(), 1 weeks);
        assertEq(dao.proposalThreshold(), 10_000e18);
        // 4% of 1,000,000 RLM = 40,000 RLM.
        assertEq(dao.quorum(block.timestamp - 1), 40_000e18);
        assertEq(timelock.getMinDelay(), TL_DELAY);
    }

    // ─── Full lifecycle: propose -> vote -> queue -> execute ──────────────────
    function test_fullGovernanceLifecycle() public {
        uint256 newFee = 99;

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _setManaFeeProposal(newFee);
        bytes32 descHash = keccak256(bytes(description));

        // 1. Propose.
        vm.prank(voter);
        uint256 id = dao.propose(targets, values, calldatas, description);
        assertEq(uint8(dao.state(id)), uint8(IGovernor.ProposalState.Pending));

        // 2. Wait out the voting delay, then vote FOR.
        vm.warp(block.timestamp + dao.votingDelay() + 1);
        assertEq(uint8(dao.state(id)), uint8(IGovernor.ProposalState.Active));
        vm.prank(voter);
        dao.castVote(id, 1); // 1 = For

        // 3. Wait out the voting period -> Succeeded.
        vm.warp(block.timestamp + dao.votingPeriod() + 1);
        assertEq(uint8(dao.state(id)), uint8(IGovernor.ProposalState.Succeeded));

        // 4. Queue into the Timelock.
        dao.queue(targets, values, calldatas, descHash);
        assertEq(uint8(dao.state(id)), uint8(IGovernor.ProposalState.Queued));

        // 5. Wait out the timelock delay, then execute.
        vm.warp(block.timestamp + TL_DELAY + 1);
        dao.execute(targets, values, calldatas, descHash);
        assertEq(uint8(dao.state(id)), uint8(IGovernor.ProposalState.Executed));

        // 6. The governed parameter actually changed.
        assertEq(crafting.manaFee(), newFee);
    }

    function test_proposal_defeatedOnAgainstVote() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _setManaFeeProposal(7);

        vm.prank(voter);
        uint256 id = dao.propose(targets, values, calldatas, description);

        vm.warp(block.timestamp + dao.votingDelay() + 1);
        vm.prank(voter);
        dao.castVote(id, 0); // 0 = Against

        vm.warp(block.timestamp + dao.votingPeriod() + 1);
        assertEq(uint8(dao.state(id)), uint8(IGovernor.ProposalState.Defeated));
    }

    function test_propose_revertsBelowThreshold() public {
        // voter2 has only 100 RLM (< 10_000e18 threshold).
        token.mint(voter2, 100e18);
        vm.prank(voter2);
        token.delegate(voter2);
        vm.warp(block.timestamp + 1);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _setManaFeeProposal(1);

        vm.prank(voter2);
        vm.expectRevert();
        dao.propose(targets, values, calldatas, description);
    }

    function test_execute_revertsBeforeTimelockDelay() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _setManaFeeProposal(50);
        bytes32 descHash = keccak256(bytes(description));

        vm.prank(voter);
        uint256 id = dao.propose(targets, values, calldatas, description);
        vm.warp(block.timestamp + dao.votingDelay() + 1);
        vm.prank(voter);
        dao.castVote(id, 1);
        vm.warp(block.timestamp + dao.votingPeriod() + 1);
        dao.queue(targets, values, calldatas, descHash);

        // Executing before the timelock delay elapses must revert.
        vm.expectRevert();
        dao.execute(targets, values, calldatas, descHash);
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────
    function _setManaFeeProposal(uint256 newFee)
        internal
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description)
    {
        targets = new address[](1);
        values = new uint256[](1);
        calldatas = new bytes[](1);
        targets[0] = address(crafting);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(CraftingEngine.setManaFee, (newFee));
        description = string(abi.encodePacked("Set crafting MANA fee to ", vm.toString(newFee)));
    }
}
