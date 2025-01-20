// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.28;

import {AcrossV3Migrator} from "./base/AcrossV3Migrator.sol";
import {IAcrossV3SpokePool} from "./interfaces/external/IAcrossV3.sol";
import {IUniswapV3PositionManager} from "./interfaces/external/IUniswapV3.sol";
import {IDualTokensV3Settler} from "./interfaces/IDualTokensV3Settler.sol";
import {IDualTokensV3V3Migrator} from "./interfaces/IDualTokensV3V3Migrator.sol";
import {AcrossV3Library} from "./libraries/AcrossV3Library.sol";
import {UniswapV3Library} from "./libraries/UniswapV3Library.sol";

contract DualTokensV3V3Migrator is IDualTokensV3V3Migrator, AcrossV3Migrator {
    error DestinationChainSettlerNotFound();

    using AcrossV3Library for IAcrossV3SpokePool;
    using UniswapV3Library for IUniswapV3PositionManager;

    IUniswapV3PositionManager internal immutable positionManager;

    constructor(address _positionManager, address _spokePool) AcrossV3Migrator(_positionManager, _spokePool) {
        positionManager = IUniswapV3PositionManager(_positionManager);
    }

    function _migrate(address sender, uint256 positionId, bytes memory data) internal override {
        MigrationParams memory params = abi.decode(data, (MigrationParams));
        require(chainSettlers[params.destinationChainId] != address(0), DestinationChainSettlerNotFound());

        // liquidate position
        (address token0, address token1,, uint256 amount0, uint256 amount1) =
            positionManager.liquidatePosition(positionId, address(this));

        // prepare settlement message
        bytes memory message = abi.encode(
            IDualTokensV3Settler.SettlementParams({
                counterpartKey: amount0 > 0 && amount1 > 0
                    ? keccak256(abi.encode(block.chainid, address(positionManager), positionId))
                    : bytes32(0),
                recipient: params.recipient,
                token0: params.token0,
                token1: params.token1,
                fee: params.fee,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper
            })
        );

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
                message
            );
        }
        if (amount1 > 0) {
            spokePool.migrate(
                sender,
                params.destinationChainId,
                chainSettlers[params.destinationChainId],
                token1, // trusting filler to specify destination token, which should be params.token1
                amount1,
                params.minOutputAmount1,
                params.fillDeadlineOffset,
                message
            );
        }
    }
}
