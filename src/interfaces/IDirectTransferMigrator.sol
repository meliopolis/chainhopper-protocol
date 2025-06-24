// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IDirectTransferMigrator
/// @notice Interface for the DirectTransferMigrator contract
interface IDirectTransferMigrator {
    /// @notice Error thrown when cross-chain migration is attempted
    error CrossChainNotSupported();
}
