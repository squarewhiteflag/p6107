// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Script } from "forge-std/Script.sol";
import { ChainFateArena } from "../src/ChainFateArena.sol";
import { ChainlinkVRFCoordinatorAdapter } from "../src/ChainlinkVRFCoordinatorAdapter.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";

contract DeployChainlinkVRFChainFateArena is Script {
    uint256 internal constant ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    // Chainlink VRF v2.5 Sepolia values from the Chainlink documentation.
    address internal constant SEPOLIA_VRF_COORDINATOR = 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B;
    bytes32 internal constant SEPOLIA_KEY_HASH =
        0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae;

    function run() external {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", ANVIL_PRIVATE_KEY);
        address deployer = vm.addr(deployerKey);

        address vrfCoordinator =
            address(uint160(vm.envOr("VRF_COORDINATOR", uint256(uint160(SEPOLIA_VRF_COORDINATOR)))));
        uint256 subscriptionId = vm.envOr("VRF_SUBSCRIPTION_ID", uint256(1));
        bytes32 keyHash = bytes32(vm.envOr("VRF_KEY_HASH", uint256(SEPOLIA_KEY_HASH)));
        uint32 callbackGasLimit = uint32(vm.envOr("VRF_CALLBACK_GAS_LIMIT", uint256(500_000)));
        uint16 requestConfirmations = uint16(vm.envOr("VRF_REQUEST_CONFIRMATIONS", uint256(3)));
        bool nativePayment = vm.envOr("VRF_NATIVE_PAYMENT", uint256(0)) != 0;

        uint256 initialEthBankroll = vm.envOr("INITIAL_ETH_BANKROLL", uint256(0));
        uint256 initialFateBankroll = vm.envOr("INITIAL_FATE_BANKROLL", uint256(0));

        vm.startBroadcast(deployerKey);

        ChainlinkVRFCoordinatorAdapter adapter = new ChainlinkVRFCoordinatorAdapter(
            vrfCoordinator, subscriptionId, keyHash, callbackGasLimit, requestConfirmations, nativePayment
        );
        ChainFateArena arena = new ChainFateArena(deployer, address(adapter));
        MockERC20 chip = new MockERC20("Fate Chip", "FATE", 18);

        adapter.setConsumer(address(arena), true);

        arena.configureToken(address(0), true, 250, 0.005 ether, 0.5 ether);
        arena.configureToken(address(chip), true, 300, 50 ether, 5_000 ether);

        if (initialEthBankroll > 0) {
            arena.seedBankroll{ value: initialEthBankroll }(address(0), initialEthBankroll);
        }

        chip.mint(deployer, 300_000 ether);
        if (initialFateBankroll > 0) {
            chip.approve(address(arena), initialFateBankroll);
            arena.seedBankroll(address(chip), initialFateBankroll);
        }

        arena.createRaffleRound(address(0), 0.02 ether, uint64(block.timestamp + 1 days));
        arena.createRaffleRound(address(chip), 100 ether, uint64(block.timestamp + 1 days));

        vm.stopBroadcast();
    }
}
