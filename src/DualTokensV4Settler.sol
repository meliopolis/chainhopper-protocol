// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.28;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {AcrossV3Settler} from "./base/AcrossV3Settler.sol";
import {IPositionManager} from "./interfaces/external/IUniswapV4.sol";
import {IDualTokensV4Settler} from "./interfaces/IDualTokensV4Settler.sol";
import {UniswapV4Library} from "./libraries/UniswapV4Library.sol";

contract DualTokensV4Settler is IDualTokensV4Settler, AcrossV3Settler {
    struct PartialSettlement {
        address token;
        uint256 amount;
        address recipient;
    }

    using SafeERC20 for IERC20;
    using UniswapV4Library for IPositionManager;

    IPositionManager private immutable positionManager;
    mapping(bytes32 => PartialSettlement) private partialSettlements;

    constructor(address _positionManager, address _spokePool) AcrossV3Settler(_spokePool) {
        positionManager = IPositionManager(_positionManager);
    }

    function _settle(address token, uint256 amount, bytes memory message) internal override {
        SettlementParams memory params = abi.decode(message, (SettlementParams));
        PartialSettlement memory partialSettlement = partialSettlements[params.migrationId];

        if (params.migrationId != bytes32(0) && partialSettlement.token == address(0)) {
            // if expecting a partial settlement, but is not present yet, store as a partial settlement
            partialSettlements[params.migrationId] = PartialSettlement(token, amount, params.recipient);

            emit PartialSettle(params.migrationId, params.recipient, token, amount);
        } else {
            // match up amounts to tokens
            (uint256 amount0, uint256 amount1) =
                token == params.token0 ? (amount, partialSettlement.amount) : (partialSettlement.amount, amount);

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

            // clear partial settlement
            delete partialSettlements[params.migrationId];

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
        PartialSettlement memory partialSettlement = partialSettlements[migrationId];

        if (partialSettlement.token != address(0) && partialSettlement.amount > 0) {
            IERC20(partialSettlement.token).safeTransfer(partialSettlement.recipient, partialSettlement.amount);
            delete partialSettlements[migrationId];
        }

        emit Escape(migrationId, partialSettlement.recipient, partialSettlement.token, partialSettlement.amount);
    }
}
