// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "@forge-std/Test.sol";
import {IHooks} from "@uniswap-v4-core/interfaces/IHooks.sol";
import {Currency} from "@uniswap-v4-core/types/Currency.sol";
import {PoolKey} from "@uniswap-v4-core/types/PoolKey.sol";

contract TestContext is Test {
    address user = makeAddr("user");
    address owner = makeAddr("owner");

    address weth;
    address usdc;
    address usdt;
    address virtualToken;
    address destChainUsdc;

    address acrossSpokePool;
    address permit2;
    address universalRouter;
    address v3PositionManager;
    address v4PositionManager;

    PoolKey v4NativePoolKey;
    PoolKey v4TokenPoolKey;

    function _loadChain(string memory srcChainName, string memory destChainName) internal {
        // setting block number to 28545100 for repeatability
        vm.createSelectFork(vm.envString(string(abi.encodePacked(srcChainName, "_RPC_URL"))), 28545100);

        weth = vm.envAddress(string(abi.encodePacked(srcChainName, "_WETH")));
        usdc = vm.envAddress(string(abi.encodePacked(srcChainName, "_USDC")));
        usdt = vm.envAddress(string(abi.encodePacked(srcChainName, "_USDT")));
        virtualToken = address(0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b); // useful as it sorts before weth and usdc
        destChainUsdc = vm.envAddress(string(abi.encodePacked(destChainName, "_USDC")));

        acrossSpokePool = vm.envAddress(string(abi.encodePacked(srcChainName, "_ACROSS_SPOKE_POOL")));
        permit2 = vm.envAddress(string(abi.encodePacked(srcChainName, "_UNISWAP_PERMIT2")));
        universalRouter = vm.envAddress(string(abi.encodePacked(srcChainName, "_UNISWAP_UNIVERSAL_ROUTER")));
        v3PositionManager = vm.envAddress(string(abi.encodePacked(srcChainName, "_UNISWAP_V3_POSITION_MANAGER")));
        v4PositionManager = vm.envAddress(string(abi.encodePacked(srcChainName, "_UNISWAP_V4_POSITION_MANAGER")));

        v4NativePoolKey = PoolKey(Currency.wrap(address(0)), Currency.wrap(usdc), 500, 10, IHooks(address(0)));
        v4TokenPoolKey = PoolKey(
            Currency.wrap(usdc > usdt ? usdt : usdc),
            Currency.wrap(usdc > usdt ? usdc : usdt),
            100,
            1,
            IHooks(address(0))
        );
    }

    // add this to be excluded from coverage report
    function test() public virtual {}
}
