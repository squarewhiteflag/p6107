// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice VRF-like coordinator interface. A Chainlink VRF adapter can implement this shape.
interface IRandomnessCoordinator {
    function requestRandomness() external returns (uint256 requestId);
}

/// @notice Consumer callback used by the local mock and any production adapter.
interface IRandomnessConsumer {
    function rawFulfillRandomness(uint256 requestId, uint256 randomWord, bytes32 proofHash) external;
}

