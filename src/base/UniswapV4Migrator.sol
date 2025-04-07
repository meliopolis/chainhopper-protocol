// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC721Receiver} from "@openzeppelin/token/ERC721/IERC721Receiver.sol";
import {Currency} from "@uniswap-v4-core/types/Currency.sol";
import {PoolKey} from "@uniswap-v4-core/types/PoolKey.sol";
import {IUniswapV4Migrator} from "../interfaces/IUniswapV4Migrator.sol";
import {UniswapV4Proxy} from "../libraries/UniswapV4Proxy.sol";
import {Migrator} from "./Migrator.sol";

/// @title UniswapV4Migrator
/// @notice Abstract contract for migrating positions between chains using Uniswap V4
abstract contract UniswapV4Migrator is IUniswapV4Migrator, IERC721Receiver, Migrator {
    UniswapV4Proxy private proxy;

    /// @notice Constructor for the UniswapV4Migrator contract
    /// @param positionManager The position manager address
    /// @param universalRouter The universal router address
    /// @param permit2 The permit2 address
    constructor(address positionManager, address universalRouter, address permit2) {
        proxy.initialize(positionManager, universalRouter, permit2);
    }

    /// @notice Callback function for ERC721 tokens
    /// @dev This function is called when a user transfers an ERC721 token to the contract. If it fails, the transaction will revert.
    /// @param from The sender of the transfer (ex: User EOA)
    /// @param tokenId The token id
    /// @param data The data of the transfer
    /// @return selector The selector of the callback
    function onERC721Received(address, address from, uint256 tokenId, bytes memory data) external returns (bytes4) {
        if (msg.sender != address(proxy.positionManager)) revert NotPositionManager();

        _migrate(from, tokenId, data);

        return this.onERC721Received.selector;
    }

    /// @notice Internal function to liquidate a position
    /// @param positionId The id of the position
    /// @return token0 The first token
    /// @return token1 The second token
    /// @return amount0 The amount of token0
    /// @return amount1 The amount of token1
    /// @return poolInfo The pool info
    function _liquidate(uint256 positionId)
        internal
        override
        returns (address token0, address token1, uint256 amount0, uint256 amount1, bytes memory poolInfo)
    {
        PoolKey memory poolKey;
        (poolKey, amount0, amount1) = proxy.liquidatePosition(positionId, 0, 0, address(this));

        token0 = Currency.unwrap(poolKey.currency0);
        token1 = Currency.unwrap(poolKey.currency1);
        poolInfo = abi.encode(poolKey);
    }

    /// @notice Internal function to swap tokens
    /// @param poolInfo The pool info
    /// @param zeroForOne The direction of the swap
    /// @param amountIn The amount to swap
    /// @return amountOut The amount of tokens received
    function _swap(bytes memory poolInfo, bool zeroForOne, uint256 amountIn)
        internal
        override
        returns (uint256 amountOut)
    {
        PoolKey memory poolKey = abi.decode(poolInfo, (PoolKey));

        amountOut = proxy.swap(poolKey, zeroForOne, amountIn, 0, address(this));
    }

    /// @notice Receive function to allow the contract to receive native tokens, which are supported in Uniswap v4
    receive() external payable {}
}
