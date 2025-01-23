// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "lib/forge-std/src/Test.sol";

contract SingleTokenV3V3SettlerTest is Test {
    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_MAINNET_RPC_URL"), 25394775);
    }

    function test_settler() public {
        console.log("test_settler");
    }
}
