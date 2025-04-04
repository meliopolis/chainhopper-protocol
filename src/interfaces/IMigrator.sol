// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MigrationId} from "../types/MigrationId.sol";

interface IMigrator {
    error MissingTokenRoutes();
    error TooManyTokenRoutes();
    error TokenAndRouteMismatch(address token);
    error TokensAndRoutesMismatch(address token0, address token1);
    error AmountTooLow(uint256 amount, uint256 amountMin);
    error ChainSettlerNotSupported(uint32 chainId, address settler);

    event Migration(
        MigrationId indexed migrationId,
        uint256 indexed positionId,
        address indexed token,
        address sender,
        uint256 amount
    );

    struct TokenRoute {
        address token;
        uint256 amountOutMin;
        bytes route;
    }

    struct MigrationParams {
        uint32 chainId;
        address settler;
        TokenRoute[] tokenRoutes;
        bytes settlementParams;
    }
}
