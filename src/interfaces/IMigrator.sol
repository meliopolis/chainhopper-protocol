// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MigrationId} from "../types/MigrationId.sol";

interface IMigrator {
    error NotPositionManager();
    error ChainSettlerNotFound(uint32 chainId, address settler);
    error TokenRoutesMissing();
    error TokenRoutesTooMany();
    error TokenAmountInsufficient();
    error TokenAmountMissing(address token);
    error TokenNotRouted(address token);
    error TokensNotRouted(address token0, address token1);

    event Migration(
        MigrationId indexed migrationId,
        uint256 indexed positionId,
        address indexed token,
        address sender,
        uint256 amout
    );

    struct TokenRoute {
        address token;
        bytes route;
    }

    struct MigrationParams {
        uint32 chainId;
        address settler;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 amountSwapOutMin;
        TokenRoute[] tokenRoutes;
        bytes settlementParams;
    }
}
