// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MigrationMode} from "../types/MigrationMode.sol";

/// @title IMigrator
/// @notice Interface for the Migrator contract (abstract)
interface IMigrator {
    /// @notice Error thrown when a token route is missing
    error MissingTokenRoutes();
    /// @notice Error thrown when too many token routes are provided
    error TooManyTokenRoutes();
    /// @notice Error thrown when a token and route mismatch
    error TokenAndRouteMismatch(address token);
    /// @notice Error thrown when multiple tokens and routes mismatch
    error TokensAndRoutesMismatch(address token0, address token1);
    /// @notice Error thrown when an amount is too low
    error AmountTooLow(uint256 amount, uint256 amountMin);

    /// @notice Event emitted when a migration is started
    event MigrationStarted(
        bytes32 indexed migrationId,
        uint256 indexed positionId,
        uint256 indexed chainId,
        address settler,
        MigrationMode mode,
        address sender,
        address token,
        uint256 amount
    );

    /// @notice Struct for a token route
    struct TokenRoute {
        address token;
        uint256 amountOutMin;
        bytes route;
    }

    /// @notice Struct for migration parameters
    struct MigrationParams {
        uint256 chainId;
        address settler;
        TokenRoute[] tokenRoutes;
        bytes settlementParams;
    }
}
