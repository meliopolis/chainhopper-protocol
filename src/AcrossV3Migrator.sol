// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {INonfungiblePositionManager} from "@uniswap-v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {ISwapRouter} from "@uniswap-v3-periphery/interfaces/ISwapRouter.sol";
import {V3SpokePoolInterface} from "@across/interfaces/V3SpokePoolInterface.sol";
import {AcrossMigrator} from "./base/AcrossMigrator.sol";
import {UniswapV3Library} from "./libraries/UniswapV3Library.sol";
import {AcrossV3Library} from "./libraries/AcrossV3Library.sol";
import {IAcrossMigrator} from "./interfaces/IAcrossMigrator.sol";
import {IV3Settler} from "./interfaces/IV3Settler.sol";

contract AcrossV3Migrator is IAcrossMigrator, AcrossMigrator {
    using UniswapV3Library for INonfungiblePositionManager;
    using AcrossV3Library for V3SpokePoolInterface;
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
        if (!chainSettlers[migrationParams.baseParams.destinationChainId][migrationParams.baseParams.recipient]) {
            revert DestinationChainSettlerNotFound();
        }

        // determine number of routes sent for migration
        uint256 numRoutes = migrationParams.acrossRoutes.length;

        if (numRoutes == 0) {
            revert NoAcrossRoutesFound();
        } else if (numRoutes == 1) {
            // singleToken path
            AcrossRoute memory route = migrationParams.acrossRoutes[0];

            uint256 amountInForBridge;
            {
                // liquidate position
                (address token0, address token1, uint24 feeTier, uint256 amount0, uint256 amount1) =
                    positionManager.liquidatePosition(tokenId, address(this));

                // get the amount of input token to swap
                address tokenInForSwap = address(0);
                uint256 amountInForSwap = 0;
                uint256 amountOutputAlreadyAvailable = 0;

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
                amountInForBridge = amountOut + amountOutputAlreadyAvailable;
            }

            spokePool.bridge(
                from,
                migrationParams.baseParams.destinationChainId,
                migrationParams.baseParams.recipient,
                route,
                amountInForBridge,
                amountInForBridge - route.maxFees,
                abi.encode(bytes32(0), migrationParams.baseParams.settlementParams)
            );
            emit PositionSent(
                tokenId,
                migrationParams.baseParams.destinationChainId,
                migrationParams.baseParams.recipient,
                abi.encode(bytes32(0), migrationParams.baseParams.settlementParams)
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
            bytes32 migrationId = _generateMigrationId(tokenId, migrationParams.baseParams);
            bytes memory message = abi.encode(migrationId, migrationParams.baseParams.settlementParams);
            // bridge both tokens
            spokePool.bridge(
                from,
                migrationParams.baseParams.destinationChainId,
                migrationParams.baseParams.recipient,
                route0,
                amount0,
                amount0 - route0.maxFees,
                message
            );
            spokePool.bridge(
                from,
                migrationParams.baseParams.destinationChainId,
                migrationParams.baseParams.recipient,
                route1,
                amount1,
                amount1 - route1.maxFees,
                message
            );
            emit PositionSent(
                tokenId, migrationParams.baseParams.destinationChainId, migrationParams.baseParams.recipient, message
            );
        } else {
            revert TooManyAcrossRoutes();
        }
    }

    function _generateMigrationId(uint256 tokenId, BaseMigrationParams memory baseParams) internal returns (bytes32) {
        return keccak256(
            abi.encode(
                block.chainid,
                address(positionManager),
                tokenId,
                address(this),
                baseParams.destinationChainId,
                baseParams.recipient,
                ++_migrationCounter
            )
        );
        // should settle params be included here?
    }
}
