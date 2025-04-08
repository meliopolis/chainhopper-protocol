// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IMigrator} from "../interfaces/IMigrator.sol";
import {MigrationId, MigrationIdLibrary} from "../types/MigrationId.sol";
import {MigrationModes} from "../types/MigrationMode.sol";
import {ChainSettlers} from "./ChainSettlers.sol";

/// @title Migrator
/// @notice Abstract contract for migrating positions between chains
abstract contract Migrator is IMigrator, ChainSettlers {
    uint56 public migrationCounter;

    /// @notice Constructor for the Migrator contract
    /// @param initialOwner The initial owner of the contract
    constructor(address initialOwner) ChainSettlers(initialOwner) {}

    /// @notice Internal function to migrate a position
    /// @param sender The sender of the migration
    /// @param positionId The id of the position
    /// @param data The data containing the migration parameters
    function _migrate(address sender, uint256 positionId, bytes memory data) internal virtual {
        MigrationParams memory params = abi.decode(data, (MigrationParams));
        if (!chainSettlers[params.chainId][params.settler]) {
            revert ChainSettlerNotSupported(params.chainId, params.settler);
        }

        // liquidate the position
        (address token0, address token1, uint256 amount0, uint256 amount1, bytes memory poolInfo) =
            _liquidate(positionId);

        if (params.tokenRoutes.length == 0) {
            revert MissingTokenRoutes();
        } else if (params.tokenRoutes.length == 1) {
            TokenRoute memory tokenRoute = params.tokenRoutes[0];

            if (!_matchTokenWithRoute(token0, tokenRoute) && token1 != tokenRoute.token) {
                revert TokensAndRoutesMismatch(token0, token1);
            }

            // calculate amount, swap if needed
            uint256 amount = _matchTokenWithRoute(token0, tokenRoute)
                ? amount0 + (amount1 > 0 ? _swap(poolInfo, false, amount1) : 0)
                : amount1 + (amount0 > 0 ? _swap(poolInfo, true, amount0) : 0);
            if (!_isAmountSufficient(amount, tokenRoute)) revert AmountTooLow(amount, tokenRoute.amountOutMin);

            // generate migration id and data (reusing the data variable)
            MigrationId migrationId =
                MigrationIdLibrary.from(uint32(block.chainid), address(this), MigrationModes.SINGLE, ++migrationCounter);
            data = abi.encode(migrationId, params.settlementParams);

            // bridge token
            _bridge(sender, params.chainId, params.settler, token0, amount, tokenRoute.token, tokenRoute.route, data);

            emit MigrationStarted(migrationId, positionId, tokenRoute.token, sender, amount);
        } else if (params.tokenRoutes.length == 2) {
            TokenRoute memory tokenRoute0 = params.tokenRoutes[0];
            TokenRoute memory tokenRoute1 = params.tokenRoutes[1];

            if (_matchTokenWithRoute(token0, tokenRoute1) && token1 == tokenRoute0.token) {
                // flip amounts to match token routes
                (amount0, amount1) = (amount1, amount0);
            } else if (!_matchTokenWithRoute(token0, tokenRoute0)) {
                revert TokenAndRouteMismatch(token0);
            } else if (token1 != tokenRoute1.token) {
                revert TokenAndRouteMismatch(token1);
            }

            if (!_isAmountSufficient(amount0, tokenRoute0)) revert AmountTooLow(amount0, tokenRoute0.amountOutMin);
            if (!_isAmountSufficient(amount1, tokenRoute1)) revert AmountTooLow(amount1, tokenRoute1.amountOutMin);

            // generate migration id and data (reusing the data variable)
            MigrationId migrationId =
                MigrationIdLibrary.from(uint32(block.chainid), address(this), MigrationModes.DUAL, ++migrationCounter);
            data = abi.encode(migrationId, params.settlementParams);

            // bridge tokens
            _bridge(sender, params.chainId, params.settler, token0, amount0, tokenRoute0.token, tokenRoute0.route, data);
            _bridge(sender, params.chainId, params.settler, token1, amount1, tokenRoute1.token, tokenRoute1.route, data);

            emit MigrationStarted(migrationId, positionId, tokenRoute0.token, sender, amount0);
            emit MigrationStarted(migrationId, positionId, tokenRoute1.token, sender, amount1);
        } else {
            revert TooManyTokenRoutes();
        }
    }

    /// @notice Internal function to bridge tokens
    /// @param sender The sender of the migration
    /// @param chainId The chain id
    /// @param settler The settler address
    /// @param token The token to bridge
    /// @param amount The amount to bridge
    function _bridge(
        address sender,
        uint32 chainId,
        address settler,
        address token,
        uint256 amount,
        address inputToken,
        bytes memory route,
        bytes memory data
    ) internal virtual;

    /// @notice Internal function to liquidate a position
    /// @param positionId The id of the position
    /// @return token0 The first token
    /// @return token1 The second token
    /// @return amount0 The amount of token0
    /// @return amount1 The amount of token1
    /// @return poolInfo The pool info
    function _liquidate(uint256 positionId)
        internal
        virtual
        returns (address token0, address token1, uint256 amount0, uint256 amount1, bytes memory poolInfo);

    /// @notice Internal function to swap tokens
    /// @param poolInfo The pool info
    /// @param zeroForOne The direction of the swap
    /// @param amountIn The amount to swap
    /// @return amountOut The amount of tokens received
    function _swap(bytes memory poolInfo, bool zeroForOne, uint256 amountIn)
        internal
        virtual
        returns (uint256 amountOut);

    /// @notice Internal function to match a token with a route
    /// @param token The token to match
    /// @param tokenRoute The route to match
    /// @return isMatch True if the token matches the route, false otherwise
    function _matchTokenWithRoute(address token, TokenRoute memory tokenRoute)
        internal
        virtual
        returns (bool isMatch);

    /// @notice Internal function to check if an amount more than the minimum amount specified in the route
    /// @param amount The amount to check
    /// @param tokenRoute The route to check
    /// @return isSufficient True if the amount is sufficient, false otherwise
    function _isAmountSufficient(uint256 amount, TokenRoute memory tokenRoute)
        internal
        virtual
        returns (bool isSufficient);
}
