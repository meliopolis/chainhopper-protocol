// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {MigrationMode} from "./MigrationMode.sol";

type MigrationId is bytes32;

using MigrationIdLibrary for MigrationId global;

/// @title MigrationIdLibrary
/// @notice Library for MigrationId
library MigrationIdLibrary {
    /// @notice Function to create a MigrationId
    /// @param _chainId The chain id
    /// @param _migrator The migrator
    /// @param _mode The mode
    /// @param _nonce The nonce
    /// @return migrationId The migration id
    // TODO: chain id size limit non-issue after reworking the migration id
    function from(uint32 _chainId, address _migrator, MigrationMode _mode, uint56 _nonce)
        internal
        pure
        returns (MigrationId migrationId)
    {
        assembly {
            _chainId := and(_chainId, 0xFFFFFFFF)
            _migrator := and(_migrator, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            _mode := and(_mode, 0xFF)
            _nonce := and(_nonce, 0xFFFFFFFFFFFFFF)

            migrationId := or(shl(224, _chainId), or(shl(64, _migrator), or(shl(56, _mode), _nonce)))
        }
    }

    /// @notice Function to get the chain id
    /// @param self The migration id
    /// @return _chainId The chain id
    function chainId(MigrationId self) internal pure returns (uint32 _chainId) {
        assembly {
            _chainId := and(shr(224, self), 0xFFFFFFFF)
        }
    }

    /// @notice Function to get the migrator
    /// @param self The migration id
    /// @return _migrator The migrator
    function migrator(MigrationId self) internal pure returns (address _migrator) {
        assembly {
            _migrator := and(shr(64, self), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        }
    }

    /// @notice Function to get the mode
    /// @param self The migration id
    /// @return _mode The mode
    function mode(MigrationId self) internal pure returns (MigrationMode _mode) {
        assembly {
            _mode := and(shr(56, self), 0xFF)
        }
    }

    /// @notice Function to get the nonce
    /// @param self The migration id
    /// @return _nonce The nonce
    function nonce(MigrationId self) internal pure returns (uint56 _nonce) {
        assembly {
            _nonce := and(self, 0xFFFFFFFFFFFFFF)
        }
    }
}
