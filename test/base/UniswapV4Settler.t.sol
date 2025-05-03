// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.24;

// import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";
// import {IHooks} from "@uniswap-v4-core/interfaces/IHooks.sol";
// import {IPoolManager} from "@uniswap-v4-core/interfaces/IPoolManager.sol";
// import {Currency} from "@uniswap-v4-core/types/Currency.sol";
// import {PoolId} from "@uniswap-v4-core/types/PoolId.sol";
// import {PoolKey} from "@uniswap-v4-core/types/PoolKey.sol";
// import {IWETH9} from "../../src/interfaces/external/IWETH9.sol";
// import {IUniswapV4Settler} from "../../src/interfaces/IUniswapV4Settler.sol";
// import {MockUniswapV4Settler} from "../mocks/MockUniswapV4Settler.sol";
// import {TestContext} from "../utils/TestContext.sol";

// contract UniswapV4SettlerTest is TestContext {
//     string constant CHAIN_NAME = "BASE";

//     MockUniswapV4Settler settler;

//     function setUp() public {
//         _loadChain(CHAIN_NAME);

//         settler = new MockUniswapV4Settler(owner, v4PositionManager, universalRouter, permit2, weth);

//         if (uniswapV4Proxy.getPoolSqrtPriceX96(v4NativePoolKey) == 0) {
//             uniswapV4Proxy.initializePool(v4NativePoolKey, 1e18);
//         }
//         if (uniswapV4Proxy.getPoolSqrtPriceX96(v4TokenPoolKey) == 0) {
//             uniswapV4Proxy.initializePool(v4TokenPoolKey, 1e18);
//         }
//     }

//     function test_mintPosition_singleRoute_fails_ifTokenIsUnused() public {
//         bytes memory data = abi.encode(
//             IUniswapV4Settler.MintParams(
//                 Currency.unwrap(v4TokenPoolKey.currency0),
//                 Currency.unwrap(v4TokenPoolKey.currency1),
//                 v4TokenPoolKey.fee,
//                 v4TokenPoolKey.tickSpacing,
//                 address(0),
//                 1_000_000_000_000,
//                 -600,
//                 600,
//                 5_000_000,
//                 0,
//                 0
//             )
//         );

//         vm.expectRevert(abi.encodeWithSelector(IUniswapV4Settler.UnusedToken.selector, weth));

//         settler.mintPosition(weth, 100, user, data);
//     }

//     function test_mintPosition_dualRoute_fails_ifTokenAIsUnused() public {
//         bytes memory data = abi.encode(
//             IUniswapV4Settler.MintParams(
//                 Currency.unwrap(v4TokenPoolKey.currency0),
//                 Currency.unwrap(v4TokenPoolKey.currency1),
//                 v4TokenPoolKey.fee,
//                 v4TokenPoolKey.tickSpacing,
//                 address(0),
//                 1_000_000_000_000,
//                 -600,
//                 600,
//                 5_000_000,
//                 0,
//                 0
//             )
//         );

//         vm.expectRevert(abi.encodeWithSelector(IUniswapV4Settler.UnusedToken.selector, weth));

//         settler.mintPosition(weth, usdc, 100, 100, user, data);
//     }

//     function test_mintPosition_dualRoute_fails_ifTokenBIsUnused() public {
//         bytes memory data = abi.encode(
//             IUniswapV4Settler.MintParams(
//                 Currency.unwrap(v4TokenPoolKey.currency0),
//                 Currency.unwrap(v4TokenPoolKey.currency1),
//                 v4TokenPoolKey.fee,
//                 v4TokenPoolKey.tickSpacing,
//                 address(0),
//                 1_000_000_000_000,
//                 -600,
//                 600,
//                 5_000_000,
//                 0,
//                 0
//             )
//         );

//         vm.expectRevert(abi.encodeWithSelector(IUniswapV4Settler.UnusedToken.selector, weth));

//         settler.mintPosition(usdc, weth, 100, 100, user, data);
//     }

//     function test_mintPosition_dualRoute_intializeNewPool() public {
//         deal(usdc, address(settler), 100);
//         deal(usdt, address(settler), 100);

//         bytes memory data = abi.encode(
//             IUniswapV4Settler.MintParams(
//                 Currency.unwrap(v4TokenPoolKey.currency0),
//                 Currency.unwrap(v4TokenPoolKey.currency1),
//                 --v4TokenPoolKey.fee,
//                 v4TokenPoolKey.tickSpacing,
//                 address(0),
//                 1_000_000_000_000,
//                 -600,
//                 600,
//                 5_000_000,
//                 0,
//                 0
//             )
//         );

