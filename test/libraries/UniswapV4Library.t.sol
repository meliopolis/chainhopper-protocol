// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Currency} from "@uniswap-v4-core/types/Currency.sol";
import {PoolKey} from "@uniswap-v4-core/types/PoolKey.sol";
import {IV4Router} from "@uniswap-v4-periphery/interfaces/IV4Router.sol";
import {SlippageCheck} from "@uniswap-v4-periphery/libraries/SlippageCheck.sol";
import {UniswapV4Library} from "../../src/libraries/UniswapV4Library.sol";
import {TestContext} from "../utils/TestContext.sol";

contract UniswapV4LibraryTest is TestContext {
    string public constant SRC_CHAIN_NAME = "BASE";
    string public constant DEST_CHAIN_NAME = "";

    mapping(Currency => bool) private isPermit2Approved;

    function setUp() public {
        _loadChain(SRC_CHAIN_NAME, DEST_CHAIN_NAME);

        UniswapV4Library.initializePool(v4PositionManager, v4FreshPoolKey, 1e18);
        if (UniswapV4Library.getPoolSqrtPriceX96(v4PositionManager, v4NativePoolKey) == 0) {
            UniswapV4Library.initializePool(v4PositionManager, v4NativePoolKey, 1e18);
        }
        if (UniswapV4Library.getPoolSqrtPriceX96(v4PositionManager, v4TokenPoolKey) == 0) {
            UniswapV4Library.initializePool(v4PositionManager, v4TokenPoolKey, 1e18);
        }
    }

    function test_fuzz_mintPosition(bool isTooMuchSlippage) public {
        deal(address(this), 100);
        deal(Currency.unwrap(v4NativePoolKey.currency1), address(this), 200);

        uint256 amount0Min = isTooMuchSlippage ? type(uint128).max : 0;
        uint256 amount1Min = isTooMuchSlippage ? type(uint128).max : 0;

        if (isTooMuchSlippage) {
            vm.expectRevert(abi.encodeWithSelector(UniswapV4Library.TooMuchSlippage.selector));
        }

        this.mintPositionWrapper(v4NativePoolKey, -600, 600, 100, 200, amount0Min, amount1Min, address(this));

        deal(Currency.unwrap(v4TokenPoolKey.currency0), address(this), 100);
        deal(Currency.unwrap(v4TokenPoolKey.currency1), address(this), 200);

        if (isTooMuchSlippage) {
            vm.expectRevert(abi.encodeWithSelector(UniswapV4Library.TooMuchSlippage.selector));
        }

        this.mintPositionWrapper(v4TokenPoolKey, -600, 600, 100, 200, amount0Min, amount1Min, address(this));
    }

    function test_mintPosition_belowSqrtPrice() public {
        deal(Currency.unwrap(v4TokenPoolKey.currency0), address(this), 100);
        deal(Currency.unwrap(v4TokenPoolKey.currency1), address(this), 200);

        this.mintPositionWrapper(v4TokenPoolKey, -1200, -900, 100, 200, 0, 0, address(this));
    }

    function test_mintPosition_aboveSqrtPrice() public {
        deal(Currency.unwrap(v4TokenPoolKey.currency0), address(this), 100);
        deal(Currency.unwrap(v4TokenPoolKey.currency1), address(this), 200);

        this.mintPositionWrapper(v4TokenPoolKey, 900, 1200, 100, 200, 0, 0, address(this));
    }

    function test_fuzz_liquidatePosition(bool hasMinAmounts) public {
        deal(address(this), 100);
        deal(Currency.unwrap(v4NativePoolKey.currency1), address(this), 200);

        uint256 amount0Min = hasMinAmounts ? type(uint128).max : 0;
        uint256 amount1Min = hasMinAmounts ? type(uint128).max : 0;

        (uint256 positionId,,,) = this.mintPositionWrapper(v4NativePoolKey, -600, 600, 100, 200, 0, 0, address(this));

        if (hasMinAmounts) {
            vm.expectPartialRevert(SlippageCheck.MinimumAmountInsufficient.selector);
        }

        this.liquidatePositionWrapper(positionId, amount0Min, amount1Min, address(this));

        deal(Currency.unwrap(v4TokenPoolKey.currency0), address(this), 100);
        deal(Currency.unwrap(v4TokenPoolKey.currency1), address(this), 200);

        (positionId,,,) = this.mintPositionWrapper(v4TokenPoolKey, -600, 600, 100, 200, 0, 0, address(this));

        if (hasMinAmounts) {
            vm.expectPartialRevert(SlippageCheck.MinimumAmountInsufficient.selector);
        }

        this.liquidatePositionWrapper(positionId, amount0Min, amount1Min, address(this));
    }

    function test_fuzz_swap(bool isZeroForOne, bool hasMinAmount) public {
        deal(address(this), 100);
        deal(Currency.unwrap(v4NativePoolKey.currency1), address(this), 200);

        uint256 amountOutMin = !hasMinAmount ? type(uint128).max : 0;

        if (!hasMinAmount) {
            vm.expectPartialRevert(IV4Router.V4TooLittleReceived.selector);
        }

        this.swapWrapper(v4NativePoolKey, isZeroForOne, 100, amountOutMin, address(this));

        deal(Currency.unwrap(v4TokenPoolKey.currency0), address(this), 100);
        deal(Currency.unwrap(v4TokenPoolKey.currency1), address(this), 200);

        if (!hasMinAmount) {
            vm.expectPartialRevert(IV4Router.V4TooLittleReceived.selector);
        }

        this.swapWrapper(v4TokenPoolKey, isZeroForOne, 100, amountOutMin, address(this));
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
    ) external returns (uint256, uint128, uint256, uint256) {
        return UniswapV4Library.mintPosition(
            v4PositionManager,
            permit2,
            isPermit2Approved,
            poolKey,
            tickLower,
            tickUpper,
            amount0Desired,
            amount1Desired,
            amount0Min,
            amount1Min,
            recipient
        );
    }

    function liquidatePositionWrapper(uint256 positionId, uint256 amount0Min, uint256 amount1Min, address recipient)
        external
        returns (PoolKey memory, uint256, uint256)
    {
        return UniswapV4Library.liquidatePosition(v4PositionManager, positionId, amount0Min, amount1Min, recipient);
    }

    function swapWrapper(
        PoolKey memory poolKey,
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOutMin,
        address recipient
    ) external returns (uint256 amountOut) {
        return UniswapV4Library.swap(
            universalRouter, permit2, isPermit2Approved, poolKey, zeroForOne, amountIn, amountOutMin, recipient
        );
    }
}
