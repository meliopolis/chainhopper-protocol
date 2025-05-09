// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor(string memory name, string memory symbol, address initialHolder, uint256 initialSupply)
        ERC20(name, symbol)
    {
        _mint(initialHolder, initialSupply);
    }

    // Add this function to allow minting for testing purposes
    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }
}
