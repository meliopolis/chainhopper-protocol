// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Migrator} from "../../src/base/Migrator.sol";
import {V4Migrator} from "../../src/base/V4Migrator.sol";

contract MockV4Migrator is V4Migrator {
    event NoOp();

    constructor(address positionManager, address universalRouter, address permit2)
        V4Migrator(positionManager, universalRouter, permit2)
        Migrator(msg.sender)
    {}

    function liquidate(uint256 positionId, uint256 amount0Min, uint256 amount1Min)
        external
        returns (address, address, uint256, uint256, bytes memory)
    {
        return _liquidate(positionId, amount0Min, amount1Min);
    }

    function swap(bytes memory poolInfo, bool zeroForOne, uint256 amountIn, uint256 amountOutMin)
        external
        returns (uint256)
    {
        return _swap(poolInfo, zeroForOne, amountIn, amountOutMin);
    }

    function _bridge(address, uint32, address, address, uint256, bytes memory, bytes memory) internal override {
        emit NoOp();
    }

    function _migrate(address, uint256, bytes memory) internal override {
        emit NoOp();
    }

    // add this to be excluded from coverage report
    function test() public {}
}
