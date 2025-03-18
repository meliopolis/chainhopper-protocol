// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IPermit2} from "@uniswap-permit2/interfaces/IPermit2.sol";
import {IUniversalRouter} from "@uniswap-universal-router/interfaces/IUniversalRouter.sol";
import {Commands} from "@uniswap-universal-router/libraries/Commands.sol";
// copied and modified from uniswap-v3-periphery, as the original had bad imports
import {INonfungiblePositionManager as IPositionManager} from "../interfaces/external/INonfungiblePositionManager.sol";
import {Migrator} from "./Migrator.sol";

abstract contract V3Migrator is Migrator {
    using SafeERC20 for IERC20;

    IPositionManager private immutable positionManager;
    IUniversalRouter private immutable universalRouter;
    IPermit2 private immutable permit2;

    constructor(address _positionManager, address _universalRouter, address _permit2) {
        positionManager = IPositionManager(_positionManager);
        universalRouter = IUniversalRouter(_universalRouter);
        permit2 = IPermit2(_permit2);
    }

    function _liquidate(uint256 positionId)
        internal
        override
        returns (address, address, uint256, uint256, bytes memory)
    {
        // get position info
        (,, address token0, address token1, uint24 fee,,, uint128 liquidity,,,,) = positionManager.positions(positionId);

        // burn liquidity
        positionManager.decreaseLiquidity(
            IPositionManager.DecreaseLiquidityParams(positionId, liquidity, 0, 0, block.timestamp)
        );

        // collect tokens
        (uint256 amount0, uint256 amount1) = positionManager.collect(
            IPositionManager.CollectParams(positionId, address(this), type(uint128).max, type(uint128).max)
        );

        // burn position
        positionManager.burn(positionId);

        return (token0, token1, amount0, amount1, abi.encode(token0, token1, fee));
    }

    function _swap(bytes memory poolInfo, bool zeroForOne, uint256 amountIn, uint256 amountOutMin)
        internal
        override
        returns (uint256)
    {
        // decode pool info
        (address token0, address token1, uint24 fee) = abi.decode(poolInfo, (address, address, uint24));

        // get token in and out
        (address tokenIn, address tokenOut) = zeroForOne ? (token0, token1) : (token1, token0);

        // cache balance before swap
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(address(this));

        // approve token transfer via permit2
        IERC20(tokenIn).safeIncreaseAllowance(address(permit2), amountIn);
        permit2.approve(tokenIn, address(positionManager), uint160(amountIn), 0);

        // execute swap via universal router
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.V3_SWAP_EXACT_IN)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(this), amountIn, amountOutMin, abi.encodePacked(tokenIn, fee, tokenOut), true);
        universalRouter.execute(commands, inputs, block.timestamp);

        return IERC20(tokenOut).balanceOf(address(this)) - balanceBefore;
    }
}
