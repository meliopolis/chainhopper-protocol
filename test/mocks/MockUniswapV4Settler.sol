// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Settler} from "../../src/base/Settler.sol";
import {UniswapV4Settler} from "../../src/base/UniswapV4Settler.sol";

contract MockUniswapV4Settler is UniswapV4Settler {
    constructor(address initialOwner, address positionManager, address universalRouter, address permit2, address weth)
        Settler(initialOwner)
        UniswapV4Settler(positionManager, universalRouter, permit2, weth)
    {}

    // add this to be excluded from coverage report
    function test() public {}
}
