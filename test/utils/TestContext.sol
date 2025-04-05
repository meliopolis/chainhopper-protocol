// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "@forge-std/Test.sol";

contract TestContext is Test {
    address user = makeAddr("user");
    address owner = makeAddr("owner");

    address weth;
    address usdc;

    address acrossSpokePool;

    function _loadChain(string memory chainName) internal {
        vm.createSelectFork(vm.envString(string(abi.encodePacked(chainName, "_RPC_URL"))));

        weth = vm.envAddress(string(abi.encodePacked(chainName, "_WETH")));
        usdc = vm.envAddress(string(abi.encodePacked(chainName, "_USDC")));

        acrossSpokePool = vm.envAddress(string(abi.encodePacked(chainName, "_ACROSS_SPOKE_POOL")));
    }
}
