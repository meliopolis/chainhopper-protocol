// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IHooks, IPositionManager} from "../interfaces/external/IUniswapV4.sol";

library UniswapV4Library {
    type Currency is address;

    struct PoolKey {
        Currency currency0;
        Currency currency1;
        uint24 fee;
        int24 tickSpacing;
        IHooks hooks;
    }

    function mintPosition(
        IPositionManager self,
        address token0,
        address token1,
        uint24 fee,
        int24 tickSpacing,
        address hooks,
        int24 tickLower,
        int24 tickUpper,
        bytes32 salt,
        uint256 amount0Desired,
        uint256 amount1Desired,
        address recipient
    ) internal returns (uint256 positionId, uint128 liquidity, uint256 amount0, uint256 amount1) {
        // record balance before minting
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        // mint new position w/ deltas, let Uni handle the liquidity math
        bytes memory actions = abi.encodePacked(Actions.MINT_POSITION_FROM_DELTAS, Actions.SETTLE_PAIR);
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(
            PoolKey({
                currency0: Currency.wrap(token0),
                currency1: Currency.wrap(token1),
                fee: fee,
                tickSpacing: tickSpacing,
                hooks: IHooks(hooks)
            }),
            tickLower,
            tickUpper,
            amount0Desired,
            amount1Desired,
            recipient,
            salt
        );
        params[1] = abi.encode(Currency.wrap(token0), Currency.wrap(token1));

        positionId = self.nextTokenId();
        try self.modifyLiquidities(abi.encode(actions, params), block.timestamp) {
            liquidity = self.getPositionLiquidity(positionId);
            // amounts used
            amount0 = balance0 - IERC20(token0).balanceOf(address(this));
            amount1 = balance1 - IERC20(token1).balanceOf(address(this));
        } catch {
            positionId = 0;
        }
    }
}

library Actions {
    uint256 internal constant MINT_POSITION_FROM_DELTAS = 0x05;
    uint256 internal constant SETTLE_PAIR = 0x0d;
}
