// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IUniswapV3Migrator
/// @notice Interface for the UniswapV3Migrator contract
interface IUniswapV3Migrator {
    /// @notice Error thrown when the caller is not v3 position manager
    error NotPositionManager();
}
