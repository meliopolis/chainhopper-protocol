// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable2Step, Ownable} from "@openzeppelin/access/Ownable2Step.sol";
import {IERC721Receiver} from "@openzeppelin/token/ERC721/IERC721Receiver.sol";
import {IMigrator} from "../interfaces/IMigrator.sol";

abstract contract Migrator is IMigrator, IERC721Receiver, Ownable2Step {
    uint256 private migrationCounter;
    address internal immutable positionManager;
    mapping(uint32 => mapping(address => bool)) internal chainSettlers;

    function setChainSettler(uint32 chainId, address settler, bool supported) external onlyOwner {
        chainSettlers[chainId][settler] = supported;
    }

    constructor(address _positionManager) Ownable(msg.sender) {
        positionManager = _positionManager;
    }

    function onERC721Received(address, address from, uint256 tokenId, bytes memory data) external returns (bytes4) {
        if (msg.sender != positionManager) revert NotPositionManager();

        MigrationParams memory params = abi.decode(data, (MigrationParams));
        if (!chainSettlers[params.destinationChainId][params.destinationSettler]) revert ChainSettlerNotSupported();

        TokenRoute[] memory tokenRoutes = params.tokenRoutes;
        if (tokenRoutes.length == 0 || tokenRoutes.length > 2) revert MisconfigedTokenRoutes();

        (address token0, address token1, uint256 amount0, uint256 amount1, bytes memory poolInfo) = _liquidate(tokenId);
        if (amount0 == 0 && amount1 == 0) revert AmountsCannotAllBeZero();

        if (tokenRoutes.length == 1) {
            if (token0 != tokenRoutes[0].token && token1 != tokenRoutes[0].token) revert TokenNotRouted();

            uint256 amount = token0 == tokenRoutes[0].token
                ? amount0 + (amount1 > 0 ? _swap(poolInfo, false, amount1, 0) : 0) // TODO: slippage control
                : amount1 + (amount0 > 0 ? _swap(poolInfo, true, amount0, 0) : 0); // TODO: slippage control
            bytes memory message = abi.encode(bytes32(0), params.settlementParams);

            _migrate(from, params.destinationChainId, params.destinationSettler, tokenRoutes[0], amount, message);

            emit Migrated(
                bytes32(0), params.destinationChainId, params.destinationSettler, from, tokenRoutes[0].token, amount
            );
        } else {
            if (amount0 == 0 || amount1 == 0) revert MisconfigedTokenRoutes();
            if (token0 == params.tokenRoutes[1].token && token1 == params.tokenRoutes[0].token) {
                (amount0, amount1) = (amount1, amount0);
            } else if (token0 != params.tokenRoutes[0].token || token1 != params.tokenRoutes[1].token) {
                revert TokenNotRouted();
            }

            bytes32 migrationId = keccak256(abi.encodePacked(block.chainid, address(this), ++migrationCounter));
            bytes memory message = abi.encode(migrationId, params.settlementParams);

            _migrate(from, params.destinationChainId, params.destinationSettler, tokenRoutes[0], amount0, message);
            _migrate(from, params.destinationChainId, params.destinationSettler, tokenRoutes[1], amount1, message);

            emit Migrated(
                migrationId, params.destinationChainId, params.destinationSettler, from, tokenRoutes[0].token, amount0
            );
            emit Migrated(
                migrationId, params.destinationChainId, params.destinationSettler, from, tokenRoutes[1].token, amount1
            );
        }

        return this.onERC721Received.selector;
    }

    function _liquidate(uint256 positionId)
        internal
        virtual
        returns (address token0, address token1, uint256 amount0, uint256 amount1, bytes memory poolInfo);

    function _migrate(
        address sender,
        uint32 destinationChainId,
        address destinationSettler,
        TokenRoute memory tokenRoute,
        uint256 amount,
        bytes memory message
    ) internal virtual;

    function _swap(bytes memory poolInfo, bool zeroForOne, uint256 amountIn, uint256 amountOutMin)
        internal
        virtual
        returns (uint256 amountOut);
}
