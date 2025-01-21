// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.28;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {AcrossV3Settler} from "./base/AcrossV3Settler.sol";
import {IUniswapV3PositionManager} from "./interfaces/external/IUniswapV3.sol";
import {IDualTokensV3Settler} from "./interfaces/IDualTokensV3Settler.sol";
import {UniswapV3Library} from "./libraries/UniswapV3Library.sol";

contract DualTokensV3Settler is IDualTokensV3Settler, AcrossV3Settler {
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
            // match up amounts to tokens
            (uint256 amount0, uint256 amount1) =
                token == params.token0 ? (amount, counterpart.amount) : (counterpart.amount, amount);

            // todo add a try catch for mintPosition that will give everything back to recipient if mint fails

            // mint the new position
            (uint256 amount0Paid, uint256 amount1Paid) = positionManager.mintPosition(
                params.token0,
                params.token1,
                params.fee,
                params.tickLower,
                params.tickUpper,
                amount0,
                amount1,
                params.recipient
            );

            // refund any leftovers
            // todo: most likely only one token will be left over, so could check for the one with greater than 0 amount
            if (amount0Paid < amount0) IERC20(params.token0).safeTransfer(params.recipient, amount0 - amount0Paid);
            if (amount1Paid < amount1) IERC20(params.token1).safeTransfer(params.recipient, amount1 - amount1Paid);

            // clear counterpart
            delete counterparts[params.counterpartKey];
        }
    }
}
