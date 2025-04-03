// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IMigrator} from "../interfaces/IMigrator.sol";
import {MigrationId, MigrationIdLibrary} from "../types/MigrationId.sol";
import {MigrationModes} from "../types/MigrationMode.sol";

abstract contract Migrator is IMigrator {
    uint56 public migrationCounter;

    function _migrate(address sender, uint256 positionId, bytes memory data) internal {
        MigrationParams memory params = abi.decode(data, (MigrationParams));

        // liquidate the position
        (address token0, address token1, uint256 amount0, uint256 amount1, bytes memory poolInfo) =
            _liquidate(positionId);

        if (params.tokenRoutes.length == 0) {
            revert MissingTokenRoutes();
        } else if (params.tokenRoutes.length == 1) {
            TokenRoute memory tokenRoute = params.tokenRoutes[0];

            if (!_checkToken(token0, tokenRoute) && !_checkToken(token1, tokenRoute)) {
                revert CannotBridgeTokens(token0, token1);
            }

            // calculate amount, swap if needed
            uint256 amount = _checkToken(token0, tokenRoute)
                ? amount0 + (amount1 > 0 ? _swap(poolInfo, false, amount1) : 0)
                : amount1 + (amount0 > 0 ? _swap(poolInfo, true, amount0) : 0);
            if (!_checkAmount(amount, tokenRoute)) revert CannotBridgeAmount(amount, tokenRoute.amountOutMin);

            // generate migration id and data (reusing the data variable)
            MigrationId migrationId =
                MigrationIdLibrary.from(uint32(block.chainid), address(this), MigrationModes.SINGLE, ++migrationCounter);
            data = abi.encode(migrationId, params.settlementParams);

            // bridge token
            _bridge(sender, params.chainId, params.settler, tokenRoute.token, amount, tokenRoute.route, data);

            emit Migration(migrationId, positionId, tokenRoute.token, sender, amount);
        } else if (params.tokenRoutes.length == 2) {
            TokenRoute memory tokenRoute0 = params.tokenRoutes[0];
            TokenRoute memory tokenRoute1 = params.tokenRoutes[1];

            if (_checkToken(token0, tokenRoute1) && _checkToken(token1, tokenRoute0)) {
                // flip amounts to match token routes
                (amount0, amount1) = (amount1, amount0);
            } else if (!_checkToken(token0, tokenRoute0)) {
                revert CannotBridgeToken(token0);
            } else if (!_checkToken(token1, tokenRoute1)) {
                revert CannotBridgeToken(token1);
            }

            if (!_checkAmount(amount0, tokenRoute0)) revert CannotBridgeAmount(amount0, tokenRoute0.amountOutMin);
            if (!_checkAmount(amount1, tokenRoute1)) revert CannotBridgeAmount(amount1, tokenRoute1.amountOutMin);

            // generate migration id and data (reusing the data variable)
            MigrationId migrationId =
                MigrationIdLibrary.from(uint32(block.chainid), address(this), MigrationModes.DUAL, ++migrationCounter);
            data = abi.encode(migrationId, params.settlementParams);

            // bridge tokens
            _bridge(sender, params.chainId, params.settler, tokenRoute0.token, amount0, tokenRoute0.route, data);
            _bridge(sender, params.chainId, params.settler, tokenRoute1.token, amount1, tokenRoute1.route, data);

            emit Migration(migrationId, positionId, tokenRoute0.token, sender, amount0);
            emit Migration(migrationId, positionId, tokenRoute1.token, sender, amount1);
        } else {
            revert TooManyTokenRoutes();
        }
    }

    function _bridge(
        address sender,
        uint32 chainId,
        address settler,
        address token,
        uint256 amount,
        bytes memory route,
        bytes memory data
    ) internal virtual;

    function _liquidate(uint256 positionId)
        internal
        virtual
        returns (address token0, address token1, uint256 amount0, uint256 amount1, bytes memory poolInfo);

    function _swap(bytes memory poolInfo, bool zeroForOne, uint256 amountIn)
        internal
        virtual
        returns (uint256 amountOut);

    function _checkToken(address token, TokenRoute memory tokenRoute) internal view virtual returns (bool);

    function _checkAmount(uint256 amount, TokenRoute memory tokenRoute) internal view virtual returns (bool);
}
