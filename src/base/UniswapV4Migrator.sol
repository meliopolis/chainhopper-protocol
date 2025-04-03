// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC721Receiver} from "@openzeppelin/token/ERC721/IERC721Receiver.sol";
import {Currency} from "@uniswap-v4-core/types/Currency.sol";
import {PoolKey} from "@uniswap-v4-core/types/PoolKey.sol";
import {IUniswapV4Migrator} from "../interfaces/IUniswapV4Migrator.sol";
import {UniswapV4Proxy} from "../libraries/UniswapV4Proxy.sol";
import {Migrator} from "./Migrator.sol";

abstract contract UniswapV4Migrator is IUniswapV4Migrator, IERC721Receiver, Migrator {
    UniswapV4Proxy private proxy;

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
        PoolKey memory poolKey;
        (poolKey, amount0, amount1) = proxy.liquidatePosition(positionId, 0, 0, address(this));

        token0 = Currency.unwrap(poolKey.currency0);
        token1 = Currency.unwrap(poolKey.currency1);
        poolInfo = abi.encode(poolKey);
    }

    function _swap(bytes memory poolInfo, bool zeroForOne, uint256 amountIn)
        internal
        override
        returns (uint256 amountOut)
    {
        PoolKey memory poolKey = abi.decode(poolInfo, (PoolKey));

        amountOut = proxy.swap(poolKey, zeroForOne, amountIn, 0, address(this));
    }

    receive() external payable {}
}
