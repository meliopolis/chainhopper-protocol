// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {AcrossMigrator} from "./base/AcrossMigrator.sol";
import {IAcrossV3SpokePool} from "./interfaces/external/IAcrossV3.sol";
import {IUniswapV3PositionManager} from "./interfaces/external/IUniswapV3.sol";
import {UniswapV3Library} from "./libraries/UniswapV3Library.sol";
import {AcrossV3Library} from "./libraries/AcrossV3Library.sol";
import {ISwapRouter} from "./interfaces/external/IUniswapV3.sol";
import {IAcrossMigrator} from "./interfaces/IAcrossMigrator.sol";
import {IV3Settler} from "./interfaces/IV3Settler.sol";

contract AcrossV3Migrator is IAcrossMigrator, AcrossMigrator {
    using UniswapV3Library for IUniswapV3PositionManager;
    using AcrossV3Library for IAcrossV3SpokePool;
    using UniswapV3Library for ISwapRouter;

    ISwapRouter public immutable swapRouter;

    /**
     *
     *  Functions  *
     *
     */
    constructor(address _nonfungiblePositionManager, address _spokePool, address _swapRouter)
        AcrossMigrator(_nonfungiblePositionManager, _spokePool)
    {
        swapRouter = ISwapRouter(_swapRouter);
    }

    function _migrate(address from, uint256 tokenId, bytes memory data) internal override {
        AcrossMigrationParams memory migrationParams = abi.decode(data, (AcrossMigrationParams));
        if (!chainSettlers[migrationParams.baseParams.destinationChainId][migrationParams.baseParams.recipient])
            revert DestinationChainSettlerNotFound();

        // determine number of routes to migrate
        uint256 numRoutes = migrationParams.acrossRoutes.length;

        if (numRoutes == 0) {
            revert NoAcrossRoutesFound();
        } else if (numRoutes == 1) {
            // singleToken path
            // liquidate position
            (address token0, address token1, uint24 feeTier, uint256 amount0, uint256 amount1) =
                positionManager.liquidatePosition(tokenId, address(this));

            // get the amount of input token to swap
            address tokenInForSwap = address(0);
            uint256 amountInForSwap = 0;
            uint256 amountOutputAlreadyAvailable = 0;

            AcrossRoute memory route = migrationParams.acrossRoutes[0];

            // confirm that at least one of the tokens is the route input token
            if (token0 != route.inputToken && token1 != route.inputToken) revert RouteInputTokenNotFound(0);

            // determine which token to swap
            if (token0 == route.inputToken && amount1 > 0) {
                tokenInForSwap = token1;
                amountInForSwap = amount1;
                amountOutputAlreadyAvailable = amount0;
            } else if (token1 == route.inputToken && amount0 > 0) {
                tokenInForSwap = token0;
                amountInForSwap = amount0;
                amountOutputAlreadyAvailable = amount1;
            }

            uint256 amountOut = 0;
            if (amountInForSwap > 0) {
                amountOut = swapRouter.swap(tokenInForSwap, route.inputToken, feeTier, amountInForSwap, 0);
            }
            uint256 amountInForBridge = amountOut + amountOutputAlreadyAvailable;
            spokePool.bridge(
                from,
                migrationParams.baseParams.destinationChainId,
                migrationParams.baseParams.recipient,
                route.inputToken,
                amountInForBridge,
                route.outputToken,
                amountInForBridge - route.maxFees,
                route.quoteTimestamp,
                uint32(block.timestamp) + route.fillDeadlineOffset,
                route.exclusiveRelayer,
                route.exclusivityDeadline,
                abi.encode(bytes32(0), migrationParams.baseParams.settlementParams)
            );
            emit PositionSent(
                tokenId,
                migrationParams.baseParams.destinationChainId,
                migrationParams.baseParams.recipient,
                migrationParams.baseParams.settlementParams
            );
        } else if (numRoutes == 2) {
            // dualToken path
            AcrossRoute memory route0 = migrationParams.acrossRoutes[0];
            AcrossRoute memory route1 = migrationParams.acrossRoutes[1];

            // liquidate position
            (address token0, address token1,, uint256 amount0, uint256 amount1) =
                positionManager.liquidatePosition(tokenId, address(this));


            if (amount0 == 0 || amount1 == 0) revert UnusedExtraRoute();

            // confirm that both tokens are the route input tokens
            if (token0 != route0.inputToken) revert RouteInputTokenNotFound(0);
            if (token1 != route1.inputToken) revert RouteInputTokenNotFound(1);

            // prepare settlement message
            bytes32 migrationId = keccak256(
                abi.encode(
                    block.chainid,
                    address(positionManager),
                    tokenId,
                    address(this),
                    migrationParams.baseParams.destinationChainId,
                    migrationParams.baseParams.recipient,
                    ++_migrationCounter
                )
            );

            // bridge both tokens
            spokePool.bridge(
                from,
                migrationParams.baseParams.destinationChainId,
                migrationParams.baseParams.recipient,
                route0.inputToken,
                amount0,
                route0.outputToken,
                amount0 - route0.maxFees,
                route0.quoteTimestamp,
                uint32(block.timestamp) + route0.fillDeadlineOffset,
                route0.exclusiveRelayer,
                route0.exclusivityDeadline,
                abi.encode(migrationId, migrationParams.baseParams.settlementParams)
            );
            spokePool.bridge(
                from,
                migrationParams.baseParams.destinationChainId,
                migrationParams.baseParams.recipient,
                route1.inputToken,
                amount1,
                route1.outputToken,
                amount1 - route1.maxFees,
                route1.quoteTimestamp,
                uint32(block.timestamp) + route1.fillDeadlineOffset,
                route1.exclusiveRelayer,
                route1.exclusivityDeadline,
                abi.encode(migrationId, migrationParams.baseParams.settlementParams)
            );
            emit PositionSent(
                tokenId,
                migrationParams.baseParams.destinationChainId,
                migrationParams.baseParams.recipient,
                abi.encode(migrationId, migrationParams.baseParams.settlementParams)
            );
        } else {
            revert TooManyAcrossRoutes();
        }
    }
}
