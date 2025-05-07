// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

type MigrationMode is uint8;

using {equals as ==} for MigrationMode global;

function equals(MigrationMode a, MigrationMode b) pure returns (bool) {
    return MigrationMode.unwrap(a) == MigrationMode.unwrap(b);
}

/// @title MigrationModes
/// @notice Migration modes
library MigrationModes {
    /// @notice Single migration mode
    MigrationMode constant SINGLE = MigrationMode.wrap(1);
    /// @notice Dual migration mode
    MigrationMode constant DUAL = MigrationMode.wrap(2);
}
