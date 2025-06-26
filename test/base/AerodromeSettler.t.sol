// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";
import {IAerodromeSettler} from "../../src/interfaces/IAerodromeSettler.sol";
import {MockAerodromeSettler} from "../mocks/MockAerodromeSettler.sol";
import {TestContext} from "../utils/TestContext.sol";

contract AerodromeSettlerTest is TestContext {
    string public constant SRC_CHAIN_NAME = "BASE";
    string public constant DEST_CHAIN_NAME = "";

    MockAerodromeSettler settler;
    address private aerodromePositionManager;
    int24 private tickSpacing = 100; // Default tick spacing for Aerodrome
    uint160 private sqrtPriceX96 = 79228162514264337593543950336; // 1:1 price ratio

    function setUp() public {
        _loadChain(SRC_CHAIN_NAME, DEST_CHAIN_NAME);

        // Set up Aerodrome position manager
        aerodromePositionManager = vm.envAddress(string(abi.encodePacked(SRC_CHAIN_NAME, "_AERODROME_POSITION_MANAGER")));

        settler = new MockAerodromeSettler(
            owner, 
            aerodromePositionManager, 
            address(universalRouter), 
            address(permit2)
        );
    }

    function test_mintPosition_singleRoute_fails_ifTokenIsUnused() public {
        bytes memory data = abi.encode(
            IAerodromeSettler.MintParams(
                weth, 
                usdc, 
                tickSpacing, 
                sqrtPriceX96, 
                -600, 
                600, 
                5_000_000, 
                0, 
                0
            )
        );

        vm.expectRevert(abi.encodeWithSelector(IAerodromeSettler.UnusedToken.selector, usdt));

        settler.mintPosition(usdt, 100, user, data);
    }

    function test_fuzz_mintPosition_singleRoute(bool isToken0) public {
        (address token0, address token1) = weth < usdc ? (weth, usdc) : (usdc, weth);
        address token = isToken0 ? token0 : token1;
        deal(token, address(settler), 100);

        bytes memory data = abi.encode(
            IAerodromeSettler.MintParams(
                token0, 
                token1, 
                tickSpacing, 
                0, 
                -600, 
                600, 
                5_000_000, 
                0, 
                0
            )
        );

        vm.expectEmit(true, true, false, false);
        emit IERC721.Transfer(address(0), user, 0);

        settler.mintPosition(token, 100, user, data);
    }

    function test_mintPosition_dualRoute_fails_ifTokenAIsUnused() public {
        bytes memory data = abi.encode(
            IAerodromeSettler.MintParams(
                weth, 
                usdc, 
                tickSpacing, 
                sqrtPriceX96, 
                -600, 
                600, 
                5_000_000, 
                0, 
                0
            )
        );

        vm.expectRevert(abi.encodeWithSelector(IAerodromeSettler.UnusedToken.selector, usdt));

        settler.mintPosition(usdt, usdc, 100, 200, user, data);
    }

    function test_mintPosition_dualRoute_fails_ifTokenBIsUnused() public {
        bytes memory data = abi.encode(
            IAerodromeSettler.MintParams(
                weth, 
                usdc, 
                tickSpacing, 
                sqrtPriceX96, 
                -600, 
                600, 
                5_000_000, 
                0, 
                0
            )
        );

        vm.expectRevert(abi.encodeWithSelector(IAerodromeSettler.UnusedToken.selector, usdt));

        settler.mintPosition(weth, usdt, 100, 200, user, data);
    }

    function test_fuzz_mintPosition_dualRoute(bool areTokensInOrder, bool hasTokenASurplus) public {
        (address token0, address token1) = usdc < usdt ? (usdc, usdt) : (usdt, usdc);
        (address tokenA, address tokenB) = areTokensInOrder ? (token0, token1) : (token1, token0);
        deal(tokenA, address(settler), hasTokenASurplus ? 1_000_000 : 100);
        deal(tokenB, address(settler), 200);

        bytes memory data = abi.encode(
            IAerodromeSettler.MintParams(
                token0, 
                token1, 
                tickSpacing, 
                sqrtPriceX96, 
                -600, 
                600, 
                5_000_000, 
                0, 
                0
            )
        );

        vm.expectEmit(true, true, false, false);
        emit IERC721.Transfer(address(0), user, 0);

        settler.mintPosition(tokenA, tokenB, hasTokenASurplus ? 1_000_000 : 100, 200, user, data);
    }

    function test_mintPosition_withSwap() public {
        (address token0, address token1) = weth < usdc ? (weth, usdc) : (usdc, weth);
        address token = token0;
        deal(token, address(settler), 1000);

        bytes memory data = abi.encode(
            IAerodromeSettler.MintParams(
                token0, 
                token1, 
                tickSpacing, 
                0, 
                -600, 
                600, 
                5_000_000, // 50% swap
                0, 
                0
            )
        );

        vm.expectEmit(true, true, false, false);
        emit IERC721.Transfer(address(0), user, 0);

        settler.mintPosition(token, 1000, user, data);
    }

    function test_mintPosition_withoutSwap() public {
        (address token0, address token1) = weth < usdc ? (weth, usdc) : (usdc, weth);
        address token = token0;
        deal(token, address(settler), 1000);

        bytes memory data = abi.encode(
            IAerodromeSettler.MintParams(
                token0, 
                token1, 
                tickSpacing, 
                0, 
                -600, 
                600, 
                0, // No swap
                0, 
                0
            )
        );

        vm.expectEmit(true, true, false, false);
        emit IERC721.Transfer(address(0), user, 0);

        settler.mintPosition(token, 1000, user, data);
    }

    function test_mintPosition_withMinimumAmounts() public {
        (address token0, address token1) = weth < usdc ? (weth, usdc) : (usdc, weth);
        deal(token0, address(settler), 1000000000000000000);
        deal(token1, address(settler), 1000000000000000000);

        bytes memory data = abi.encode(
            IAerodromeSettler.MintParams(
                token0, 
                token1, 
                tickSpacing, 
                0, 
                -300000, 
                300000, 
                5_000_000, 
                100, // Minimum amount0
                100  // Minimum amount1
            )
        );

        vm.expectEmit(true, true, false, false);
        emit IERC721.Transfer(address(0), user, 0);

        settler.mintPosition(token0, token1, 1000000000000000000, 1000000000000000000, user, data);
    }

    function test_mintPosition_withDifferentTickRanges() public {
        (address token0, address token1) = weth < usdc ? (weth, usdc) : (usdc, weth);
        deal(token0, address(settler), 1000000000000000000);
        deal(token1, address(settler), 1000000000000000000);

        int24[] memory tickRanges = new int24[](3);
        tickRanges[0] = 300000;  // Narrow range
        tickRanges[1] = 400000;
        tickRanges[2] = 700000;  // Wide range

        for (uint i = 0; i < tickRanges.length; i++) {
            bytes memory data = abi.encode(
                IAerodromeSettler.MintParams(
                    token0, 
                    token1, 
                    tickSpacing, 
                    0, 
                    -tickRanges[i], 
                    tickRanges[i], 
                    0, 
                    0, 
                    0
                )
            );

            vm.expectEmit(true, true, false, false);
            emit IERC721.Transfer(address(0), user, 0);

            settler.mintPosition(token0, token1, 1000000, 10000000, user, data);
        }
    }

    function test_mintPosition_withSqrtPriceX96() public {
        (address token0, address token1) = usdc < usdt ? (usdc, usdt) : (usdt, usdc);
        deal(token0, address(settler), 1000000000000000000);
        deal(token1, address(settler), 1000000000000000000);

        bytes memory data = abi.encode(
            IAerodromeSettler.MintParams(
                token0, 
                token1, 
                tickSpacing, 
                sqrtPriceX96,
                -600, 
                600, 
                0, 
                0, 
                0
            )
        );

        vm.expectEmit(true, true, false, false);
        emit IERC721.Transfer(address(0), user, 0);

        settler.mintPosition(token0, token1, 1000, 1000, user, data);
    }
} 