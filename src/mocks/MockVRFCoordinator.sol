// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IRandomnessCoordinator, IRandomnessConsumer } from "../interfaces/IRandomnessCoordinator.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

error RequestNotFound();
error RequestAlreadyFulfilled();

/// @notice Local VRF-style oracle. It models asynchronous request/fulfill behavior and proof hashes.
contract MockVRFCoordinator is IRandomnessCoordinator, Ownable, Pausable {
    struct Request {
        address requester;
        uint64 requestedAt;
        bool fulfilled;
        uint256 randomWord;
        bytes32 proofHash;
    }

    uint256 public nextRequestId = 1;
    uint256 private entropyNonce;

    mapping(uint256 => Request) public requests;

    event RandomnessRequested(uint256 indexed requestId, address indexed requester);
    event RandomnessFulfilled(uint256 indexed requestId, uint256 randomWord, bytes32 indexed proofHash);

    constructor(address initialOwner) Ownable(initialOwner) { }

    /// @notice Pauses local randomness requests and fulfillment during demos or tests.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Resumes local randomness requests and fulfillment.
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @inheritdoc IRandomnessCoordinator
    function requestRandomness() external override whenNotPaused returns (uint256 requestId) {
        requestId = nextRequestId++;
        requests[requestId] = Request({
            requester: msg.sender,
            requestedAt: uint64(block.timestamp),
            fulfilled: false,
            randomWord: 0,
            proofHash: bytes32(0)
        });
        emit RandomnessRequested(requestId, msg.sender);
    }

    /// @notice Fulfills a request using locally generated entropy for demos.
    function fulfillRequest(uint256 requestId)
        external
        whenNotPaused
        returns (uint256 randomWord, bytes32 proofHash)
    {
        Request storage request = _loadOpenRequest(requestId);
        bytes32 seed = keccak256(
            abi.encodePacked(
                requestId,
                request.requester,
                request.requestedAt,
                blockhash(block.number - 1),
                block.timestamp,
                entropyNonce++
            )
        );
        randomWord = uint256(keccak256(abi.encodePacked(seed, "CHAIN_FATE")));
        proofHash = keccak256(abi.encodePacked(requestId, request.requester, seed, randomWord));
        _deliver(requestId, request, randomWord, proofHash);
    }

    /// @notice Deterministic owner-only fulfillment used by tests and scripted demos.
    function fulfillRequestWithWord(uint256 requestId, uint256 randomWord) external onlyOwner whenNotPaused {
        Request storage request = _loadOpenRequest(requestId);
        bytes32 proofHash =
            keccak256(abi.encodePacked("MANUAL_PROOF", requestId, request.requester, randomWord));
        _deliver(requestId, request, randomWord, proofHash);
    }

    function _loadOpenRequest(uint256 requestId) internal view returns (Request storage request) {
        request = requests[requestId];
        if (request.requester == address(0)) revert RequestNotFound();
        if (request.fulfilled) revert RequestAlreadyFulfilled();
    }

    function _deliver(uint256 requestId, Request storage request, uint256 randomWord, bytes32 proofHash)
        internal
    {
        request.fulfilled = true;
        request.randomWord = randomWord;
        request.proofHash = proofHash;
        IRandomnessConsumer(request.requester).rawFulfillRandomness(requestId, randomWord, proofHash);
        emit RandomnessFulfilled(requestId, randomWord, proofHash);
    }
}
