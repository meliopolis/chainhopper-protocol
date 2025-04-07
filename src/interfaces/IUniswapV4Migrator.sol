// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @title IUniswapV4Migrator
/// @notice Interface for the UniswapV4Migrator contract
interface IUniswapV4Migrator {
    /// @notice Error thrown when the caller is not v4 position manager
    error NotPositionManager();
}
