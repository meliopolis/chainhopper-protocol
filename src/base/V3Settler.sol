// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IPermit2} from "@uniswap-permit2/interfaces/IPermit2.sol";
import {IUniversalRouter} from "@uniswap-universal-router/interfaces/IUniversalRouter.sol";
import {Commands} from "@uniswap-universal-router/libraries/Commands.sol";
// copied and modified from uniswap-v3-periphery, as the original had bad imports
import {INonfungiblePositionManager as IPositionManager} from "../interfaces/external/INonfungiblePositionManager.sol";
import {IV3Settler} from "../interfaces/IV3Settler.sol";
import {Settler} from "./Settler.sol";

abstract contract V3Settler is IV3Settler, Settler {
    using SafeERC20 for IERC20;

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
        returns (uint256, address, address, uint256, uint256, uint256, uint256)
    {
        // decode settlement params
        SettlementParams memory params = abi.decode(message, (SettlementParams));

        // calculate swap direction
        bool zeroForOne = token == params.token0;
        uint256 amountNotIn = zeroForOne ? params.amount0Min : params.amount1Min;
        (address tokenIn, address tokenOut) = zeroForOne ? (token, params.token1) : (params.token0, token);

        // calculate amount in and out
        uint256 amountIn = amount - amountNotIn;
        uint256 amountOut;
        if (amountIn > 0) {
            // cache balance before swap
            uint256 balanceBefore = IERC20(tokenOut).balanceOf(address(this));

            // approve token transfer via permit2
            IERC20(tokenIn).approve(address(permit2), amountIn);
            permit2.approve(tokenIn, address(positionManager), uint160(amountIn), 0);

            // execute swap via universal router
            bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.V3_SWAP_EXACT_IN)));
            bytes[] memory inputs = new bytes[](1);
            inputs[0] = abi.encode(address(this), amountIn, 0, abi.encodePacked(tokenIn, params.fee, tokenOut), true);
            universalRouter.execute(commands, inputs, block.timestamp);

            // calculate amount out
            amountOut = IERC20(tokenOut).balanceOf(address(this)) - balanceBefore;
        }

        return _settle(tokenIn, tokenOut, amountNotIn, amountOut, message);
    }

    function _settle(address tokenA, address tokenB, uint256 amountA, uint256 amountB, bytes memory message)
        internal
        override
        returns (uint256, address, address, uint256, uint256, uint256, uint256)
    {
        // decode settlement params
        SettlementParams memory params = abi.decode(message, (SettlementParams));

        if (tokenA != params.token0 && tokenA != params.token1) revert TokenNotUsed(tokenA);
        if (tokenB != params.token0 && tokenB != params.token1) revert TokenNotUsed(tokenB);

        // align amounts to settlement tokens
        (uint256 amount0, uint256 amount1) = tokenA == params.token0 ? (amountA, amountB) : (amountB, amountA);

        // approve token transfers
        if (amount0 > 0) IERC20(params.token0).safeIncreaseAllowance(address(positionManager), amount0);
        if (amount1 > 0) IERC20(params.token1).safeIncreaseAllowance(address(positionManager), amount1);

        // mint position
        (uint256 positionId,, uint256 amount0Used, uint256 amount1Used) = positionManager.mint(
            IPositionManager.MintParams(
                params.token0,
                params.token1,
                params.fee,
                params.tickLower,
                params.tickUpper,
                amount0,
                amount1,
                params.amount0Min,
                params.amount1Min,
                params.baseParams.recipient,
                block.timestamp
            )
        );

        // calculate leftovers
        uint256 amount0Refunded = amount0 - amount0Used;
        uint256 amount1Refunded = amount1 - amount1Used;

        // revoke approvals and refund leftovers
        if (amount0Refunded > 0) {
            IERC20(params.token0).safeDecreaseAllowance(address(positionManager), amount0Refunded);
            IERC20(params.token0).safeTransfer(params.baseParams.recipient, amount0Refunded);
        }
        if (amount1Refunded > 0) {
            IERC20(params.token1).safeDecreaseAllowance(address(positionManager), amount1Refunded);
            IERC20(params.token1).safeTransfer(params.baseParams.recipient, amount1Refunded);
        }

        return (positionId, params.token0, params.token1, amount0Used, amount1Used, amount0Refunded, amount1Refunded);
    }
}
