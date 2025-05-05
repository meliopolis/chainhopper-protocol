// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.24;

// import {Test} from "@forge-std/Test.sol";
// import {IHooks} from "@uniswap-v4-core/interfaces/IHooks.sol";
// import {Currency} from "@uniswap-v4-core/types/Currency.sol";
// import {PoolKey} from "@uniswap-v4-core/types/PoolKey.sol";
// import {UniswapV3Proxy} from "../../src/libraries/UniswapV3Proxy.sol";
// import {UniswapV4Proxy} from "../../src/libraries/UniswapV4Proxy.sol";

// contract TestContext is Test {
//     address user = makeAddr("user");
//     address owner = makeAddr("owner");

//     address weth;
//     address usdc;
//     address usdt;

//     address acrossSpokePool;
//     address permit2;
//     address universalRouter;
//     address v3PositionManager;
//     address v4PositionManager;

//     UniswapV3Proxy public uniswapV3Proxy;
//     UniswapV4Proxy public uniswapV4Proxy;

//     PoolKey v4NativePoolKey;
//     PoolKey v4TokenPoolKey;

//     function _loadChain(string memory chainName) internal {
//         // setting block number to 28545100 for repeatability
//         vm.createSelectFork(vm.envString(string(abi.encodePacked(chainName, "_RPC_URL"))), 28545100);

//         weth = vm.envAddress(string(abi.encodePacked(chainName, "_WETH")));
//         usdc = vm.envAddress(string(abi.encodePacked(chainName, "_USDC")));
//         usdt = vm.envAddress(string(abi.encodePacked(chainName, "_USDT")));

//         acrossSpokePool = vm.envAddress(string(abi.encodePacked(chainName, "_ACROSS_SPOKE_POOL")));
//         permit2 = vm.envAddress(string(abi.encodePacked(chainName, "_UNISWAP_PERMIT2")));
//         universalRouter = vm.envAddress(string(abi.encodePacked(chainName, "_UNISWAP_UNIVERSAL_ROUTER")));
//         v3PositionManager = vm.envAddress(string(abi.encodePacked(chainName, "_UNISWAP_V3_POSITION_MANAGER")));
//         v4PositionManager = vm.envAddress(string(abi.encodePacked(chainName, "_UNISWAP_V4_POSITION_MANAGER")));

//         uniswapV3Proxy.initialize(v3PositionManager, universalRouter, permit2);
//         uniswapV4Proxy.initialize(v4PositionManager, universalRouter, permit2);

//         v4NativePoolKey = PoolKey(Currency.wrap(address(0)), Currency.wrap(usdc), 500, 10, IHooks(address(0)));
//         v4TokenPoolKey = PoolKey(
//             Currency.wrap(usdc > usdt ? usdt : usdc),
//             Currency.wrap(usdc > usdt ? usdc : usdt),
//             100,
//             1,
//             IHooks(address(0))
//         );
//     }

//     // add this to be excluded from coverage report
//     function test() public virtual {}
// }
