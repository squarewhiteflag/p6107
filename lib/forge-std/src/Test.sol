// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface Vm {
    function deal(address who, uint256 newBalance) external;
    function prank(address msgSender) external;
    function startPrank(address msgSender) external;
    function stopPrank() external;
    function warp(uint256 newTimestamp) external;
    function expectRevert(bytes4 revertData) external;
    function expectRevert(bytes calldata revertData) external;
}

abstract contract Test {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertTrue(bool condition) internal pure {
        require(condition, "assertTrue failed");
    }

    function assertFalse(bool condition) internal pure {
        require(!condition, "assertFalse failed");
    }

    function assertEq(uint256 actual, uint256 expected) internal pure {
        require(actual == expected, "assertEq(uint256) failed");
    }

    function assertEq(address actual, address expected) internal pure {
        require(actual == expected, "assertEq(address) failed");
    }

    function assertEq(bytes32 actual, bytes32 expected) internal pure {
        require(actual == expected, "assertEq(bytes32) failed");
    }

    function assertGt(uint256 actual, uint256 floor) internal pure {
        require(actual > floor, "assertGt(uint256) failed");
    }

    function assertGe(uint256 actual, uint256 floor) internal pure {
        require(actual >= floor, "assertGe(uint256) failed");
    }
}
