// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {V3Migrator} from "../../src/base/V3Migrator.sol";

contract MockV3Migrator is V3Migrator {
    event NoOp();

    constructor(address positionManager, address universalRouter, address permit2)
        V3Migrator(positionManager, universalRouter, permit2)
    {}

    function liquidate(uint256 positionId) external returns (address, address, uint256, uint256, bytes memory) {
        return _liquidate(positionId);
    }

    function swap(bytes memory poolInfo, bool zeroForOne, uint256 amountIn, uint256 amountOutMin)
        external
        returns (uint256)
    {
        return _swap(poolInfo, zeroForOne, amountIn, amountOutMin);
    }

    function _bridge(address, uint32, address, TokenRoute memory, uint256, bytes memory) internal override {
        emit NoOp();
    }

    function _migrate(address sender, uint256 positionId, bytes memory data) internal override {
        emit NoOp();
    }

    // add this to be excluded from coverage report
    function test() public {}
}
