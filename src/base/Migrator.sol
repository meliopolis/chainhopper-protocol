// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable2Step, Ownable} from "@openzeppelin/access/Ownable2Step.sol";
import {IMigrator} from "../interfaces/IMigrator.sol";

abstract contract Migrator is IMigrator, Ownable2Step {
    uint256 private migrationCounter;
    mapping(uint32 => mapping(address => bool)) private chainSettlers;

    constructor() Ownable(msg.sender) {}

    function setChainSettler(uint32 chainId, address settler, bool supported) external onlyOwner {
        chainSettlers[chainId][settler] = supported;
    }

    function migrate(address sender, uint256 positionId, bytes memory data) external {
        MigrationParams memory params = abi.decode(data, (MigrationParams));
        if (!chainSettlers[params.destinationChainId][params.destinationSettler]) revert ChainSettlerNotSupported();

        // liquidate (implemented in child position manager contract) the position
        (address token0, address token1, uint256 amount0, uint256 amount1, bytes memory poolInfo) =
            _liquidate(positionId);

        if (amount0 == 0 && amount1 == 0) revert AmountsCannotAllBeZero();

        TokenRoute[] memory tokenRoutes = params.tokenRoutes;
        if (tokenRoutes.length == 0) {
            revert MissingTokenRoutes();
        } else if (tokenRoutes.length == 1) {
            if (token0 != tokenRoutes[0].token && token1 != tokenRoutes[0].token) revert TokensNotRouted();

            // amount to migrate, swap (implemented in child position manager contract) if necessary
            uint256 amount = token0 == tokenRoutes[0].token
                ? amount0 + (amount1 > 0 ? _swap(poolInfo, false, amount1, 0) : 0) // TODO: slippage control
                : amount1 + (amount0 > 0 ? _swap(poolInfo, true, amount0, 0) : 0); // TODO: slippage control

            // prepare migration message with empty migration id
            bytes memory message = abi.encode(bytes32(0), params.settlementParams);

            // migrate (implemented in child bridge contract) token
            _migrate(sender, params.destinationChainId, params.destinationSettler, tokenRoutes[0], amount, message);

            emit Migrated(
                bytes32(0), params.destinationChainId, params.destinationSettler, sender, tokenRoutes[0].token, amount
            );
        } else if (tokenRoutes.length == 2) {
            if (amount0 == 0) revert AmountCannotBeZero(token0);
            if (amount1 == 0) revert AmountCannotBeZero(token1);

            if (token0 == params.tokenRoutes[1].token && token1 == params.tokenRoutes[0].token) {
                // flip amounts to match token routes if necessary
                (amount0, amount1) = (amount1, amount0);
            } else if (token0 != params.tokenRoutes[0].token) {
                revert TokenNotRouted(token0);
            } else if (token1 != params.tokenRoutes[1].token) {
                revert TokenNotRouted(token1);
            }

            // prepare migration message with an unique migration id
            bytes32 migrationId = keccak256(abi.encodePacked(block.chainid, address(this), ++migrationCounter));
            bytes memory message = abi.encode(migrationId, params.settlementParams);

            // migrate (implemented in child bridge contract) tokens
            _migrate(sender, params.destinationChainId, params.destinationSettler, tokenRoutes[0], amount0, message);
            _migrate(sender, params.destinationChainId, params.destinationSettler, tokenRoutes[1], amount1, message);

            emit Migrated(
                migrationId, params.destinationChainId, params.destinationSettler, sender, tokenRoutes[0].token, amount0
            );
            emit Migrated(
                migrationId, params.destinationChainId, params.destinationSettler, sender, tokenRoutes[1].token, amount1
            );
        } else {
            revert TooManyTokenRoutes();
        }
    }

    function _liquidate(uint256 positionId)
        internal
        virtual
        returns (address token0, address token1, uint256 amount0, uint256 amount1, bytes memory poolInfo);

    function _swap(bytes memory poolInfo, bool zeroForOne, uint256 amountIn, uint256 amountOutMin)
        internal
        virtual
        returns (uint256 amountOut);

    function _migrate(
        address sender,
        uint32 destinationChainId,
        address destinationSettler,
        TokenRoute memory tokenRoute,
        uint256 amount,
        bytes memory message
    ) internal virtual;
}
