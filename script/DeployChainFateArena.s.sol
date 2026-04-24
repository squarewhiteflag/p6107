// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Script } from "forge-std/Script.sol";
import { ChainFateArena } from "../src/ChainFateArena.sol";
import { MockVRFCoordinator } from "../src/mocks/MockVRFCoordinator.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";

contract DeployChainFateArena is Script {
    uint256 internal constant ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    function run() external {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", ANVIL_PRIVATE_KEY);
        address deployer = vm.addr(deployerKey);
        vm.startBroadcast(deployerKey);

        MockVRFCoordinator coordinator = new MockVRFCoordinator(deployer);
        ChainFateArena arena = new ChainFateArena(deployer, address(coordinator));
        MockERC20 chip = new MockERC20("Fate Chip", "FATE", 18);

        arena.configureToken(address(0), true, 250, 0.05 ether, 5 ether);
        arena.configureToken(address(chip), true, 300, 50 ether, 5_000 ether);

        arena.seedBankroll{ value: 20 ether }(address(0), 20 ether);
        chip.mint(deployer, 300_000 ether);
        chip.approve(address(arena), type(uint256).max);
        arena.seedBankroll(address(chip), 120_000 ether);

        arena.createRaffleRound(address(0), 0.2 ether, uint64(block.timestamp + 1 days));
        arena.createRaffleRound(address(chip), 100 ether, uint64(block.timestamp + 1 days));

        vm.stopBroadcast();
    }
}
