// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IPermit2} from "@uniswap-permit2/interfaces/IPermit2.sol";
import {IUniversalRouter} from "@uniswap-universal-router/interfaces/IUniversalRouter.sol";
import {Commands} from "@uniswap-universal-router/libraries/Commands.sol";
import {IHooks} from "@uniswap-v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap-v4-core/interfaces/IPoolManager.sol";
import {StateLibrary} from "@uniswap-v4-core/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap-v4-core/libraries/TickMath.sol";
import {Currency} from "@uniswap-v4-core/types/Currency.sol";
import {PoolKey} from "@uniswap-v4-core/types/PoolKey.sol";
import {IPositionManager} from "@uniswap-v4-periphery/interfaces/IPositionManager.sol";
import {IV4Router} from "@uniswap-v4-periphery/interfaces/IV4Router.sol";
import {Actions} from "@uniswap-v4-periphery/libraries/Actions.sol";
import {LiquidityAmounts} from "@uniswap-v4-periphery/libraries/LiquidityAmounts.sol";
import {IV4Settler} from "../interfaces/IV4Settler.sol";
import {Settler} from "./Settler.sol";

abstract contract V4Settler is IV4Settler, Settler {
    using SafeERC20 for IERC20;
    using StateLibrary for IPoolManager;

    IPositionManager private immutable positionManager;
    IUniversalRouter private immutable universalRouter;
    IPermit2 private immutable permit2;

    constructor(address _positionManager, address _universalRouter, address _permit2) {
        positionManager = IPositionManager(_positionManager);
        universalRouter = IUniversalRouter(_universalRouter);
        permit2 = IPermit2(_permit2);
    }

    function _settle(address token, uint256 amount, bytes memory message)
        internal
        override
        returns (uint256, address, address, uint128)
    {
        // decode settlement params and create pool key
        SettlementParams memory params = abi.decode(message, (SettlementParams));
        PoolKey memory poolKey = PoolKey(
            Currency.wrap(params.token0),
            Currency.wrap(params.token1),
            params.fee,
            params.tickSpacing,
            IHooks(params.hooks)
        );

        // calculate swap direction
        bool zeroForOne = token == params.token0;
        (Currency currencyIn, Currency currencyOut) =
            zeroForOne ? (poolKey.currency0, poolKey.currency1) : (poolKey.currency1, poolKey.currency0);

        // calculate amount in and out
        uint256 amountIn = amount - (zeroForOne ? params.amount0Min : params.amount1Min);
        uint256 amountOut;
        if (amountIn > 0) {
            // cache balance before swap
            uint256 balanceBefore = currencyOut.balanceOfSelf();

            uint128 amountOutMin = uint128(zeroForOne ? params.amount1Min : params.amount0Min);

            // approve token transfer via permit2
            IERC20(Currency.unwrap(currencyIn)).safeIncreaseAllowance(address(permit2), amountIn);
            permit2.approve(Currency.unwrap(currencyIn), address(positionManager), uint160(amountIn), 0);

            // prepare v4 router actions and params
            bytes memory actions = abi.encodePacked(
                bytes1(uint8(Actions.SWAP_EXACT_IN_SINGLE)),
                bytes1(uint8(Actions.TAKE_ALL)),
                bytes1(uint8(Actions.SETTLE))
            );
            bytes[] memory _params = new bytes[](3);
            _params[0] =
                abi.encode(IV4Router.ExactInputSingleParams(poolKey, zeroForOne, uint128(amountIn), amountOutMin, ""));
            _params[1] = abi.encode(Currency.unwrap(currencyOut), 0);
            _params[2] = abi.encode(Currency.unwrap(currencyIn), amountIn, true);

            // execute swap via universal router
            bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.V4_SWAP)));
            bytes[] memory inputs = new bytes[](1);
            inputs[0] = abi.encode(actions, _params);
            universalRouter.execute(commands, inputs, block.timestamp);

            // calculate amount out
            amountOut = currencyOut.balanceOfSelf() - balanceBefore;
        }

        return _settle(
            Currency.unwrap(currencyIn),
            Currency.unwrap(currencyOut),
            zeroForOne ? params.amount0Min : params.amount1Min,
            amountOut,
            message
        );
    }

    function _settle(address tokenA, address tokenB, uint256 amountA, uint256 amountB, bytes memory message)
        internal
        override
        returns (uint256, address, address, uint128)
    {
        // decode settlement params and create pool key
        SettlementParams memory params = abi.decode(message, (SettlementParams));
        PoolKey memory poolKey = PoolKey(
            Currency.wrap(params.token0),
            Currency.wrap(params.token1),
            params.fee,
            params.tickSpacing,
            IHooks(params.hooks)
        );

        if (tokenA != params.token0 && tokenA != params.token1) revert TokenNotUsed(tokenA);
        if (tokenB != params.token0 && tokenB != params.token1) revert TokenNotUsed(tokenB);

        // align amounts to settlement tokens
        (uint256 amount0, uint256 amount1) = tokenA == params.token0 ? (amountA, amountB) : (amountB, amountA);

        // cache balance before mint
        uint256 balance0Before = poolKey.currency0.balanceOfSelf();
        uint256 balance1Before = poolKey.currency1.balanceOfSelf();

        // approve token transfers via permit2
        IERC20(params.token0).safeIncreaseAllowance(address(permit2), amount0);
        permit2.approve(params.token0, address(positionManager), uint160(amount0), 0);
        IERC20(params.token0).safeIncreaseAllowance(address(permit2), amount1);
        permit2.approve(params.token0, address(positionManager), uint160(amount1), 0);

        // get position id
        uint256 positionId = positionManager.nextTokenId();

        // get liquidity
        (uint160 sqrtPriceX96,,,) = positionManager.poolManager().getSlot0(poolKey.toId());
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(params.tickLower),
            TickMath.getSqrtPriceAtTick(params.tickUpper),
            amount0,
            amount1
        );

        // mint position
        bytes memory actions =
            abi.encodePacked(bytes1(uint8(Actions.MINT_POSITION)), bytes1(uint8(Actions.SETTLE_PAIR)));
        bytes[] memory _params = new bytes[](2);
        _params[0] = abi.encode(
            poolKey, params.tickLower, params.tickUpper, liquidity, amount0, amount1, params.baseParams.recipient, ""
        );
        _params[1] = abi.encode(poolKey.currency0, poolKey.currency1);
        positionManager.modifyLiquidities(abi.encode(actions, _params), block.timestamp);

        // refund unused tokens
        uint256 balance0After = poolKey.currency0.balanceOfSelf();
        uint256 balance1After = poolKey.currency1.balanceOfSelf();
        if (balance0After + amount0 > balance0Before) {
            poolKey.currency0.transfer(params.baseParams.recipient, balance0After + amount0 - balance0Before);
        }
        if (balance1After + amount1 > balance1Before) {
            poolKey.currency1.transfer(params.baseParams.recipient, balance1After + amount1 - balance1Before);
        }

        return (positionId, params.token0, params.token1, liquidity);
    }
}
