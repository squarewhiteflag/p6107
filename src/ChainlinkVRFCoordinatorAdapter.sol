// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IRandomnessCoordinator, IRandomnessConsumer } from "./interfaces/IRandomnessCoordinator.sol";
import { VRFConsumerBaseV2Plus } from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import { VRFV2PlusClient } from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

error UnauthorizedConsumer();
error InvalidVRFConfig();
error InvalidRequest();
error RequestAlreadyFulfilled();

/// @notice Chainlink VRF v2.5 adapter that matches the platform's randomness coordinator interface.
/// @dev The Chainlink coordinator verifies the VRF proof before this adapter receives fulfillRandomWords.
/// The `proofHash` forwarded to ChainFateArena is a fulfillment correlation hash for UI/audit trails.
contract ChainlinkVRFCoordinatorAdapter is IRandomnessCoordinator, VRFConsumerBaseV2Plus {
    uint32 public constant NUM_WORDS = 1;

    struct Request {
        address requester;
        bool fulfilled;
        uint256 randomWord;
        bytes32 fulfillmentHash;
    }

    uint256 public subscriptionId;
    bytes32 public keyHash;
    uint32 public callbackGasLimit;
    uint16 public requestConfirmations;
    bool public nativePayment;

    mapping(address => bool) public allowedConsumers;
    mapping(uint256 => Request) public requests;

    event ConsumerAllowed(address indexed consumer, bool allowed);
    event VRFConfigUpdated(
        uint256 subscriptionId,
        bytes32 indexed keyHash,
        uint32 callbackGasLimit,
        uint16 requestConfirmations,
        bool nativePayment
    );
    event ChainlinkRandomnessRequested(uint256 indexed requestId, address indexed requester);
    event ChainlinkRandomnessFulfilled(
        uint256 indexed requestId, address indexed requester, uint256 randomWord, bytes32 fulfillmentHash
    );

    constructor(
        address vrfCoordinator,
        uint256 initialSubscriptionId,
        bytes32 initialKeyHash,
        uint32 initialCallbackGasLimit,
        uint16 initialRequestConfirmations,
        bool initialNativePayment
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        _setVrfConfig(
            initialSubscriptionId,
            initialKeyHash,
            initialCallbackGasLimit,
            initialRequestConfirmations,
            initialNativePayment
        );
    }

    /// @notice Allows or blocks a game contract from billing this adapter's VRF subscription.
    function setConsumer(address consumer, bool allowed) external onlyOwner {
        if (consumer == address(0)) revert InvalidVRFConfig();
        allowedConsumers[consumer] = allowed;
        emit ConsumerAllowed(consumer, allowed);
    }

    /// @notice Updates VRF v2.5 subscription and request parameters.
    function setVrfConfig(
        uint256 newSubscriptionId,
        bytes32 newKeyHash,
        uint32 newCallbackGasLimit,
        uint16 newRequestConfirmations,
        bool newNativePayment
    ) external onlyOwner {
        _setVrfConfig(
            newSubscriptionId, newKeyHash, newCallbackGasLimit, newRequestConfirmations, newNativePayment
        );
    }

    /// @inheritdoc IRandomnessCoordinator
    function requestRandomness() external override returns (uint256 requestId) {
        if (!allowedConsumers[msg.sender]) revert UnauthorizedConsumer();

        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({ nativePayment: nativePayment })
                )
            })
        );

        requests[requestId] =
            Request({ requester: msg.sender, fulfilled: false, randomWord: 0, fulfillmentHash: bytes32(0) });
        emit ChainlinkRandomnessRequested(requestId, msg.sender);
    }

    /// @notice Receives verified VRF output from the Chainlink coordinator and forwards it to the game.
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        Request storage request = requests[requestId];
        if (request.requester == address(0)) revert InvalidRequest();
        if (request.fulfilled) revert RequestAlreadyFulfilled();

        uint256 randomWord = randomWords[0];
        bytes32 fulfillmentHash = keccak256(
            abi.encodePacked(
                "CHAINLINK_VRF_V2_5_FULFILLMENT",
                block.chainid,
                address(s_vrfCoordinator),
                address(this),
                requestId,
                randomWord
            )
        );

        request.fulfilled = true;
        request.randomWord = randomWord;
        request.fulfillmentHash = fulfillmentHash;

        IRandomnessConsumer(request.requester).rawFulfillRandomness(requestId, randomWord, fulfillmentHash);

        emit ChainlinkRandomnessFulfilled(requestId, request.requester, randomWord, fulfillmentHash);
    }

    function _setVrfConfig(
        uint256 newSubscriptionId,
        bytes32 newKeyHash,
        uint32 newCallbackGasLimit,
        uint16 newRequestConfirmations,
        bool newNativePayment
    ) internal {
        if (newSubscriptionId == 0 || newKeyHash == bytes32(0) || newCallbackGasLimit == 0) {
            revert InvalidVRFConfig();
        }
        subscriptionId = newSubscriptionId;
        keyHash = newKeyHash;
        callbackGasLimit = newCallbackGasLimit;
        requestConfirmations = newRequestConfirmations;
        nativePayment = newNativePayment;
        emit VRFConfigUpdated(
            newSubscriptionId, newKeyHash, newCallbackGasLimit, newRequestConfirmations, newNativePayment
        );
    }
}
