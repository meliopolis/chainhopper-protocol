// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IMigrator} from "../interfaces/IMigrator.sol";
import {MigrationId, MigrationIdLibrary} from "../types/MigrationId.sol";
import {MigrationModes} from "../types/MigrationMode.sol";
import {ChainSettlers} from "./ChainSettlers.sol";

abstract contract Migrator is IMigrator, ChainSettlers {
    uint56 public migrationCounter;

    constructor(address initialOwner) ChainSettlers(initialOwner) {}

    function _migrate(address sender, uint256 positionId, bytes memory data) internal {
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

            emit Migration(migrationId, positionId, tokenRoute.token, sender, amount);
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
        address inputToken,
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

    function _matchTokenWithRoute(address token, TokenRoute memory tokenRoute) internal virtual returns (bool);

    function _isAmountSufficient(uint256 amount, TokenRoute memory tokenRoute) internal virtual returns (bool);
}
