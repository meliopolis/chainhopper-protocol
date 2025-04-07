// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MigrationId} from "../types/MigrationId.sol";

/// @title IAcrossSettler
/// @notice Interface for the AcrossSettler contract
interface IAcrossSettler {
    /// @notice Error thrown when the caller is not the spoke pool
    error NotSpokePool();

    /// @notice Event emitted when a receipt is issued
    event Receipt(MigrationId indexed migrationId, address indexed recipient, address indexed token, uint256 amount);
}
