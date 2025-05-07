// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IAcrossSettler
/// @notice Interface for the AcrossSettler contract
interface IAcrossSettler {
    /// @notice Error thrown when the caller is not the spoke pool
    error NotSpokePool();

    /// @notice Event emitted when a receipt is issued
    event Receipt(bytes32 indexed migrationHash, address indexed recipient, address indexed token, uint256 amount);
}
