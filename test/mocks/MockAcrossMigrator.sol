// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AcrossMigrator} from "../../src/base/AcrossMigrator.sol";
import {Migrator} from "../../src/base/Migrator.sol";

contract MockAcrossMigrator is AcrossMigrator {
    constructor(address initialOwner, address spokePool, address weth)
        Migrator(initialOwner)
        AcrossMigrator(spokePool, weth)
    {}

    function _liquidate(uint256 positionId)
        internal
        override
        returns (address token0, address token1, uint256 amount0, uint256 amount1, bytes memory poolInfo)
    {}

    function _swap(bytes memory poolInfo, bool zeroForOne, uint256 amountIn)
        internal
        override
        returns (uint256 amountOut)
    {}

    // add this to be excluded from coverage report
    function test() public {}
}
