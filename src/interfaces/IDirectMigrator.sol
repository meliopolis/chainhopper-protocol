// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IDirectMigrator
/// @notice Interface for the DirectMigrator contract
interface IDirectMigrator {
    /// @notice Error thrown when cross-chain migration is attempted
    error CrossChainNotSupported();
}
