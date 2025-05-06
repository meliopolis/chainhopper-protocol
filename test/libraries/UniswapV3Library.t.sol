// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {SafeCast} from "@openzeppelin/utils/math/SafeCast.sol";
import {V3SwapRouter} from "@uniswap-universal-router/modules/uniswap/v3/V3SwapRouter.sol";
// // using v4 tick math as v3 contract has version conflict
import {TickMath} from "@uniswap-v4-core/libraries/TickMath.sol";
import {UniswapV3Library} from "../../src/libraries/UniswapV3Library.sol";
import {TestContext} from "../utils/TestContext.sol";

contract UniswapV3LibraryTest is TestContext {
    string public constant SRC_CHAIN_NAME = "BASE";
    string public constant DEST_CHAIN_NAME = "UNICHAIN";

    address private token0;
    address private token1;
    uint24 private fee;
    uint160 private sqrtPriceX96;
    mapping(address => bool) private isPermit2Approved;

    function setUp() public {
        _loadChain(SRC_CHAIN_NAME, DEST_CHAIN_NAME);

        token0 = usdc < usdt ? usdc : usdt;
        token1 = usdc > usdt ? usdc : usdt;
        fee = 100;
        sqrtPriceX96 = 1e18;

        UniswapV3Library.createAndInitializePoolIfNecessary(v3PositionManager, token0, token1, fee, sqrtPriceX96);
    }

    function test_fuzz_mintPosition(bool extraOnZero, bool isTooMuchSlippage) public {
        deal(token0, address(this), 200);
        deal(token1, address(this), 200);

        uint256 amount0Min = isTooMuchSlippage ? 201 : 0;
        uint256 amount1Min = isTooMuchSlippage ? 201 : 0;

        if (isTooMuchSlippage) {
            vm.expectRevert("Price slippage check");
        }

        this.mintPositionWrapper(-600, 600, extraOnZero ? 200 : 100, extraOnZero ? 100 : 200, amount0Min, amount1Min);
    }

    function test_fuzz_liquidatePosition(bool hasMinMounts) public {
        deal(token0, address(this), 200);
        deal(token1, address(this), 200);

        (uint256 positionId,,,) = this.mintPositionWrapper(-600, 600, 200, 200, 0, 0);

        if (hasMinMounts) {
            vm.expectRevert("Price slippage check");
        }

        this.liquidatePositionWrapper(positionId, hasMinMounts ? 201 : 0, hasMinMounts ? 201 : 0);
    }

    function test_fuzz_swap(bool isZeroForOne, bool isTooMuchSlippage) public {
        deal(token0, address(this), 200);
        deal(token1, address(this), 200);

        address tokenIn = isZeroForOne ? token0 : token1;
        address tokenOut = isZeroForOne ? token1 : token0;

        if (isTooMuchSlippage) {
            vm.expectRevert(abi.encodeWithSelector(V3SwapRouter.V3TooLittleReceived.selector));
        }

        this.swapWrapper(tokenIn, tokenOut, 200, isTooMuchSlippage ? type(uint256).max : 0);
    }

    function mintPositionWrapper(
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    ) public returns (uint256, uint128, uint256, uint256) {
        return UniswapV3Library.mintPosition(
            v3PositionManager,
            token0,
            token1,
            fee,
            tickLower,
            tickUpper,
            amount0Desired,
            amount1Desired,
            amount0Min,
            amount1Min,
            address(this)
        );
    }

    function liquidatePositionWrapper(uint256 positionId, uint256 amount0Min, uint256 amount1Min)
        public
        returns (address, address, uint24, uint256, uint256)
    {
        return UniswapV3Library.liquidatePosition(v3PositionManager, positionId, amount0Min, amount1Min, address(this));
    }

    function swapWrapper(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin)
        public
        returns (uint256)
    {
        return UniswapV3Library.swap(
            universalRouter, permit2, isPermit2Approved, tokenIn, tokenOut, fee, amountIn, amountOutMin, address(this)
        );
    }
}
