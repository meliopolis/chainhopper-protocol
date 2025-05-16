// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IAcrossSettler
/// @notice Interface for the AcrossSettler contract
interface IAcrossSettler {
    /// @notice Error thrown when the caller is not the spoke pool
    error NotSpokePool();
    /// @notice Error thrown when the amount is missing
    error MissingAmount(address token);
    /// @notice Error thrown when the migration ID does not match with data
    error InvalidMigration();
}
