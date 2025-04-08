// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC721Receiver} from "@openzeppelin/token/ERC721/IERC721Receiver.sol";
import {IUniswapV3Migrator} from "../interfaces/IUniswapV3Migrator.sol";
import {UniswapV3Proxy} from "../libraries/UniswapV3Proxy.sol";
import {Migrator} from "./Migrator.sol";

/// @title UniswapV3Migrator
/// @notice Abstract contract for migrating positions between chains using Uniswap V3
abstract contract UniswapV3Migrator is IUniswapV3Migrator, IERC721Receiver, Migrator {
    UniswapV3Proxy private proxy;

    /// @notice Constructor for the UniswapV3Migrator contract
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
    /// @return amount0 The amount of token0 received
    /// @return amount1 The amount of token1 received
    /// @return poolInfo The pool info
    function _liquidate(uint256 positionId)
        internal
        override
        returns (address token0, address token1, uint256 amount0, uint256 amount1, bytes memory poolInfo)
    {
        uint24 fee;
        (token0, token1, fee, amount0, amount1) = proxy.liquidatePosition(positionId, 0, 0, address(this));

        poolInfo = abi.encode(token0, token1, fee);
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
        (address token0, address token1, uint24 fee) = abi.decode(poolInfo, (address, address, uint24));

        // get token in and out
        (address tokenIn, address tokenOut) = zeroForOne ? (token0, token1) : (token1, token0);

        amountOut = proxy.swap(tokenIn, tokenOut, fee, amountIn, 0, address(this));
    }
}
