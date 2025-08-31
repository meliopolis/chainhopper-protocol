// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Settler} from "../../src/base/Settler.sol";
import {AerodromeSettler} from "../../src/base/AerodromeSettler.sol";

contract MockAerodromeSettler is AerodromeSettler {
    constructor(address initialOwner, address positionManager, address universalRouter, address permit2)
        Settler(initialOwner)
        AerodromeSettler(positionManager, universalRouter, permit2)
    {}

    function mintPosition(address token, uint256 amount, address recipient, bytes memory data)
        external
        returns (uint256)
    {
        return _mintPosition(token, amount, recipient, data);
    }

    function mintPosition(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        address recipient,
        bytes memory data
    ) external returns (uint256) {
        return _mintPosition(tokenA, tokenB, amountA, amountB, recipient, data);
    }

    // add this to be excluded from coverage report
    function test() public {}
}
