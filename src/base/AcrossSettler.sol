// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AcrossMessageHandler as IAcrossMessageHandler} from "@across/interfaces/SpokePoolMessageHandler.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IAcrossSettler} from "../interfaces/IAcrossSettler.sol";
import {MigrationData} from "../types/MigrationData.sol";
import {MigrationMode, MigrationModes} from "../types/MigrationMode.sol";
import {Settler} from "./Settler.sol";

/// @title AcrossSettler
/// @notice Contract for settling migrations on Across
abstract contract AcrossSettler is IAcrossSettler, IAcrossMessageHandler, Settler {
    using SafeERC20 for IERC20;

    /// @notice The Across Spokepool address
    address private immutable spokePool;

    /// @notice Constructor for the AcrossSettler contract
    /// @param _spokePool The spokepool address
    constructor(address _spokePool) {
        spokePool = _spokePool;
    }

    /// @notice Function to handle a message from the Across Spokepool
    /// @param token The token to settle
    /// @param amount The amount to settle
    /// @param message The message to settle
    function handleV3AcrossMessage(address token, uint256 amount, address, bytes memory message) external {
        if (msg.sender != spokePool) revert NotSpokePool();
        if (amount == 0) revert MissingAmount(token);
        (bytes32 migrationId, MigrationData memory migrationData) = abi.decode(message, (bytes32, MigrationData));
        if (migrationData.toId() != migrationId) revert InvalidMigration();

        emit Receipt(migrationId, token, amount);

        try this.selfSettle(migrationId, token, amount, migrationData) returns (bool isAccepted) {
            if (!isAccepted) revert();
        } catch {
            SettlementParams memory settlementParams = abi.decode(migrationData.settlementData, (SettlementParams));

            // refund this and cached settlement if applicable (Across only receive ERC20 tokens)
            IERC20(token).safeTransfer(settlementParams.recipient, amount);
            emit Refund(migrationId, settlementParams.recipient, token, amount);
            if (migrationData.mode == MigrationModes.DUAL) {
                _refund(migrationId, false);
            }
        }
    }
}
