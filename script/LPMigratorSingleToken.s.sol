// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {LPMigratorSingleToken} from "../src/LPMigratorSingleToken.sol";

contract LPMigratorSingleTokenScript is Script {
    LPMigratorSingleToken public migrator;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        vm.stopBroadcast();
    }
}
