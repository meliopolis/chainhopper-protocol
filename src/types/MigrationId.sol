// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {MigrationMode} from "./MigrationMode.sol";

type MigrationId is bytes32;

using MigrationIdLibrary for MigrationId global;

library MigrationIdLibrary {
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

    function chainId(MigrationId self) internal pure returns (uint32 _chainId) {
        assembly {
            _chainId := and(shr(224, self), 0xFFFFFFFF)
        }
    }

    function migrator(MigrationId self) internal pure returns (address _migrator) {
        assembly {
            _migrator := and(shr(64, self), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        }
    }

    function mode(MigrationId self) internal pure returns (MigrationMode _mode) {
        assembly {
            _mode := and(shr(56, self), 0xFF)
        }
    }

    function nounce(MigrationId self) internal pure returns (uint56 _nounce) {
        assembly {
            _nounce := and(self, 0xFFFFFFFFFFFFFF)
        }
    }
}
