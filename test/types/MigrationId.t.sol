// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "@forge-std/Test.sol";
import {MigrationId, MigrationIdLibrary} from "../../src/types/MigrationId.sol";
import {MigrationMode} from "../../src/types/MigrationMode.sol";

contract MigrationIdTest is Test {
    function test_fuzz_conversions(uint32 chainId, address migrator, MigrationMode mode, uint56 nounce) public pure {
        MigrationId id = MigrationIdLibrary.from(chainId, migrator, mode, nounce);

        assertEq(id.chainId(), chainId);
        assertEq(id.migrator(), migrator);
        assertTrue(id.mode() == mode);
        assertEq(id.nounce(), nounce);
    }
}
