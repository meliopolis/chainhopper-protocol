// SPDX-License-Identifier: MIT
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
    /// @notice Function to create a migration ID from data
    /// @param self The migration data
    /// @return The migration ID
    function toId(MigrationData memory self) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(self.sourceChainId, self.migrator, self.nonce, self.mode, self.routesData, self.settlementData)
        );
    }
}
