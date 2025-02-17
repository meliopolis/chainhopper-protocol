// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IHooks, IV4Router} from "../interfaces/external/IUniswapV4.sol";
import {IUniversalRouter} from "../interfaces/external/IUniversalRouter.sol";
import {Actions, Currency, PoolKey} from "./UniswapV4Library.sol";

library UniversalRouterLibrary {
    using SafeERC20 for IERC20;

    function swap(
        IUniversalRouter self,
        address token0,
        address token1,
        uint24 feeTier,
        int24 tickSpacing,
        address hooks,
        bool zeroForOne,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        bytes memory actions = abi.encodePacked(
            bytes1(uint8(Actions.SETTLE)),
            bytes1(uint8(Actions.SWAP_EXACT_IN_SINGLE)),
            bytes1(uint8(Actions.TAKE_ALL)),
            bytes1(uint8(Actions.TAKE_ALL))
        );
        bytes[] memory params = new bytes[](4);
        params[0] = abi.encode(zeroForOne ? token0 : token1, amountIn, false);
        params[1] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: PoolKey({
                    currency0: Currency.wrap(token0),
                    currency1: Currency.wrap(token1),
                    fee: feeTier,
                    tickSpacing: tickSpacing,
                    hooks: IHooks(hooks)
                }),
                zeroForOne: zeroForOne,
                amountIn: uint128(amountIn),
                amountOutMinimum: 0,
                hookData: ""
            })
        );
        params[2] = abi.encode(token0, 0);
        params[3] = abi.encode(token1, 0);

        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.V4_SWAP)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);

        uint256 balanceBefore = !zeroForOne && token0 == address(0)
            ? address(this).balance
            : IERC20(zeroForOne ? token1 : token0).balanceOf(address(this));

        if (zeroForOne && token0 == address(0)) {
            self.execute{value: amountIn}(commands, inputs, block.timestamp);
        } else {
            IERC20(zeroForOne ? token0 : token1).safeTransfer(address(self), amountIn);
            self.execute(commands, inputs, block.timestamp);
        }

        uint256 balanceAfter = !zeroForOne && token0 == address(0)
            ? address(this).balance
            : IERC20(zeroForOne ? token1 : token0).balanceOf(address(this));

        amountOut = balanceAfter - balanceBefore;
    }
}

library Commands {
    uint256 constant V4_SWAP = 0x10;
}
