// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.28;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {AcrossV3Settler} from "./base/AcrossV3Settler.sol";
import {IUniswapV3PositionManager, ISwapRouter} from "./interfaces/external/IUniswapV3.sol";
import {ISingleTokenV3Settler} from "./interfaces/ISingleTokenV3Settler.sol";
import {BasisPoints} from "./libraries/BasisPoints.sol";
import {FixedPoint96} from "./libraries/FixedPoint96.sol";
import {FullMath} from "./libraries/FullMath.sol";
import {TickMath} from "./libraries/TickMath.sol";
import {UniswapV3Library} from "./libraries/UniswapV3Library.sol";

contract SingleTokenV3Settler is ISingleTokenV3Settler, AcrossV3Settler {
    using SafeERC20 for IERC20;
    using UniswapV3Library for IUniswapV3PositionManager;
    using UniswapV3Library for ISwapRouter;

    IUniswapV3PositionManager private immutable positionManager;
    ISwapRouter private immutable swapRouter;

    constructor(address _positionManager, address _swapRouter, address _spokePool) AcrossV3Settler(_spokePool) {
        positionManager = IUniswapV3PositionManager(_positionManager);
        swapRouter = ISwapRouter(_swapRouter);
    }

    function _settle(address token, uint256 amount, bytes memory message) internal override {
        SettlementParams memory params = abi.decode(message, (SettlementParams));

        // get current sqrtPriceX96 and tick
        (uint160 sqrtPriceX96, int24 tick) =
            positionManager.getCurrentSqrtPriceAndTick(params.token0, params.token1, params.fee);

        uint256 amount0;
        uint256 amount1;
        if (tick < params.tickLower) {
            amount0 = token == params.token0
                ? amount
                : swapRouter.swap(params.token1, params.token0, params.fee, amount, type(uint160).max);
        } else if (tick < params.tickUpper) {
            // get tokens's value ratios in the position
            (uint256 valueRatio0Bps, uint256 valueRatio1Bps) = _getValueRatios(
                sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(params.tickLower),
                TickMath.getSqrtPriceAtTick(params.tickUpper)
            );

            // swap token according to value ratio
            if (token == params.token0) {
                uint256 swapAmount = amount * valueRatio1Bps / BasisPoints.UNIT;
                amount0 = amount - swapAmount;
                amount1 = swapRouter.swap(params.token0, params.token1, params.fee, swapAmount, 0);
            } else {
                uint256 swapAmount = amount * valueRatio0Bps / BasisPoints.UNIT;
                amount0 = swapRouter.swap(params.token1, params.token0, params.fee, swapAmount, type(uint160).max);
                amount1 = amount - swapAmount;
            }
        } else {
            amount1 =
                token == params.token1 ? amount : swapRouter.swap(params.token0, params.token1, params.fee, amount, 0);
        }

        // mint the new position
        (uint256 amount0Paid, uint256 amount1Paid) = positionManager.mintPosition(
            params.token0,
            params.token1,
            params.fee,
            params.tickLower,
            params.tickUpper,
            amount0,
            amount1,
            params.recipient
        );

        // refund any leftovers
        if (amount0Paid < amount0) IERC20(params.token0).safeTransfer(params.recipient, amount0 - amount0Paid);
        if (amount1Paid < amount1) IERC20(params.token1).safeTransfer(params.recipient, amount1 - amount1Paid);
    }

    function _getValueRatios(uint160 sqrtPriceX96, uint160 sqrtPriceLowerX96, uint160 sqrtPriceUpperX96)
        private
        pure
        returns (uint256 value0RatioBps, uint256 value1RatioBps)
    {
        // amounts (per unit of liquidity)
        uint256 amount0 = (sqrtPriceUpperX96 - sqrtPriceX96) / (sqrtPriceUpperX96 * sqrtPriceX96);
        uint256 amount1 = (sqrtPriceX96 - sqrtPriceLowerX96);

        // total value (in token1)
        uint256 totalValue = FullMath.mulDiv(amount0, sqrtPriceX96 ** 2, FixedPoint96.UNIT ** 2) + amount1;

        value1RatioBps = FullMath.mulDiv(amount1, BasisPoints.UNIT, totalValue);
        value0RatioBps = BasisPoints.UNIT - value1RatioBps;
    }
}
