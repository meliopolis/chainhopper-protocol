// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable2Step, Ownable} from "@openzeppelin/access/Ownable2Step.sol";
import {IMigrator} from "../interfaces/IMigrator.sol";
import {MigrationId, MigrationIdLibrary} from "../types/MigrationId.sol";
import {MigrationModes} from "../types/MigrationMode.sol";

abstract contract Migrator is IMigrator, Ownable2Step {
    error ParamsLengthMismatch();

    event ChainSettlerUpdated(uint32 indexed chainId, address indexed settler, bool value);

    uint40 public lastNounce;
    mapping(uint32 => mapping(address => bool)) public chainSettlers;

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setChainSettlers(uint32[] calldata chainIds, address[] calldata settlers, bool[] calldata values)
        external
        onlyOwner
    {
        if (chainIds.length != values.length || settlers.length != values.length) revert ParamsLengthMismatch();

        for (uint256 i = 0; i < values.length; i++) {
            chainSettlers[chainIds[i]][settlers[i]] = values[i];
            emit ChainSettlerUpdated(chainIds[i], settlers[i], values[i]);
        }
    }

    function _migrate(address sender, uint256 positionId, bytes memory data) internal virtual {
        MigrationParams memory params = abi.decode(data, (MigrationParams));
        if (!chainSettlers[params.chainId][params.settler]) revert ChainSettlerNotFound(params.chainId, params.settler);

        if (params.tokenRoutes.length == 0) {
            revert TokenRoutesMissing();
        } else if (params.tokenRoutes.length == 1) {
            TokenRoute memory tokenRoute = params.tokenRoutes[0];

            uint256 amount;
            {
                // liquidate the position
                (address token0, address token1, uint256 amount0, uint256 amount1, bytes memory poolInfo) =
                    _liquidate(positionId, params.amount0Min, params.amount1Min);


                if (token0 != tokenRoute.token && token1 != tokenRoute.token) revert TokensNotRouted(token0, token1);

                // calculate amount
                amount = token0 == tokenRoute.token
                    ? amount0 + (amount1 > 0 ? _swap(poolInfo, false, amount1, params.amountSwapOutMin) : 0)
                    : amount1 + (amount0 > 0 ? _swap(poolInfo, true, amount0, params.amountSwapOutMin) : 0);
                if (amount == 0) revert TokenAmountMissing(tokenRoute.token);
            }

            // generate migration id and data (reusing the data variable)
            MigrationId migrationId =
                MigrationIdLibrary.from(uint32(block.chainid), address(this), MigrationModes.SINGLE, ++lastNounce);
            data = abi.encode(migrationId, params.settlementParams);

            // bridge token
            _bridge(sender, params.chainId, params.settler, tokenRoute.token, amount, tokenRoute.route, data);

            emit Migration(migrationId, positionId, tokenRoute.token, sender, amount);
        } else if (params.tokenRoutes.length == 2) {
            TokenRoute memory tokenRoute0 = params.tokenRoutes[0];
            TokenRoute memory tokenRoute1 = params.tokenRoutes[1];

            uint256 amount0;
            uint256 amount1;
            {
                // liquidate the position
                address token0;
                address token1;
                (token0, token1, amount0, amount1,) = _liquidate(positionId, params.amount0Min, params.amount1Min);

                if (token0 == tokenRoute1.token && token1 == tokenRoute0.token) {
                    // flip amounts to match token routes
                    (amount0, amount1) = (amount1, amount0);
                } else if (token0 != tokenRoute0.token) {
                    revert TokenNotRouted(token0);
                } else if (token1 != tokenRoute1.token) {
                    revert TokenNotRouted(token1);
                }

                if (amount0 == 0) revert TokenAmountMissing(tokenRoute0.token);
                if (amount1 == 0) revert TokenAmountMissing(tokenRoute1.token);
            }

            // generate migration id and data (reusing the data variable)
            MigrationId migrationId =
                MigrationIdLibrary.from(uint32(block.chainid), address(this), MigrationModes.DUAL, ++lastNounce);
            data = abi.encode(migrationId, params.settlementParams);

            // bridge  tokens
            _bridge(sender, params.chainId, params.settler, tokenRoute0.token, amount0, tokenRoute0.route, data);
            _bridge(sender, params.chainId, params.settler, tokenRoute1.token, amount1, tokenRoute1.route, data);

            emit Migration(migrationId, positionId, tokenRoute0.token, sender, amount0);
            emit Migration(migrationId, positionId, tokenRoute1.token, sender, amount1);
        } else {
            revert TokenRoutesTooMany();
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

    function _liquidate(uint256 positionId, uint256 amount0Min, uint256 amount1Min)
        internal
        virtual
        returns (address token0, address token1, uint256 amount0, uint256 amount1, bytes memory poolInfo);

    function _swap(bytes memory poolInfo, bool zeroForOne, uint256 amountIn, uint256 amountOutMin)
        internal
        virtual
        returns (uint256 amountOut);
}
