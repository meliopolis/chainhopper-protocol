// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IUniswapV3Settler} from "../interfaces/IUniswapV3Settler.sol";
import {UniswapV3Proxy} from "../libraries/UniswapV3Proxy.sol";
import {Settler} from "./Settler.sol";

abstract contract UniswapV3Settler is IUniswapV3Settler, Settler {
    using SafeERC20 for IERC20;

    UniswapV3Proxy private proxy;

    constructor(address positionManager, address universalRouter, address permit2) {
        proxy.initialize(positionManager, universalRouter, permit2);
    }

    function _mintPosition(address token, uint256 amount, address recipient, bytes memory data)
        internal
        override
        returns (uint256 positionId)
    {
        MintParams memory mintParams = abi.decode(data, (MintParams));
        if (token != mintParams.token0 && token != mintParams.token1) revert UnusedToken(token);

        // get token out and amount in
        address tokenOut = token == mintParams.token0 ? mintParams.token1 : mintParams.token0;
        uint256 amountIn = (amount * mintParams.swapAmountInMilliBps) / 10_000_000;

        // swap tokens if needed
        uint256 amountOut;
        if (amountIn > 0) amountOut = proxy.swap(token, tokenOut, mintParams.fee, amountIn, 0, address(this));

        return _mintPosition(token, tokenOut, amount - amountIn, amountOut, recipient, data);
    }

    function _mintPosition(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        address recipient,
        bytes memory data
    ) internal override returns (uint256 positionId) {
        MintParams memory mintParams = abi.decode(data, (MintParams));
        if (tokenA != mintParams.token0 && tokenA != mintParams.token1) revert UnusedToken(tokenA);
        if (tokenB != mintParams.token0 && tokenB != mintParams.token1) revert UnusedToken(tokenB);

        // ensure tokens and amounts are in the right order
        if (mintParams.token0 > mintParams.token1) {
            (mintParams.token0, mintParams.token1) = (mintParams.token1, mintParams.token0);
            (mintParams.amount0Min, mintParams.amount1Min) = (mintParams.amount1Min, mintParams.amount0Min);
        }
        (uint256 amount0, uint256 amount1) = tokenA == mintParams.token0 ? (amountA, amountB) : (amountB, amountA);

        // create and initialize pool if necessary
        proxy.createAndInitializePoolIfNecessary(
            mintParams.token0, mintParams.token1, mintParams.fee, mintParams.sqrtPriceX96
        );

        // mint position
        uint256 amount0Used;
        uint256 amount1Used;
        (positionId,, amount0Used, amount1Used) = proxy.mintPosition(
            mintParams.token0,
            mintParams.token1,
            mintParams.fee,
            mintParams.tickLower,
            mintParams.tickUpper,
            amount0,
            amount1,
            mintParams.amount0Min,
            mintParams.amount1Min,
            recipient
        );

        // refund surplus tokens
        if (amount0 > amount0Used) IERC20(mintParams.token0).safeTransfer(recipient, amount0 - amount0Used);
        if (amount1 > amount1Used) IERC20(mintParams.token1).safeTransfer(recipient, amount1 - amount1Used);
    }
}
