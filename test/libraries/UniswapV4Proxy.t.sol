// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {console} from "@forge-std/console.sol";
import {IHooks} from "@uniswap-v4-core/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap-v4-core/libraries/LPFeeLibrary.sol";
import {TickMath} from "@uniswap-v4-core/libraries/TickMath.sol";
import {Currency} from "@uniswap-v4-core/types/Currency.sol";
import {PoolKey} from "@uniswap-v4-core/types/PoolKey.sol";
import {IV4Router} from "@uniswap-v4-periphery/interfaces/IV4Router.sol";
import {SlippageCheck} from "@uniswap-v4-periphery/libraries/SlippageCheck.sol";
import {UniswapV4Library} from "../../src/libraries/UniswapV4Proxy.sol";
import {TestContext} from "../utils/TestContext.sol";

contract UniswapV4ProxyTest is TestContext {
    string private constant CHAIN_NAME = "BASE";

    function setUp() public {
        _loadChain(CHAIN_NAME);

        if (uniswapV4Proxy.getPoolSqrtPriceX96(v4NativePoolKey) == 0) {
            uniswapV4Proxy.initializePool(v4NativePoolKey, 1e18);
        }
        if (uniswapV4Proxy.getPoolSqrtPriceX96(v4TokenPoolKey) == 0) {
            uniswapV4Proxy.initializePool(v4TokenPoolKey, 1e18);
        }
    }

    function test_fuzz_initialize(address positionManager, address universalRouter, address permit2) public {
        uniswapV4Proxy.initialize(positionManager, universalRouter, permit2);

        assertEq(address(uniswapV4Proxy.positionManager), positionManager);
        assertEq(address(uniswapV4Proxy.universalRouter), universalRouter);
        assertEq(address(uniswapV4Proxy.permit2), permit2);
    }

    function test_fuzz_initializePool(PoolKey memory poolKey, uint160 sqrtPriceX96) public {
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE));
        poolKey.fee = uint24(bound(poolKey.fee, 1, LPFeeLibrary.MAX_LP_FEE));
        poolKey.tickSpacing = int24(bound(poolKey.tickSpacing, TickMath.MIN_TICK_SPACING, TickMath.MAX_TICK_SPACING));

        (poolKey.currency0, poolKey.currency1) = poolKey.currency0 < poolKey.currency1
            ? (poolKey.currency0, poolKey.currency1)
            : (poolKey.currency1, poolKey.currency0);
        poolKey.hooks = IHooks(address(0));

        uniswapV4Proxy.initializePool(poolKey, sqrtPriceX96);

        assertEq(uniswapV4Proxy.getPoolSqrtPriceX96(poolKey), sqrtPriceX96);
    }

    function test_fuzz_mintPosition(bool isTooMuchSlippage) public {
        deal(address(this), 100);
        deal(Currency.unwrap(v4NativePoolKey.currency1), address(this), 200);

        if (isTooMuchSlippage) {
            vm.expectRevert(abi.encodeWithSelector(UniswapV4Library.TooMuchSlippage.selector));
        }

        this.mintPositionWrapper(
            v4NativePoolKey, -600, 600, 100, 200, isTooMuchSlippage ? 101 : 0, isTooMuchSlippage ? 201 : 0, user
        );

        deal(Currency.unwrap(v4TokenPoolKey.currency0), address(this), 100);
        deal(Currency.unwrap(v4TokenPoolKey.currency1), address(this), 200);

        if (isTooMuchSlippage) {
            vm.expectRevert(abi.encodeWithSelector(UniswapV4Library.TooMuchSlippage.selector));
        }

        this.mintPositionWrapper(
            v4TokenPoolKey, -600, 600, 100, 200, isTooMuchSlippage ? 101 : 0, isTooMuchSlippage ? 201 : 0, user
        );
    }

    function test_fuzz_liquidatePosition(bool hasMinAmounts) public {
        deal(address(this), 100);
        deal(Currency.unwrap(v4NativePoolKey.currency1), address(this), 200);

        (uint256 positionId,,,) = this.mintPositionWrapper(v4NativePoolKey, -600, 600, 100, 200, 0, 0, address(this));

        if (hasMinAmounts) {
            vm.expectPartialRevert(SlippageCheck.MinimumAmountInsufficient.selector);
        }

        this.liquidatePositionWrapper(positionId, hasMinAmounts ? 101 : 0, hasMinAmounts ? 201 : 0, user);

        deal(Currency.unwrap(v4TokenPoolKey.currency0), address(this), 100);
        deal(Currency.unwrap(v4TokenPoolKey.currency1), address(this), 200);

        (positionId,,,) = this.mintPositionWrapper(v4TokenPoolKey, -600, 600, 100, 200, 0, 0, address(this));

        if (hasMinAmounts) {
            vm.expectPartialRevert(SlippageCheck.MinimumAmountInsufficient.selector);
        }

        this.liquidatePositionWrapper(positionId, hasMinAmounts ? 101 : 0, hasMinAmounts ? 201 : 0, user);
    }

    function test_fuzz_swap(bool hasMinAmount) public {
        deal(address(this), 100);
        deal(Currency.unwrap(v4NativePoolKey.currency1), address(this), 200);

        if (hasMinAmount) {
            vm.expectPartialRevert(IV4Router.V4TooLittleReceived.selector);
        }

        this.swapWrapper(v4NativePoolKey, true, 100, hasMinAmount ? type(uint256).max : 0, address(this));

        deal(Currency.unwrap(v4TokenPoolKey.currency0), address(this), 100);
        deal(Currency.unwrap(v4TokenPoolKey.currency1), address(this), 200);

        if (hasMinAmount) {
            vm.expectPartialRevert(IV4Router.V4TooLittleReceived.selector);
        }

        this.swapWrapper(v4TokenPoolKey, true, 100, hasMinAmount ? type(uint256).max : 0, address(this));
    }

    function mintPositionWrapper(
        PoolKey memory poolKey,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address recipient
    ) external returns (uint256 positionId, uint128 liquidity, uint256 amount0, uint256 amount1) {
        return uniswapV4Proxy.mintPosition(
            poolKey, tickLower, tickUpper, amount0Desired, amount1Desired, amount0Min, amount1Min, recipient
        );
    }

    function liquidatePositionWrapper(uint256 positionId, uint256 amount0Min, uint256 amount1Min, address recipient)
        external
        returns (PoolKey memory poolKey, uint256 amount0, uint256 amount1)
    {
        return uniswapV4Proxy.liquidatePosition(positionId, amount0Min, amount1Min, recipient);
    }

    function swapWrapper(
        PoolKey memory poolKey,
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOutMin,
        address recipient
    ) external returns (uint256 amountOut) {
        return uniswapV4Proxy.swap(poolKey, zeroForOne, amountIn, amountOutMin, recipient);
    }
}
