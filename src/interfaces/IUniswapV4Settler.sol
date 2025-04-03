// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IUniswapV4Settler {
    error UnusedToken(address token);
    error UnusedTokens(address tokenA, address tokenB);
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
        uint160 sqrtPriceX96;
        int24 tickLower;
        int24 tickUpper;
        uint24 swapAmountInMilliBps;
        uint256 amount0Min;
        uint256 amount1Min;
    }
}
