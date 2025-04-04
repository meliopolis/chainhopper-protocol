// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Settler} from "../../src/base/Settler.sol";
import {UniswapV3Settler} from "../../src/base/UniswapV3Settler.sol";

contract MockUniswapV3Settler is UniswapV3Settler {
    constructor(address initialOwner, address positionManager, address universalRouter, address permit2)
        Settler(initialOwner)
        UniswapV3Settler(positionManager, universalRouter, permit2)
    {}

    // add this to be excluded from coverage report
    function test() public {}
}
