// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.28;

import {AcrossV3Migrator} from "./base/AcrossV3Migrator.sol";
import {IAcrossV3SpokePool} from "./interfaces/external/IAcrossV3.sol";
import {ISwapRouter} from "./interfaces/external/IUniswapV3.sol";
import {ISingleTokenV3Settler} from "./interfaces/ISingleTokenV3Settler.sol";
import {ISingleTokenV3V3Migrator} from "./interfaces/ISingleTokenV3V3Migrator.sol";
import {AcrossV3Library} from "./libraries/AcrossV3Library.sol";
import {UniswapV3Library} from "./libraries/UniswapV3Library.sol";

contract SingleTokenV3V3Migrator is ISingleTokenV3V3Migrator, AcrossV3Migrator {
    error DestinationChainSettlerNotFound();
    error InvalidOutputToken();

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
                params.minOutputAmount,
                params.fillDeadlineOffset,
                abi.encode(
                    ISingleTokenV3Settler.SettlementParams({
                        recipient: params.recipient,
                        token0: params.token0,
                        token1: params.token1,
                        fee: params.fee,
                        tickLower: params.tickLower,
                        tickUpper: params.tickUpper
                    })
                )
            );
        }
    }
}
