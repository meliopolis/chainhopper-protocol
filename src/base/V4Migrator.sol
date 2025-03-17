// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IUniversalRouter} from "@uniswap-universal-router/interfaces/IUniversalRouter.sol";
import {Migrator} from "./Migrator.sol";

abstract contract V4Migrator is Migrator {
    IUniversalRouter private immutable universalRouter; // TODO: move to library

    constructor(address _universalRouter) {
        universalRouter = IUniversalRouter(_universalRouter);
    }

    function _liquidate(uint256 positionId)
        internal
        override
        returns (address token0, address token1, uint256 amount0, uint256 amount1, bytes memory poolInfo)
    {
        // TODO:
    }

    function _swap(bytes memory poolInfo, bool zeroForOne, uint256 amountIn, uint256 amountOutMin)
        internal
        override
        returns (uint256 amountOut)
    {
        // TODO:
    }
}
