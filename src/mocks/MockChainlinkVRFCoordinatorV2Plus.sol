// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { VRFV2PlusClient } from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

error ChainlinkRequestNotFound();
error ChainlinkRequestAlreadyFulfilled();

interface IRawVRFConsumerV2Plus {
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external;
}

/// @notice Minimal Chainlink VRF v2.5 coordinator shape for adapter integration tests.
contract MockChainlinkVRFCoordinatorV2Plus {
    struct Request {
        address requester;
        bool fulfilled;
    }

    uint256 public nextRequestId = 1;
    mapping(uint256 => Request) public requests;

    event RandomWordsRequested(uint256 indexed requestId, address indexed requester);
    event RandomWordsFulfilled(uint256 indexed requestId, uint256 randomWord);

    function requestRandomWords(VRFV2PlusClient.RandomWordsRequest calldata)
        external
        returns (uint256 requestId)
    {
        requestId = nextRequestId++;
        requests[requestId] = Request({ requester: msg.sender, fulfilled: false });
        emit RandomWordsRequested(requestId, msg.sender);
    }

    function fulfillRequestWithWord(uint256 requestId, uint256 randomWord) external {
        Request storage request = requests[requestId];
        if (request.requester == address(0)) revert ChainlinkRequestNotFound();
        if (request.fulfilled) revert ChainlinkRequestAlreadyFulfilled();

        request.fulfilled = true;
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = randomWord;
        IRawVRFConsumerV2Plus(request.requester).rawFulfillRandomWords(requestId, randomWords);
        emit RandomWordsFulfilled(requestId, randomWord);
    }
}
