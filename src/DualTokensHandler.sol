// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {IPositionManager} from "v4-periphery/interfaces/IPositionManager.sol";
import {Actions} from "v4-periphery/libraries/Actions.sol";
import {V3SpokePoolInterface} from "./interfaces/external/ISpokePool.sol";
import {IDualTokensHandler} from "./interfaces/IDualTokensHandler.sol";
import {IDualTokensMigrator} from "./interfaces/IDualTokensMigrator.sol";

contract DualTokensHandler is IDualTokensHandler {
    struct MigrationPartial {
        address token;
        uint256 amount;
    }

    using SafeERC20 for IERC20;

    IPositionManager public immutable positionManager;
    V3SpokePoolInterface public immutable spokePool;

    // migration id => (token, amount)
    mapping(uint256 => MigrationPartial) public migrationPartials;

    constructor(address _positionManager, address _spokePool) {
        positionManager = IPositionManager(_positionManager);
        spokePool = V3SpokePoolInterface(_spokePool);
    }

    function handleV3AcrossMessage(address tokenSent, uint256 amount, address, bytes memory message) external {
        require(msg.sender == address(spokePool));

        // decode the migration message and retrieve migration partial if any
        IDualTokensMigrator.MigrationMessage memory migrationMessage =
            abi.decode(message, (IDualTokensMigrator.MigrationMessage));
        MigrationPartial memory migrationPartial = migrationPartials[migrationMessage.migrationId];

        if (migrationPartial.token == address(0)) {
            // if no migration partial present, store current migration as partial
            migrationPartials[migrationMessage.migrationId] = MigrationPartial({token: tokenSent, amount: amount});
        } else {
            require(migrationPartial.token != tokenSent);

            // sort currencies and amounts
            (address token0, address token1) = migrationPartial.token < tokenSent
                ? (migrationPartial.token, tokenSent)
                : (tokenSent, migrationPartial.token);
            (uint256 amount0, uint256 amount1) = migrationPartial.token < tokenSent
                ? (migrationPartial.amount, amount)
                : (amount, migrationPartial.amount);

            // mint new position w/ deltas, let Uni handle the liquidity math
            bytes memory actions = abi.encodePacked(Actions.MINT_POSITION_FROM_DELTAS, Actions.SETTLE_PAIR);
            bytes[] memory params = new bytes[](2);
            params[0] = abi.encode(
                PoolKey({
                    currency0: Currency.wrap(token0),
                    currency1: Currency.wrap(token1),
                    fee: migrationMessage.fee,
                    tickSpacing: 60,
                    hooks: IHooks(address(0))
                }), // TODO: poolKey should be passed in from frontend to migrator
                migrationMessage.tickLower,
                migrationMessage.tickUpper,
                amount0,
                amount1,
                migrationMessage.recipient,
                "" // TODO: also passed in from frontend?
            );
            params[1] = abi.encode(Currency.wrap(token0), Currency.wrap(token1));
            positionManager.modifyLiquidities(abi.encode(actions, params), block.timestamp);

            // send any remaining tokens to the recipient
            amount0 = IERC20(token0).balanceOf(address(this));
            amount1 = IERC20(token1).balanceOf(address(this));
            if (amount0 > 0) IERC20(token0).safeTransfer(migrationMessage.recipient, amount0);
            if (amount1 > 0) IERC20(token1).safeTransfer(migrationMessage.recipient, amount1);

            // clear migration partial
            delete migrationPartials[migrationMessage.migrationId];
        }
    }
}
