// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { ChainFateArena } from "../src/ChainFateArena.sol";
import {
    ChainlinkVRFCoordinatorAdapter,
    UnauthorizedConsumer
} from "../src/ChainlinkVRFCoordinatorAdapter.sol";
import { MockChainlinkVRFCoordinatorV2Plus } from "../src/mocks/MockChainlinkVRFCoordinatorV2Plus.sol";

contract ChainlinkVRFAdapterTest is Test {
    ChainFateArena internal arena;
    ChainlinkVRFCoordinatorAdapter internal adapter;
    MockChainlinkVRFCoordinatorV2Plus internal chainlinkCoordinator;

    address internal alice = address(0xA11CE);
    bytes32 internal constant KEY_HASH = 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae;

    function setUp() public {
        chainlinkCoordinator = new MockChainlinkVRFCoordinatorV2Plus();
        adapter = new ChainlinkVRFCoordinatorAdapter(
            address(chainlinkCoordinator), 1, KEY_HASH, 500_000, 3, false
        );
        arena = new ChainFateArena(address(this), address(adapter));
        adapter.setConsumer(address(arena), true);

        arena.configureToken(address(0), true, 250, 0.05 ether, 5 ether);
        vm.deal(address(this), 20 ether);
        arena.seedBankroll{ value: 10 ether }(address(0), 10 ether);
        vm.deal(alice, 5 ether);
    }

    function testChainlinkAdapterDiceFlow() public {
        bytes32 seed = keccak256("chainlink-adapter-dice");
        bytes32 commitment = arena.commitmentFor(alice, seed);

        vm.prank(alice);
        uint256 betId =
            arena.commitDiceBet{ value: 0.55 ether }(address(0), 0.5 ether, 60, commitment, 0.05 ether);

        ChainFateArena.DiceBet memory betBefore = arena.getDiceBet(betId);
        chainlinkCoordinator.fulfillRequestWithWord(betBefore.requestId, 777);

        ChainFateArena.DiceBet memory betAfterFulfill = arena.getDiceBet(betId);
        assertTrue(betAfterFulfill.randomnessReady);
        assertEq(betAfterFulfill.vrfWord, 777);
        assertTrue(betAfterFulfill.proofHash != bytes32(0));

        vm.prank(alice);
        arena.revealDiceSeed(betId, seed);

        ChainFateArena.DiceBet memory settled = arena.getDiceBet(betId);
        assertTrue(settled.settled);
    }

    function testAdapterRejectsUnapprovedConsumer() public {
        vm.expectRevert(UnauthorizedConsumer.selector);
        adapter.requestRandomness();
    }
}
