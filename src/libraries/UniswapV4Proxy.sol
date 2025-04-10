// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
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

/// @title UniswapV4Proxy
/// @notice Proxy for Uniswap V4
struct UniswapV4Proxy {
    /// @notice The position manager
    IPositionManager positionManager;
    /// @notice The universal router
    IUniversalRouter universalRouter;
    /// @notice The permit2
    IPermit2 permit2;
    /// @notice Whether the permit2 is approved for the token
    mapping(Currency => bool) isPermit2Approved;
}

using UniswapV4Library for UniswapV4Proxy global;

/// @title UniswapV4Library
/// @notice Library for Uniswap V4
library UniswapV4Library {
    using StateLibrary for IPoolManager;

    /// @notice Error thrown when the proxy is already initialized
    error AlreadyInitialized();
    /// @notice Error thrown when the slippage is too high
    error TooMuchSlippage();

    /// @notice Initialize the proxy
    /// @param self The proxy
    /// @param positionManager The position manager
    /// @param universalRouter The universal router
    /// @param permit2 The permit2
    function initialize(UniswapV4Proxy storage self, address positionManager, address universalRouter, address permit2)
        internal
    {
        if (address(self.positionManager) != address(0)) revert AlreadyInitialized();

        self.positionManager = IPositionManager(positionManager);
        self.universalRouter = IUniversalRouter(universalRouter);
        self.permit2 = IPermit2(permit2);
    }

    /// @notice Initialize a pool
    /// @param self The proxy
    /// @param poolKey The PoolKey
    /// @param sqrtPriceX96 The sqrtPriceX96
    function initializePool(UniswapV4Proxy storage self, PoolKey memory poolKey, uint160 sqrtPriceX96) internal {
        // create and initialize pool
        self.positionManager.initializePool(poolKey, sqrtPriceX96);
    }

    /// @notice Mint a position
    /// @param self The proxy
    /// @param poolKey The PoolKey
    /// @param tickLower The tick lower
    /// @param tickUpper The tick upper
    /// @param amount0Desired The amount of token0 desired
    /// @param amount1Desired The amount of token1 desired
    function mintPosition(
        UniswapV4Proxy storage self,
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
            self.approve(poolKey.currency0, address(self.positionManager), amount0Desired);
        }
        self.approve(poolKey.currency1, address(self.positionManager), amount1Desired);

        // get position id
        positionId = self.positionManager.nextTokenId();

        // calculate liquidity
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            self.getPoolSqrtPriceX96(poolKey),
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
        self.positionManager.modifyLiquidities{value: value}(abi.encode(actions, params), block.timestamp);

        // calculate amounts
        amount0 = balance0Before - poolKey.currency0.balanceOfSelf();
        amount1 = balance1Before - poolKey.currency1.balanceOfSelf();

        if (amount0 < amount0Min || amount1 < amount1Min) revert TooMuchSlippage();
    }

    /// @notice Liquidate a position
    /// @param self The proxy
    /// @param positionId The position id
    /// @param amount0Min The minimum amount of token0
    /// @param amount1Min The minimum amount of token1
    /// @param recipient The recipient
    function liquidatePosition(
        UniswapV4Proxy storage self,
        uint256 positionId,
        uint256 amount0Min,
        uint256 amount1Min,
        address recipient
    ) internal returns (PoolKey memory poolKey, uint256 amount0, uint256 amount1) {
        // get pool key
        (poolKey,) = self.positionManager.getPoolAndPositionInfo(positionId);

        // cache balances before liquidation
        uint256 balance0Before = poolKey.currency0.balanceOf(recipient);
        uint256 balance1Before = poolKey.currency1.balanceOf(recipient);

        // liquidate position
        bytes memory actions = abi.encodePacked(bytes1(uint8(Actions.BURN_POSITION)), bytes1(uint8(Actions.TAKE_PAIR)));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(positionId, amount0Min, amount1Min, "");
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1, recipient);
        self.positionManager.modifyLiquidities(abi.encode(actions, params), block.timestamp);

        // calculate amounts
        amount0 = poolKey.currency0.balanceOf(recipient) - balance0Before;
        amount1 = poolKey.currency1.balanceOf(recipient) - balance1Before;
    }

    /// @notice Swap tokens
    /// @param self The proxy
    /// @param poolKey The PoolKey
    /// @param zeroForOne The direction of the swap
    /// @param amountIn The amount of input tokens
    /// @param amountOutMin The minimum amount of output tokens
    /// @param recipient The recipient
    function swap(
        UniswapV4Proxy storage self,
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
            self.approve(currencyIn, address(self.universalRouter), amountIn);
        }

        // prepare v4 router actions and params
        bytes memory actions = abi.encodePacked(
            bytes1(uint8(Actions.SWAP_EXACT_IN_SINGLE)),
            bytes1(uint8(Actions.TAKE_ALL)),
            bytes1(uint8(Actions.SETTLE_ALL))
        );
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams(poolKey, zeroForOne, uint128(amountIn), uint128(amountOutMin), "")
        );
        params[1] = abi.encode(currencyOut, 0);
        params[2] = abi.encode(currencyIn, amountIn);

        // execute swap via universal router
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.V4_SWAP)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
        self.universalRouter.execute{value: value}(commands, inputs, block.timestamp);

        // calculate amount out
        amountOut = currencyOut.balanceOf(recipient) - balanceBefore;
    }

    /// @notice Get the sqrtPriceX96
    /// @param self The proxy
    /// @param poolKey The PoolKey
    /// @return sqrtPriceX96 The sqrtPriceX96
    function getPoolSqrtPriceX96(UniswapV4Proxy storage self, PoolKey memory poolKey)
        internal
        view
        returns (uint160 sqrtPriceX96)
    {
        (sqrtPriceX96,,,) = self.positionManager.poolManager().getSlot0(poolKey.toId());
    }

    /// @notice Approve a currency
    /// @param self The proxy
    /// @param currency The currency
    /// @param spender The spender
    /// @param amount The amount
    function approve(UniswapV4Proxy storage self, Currency currency, address spender, uint256 amount) internal {
        if (!self.isPermit2Approved[currency]) {
            IERC20(Currency.unwrap(currency)).approve(address(self.permit2), type(uint256).max);
            self.isPermit2Approved[currency] = true;
        }
        self.permit2.approve(Currency.unwrap(currency), spender, uint160(amount), uint48(block.timestamp));
    }
}
