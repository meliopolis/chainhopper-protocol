// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IPositionManager} from "@uniswap-v4-periphery/interfaces/IPositionManager.sol";

library UniswapV4Library {
    // TODO:
    // error SettlementTooMuchSlippage();

    function mint(
        IPositionManager self,
        address token0,
        address token1,
        uint24 fee,
        int24 tickSpacing,
        address hooks,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address recipient
    ) internal returns (uint256 positionId, uint256 amount0, uint256 amount1) {
        // TODO:
        // if (amount0Used < params.amount0Min || amount1Used < params.amount1Min) revert SettlementTooMuchSlippage();
    }
}
