// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.28;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {AcrossV3Settler} from "./base/AcrossV3Settler.sol";
import {IPositionManager} from "./interfaces/external/IUniswapV4.sol";
import {IDualTokensV4Settler} from "./interfaces/IDualTokensV4Settler.sol";
import {UniswapV4Library} from "./libraries/UniswapV4Library.sol";

contract DualTokensV4Settler is IDualTokensV4Settler, AcrossV3Settler {
    struct Fragment {
        address token;
        uint256 amount;
        address recipient;
    }

    using SafeERC20 for IERC20;
    using UniswapV4Library for IPositionManager;

    IPositionManager private immutable positionManager;
    mapping(bytes32 => Fragment) private fragments;

    constructor(address _positionManager, address _spokePool) AcrossV3Settler(_spokePool) {
        positionManager = IPositionManager(_positionManager);
    }

    function _settle(address token, uint256 amount, bytes memory message) internal override {
        SettlementParams memory params = abi.decode(message, (SettlementParams));
        Fragment memory fragment = fragments[params.migrationId];

        if (params.migrationId != bytes32(0) && fragment.token == address(0)) {
            // if expecting a fragment, but fragment is not present yet, store as a fragment
            fragments[params.migrationId] = Fragment(token, amount, params.recipient);
        } else {
            // match up amounts to tokens
            (uint256 amount0, uint256 amount1) =
                token == params.token0 ? (amount, fragment.amount) : (fragment.amount, amount);

            // mint the new position
            (uint256 positionId, uint128 liquidity, uint256 amount0Paid, uint256 amount1Paid) = positionManager
                .mintPosition(
                params.token0,
                params.token1,
                params.fee,
                params.tickSpacing,
                params.hooks,
                params.tickLower,
                params.tickUpper,
                params.migrationId,
                amount0,
                amount1,
                params.recipient
            );

            // refund any leftovers
            if (amount0Paid < amount0) IERC20(params.token0).safeTransfer(params.recipient, amount0 - amount0Paid);
            if (amount1Paid < amount1) IERC20(params.token1).safeTransfer(params.recipient, amount1 - amount1Paid);

            // clear fragment
            delete fragments[params.migrationId];

            emit Settle(
                params.migrationId,
                params.recipient,
                positionId,
                liquidity,
                amount0,
                amount1,
                amount0 - amount0Paid,
                amount1 - amount1Paid
            );
        }
    }

    function escape(bytes32 migrationId) external {
        Fragment memory fragment = fragments[migrationId];

        if (fragment.token != address(0) && fragment.amount > 0) {
            IERC20(fragment.token).safeTransfer(fragment.recipient, fragment.amount);
            delete fragments[migrationId];
        }

        emit Escape(migrationId, fragment.recipient, fragment.token, fragment.amount);
    }
}
