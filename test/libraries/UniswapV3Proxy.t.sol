// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {V3SwapRouter} from "@uniswap-universal-router/modules/uniswap/v3/V3SwapRouter.sol";
// using v4 tick math as v3 contract has version conflict
import {TickMath} from "@uniswap-v4-core/libraries/TickMath.sol";
import {TestContext} from "../utils/TestContext.sol";

contract UniswapV3ProxyTest is TestContext {
    string private constant CHAIN_NAME = "BASE";

    function setUp() public {
        _loadChain(CHAIN_NAME);

        uniswapV3Proxy.createAndInitializePoolIfNecessary(
            usdc > usdt ? usdt : usdc, usdc > usdt ? usdc : usdt, 100, 1e18
        );
    }

    function test_fuzz_initialize(address positionManager, address universalRouter, address permit2) public {
        uniswapV3Proxy.initialize(positionManager, universalRouter, permit2);

        assertEq(address(uniswapV3Proxy.positionManager), positionManager);
        assertEq(address(uniswapV3Proxy.universalRouter), universalRouter);
        assertEq(address(uniswapV3Proxy.permit2), permit2);
    }

    function test_fuzz_createAndInitializePoolIfNecessary(address token0, address token1, uint160 sqrtPriceX96)
        public
    {
        vm.assume(token0 > address(0));
        vm.assume(token0 < token1);

        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE + 1, TickMath.MAX_SQRT_PRICE - 1));

        uniswapV3Proxy.createAndInitializePoolIfNecessary(token0, token1, 100, sqrtPriceX96);
    }

    function test_fuzz_mintPosition(bool isTooMuchSlippage) public {
        deal(usdc, address(this), 200);
        deal(usdt, address(this), 200);

        if (isTooMuchSlippage) {
            vm.expectRevert("Price slippage check");
        }

        this.mintPositionWrapper(
            usdc > usdt ? usdt : usdc,
            usdc > usdt ? usdc : usdt,
            100,
            -500,
            500,
            200,
            200,
            isTooMuchSlippage ? 201 : 0,
            isTooMuchSlippage ? 201 : 0,
            address(this)
        );
    }

    function test_fuzz_liquidatePosition(bool hasMinMounts) public {
        deal(usdc, address(this), 200);
        deal(usdt, address(this), 200);

        (uint256 positionId,,,) = this.mintPositionWrapper(
            usdc > usdt ? usdt : usdc, usdc > usdt ? usdc : usdt, 100, -500, 500, 200, 200, 0, 0, address(this)
        );

        if (hasMinMounts) {
            vm.expectRevert("Price slippage check");
        }

        this.liquidatePositionWrapper(positionId, hasMinMounts ? 201 : 0, hasMinMounts ? 201 : 0, address(this));
    }

    function test_fuzz_swap(bool isTooMuchSlippage) public {
        deal(usdc, address(this), 200);
        deal(usdt, address(this), 200);

        if (isTooMuchSlippage) {
            vm.expectRevert(abi.encodeWithSelector(V3SwapRouter.V3TooLittleReceived.selector));
        }

        this.swapWrapper(
            usdc > usdt ? usdt : usdc,
            usdc > usdt ? usdc : usdt,
            100,
            200,
            isTooMuchSlippage ? type(uint256).max : 0,
            address(this)
        );
    }

    function mintPositionWrapper(
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address recipient
    ) public returns (uint256 positionId, uint128 liquidity, uint256 amount0, uint256 amount1) {
        return uniswapV3Proxy.mintPosition(
            token0, token1, fee, tickLower, tickUpper, amount0Desired, amount1Desired, amount0Min, amount1Min, recipient
        );
    }

    function liquidatePositionWrapper(uint256 positionId, uint256 amount0Min, uint256 amount1Min, address recipient)
        public
        returns (address token0, address token1, uint24 fee, uint256 amount0, uint256 amount1)
    {
        return uniswapV3Proxy.liquidatePosition(positionId, amount0Min, amount1Min, recipient);
    }

    function swapWrapper(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint256 amountOutMinimum,
        address recipient
    ) public returns (uint256 amountOut) {
        return uniswapV3Proxy.swap(tokenIn, tokenOut, fee, amountIn, amountOutMinimum, recipient);
    }
}
