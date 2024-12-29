// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.28;

import {AcrossV3Migrator} from "./base/AcrossV3Migrator.sol";
import {IAcrossV3SpokePool} from "./interfaces/external/IAcrossV3.sol";
import {ISwapRouter} from "./interfaces/external/IUniswapV3.sol";
import {IV3Settler} from "./interfaces/IV3Settler.sol";
import {IV3V3Migrator} from "./interfaces/IV3V3Migrator.sol";
import {AcrossV3Library} from "./libraries/AcrossV3Library.sol";
import {UniswapV3Library} from "./libraries/UniswapV3Library.sol";

contract SingleTokenV3V3Migrator is IV3V3Migrator, AcrossV3Migrator {
    error DestinationChainSettlerNotFound();
    error InvalidBaseToken();

    using UniswapV3Library for ISwapRouter;
    using AcrossV3Library for IAcrossV3SpokePool;

    ISwapRouter private immutable swapRouter;

    constructor(address _positionManager, address _spokePool, address _swapRouter)
        AcrossV3Migrator(_positionManager, _spokePool)
    {
        swapRouter = ISwapRouter(_swapRouter);
    }

    function _migrate(
        address sender,
        address token0,
        address token1,
        uint24 fee,
        uint256,
        uint256 amount0,
        uint256 amount1,
        bytes memory data
    ) internal override {
        MigrationParams memory params = abi.decode(data, (MigrationParams));
        require(chainSettlers[params.destinationChainId] != address(0), DestinationChainSettlerNotFound());

        // sort tokens and amounts
        (token0, token1, amount0, amount1) =
            token0 == params.baseToken ? (token0, token1, amount0, amount1) : (token1, token0, amount1, amount0);
        require(token0 == params.baseToken, InvalidBaseToken());

        // swap all token1 for token0
        if (amount1 > 0) {
            amount0 += swapRouter.swap(token1, token0, fee, amount1, type(uint160).max);
        }

        // initiate migration
        if (amount0 > 0) {
            spokePool.migrate(
                sender,
                params.destinationChainId,
                chainSettlers[params.destinationChainId],
                token0, // trusting filler to specify destination token, which should be params.token0
                amount0,
                params.minOutputAmount0,
                params.fillDeadlineOffset,
                abi.encode(
                    IV3Settler.SettlementParams({
                        token0: params.token0,
                        token1: params.token1,
                        fee: params.fee,
                        tickLower: params.tickLower,
                        tickUpper: params.tickUpper,
                        recipient: params.recipient,
                        counterpartKey: bytes32(0)
                    })
                )
            );
        }
    }
}
