// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import {
    ChainFateArena,
    InvalidCommitment,
    InvalidRange,
    RandomnessPending,
    RevealWindowOpen
} from "../src/ChainFateArena.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { MockVRFCoordinator } from "../src/mocks/MockVRFCoordinator.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";

contract ChainFateArenaTest is Test {
    ChainFateArena internal arena;
    MockVRFCoordinator internal vrf;
    MockERC20 internal fate;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCA20);

    function setUp() public {
        vrf = new MockVRFCoordinator(address(this));
        arena = new ChainFateArena(address(this), address(vrf));
        fate = new MockERC20("Fate Chip", "FATE", 18);

        arena.configureToken(address(0), true, 250, 0.05 ether, 5 ether);
        arena.configureToken(address(fate), true, 300, 50 ether, 5_000 ether);

        vm.deal(address(this), 200 ether);
        arena.seedBankroll{ value: 80 ether }(address(0), 80 ether);

        fate.mint(address(this), 300_000 ether);
        fate.mint(alice, 30_000 ether);
        fate.mint(bob, 30_000 ether);
        fate.approve(address(arena), type(uint256).max);
        arena.seedBankroll(address(fate), 150_000 ether);

        vm.deal(alice, 20 ether);
        vm.deal(bob, 20 ether);
        vm.deal(carol, 20 ether);

        vm.startPrank(alice);
        fate.approve(address(arena), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        fate.approve(address(arena), type(uint256).max);
        vm.stopPrank();
    }

    function testDiceWinRevealPaysOutAndRefundsBond() public {
        bytes32 seed = _seed("alice-dice-win");
        uint8 rollUnder = 80;
        uint256 vrfWord = _vrfForDiceOutcome(alice, seed, 1, rollUnder, true);
        bytes32 commitment = arena.commitmentFor(alice, seed);
        uint256 startingBalance = alice.balance;

        vm.prank(alice);
        uint256 betId =
            arena.commitDiceBet{ value: 1.1 ether }(address(0), 1 ether, rollUnder, commitment, 0.1 ether);

        ChainFateArena.DiceBet memory betBefore = arena.getDiceBet(betId);
        vrf.fulfillRequestWithWord(betBefore.requestId, vrfWord);

        uint256 payout = arena.quoteDicePayout(address(0), 1 ether, rollUnder);
        vm.prank(alice);
        arena.revealDiceSeed(betId, seed);

        ChainFateArena.DiceBet memory betAfter = arena.getDiceBet(betId);
        assertTrue(betAfter.settled);
        assertTrue(betAfter.won);
        assertTrue(betAfter.rolled <= rollUnder);
        assertEq(alice.balance, startingBalance - 1.1 ether + payout + 0.1 ether);
        assertEq(arena.reservedDicePayouts(address(0)), 0);
        assertEq(arena.reservedRevealBonds(address(0)), 0);
    }

    function testDiceLossMovesWagerToTreasuryAndRefundsBond() public {
        bytes32 seed = _seed("alice-dice-loss");
        uint8 rollUnder = 5;
        uint256 vrfWord = _vrfForDiceOutcome(alice, seed, 1, rollUnder, false);
        bytes32 commitment = arena.commitmentFor(alice, seed);
        uint256 startingBalance = alice.balance;

        vm.prank(alice);
        uint256 betId =
            arena.commitDiceBet{ value: 1.2 ether }(address(0), 1 ether, rollUnder, commitment, 0.2 ether);

        ChainFateArena.DiceBet memory betBefore = arena.getDiceBet(betId);
        vrf.fulfillRequestWithWord(betBefore.requestId, vrfWord);

        vm.prank(alice);
        arena.revealDiceSeed(betId, seed);

        ChainFateArena.DiceBet memory betAfter = arena.getDiceBet(betId);
        assertTrue(betAfter.settled);
        assertFalse(betAfter.won);
        assertTrue(betAfter.rolled > rollUnder);
        assertEq(alice.balance, startingBalance - 1 ether);
        assertEq(arena.treasuryBalance(address(0)), 1 ether);
    }

    function testDiceWrongSeedReverts() public {
        bytes32 seed = _seed("good-seed");
        bytes32 wrongSeed = _seed("wrong-seed");
        bytes32 commitment = arena.commitmentFor(alice, seed);

        vm.prank(alice);
        uint256 betId =
            arena.commitDiceBet{ value: 0.66 ether }(address(0), 0.6 ether, 60, commitment, 0.06 ether);

        ChainFateArena.DiceBet memory betBefore = arena.getDiceBet(betId);
        vrf.fulfillRequestWithWord(betBefore.requestId, 444);

        vm.prank(alice);
        vm.expectRevert(InvalidCommitment.selector);
        arena.revealDiceSeed(betId, wrongSeed);
    }

    function testDiceRetryIgnoresStaleCallback() public {
        bytes32 seed = _seed("retry");
        bytes32 commitment = arena.commitmentFor(alice, seed);

        vm.prank(alice);
        uint256 betId =
            arena.commitDiceBet{ value: 0.55 ether }(address(0), 0.5 ether, 30, commitment, 0.05 ether);

        vm.expectRevert(RandomnessPending.selector);
        arena.retryDiceRandomness(betId);

        vm.warp(block.timestamp + 16 minutes);
        uint256 newRequestId = arena.retryDiceRandomness(betId);

        vrf.fulfillRequestWithWord(1, 999);
        ChainFateArena.DiceBet memory afterStaleCallback = arena.getDiceBet(betId);
        assertEq(uint256(afterStaleCallback.requestId), uint256(newRequestId));
        assertEq(uint256(afterStaleCallback.revealDeadline), 0);
        assertFalse(afterStaleCallback.randomnessReady);

        vrf.fulfillRequestWithWord(newRequestId, 777);
        ChainFateArena.DiceBet memory afterFreshCallback = arena.getDiceBet(betId);
        assertTrue(afterFreshCallback.randomnessReady);
    }

    function testDiceExpiredRevealSlashesWagerAndBond() public {
        bytes32 seed = _seed("expire");
        bytes32 commitment = arena.commitmentFor(alice, seed);

        vm.prank(alice);
        uint256 betId =
            arena.commitDiceBet{ value: 1.2 ether }(address(0), 1 ether, 50, commitment, 0.2 ether);

        ChainFateArena.DiceBet memory betBefore = arena.getDiceBet(betId);
        vrf.fulfillRequestWithWord(betBefore.requestId, 123);

        vm.expectRevert(RevealWindowOpen.selector);
        arena.slashExpiredDice(betId);

        vm.warp(block.timestamp + 21 minutes);
        arena.slashExpiredDice(betId);

        assertEq(arena.treasuryBalance(address(0)), 1.2 ether);
        assertEq(arena.reservedRevealBonds(address(0)), 0);
        assertEq(arena.reservedDicePayouts(address(0)), 0);
    }

    function testRaffleRevealFinalizePaysWinnerAndFees() public {
        uint256 roundId = arena.createRaffleRound(address(0), 0.5 ether, uint64(block.timestamp + 1 hours));
        bytes32 aliceSeed = _seed("alice-raffle");
        bytes32 bobSeed = _seed("bob-raffle");
        bytes32 aliceCommitment = arena.commitmentFor(alice, aliceSeed);
        bytes32 bobCommitment = arena.commitmentFor(bob, bobSeed);

        vm.prank(alice);
        uint256 aliceEntry =
            arena.buyRaffleTickets{ value: 1.25 ether }(roundId, 2, aliceCommitment, 0.25 ether);
        vm.prank(bob);
        uint256 bobEntry = arena.buyRaffleTickets{ value: 0.75 ether }(roundId, 1, bobCommitment, 0.25 ether);

        vm.warp(block.timestamp + 2 hours);
        uint256 requestId = arena.drawRaffle(roundId);
        vrf.fulfillRequestWithWord(requestId, 8181);

        uint256 aliceBeforeReveal = alice.balance;
        vm.prank(alice);
        arena.revealRaffleSeed(roundId, aliceEntry, aliceSeed);
        assertEq(alice.balance, aliceBeforeReveal + 0.25 ether);

        vm.prank(bob);
        arena.revealRaffleSeed(roundId, bobEntry, bobSeed);

        ChainFateArena.RaffleRound memory roundBeforeFinalize = arena.getRaffleRound(roundId);
        vm.warp(uint256(roundBeforeFinalize.revealDeadline) + 1);

        arena.finalizeRaffle(roundId);
        ChainFateArena.RaffleRound memory roundAfterFinalize = arena.getRaffleRound(roundId);

        assertTrue(roundAfterFinalize.finalized);
        assertEq(roundAfterFinalize.totalTickets, uint32(3));
        assertTrue(roundAfterFinalize.winningTicket < 3);
        assertEq(roundAfterFinalize.ticketPrice, uint128(0.5 ether));
        assertEq(roundAfterFinalize.pot, uint128(1.5 ether));
        assertTrue(roundAfterFinalize.winner == alice || roundAfterFinalize.winner == bob);
        assertEq(arena.treasuryBalance(address(0)), (1.5 ether * 250) / 10_000);
        assertEq(arena.reservedRafflePots(address(0)), 0);
        assertEq(arena.reservedRevealBonds(address(0)), 0);
    }

    function testRaffleSlashesUnrevealedEntryBond() public {
        uint256 roundId = arena.createRaffleRound(address(0), 0.5 ether, uint64(block.timestamp + 1 hours));
        bytes32 aliceSeed = _seed("alice-reveal");
        bytes32 bobSeed = _seed("bob-hidden");
        bytes32 aliceCommitment = arena.commitmentFor(alice, aliceSeed);
        bytes32 bobCommitment = arena.commitmentFor(bob, bobSeed);

        vm.prank(alice);
        uint256 aliceEntry =
            arena.buyRaffleTickets{ value: 0.75 ether }(roundId, 1, aliceCommitment, 0.25 ether);
        vm.prank(bob);
        arena.buyRaffleTickets{ value: 0.75 ether }(roundId, 1, bobCommitment, 0.25 ether);

        vm.warp(block.timestamp + 2 hours);
        uint256 requestId = arena.drawRaffle(roundId);
        vrf.fulfillRequestWithWord(requestId, 7777);

        vm.prank(alice);
        arena.revealRaffleSeed(roundId, aliceEntry, aliceSeed);

        ChainFateArena.RaffleRound memory roundBeforeFinalize = arena.getRaffleRound(roundId);
        vm.warp(uint256(roundBeforeFinalize.revealDeadline) + 1);
        arena.finalizeRaffle(roundId);

        uint256 expectedFee = (1 ether * 250) / 10_000;
        assertEq(arena.treasuryBalance(address(0)), expectedFee + 0.25 ether);
        (, uint32 slashed) = _playerSlashingStats(bob);
        assertEq(slashed, uint32(1));
    }

    function testERC20DiceFlowSupported() public {
        bytes32 seed = _seed("erc20-dice");
        bytes32 commitment = arena.commitmentFor(alice, seed);
        uint256 beforeBalance = fate.balanceOf(alice);

        vm.prank(alice);
        uint256 betId = arena.commitDiceBet(address(fate), 100 ether, 75, commitment, 10 ether);

        ChainFateArena.DiceBet memory betBefore = arena.getDiceBet(betId);
        vrf.fulfillRequestWithWord(betBefore.requestId, _vrfForDiceOutcome(alice, seed, betId, 75, true));

        uint256 payout = arena.quoteDicePayout(address(fate), 100 ether, 75);
        vm.prank(alice);
        arena.revealDiceSeed(betId, seed);

        assertEq(fate.balanceOf(alice), beforeBalance - 110 ether + payout + 10 ether);
    }

    function testPauseAndOnlyOwnerControls() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        arena.configureToken(address(0), false, 250, 0.05 ether, 5 ether);

        arena.pause();
        bytes32 commitment = arena.commitmentFor(alice, _seed("paused"));
        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        arena.commitDiceBet{ value: 1.1 ether }(address(0), 1 ether, 50, commitment, 0.1 ether);
    }

    function testFuzzDiceQuoteRejectsInvalidRoll(uint8 rollUnder) public {
        if (rollUnder >= 2 && rollUnder <= 95) return;
        vm.expectRevert(InvalidRange.selector);
        arena.quoteDicePayout(address(0), 1 ether, rollUnder);
    }

    function testFuzzRaffleTicketAccounting(uint8 rawCount) public {
        uint32 ticketCount = uint32((uint256(rawCount) % 20) + 1);
        uint256 roundId = arena.createRaffleRound(address(0), 0.1 ether, uint64(block.timestamp + 1 hours));
        bytes32 seed = keccak256(abi.encodePacked(rawCount, "ticket-accounting"));
        bytes32 commitment = arena.commitmentFor(alice, seed);

        vm.prank(alice);
        arena.buyRaffleTickets{ value: (0.1 ether * ticketCount) + 0.05 ether }(
            roundId, ticketCount, commitment, 0.05 ether
        );

        ChainFateArena.RaffleRound memory round = arena.getRaffleRound(roundId);
        assertEq(round.totalTickets, ticketCount);
        assertEq(round.ticketPrice, uint128(0.1 ether));
        assertEq(round.pot, uint128(uint256(ticketCount) * 0.1 ether));
    }

    function invariantInitialSolvency() public view {
        assertGe(
            address(arena).balance,
            arena.reservedDicePayouts(address(0)) + arena.reservedRevealBonds(address(0))
        );
        assertGe(
            fate.balanceOf(address(arena)),
            arena.reservedDicePayouts(address(fate)) + arena.reservedRevealBonds(address(fate))
        );
    }

    function _seed(string memory label) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(label));
    }

    function _vrfForDiceOutcome(address player, bytes32 seed, uint256 betId, uint8 rollUnder, bool shouldWin)
        internal
        view
        returns (uint256)
    {
        for (uint256 word = 1; word < 10_000; ++word) {
            uint8 rolled = arena.previewDiceRoll(word, seed, player, betId);
            if ((rolled <= rollUnder) == shouldWin) {
                return word;
            }
        }
        revert("no suitable word");
    }

    function _playerSlashingStats(address player) internal view returns (uint32 revealed, uint32 slashed) {
        (,,,, revealed, slashed) = arena.playerStats(player);
    }
}
