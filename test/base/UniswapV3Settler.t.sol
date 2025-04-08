// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";
import {IUniswapV3PoolEvents} from "@uniswap-v3-core/interfaces/pool/IUniswapV3PoolEvents.sol";
import {IUniswapV3Settler} from "../../src/interfaces/IUniswapV3Settler.sol";
import {MockUniswapV3Settler} from "../mocks/MockUniswapV3Settler.sol";
import {TestContext} from "../utils/TestContext.sol";

contract UniswapV3SettlerTest is TestContext {
    string constant CHAIN_NAME = "BASE";

    MockUniswapV3Settler settler;

    function setUp() public {
        _loadChain(CHAIN_NAME);

        settler = new MockUniswapV3Settler(owner, v3PositionManager, universalRouter, permit2);
    }

    function test_mintPosition_singleRoute_fails_ifTokenIsUnused() public {
        bytes memory data =
            abi.encode(IUniswapV3Settler.MintParams(weth, usdc, 500, 1_000_000_000_000, -600, 600, 5_000_000, 0, 0));

        vm.expectRevert(abi.encodeWithSelector(IUniswapV3Settler.UnusedToken.selector, usdt));

        settler.mintPosition(usdt, 100, user, data);
    }

    function test_fuzz_mintPosition_singleRoute(bool isToken0) public {
        (address token0, address token1) = weth < usdc ? (weth, usdc) : (usdc, weth);
        address token = isToken0 ? token0 : token1;
        deal(token, address(settler), 100);

        bytes memory data =
            abi.encode(IUniswapV3Settler.MintParams(token0, token1, 500, 1_000_000_000_000, -600, 600, 5_000_000, 0, 0));

        vm.expectEmit(true, true, true, false);
        emit IUniswapV3PoolEvents.Swap(address(universalRouter), address(settler), 0, 0, 0, 0, 0);

        vm.expectEmit(true, true, true, false);
        emit IUniswapV3PoolEvents.Mint(address(v3PositionManager), address(v3PositionManager), -600, 600, 0, 0, 0);

        vm.expectEmit(true, true, false, false);
        emit IERC721.Transfer(address(0), user, 0);

        settler.mintPosition(token, 100, user, data);
    }

    function test_mintPosition_dualRoute_fails_ifTokenAIsUnused() public {
        bytes memory data =
            abi.encode(IUniswapV3Settler.MintParams(weth, usdc, 500, 1_000_000_000_000, -600, 600, 5_000_000, 0, 0));

        vm.expectRevert(abi.encodeWithSelector(IUniswapV3Settler.UnusedToken.selector, usdt));

        settler.mintPosition(usdt, usdc, 100, 200, user, data);
    }

    function test_mintPosition_dualRoute_fails_ifTokenBIsUnused() public {
        bytes memory data =
            abi.encode(IUniswapV3Settler.MintParams(weth, usdc, 500, 1_000_000_000_000, -600, 600, 5_000_000, 0, 0));

        vm.expectRevert(abi.encodeWithSelector(IUniswapV3Settler.UnusedToken.selector, usdt));

        settler.mintPosition(weth, usdt, 100, 200, user, data);
    }

    function test_fuzz_mintPosition_dualRoute(bool areTokensInOrder, bool hasTokenASurplus) public {
        (address token0, address token1) = usdc < usdt ? (usdc, usdt) : (usdt, usdc);
        (address tokenA, address tokenB) = areTokensInOrder ? (token0, token1) : (token1, token0);
        deal(tokenA, address(settler), hasTokenASurplus ? 1_000_000 : 100);
        deal(tokenB, address(settler), 200);

        bytes memory data =
            abi.encode(IUniswapV3Settler.MintParams(token0, token1, 500, 1_000_000_000_000, -600, 600, 5_000_000, 0, 0));

        vm.expectEmit(true, true, true, false);
        emit IUniswapV3PoolEvents.Mint(address(v3PositionManager), address(v3PositionManager), -600, 600, 0, 0, 0);

        vm.expectEmit(true, true, false, false);
        emit IERC721.Transfer(address(0), user, 0);

        settler.mintPosition(tokenA, tokenB, hasTokenASurplus ? 1_000_000 : 100, 200, user, data);
    }
}
