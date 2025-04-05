// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "@forge-std/Test.sol";

contract TestContext is Test {
    address user = makeAddr("user");
    address owner = makeAddr("owner");

    address weth;
    address usdc;
    address usdt;

    address acrossSpokePool;
    address v3PositionManager;
    address v4PositionManager;
    address universalRouter;
    address permit2;

    function _loadChain(string memory chainName) internal {
        // setting block number to 28545100 for repeatability
        vm.createSelectFork(vm.envString(string(abi.encodePacked(chainName, "_RPC_URL"))), 28545100);

        weth = vm.envAddress(string(abi.encodePacked(chainName, "_WETH")));
        usdc = vm.envAddress(string(abi.encodePacked(chainName, "_USDC")));
        usdt = vm.envAddress(string(abi.encodePacked(chainName, "_USDT")));

        acrossSpokePool = vm.envAddress(string(abi.encodePacked(chainName, "_ACROSS_SPOKE_POOL")));
        v3PositionManager = vm.envAddress(string(abi.encodePacked(chainName, "_UNISWAP_V3_POSITION_MANAGER")));
        universalRouter = vm.envAddress(string(abi.encodePacked(chainName, "_UNISWAP_UNIVERSAL_ROUTER")));
        permit2 = vm.envAddress(string(abi.encodePacked(chainName, "_UNISWAP_PERMIT2")));
        v4PositionManager = vm.envAddress(string(abi.encodePacked(chainName, "_UNISWAP_V4_POSITION_MANAGER")));
    }

    // add this to be excluded from coverage report
    function test() public virtual {}
}
