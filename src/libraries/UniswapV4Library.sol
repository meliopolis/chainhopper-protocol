// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/utils/math/SafeCast.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IPermit2} from "@uniswap-permit2/interfaces/IPermit2.sol";
import {IUniversalRouter} from "@uniswap-universal-router/interfaces/IUniversalRouter.sol";
import {Commands} from "@uniswap-universal-router/libraries/Commands.sol";
import {IPoolManager} from "@uniswap-v4-core/interfaces/IPoolManager.sol";
import {StateLibrary} from "@uniswap-v4-core/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap-v4-core/libraries/TickMath.sol";
import {Currency} from "@uniswap-v4-core/types/Currency.sol";
import {PoolKey} from "@uniswap-v4-core/types/PoolKey.sol";
import {IPositionManager} from "@uniswap-v4-periphery/interfaces/IPositionManager.sol";
import {IV4Router} from "@uniswap-v4-periphery/interfaces/IV4Router.sol";
import {Actions} from "@uniswap-v4-periphery/libraries/Actions.sol";
import {LiquidityAmounts} from "@uniswap-v4-periphery/libraries/LiquidityAmounts.sol";

/// @title UniswapV4Library
/// @notice Library for Uniswap V4
library UniswapV4Library {
    using StateLibrary for IPoolManager;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    /// @notice Error thrown when the slippage is too high
    error TooMuchSlippage();

    /// @notice Initialize a pool
    /// @param positionManager The position manager
    /// @param poolKey The PoolKey
    /// @param sqrtPriceX96 The sqrtPriceX96
    function initializePool(IPositionManager positionManager, PoolKey memory poolKey, uint160 sqrtPriceX96) internal {
        // create and initialize pool
        positionManager.initializePool(poolKey, sqrtPriceX96);
    }

    /// @notice Mint a position
    /// @param positionManager The position manager
    /// @param permit2 The permit2
    /// @param isPermit2Approved The mapping of approved tokens
    /// @param poolKey The PoolKey
    /// @param tickLower The tick lower
    /// @param tickUpper The tick upper
    /// @param amount0Desired The amount of token0 desired
    /// @param amount1Desired The amount of token1 desired
    function mintPosition(
        IPositionManager positionManager,
        IPermit2 permit2,
        mapping(Currency => bool) storage isPermit2Approved,
        PoolKey memory poolKey,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address recipient
    ) internal returns (uint256 positionId, uint128 liquidity, uint256 amount0, uint256 amount1) {
        // cache balances before mint
        uint256 balance0Before = poolKey.currency0.balanceOfSelf();
        uint256 balance1Before = poolKey.currency1.balanceOfSelf();

        // set transaction value and approve token transfers via permit2
        uint256 value;
        if (poolKey.currency0.isAddressZero()) {
            value = amount0Desired;
        } else {
            approve(permit2, isPermit2Approved, poolKey.currency0, address(positionManager), amount0Desired);
        }
        approve(permit2, isPermit2Approved, poolKey.currency1, address(positionManager), amount1Desired);

        // get position id
        positionId = positionManager.nextTokenId();

        // calculate liquidity
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            getPoolSqrtPriceX96(positionManager, poolKey),
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0Desired,
            amount1Desired
        );

        // mint position
        bytes memory actions =
            abi.encodePacked(bytes1(uint8(Actions.MINT_POSITION)), bytes1(uint8(Actions.SETTLE_PAIR)));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(poolKey, tickLower, tickUpper, liquidity, amount0Desired, amount1Desired, recipient, "");
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);
        positionManager.modifyLiquidities{value: value}(abi.encode(actions, params), block.timestamp);

        // calculate amounts
        amount0 = balance0Before - poolKey.currency0.balanceOfSelf();
        amount1 = balance1Before - poolKey.currency1.balanceOfSelf();

        if (amount0 < amount0Min || amount1 < amount1Min) revert TooMuchSlippage();
    }

    /// @notice Liquidate a position
    /// @param positionManager The position manager
    /// @param positionId The position id
    /// @param amount0Min The minimum amount of token0
    /// @param amount1Min The minimum amount of token1
    /// @param recipient The recipient
    function liquidatePosition(
        IPositionManager positionManager,
        uint256 positionId,
        uint256 amount0Min,
        uint256 amount1Min,
        address recipient
    ) internal returns (PoolKey memory poolKey, uint256 amount0, uint256 amount1) {
        // get pool key
        (poolKey,) = positionManager.getPoolAndPositionInfo(positionId);

        // cache balances before liquidation
        uint256 balance0Before = poolKey.currency0.balanceOf(recipient);
        uint256 balance1Before = poolKey.currency1.balanceOf(recipient);

        // liquidate position
        bytes memory actions = abi.encodePacked(bytes1(uint8(Actions.BURN_POSITION)), bytes1(uint8(Actions.TAKE_PAIR)));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(positionId, amount0Min, amount1Min, "");
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1, recipient);
        positionManager.modifyLiquidities(abi.encode(actions, params), block.timestamp);

        // calculate amounts
        amount0 = poolKey.currency0.balanceOf(recipient) - balance0Before;
        amount1 = poolKey.currency1.balanceOf(recipient) - balance1Before;
    }

    /// @notice Swap tokens
    /// @param universalRouter The universal router
    /// @param permit2 The permit2
    /// @param isPermit2Approved The mapping of approved tokens
    /// @param poolKey The PoolKey
    /// @param zeroForOne The direction of the swap
    /// @param amountIn The amount of input tokens
    /// @param amountOutMin The minimum amount of output tokens
    /// @param recipient The recipient
    function swap(
        IUniversalRouter universalRouter,
        IPermit2 permit2,
        mapping(Currency => bool) storage isPermit2Approved,
        PoolKey memory poolKey,
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOutMin,
        address recipient
    ) internal returns (uint256 amountOut) {
        // get currency in and out and cache balance before swap
        (Currency currencyIn, Currency currencyOut) =
            zeroForOne ? (poolKey.currency0, poolKey.currency1) : (poolKey.currency1, poolKey.currency0);
        uint256 balanceBefore = currencyOut.balanceOf(recipient);

        // set transaction value or approve token transfer via permit2
        uint256 value;
        if (currencyIn.isAddressZero()) {
            value = amountIn;
        } else {
            approve(permit2, isPermit2Approved, currencyIn, address(universalRouter), amountIn);
        }

        // prepare v4 router actions and params
        bytes memory actions = abi.encodePacked(
            bytes1(uint8(Actions.SWAP_EXACT_IN_SINGLE)),
            bytes1(uint8(Actions.TAKE_ALL)),
            bytes1(uint8(Actions.SETTLE_ALL))
        );
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams(poolKey, zeroForOne, amountIn.toUint128(), amountOutMin.toUint128(), "")
        );
        params[1] = abi.encode(currencyOut, 0);
        params[2] = abi.encode(currencyIn, amountIn);

        // execute swap via universal router
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.V4_SWAP)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
        universalRouter.execute{value: value}(commands, inputs, block.timestamp);

        // calculate amount out
        amountOut = currencyOut.balanceOf(recipient) - balanceBefore;
    }

    /// @notice Get the sqrtPriceX96
    /// @param positionManager The position manager
    /// @param poolKey The PoolKey
    /// @return sqrtPriceX96 The sqrtPriceX96
    function getPoolSqrtPriceX96(IPositionManager positionManager, PoolKey memory poolKey)
        internal
        view
        returns (uint160 sqrtPriceX96)
    {
        (sqrtPriceX96,,,) = positionManager.poolManager().getSlot0(poolKey.toId());
    }

    /// @notice Approve a currency
    /// @param permit2 The permit2
    /// @param isPermit2Approved The mapping of approved tokens
    /// @param currency The currency
    /// @param spender The spender
    /// @param amount The amount
    function approve(
        IPermit2 permit2,
        mapping(Currency => bool) storage isPermit2Approved,
        Currency currency,
        address spender,
        uint256 amount
    ) internal {
        if (!isPermit2Approved[currency]) {
            IERC20(Currency.unwrap(currency)).forceApprove(address(permit2), type(uint256).max);
            isPermit2Approved[currency] = true;
        }
        permit2.approve(Currency.unwrap(currency), spender, amount.toUint160(), uint48(block.timestamp));
    }
}
