// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IAcrossMigrator
/// @notice Interface for the AcrossMigrator contract
interface IAcrossMigrator {
    /// @notice Struct for a route specifically on Across
    struct Route {
        address outputToken;
        uint256 maxFees;
        uint32 quoteTimestamp;
        uint32 fillDeadlineOffset;
        address exclusiveRelayer;
        uint32 exclusivityDeadline;
    }
}