//         vm.expectEmit(true, true, true, false);
//         emit IPoolManager.Initialize(
//             v4TokenPoolKey.toId(),
//             v4TokenPoolKey.currency0,
//             v4TokenPoolKey.currency1,
//             v4TokenPoolKey.fee,
//             v4TokenPoolKey.tickSpacing,
//             IHooks(address(0)),
//             1_000_000_000_000,
//             0
//         );

//         vm.expectEmit(true, true, false, false);
//         emit IERC721.Transfer(address(0), user, 0);

//         vm.expectEmit(true, true, false, false);
//         emit IPoolManager.ModifyLiquidity(v4TokenPoolKey.toId(), address(v4PositionManager), 0, 0, 0, "");

//         settler.mintPosition(usdc, usdt, 100, 100, user, data);
//     }

//     function test_fuzz_mintPosition_singleRoute(bool hasNative, bool isTokenNative, bool isNativeWrapped) public {
//         address token;
//         if (hasNative && isTokenNative && !isNativeWrapped) {
//             token = address(0);
//             deal(address(settler), 100);
//         } else {
//             token = hasNative ? (isTokenNative ? weth : usdc) : usdt;
//             deal(token, address(settler), 100);
//         }

//         address token0 = hasNative ? address(0) : usdt;
//         address token1 = usdc;
//         if (token0 > token1) (token0, token1) = (token1, token0);

//         PoolKey memory poolKey = hasNative ? v4NativePoolKey : v4TokenPoolKey;
//         bytes memory data = abi.encode(
//             IUniswapV4Settler.MintParams(
//                 token0,
//                 token1,
//                 poolKey.fee,
//                 poolKey.tickSpacing,
//                 address(0),
//                 1_000_000_000_000,
//                 -600,
//                 600,
//                 5_000_000,
//                 0,
//                 0
//             )
//         );

//         if (hasNative && isTokenNative && isNativeWrapped) {
//             vm.expectEmit(true, true, true, true);
//             emit IWETH9.Withdrawal(address(settler), 100);
//         }

//         vm.expectEmit(true, true, true, false);
//         emit IPoolManager.Swap(poolKey.toId(), address(universalRouter), 0, 0, 0, 0, 0, 0);

//         vm.expectEmit(true, true, false, false);
//         emit IERC721.Transfer(address(0), user, 0);

//         vm.expectEmit(true, true, false, false);
//         emit IPoolManager.ModifyLiquidity(poolKey.toId(), address(v4PositionManager), 0, 0, 0, "");

//         settler.mintPosition(token, 100, user, data);
//     }

//     function test_fuzz_mintPosition_dualRoute(bool hasNative, bool isNativeWrapped, bool areTokensInOrder) public {
//         address tokenA;
//         if (hasNative && !isNativeWrapped) {
//             tokenA = address(0);
//             deal(address(settler), 100);
//         } else {
//             tokenA = hasNative ? weth : usdt;
//             deal(tokenA, address(settler), 100);
//         }
//         address tokenB = usdc;
//         deal(tokenB, address(settler), 200);
//         if (!areTokensInOrder) (tokenA, tokenB) = (tokenB, tokenA);

//         address token0 = hasNative ? address(0) : usdt;
//         address token1 = usdc;
//         if (token0 > token1) (token0, token1) = (token1, token0);

//         PoolKey memory poolKey = hasNative ? v4NativePoolKey : v4TokenPoolKey;
//         bytes memory data = abi.encode(
//             IUniswapV4Settler.MintParams(
//                 token0,
//                 token1,
//                 poolKey.fee,
//                 poolKey.tickSpacing,
//                 address(0),
//                 1_000_000_000_000,
//                 -600,
//                 600,
//                 5_000_000,
//                 0,
//                 0
//             )
//         );

//         if (hasNative && isNativeWrapped) {
//             vm.expectEmit(true, true, true, true);
//             emit IWETH9.Withdrawal(address(settler), 100);
//         }

//         vm.expectEmit(true, true, false, false);
//         emit IERC721.Transfer(address(0), user, 0);

//         vm.expectEmit(true, true, false, false);
//         emit IPoolManager.ModifyLiquidity(poolKey.toId(), address(v4PositionManager), 0, 0, 0, "");

//         settler.mintPosition(tokenA, tokenB, areTokensInOrder ? 100 : 200, areTokensInOrder ? 200 : 100, user, data);
//     }
// }
