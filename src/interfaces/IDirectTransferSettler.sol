// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IDirectTransferSettler
/// @notice Interface for the DirectTransferSettler contract
interface IDirectTransferSettler {
    /// @notice Error thrown when amount is missing
    error MissingAmount(address token);
    
    /// @notice Error thrown when migration is invalid
    error InvalidMigration();

    /// @notice Function to handle a direct transfer message
    /// @param token The token to settle
    /// @param amount The amount to settle
    /// @param message The message containing migration data
    function handleDTMessage(address token, uint256 amount, bytes memory message) external;
} 