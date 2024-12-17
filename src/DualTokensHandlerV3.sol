// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {INonfungiblePositionManager} from "./interfaces/external/INonfungiblePositionManager.sol";
import {V3SpokePoolInterface} from "./interfaces/external/ISpokePool.sol";
import {IDualTokensHandler} from "./interfaces/IDualTokensHandler.sol";
import {IDualTokensMigrator} from "./interfaces/IDualTokensMigrator.sol";

contract DualTokensHandlerV4 is IDualTokensHandler {
    struct MigrationPartial {
        address token;
        uint256 amount;
    }

    using SafeERC20 for IERC20;

    INonfungiblePositionManager public immutable positionManager;
    V3SpokePoolInterface public immutable spokePool;

    // migration id => (token, amount)
    mapping(uint256 => MigrationPartial) public migrationPartials;

    constructor(address _positionManager, address _spokePool) {
        positionManager = INonfungiblePositionManager(_positionManager);
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

            IERC20(token0).approve(address(positionManager), amount0);
            IERC20(token1).approve(address(positionManager), amount1);

            positionManager.mint(
                INonfungiblePositionManager.MintParams({
                    token0: token0,
                    token1: token1,
                    fee: migrationMessage.fee,
                    tickLower: migrationMessage.tickLower,
                    tickUpper: migrationMessage.tickUpper,
                    amount0Desired: amount0,
                    amount1Desired: amount1,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: migrationMessage.recipient,
                    deadline: block.timestamp
                })
            );

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
