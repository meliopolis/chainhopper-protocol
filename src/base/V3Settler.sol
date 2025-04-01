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
import {MigrationId} from "../types/MigrationId.sol";

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

    function _settleSingle(address token, uint256 amount, bytes memory data) internal override returns (uint256) {
        // decode settlement params
        SettlementParams memory settlementParams = abi.decode(data, (SettlementParams));
        V3MintParams memory mintParams = abi.decode(settlementParams.mintParams, (V3MintParams));

        if (token != mintParams.token0 && token != mintParams.token1) revert TokenNotUsed(token);

        // calculate swap direction
        bool zeroForOne = token == mintParams.token0;
        (address tokenIn, address tokenOut) = zeroForOne ? (token, mintParams.token1) : (mintParams.token0, token);

        // calculate amount in and out
        uint256 amountIn = amount * mintParams.swapAmountInThousandBps / 10_000_000;
        uint256 amountOut;
        if (amountIn > 0) {
            // cache balance before swap
            uint256 balanceBefore = IERC20(tokenOut).balanceOf(address(this));

            // approve token transfer via permit2
            IERC20(tokenIn).safeIncreaseAllowance(address(permit2), amountIn);
            permit2.approve(tokenIn, address(universalRouter), uint160(amountIn), 0);

            // execute swap via universal router
            bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.V3_SWAP_EXACT_IN)));
            bytes[] memory inputs = new bytes[](1);
            inputs[0] =
                abi.encode(address(this), amountIn, 0, abi.encodePacked(tokenIn, mintParams.fee, tokenOut), true);
            universalRouter.execute(commands, inputs, block.timestamp);

            // calculate amount out
            amountOut = IERC20(tokenOut).balanceOf(address(this)) - balanceBefore;
        }

        return _settleDual(tokenIn, tokenOut, amount - amountIn, amountOut, data);
    }

    function _settleDual(address tokenA, address tokenB, uint256 amountA, uint256 amountB, bytes memory data)
        internal
        override
        returns (uint256)
    {
        // decode settlement params
        SettlementParams memory settlementParams = abi.decode(data, (SettlementParams));
        V3MintParams memory mintParams = abi.decode(settlementParams.mintParams, (V3MintParams));

        if (tokenA != mintParams.token0 && tokenA != mintParams.token1) revert TokenNotUsed(tokenA);
        if (tokenB != mintParams.token0 && tokenB != mintParams.token1) revert TokenNotUsed(tokenB);

        // align amounts to settlement tokens
        (uint256 amount0, uint256 amount1) = tokenA == mintParams.token0 ? (amountA, amountB) : (amountB, amountA);

        // approve token transfers
        if (amount0 > 0) IERC20(mintParams.token0).safeIncreaseAllowance(address(positionManager), amount0);
        if (amount1 > 0) IERC20(mintParams.token1).safeIncreaseAllowance(address(positionManager), amount1);

        // mint position
        (uint256 positionId,, uint256 amount0Used, uint256 amount1Used) = positionManager.mint(
            IPositionManager.MintParams(
                mintParams.token0,
                mintParams.token1,
                mintParams.fee,
                mintParams.tickLower,
                mintParams.tickUpper,
                amount0,
                amount1,
                mintParams.amount0Min,
                mintParams.amount1Min,
                settlementParams.recipient,
                block.timestamp
            )
        );

        // refund unused tokens
        if (amount0 > amount0Used) {
            IERC20(mintParams.token0).safeTransfer(settlementParams.recipient, amount0 - amount0Used);
        }
        if (amount1 > amount1Used) {
            IERC20(mintParams.token1).safeTransfer(settlementParams.recipient, amount1 - amount1Used);
        }

        return positionId;
    }
}
