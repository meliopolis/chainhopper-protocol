// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {AcrossV3Settler} from "./base/AcrossV3Settler.sol";
import {IUniswapV3PositionManager} from "./interfaces/external/IUniswapV3.sol";
import {IDualTokensV3Settler} from "./interfaces/IDualTokensV3Settler.sol";
import {UniswapV3Library} from "./libraries/UniswapV3Library.sol";

contract DualTokensV3Settler is IDualTokensV3Settler, AcrossV3Settler {
    struct Fragment {
        address token;
        uint256 amount;
        address recipient;
    }

    error NotRecipient();

    using SafeERC20 for IERC20;
    using UniswapV3Library for IUniswapV3PositionManager;

    IUniswapV3PositionManager private immutable positionManager;
    mapping(bytes32 => Fragment) private fragments;

    constructor(address _positionManager, address _spokePool) AcrossV3Settler(_spokePool) {
        positionManager = IUniswapV3PositionManager(_positionManager);
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
                params.tickLower,
                params.tickUpper,
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
        require(fragment.recipient == msg.sender, NotRecipient());

        IERC20(fragment.token).safeTransfer(fragment.recipient, fragment.amount);
        delete fragments[migrationId];

        emit Escape(migrationId, fragment.recipient, fragment.token, fragment.amount);
    }
}
