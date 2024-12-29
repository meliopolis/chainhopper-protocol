// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.28;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {AcrossV3Settler} from "./base/AcrossV3Settler.sol";
import {IUniswapV3PositionManager} from "./interfaces/external/IUniswapV3.sol";
import {IV3Settler} from "./interfaces/IV3Settler.sol";
import {UniswapV3Library} from "./libraries/UniswapV3Library.sol";

contract DualTokensV3Settler is IV3Settler, AcrossV3Settler {
    struct Counterpart {
        address token;
        uint256 amount;
    }

    using SafeERC20 for IERC20;
    using UniswapV3Library for IUniswapV3PositionManager;

    IUniswapV3PositionManager private immutable positionManager;
    mapping(bytes32 => Counterpart) private counterparts;

    constructor(address _positionManager, address _spokePool) AcrossV3Settler(_spokePool) {
        positionManager = IUniswapV3PositionManager(_positionManager);
    }

    function _settle(address token, uint256 amount, bytes memory message) internal override {
        SettlementParams memory params = abi.decode(message, (SettlementParams));
        Counterpart memory counterpart = counterparts[params.counterpartKey];

        if (params.counterpartKey != bytes32(0) && counterpart.token == address(0)) {
            // if expecting a counterpart, but counterpart is not present yet, store the token and amount
            counterparts[params.counterpartKey] = Counterpart(token, amount);
        } else {
            // sort tokens and amounts
            (address token0, address token1) =
                params.token0 < params.token1 ? (params.token0, params.token1) : (params.token1, params.token0);
            (uint256 amount0, uint256 amount1) =
                token == token0 ? (amount, counterpart.amount) : (counterpart.amount, amount);

            // mint the new position
            (,, uint256 amount0Paid, uint256 amount1Paid) = positionManager.mintPosition(
                token0, token1, params.fee, params.tickLower, params.tickUpper, amount0, amount1, params.recipient
            );

            // refund any leftovers
            if (amount0Paid < amount0) IERC20(token0).safeTransfer(params.recipient, amount0 - amount0Paid);
            if (amount1Paid < amount1) IERC20(token1).safeTransfer(params.recipient, amount1 - amount1Paid);

            // clear counterpart
            delete counterparts[params.counterpartKey];
        }
    }
}
