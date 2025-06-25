// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IAerodromeMigrator
/// @notice Interface for the AerodromeMigrator contract
interface IAerodromeMigrator {
    /// @notice Error thrown when the caller is not aerodrome position manager
    error NotAerodromePositionManager();
}
