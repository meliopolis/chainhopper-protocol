// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC721Receiver} from "@openzeppelin/token/ERC721/IERC721Receiver.sol";
import {IUniswapV3Migrator} from "../interfaces/IUniswapV3Migrator.sol";
import {UniswapV3Proxy} from "../libraries/UniswapV3Proxy.sol";
import {Migrator} from "./Migrator.sol";

abstract contract UniswapV3Migrator is IUniswapV3Migrator, IERC721Receiver, Migrator {
    UniswapV3Proxy private proxy;

    constructor(address positionManager, address universalRouter, address permit2) {
        proxy.initialize(positionManager, universalRouter, permit2);
    }

    function onERC721Received(address, address from, uint256 tokenId, bytes memory data) external returns (bytes4) {
        if (msg.sender != address(proxy.positionManager)) revert NotPositionManager();

        _migrate(from, tokenId, data);

        return this.onERC721Received.selector;
    }

    function _liquidate(uint256 positionId)
        internal
        override
        returns (address token0, address token1, uint256 amount0, uint256 amount1, bytes memory poolInfo)
    {
        uint24 fee;
        (token0, token1, fee, amount0, amount1) = proxy.liquidatePosition(positionId, 0, 0, address(this));

        poolInfo = abi.encode(token0, token1, fee);
    }

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
