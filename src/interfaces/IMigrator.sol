// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MigrationId} from "../types/MigrationId.sol";

interface IMigrator {
    error MissingTokenRoutes();
    error TooManyTokenRoutes();
    error CannotBridgeToken(address token);
    error CannotBridgeTokens(address token0, address token1);
    error CannotBridgeAmount(uint256 amount, uint256 amountMin);

    event Migration(
        MigrationId indexed migrationId,
        uint256 indexed positionId,
        address indexed token,
        address sender,
        uint256 amount
    );

    struct TokenRoute {
        address token;
        uint256 amountMin;
        bytes route;
    }

    struct MigrationParams {
        uint32 chainId;
        address settler;
        TokenRoute[] tokenRoutes;
        bytes settlementParams;
    }
}
