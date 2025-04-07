// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MigrationId, MigrationIdLibrary} from "../../src/types/MigrationId.sol";
import {MigrationModes, MigrationMode} from "../../src/types/MigrationMode.sol";

contract MigrationIdTest is Test {
    function test_fuzz_conversions(uint32 chainId, address migrator, MigrationMode mode, uint56 nonce) public pure {
        MigrationId id = MigrationIdLibrary.from(chainId, migrator, mode, nonce);

        assertEq(id.chainId(), chainId);
        assertEq(id.migrator(), migrator);
        assertTrue(id.mode() == mode);
        assertEq(id.nonce(), nonce);
    }

    function testMigrationIdGeneration() public pure {
        // Test basic migration ID generation
        uint32 chainId = 1;
        address migrator = address(0x1234567890123456789012345678901234567890);
        MigrationMode mode = MigrationModes.SINGLE;
        uint56 nonce = 123;

        MigrationId id = MigrationIdLibrary.from(chainId, migrator, mode, nonce);

        // Verify each component is correctly packed
        // We can extract components by shifting and masking
        assertEq(id.chainId(), chainId);
        assertEq(id.migrator(), migrator);
        assertTrue(id.mode() == mode);
        assertEq(id.nonce(), nonce);
    }

    function testEdgeCases() public pure {
        // Test with max values
        uint32 maxChainId = type(uint32).max;
        address maxMigrator = address(type(uint160).max);
        uint56 maxNonce = type(uint56).max;

        MigrationId id = MigrationIdLibrary.from(maxChainId, maxMigrator, MigrationModes.SINGLE, maxNonce);

        // Verify max values are handled correctly
        assertEq(id.chainId(), maxChainId);
        assertEq(id.migrator(), maxMigrator);
        assertTrue(id.mode() == MigrationModes.SINGLE);
        assertEq(id.nonce(), maxNonce);

        // Test with zero values
        id = MigrationIdLibrary.from(0, address(0), MigrationModes.DUAL, 0);

        // Verify zero values are handled correctly
        assertEq(id.chainId(), 0);
        assertEq(id.migrator(), address(0));
        assertTrue(id.mode() == MigrationModes.DUAL);
        assertEq(id.nonce(), 0);
    }
}
