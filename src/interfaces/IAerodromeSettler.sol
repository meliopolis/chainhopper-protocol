// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IAerodromeSettler
/// @notice Interface for the AerodromeSettler contract
interface IAerodromeSettler {
    /// @notice Error thrown when a token is unused
    error UnusedToken(address token);

    /// @notice Struct for mint params
    /// @param token0 The first token
    /// @param token1 The second token
    /// @param tickSpacing The tick spacing
    /// @param sqrtPriceX96 The sqrt price to set if pool is initialized
    /// @param tickLower The lower tick
    /// @param tickUpper The upper tick
    /// @param swapAmountInMilliBps The swap amount in milli bps
    /// @param amount0Min The minimum amount of token0 that must be used in the position
    /// @param amount1Min The minimum amount of token1 that must be used in the position
    struct MintParams {
        address token0;
        address token1;
        int24 tickSpacing;
        uint160 sqrtPriceX96;
        int24 tickLower;
        int24 tickUpper;
        uint24 swapAmountInMilliBps;
        uint256 amount0Min;
        uint256 amount1Min;
    }
}
