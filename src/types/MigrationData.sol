// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {MigrationMode} from "./MigrationMode.sol";

/// @title MigrationData
/// @notice Struct for migration data
struct MigrationData {
    uint256 sourceChainId;
    address migrator;
    uint256 nonce;
    MigrationMode mode;
    bytes routesData;
    bytes settlementData;
}

using MigrationDataLibrary for MigrationData global;

/// @title MigrationDataLibrary
/// @notice Library for handling migration data
library MigrationDataLibrary {
    /// @notice Function to create a hash of the migration data
    /// @param self The migration data
    /// @return The hash of the migration data
    function toHash(MigrationData memory self) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(self.sourceChainId, self.migrator, self.nonce, self.mode, self.routesData, self.settlementData)
        );
    }
}
