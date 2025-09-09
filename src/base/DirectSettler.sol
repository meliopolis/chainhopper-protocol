// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IDirectSettler} from "../interfaces/IDirectSettler.sol";
import {ISettler} from "../interfaces/ISettler.sol";
import {MigrationData} from "../types/MigrationData.sol";
import {MigrationModes} from "../types/MigrationMode.sol";
import {Settler} from "./Settler.sol";

/// @title DirectSettler
/// @notice Contract for settling migrations on the same chain using direct transfers
abstract contract DirectSettler is IDirectSettler, Settler {
    using SafeERC20 for IERC20;

    /// @notice Function to handle a direct transfer message
    /// @param token The token to settle
    /// @param amount The amount to settle
    /// @param message The message containing migration data
    function handleDirectTransfer(address token, uint256 amount, bytes memory message) external {
        if (amount == 0) revert MissingAmount(token);

        (bytes32 migrationId, MigrationData memory migrationData) = abi.decode(message, (bytes32, MigrationData));
        // still need to check the migrationId
        if (migrationData.toId() != migrationId) revert InvalidMigration();

        emit Receipt(migrationId, token, amount);

        try this.selfSettle(migrationId, token, amount, migrationData) returns (bool isAccepted) {
            if (!isAccepted) revert();
        } catch {
            ISettler.SettlementParams memory settlementParams =
                abi.decode(migrationData.settlementData, (ISettler.SettlementParams));

            // refund this and cached settlement if applicable
            IERC20(token).safeTransfer(settlementParams.recipient, amount);
            emit Refund(migrationId, settlementParams.recipient, token, amount);
            if (migrationData.mode == MigrationModes.DUAL) {
                _refund(migrationId, false);
            }
        }
    }
}
