// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "@forge-std/Test.sol";
import {MockMigrator} from "../mocks/MockMigrator.sol";
import {MockSettler} from "../mocks/MockSettler.sol";

contract BaseTest is Test {
    string internal constant ENV = "BASE";
    address internal constant OWNER = address(0x123);
    address internal constant USER = address(0x456);

    MockMigrator internal migrator;
    MockSettler internal settler;
    address internal uniswapV3PositionManager;
    address internal uniswapV4PositionManager;
    address internal uniswapUniversalRouter;
    address internal uniswapPermit2;
    address internal acrossSpokePool;
    address internal weth;
    address internal usdc;
    address internal usdt;
    address internal vitalik;
    uint24 internal uniswapV3WethUsdcPoolFee;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString(string(abi.encodePacked(ENV, "_RPC_URL"))));
        migrator = new MockMigrator(OWNER);
        settler = new MockSettler(OWNER);

        uniswapV3PositionManager = vm.envAddress(string(abi.encodePacked(ENV, "_UNISWAP_V3_POSITION_MANAGER")));
        uniswapV4PositionManager = vm.envAddress(string(abi.encodePacked(ENV, "_UNISWAP_V4_POSITION_MANAGER")));
        uniswapUniversalRouter = vm.envAddress(string(abi.encodePacked(ENV, "_UNISWAP_UNIVERSAL_ROUTER")));
        uniswapPermit2 = vm.envAddress(string(abi.encodePacked(ENV, "_UNISWAP_PERMIT2")));
        acrossSpokePool = vm.envAddress(string(abi.encodePacked(ENV, "_ACROSS_SPOKE_POOL")));
        weth = vm.envAddress(string(abi.encodePacked(ENV, "_WETH")));
        usdc = vm.envAddress(string(abi.encodePacked(ENV, "_USDC")));
        usdt = vm.envAddress(string(abi.encodePacked(ENV, "_USDT")));
        vitalik = vm.envAddress(string(abi.encodePacked(ENV, "_VITALIK")));
        uniswapV3WethUsdcPoolFee = uint24(vm.envUint(string(abi.encodePacked(ENV, "_UNISWAP_V3_WETH_USDC_POOL_FEE"))));
    }

    // add this to be excluded from coverage report
    function test() public {}
}
