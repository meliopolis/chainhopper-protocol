// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IUniversalRouter} from "@uniswap-universal-router/interfaces/IUniversalRouter.sol";
// copied and modified from uniswap-v3-periphery, as the original had bad imports
import {INonfungiblePositionManager as IPositionManager} from "../interfaces/external/INonfungiblePositionManager.sol";
import {IV3Settler} from "../interfaces/IV3Settler.sol";
import {UniswapV3Library} from "../libraries/UniswapV3Library.sol";
import {Settler} from "./Settler.sol";

abstract contract V3Settler is IV3Settler, Settler {
    using UniswapV3Library for IPositionManager;

    IPositionManager private immutable positionManager;
    IUniversalRouter private immutable universalRouter; // TODO: move to library

    constructor(address _positionManager, address _universalRouter) {
        positionManager = IPositionManager(_positionManager);
        universalRouter = IUniversalRouter(_universalRouter);
    }

    function _settle(address token, uint256 amount, bytes memory message)
        internal
        override
        returns (uint256, address, address, uint256, uint256, uint256, uint256)
    {
        // TODO:
    }

    function _settle(address tokenA, address tokenB, uint256 amountA, uint256 amountB, bytes memory message)
        internal
        override
        returns (uint256, address, address, uint256, uint256, uint256, uint256)
    {
        SettlementParams memory params = abi.decode(message, (SettlementParams));
        if (tokenA != params.token0 && tokenA != params.token1) revert SettlementTokenNotUsed(tokenA);
        if (tokenB != params.token0 && tokenB != params.token1) revert SettlementTokenNotUsed(tokenB);

        (uint256 amount0, uint256 amount1) = tokenA == params.token0 ? (amountA, amountB) : (amountB, amountA);
        (uint256 positionId, uint256 amount0Used, uint256 amount1Used) = positionManager.mint(
            params.token0,
            params.token1,
            params.fee,
            params.tickLower,
            params.tickUpper,
            amount0,
            amount1,
            params.amount0Min,
            params.amount1Min,
            params.baseParams.recipient
        );

        uint256 amount0Refunded = amount0 - amount0Used;
        uint256 amount1Refunded = amount1 - amount1Used;
        if (amount0Refunded > 0) _transfer(params.token0, amount0Refunded, params.baseParams.recipient);
        if (amount1Refunded > 0) _transfer(params.token1, amount1Refunded, params.baseParams.recipient);

        return (positionId, params.token0, params.token1, amount0Used, amount1Used, amount0Refunded, amount1Refunded);
    }
}
