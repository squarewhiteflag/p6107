// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface Vm {
    function startBroadcast(uint256 privateKey) external;
    function stopBroadcast() external;
    function envOr(string calldata name, uint256 defaultValue) external returns (uint256);
    function addr(uint256 privateKey) external returns (address);
}

abstract contract Script {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
}
