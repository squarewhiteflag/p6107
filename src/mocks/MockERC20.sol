// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Mintable ERC-20 for local demos and tests.
contract MockERC20 is ERC20 {
    uint8 private immutable _demoDecimals;

    constructor(string memory tokenName, string memory tokenSymbol, uint8 tokenDecimals)
        ERC20(tokenName, tokenSymbol)
    {
        _demoDecimals = tokenDecimals;
    }

    /// @inheritdoc ERC20
    function decimals() public view override returns (uint8) {
        return _demoDecimals;
    }

    /// @notice Mints demo tokens. In production this contract is replaced by a real ERC-20.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
