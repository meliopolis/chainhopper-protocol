// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @title IUniswapV4Settler
/// @notice Interface for the UniswapV4Settler contract
interface IUniswapV4Settler {
    /// @notice Error thrown when a token is unused
    error UnusedToken(address token);

    /// @notice Struct for mint params
    /// @param token0 The first token
    /// @param token1 The second token
    /// @param fee The fee
    /// @param tickSpacing The tick spacing
    /// @param hooks The hooks
    /// @param sqrtPriceX96 The sqrt price
    /// @param tickLower The lower tick
    /// @param tickUpper The upper tick
    /// @param swapAmountInMilliBps The swap amount in milli bps
    /// @param amount0Min The minimum amount of token0 that must be used in the position
    /// @param amount1Min The minimum amount of token1 that must be used in the position
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
