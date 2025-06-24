// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IDirectTransferSettler} from "../interfaces/IDirectTransferSettler.sol";
import {MigrationData} from "../types/MigrationData.sol";
import {MigrationMode, MigrationModes} from "../types/MigrationMode.sol";
import {Settler} from "./Settler.sol";

/// @title DirectTransferSettler
/// @notice Contract for settling migrations on the same chain using direct transfers
abstract contract DirectTransferSettler is IDirectTransferSettler, Settler {
    using SafeERC20 for IERC20;

    /// @notice Function to handle a direct transfer message
    /// @param token The token to settle
    /// @param amount The amount to settle
    /// @param message The message containing migration data
    function handleDTMessage(address token, uint256 amount, bytes memory message) external {
        if (amount == 0) revert MissingAmount(token);
        
        (bytes32 migrationId, MigrationData memory migrationData) = abi.decode(message, (bytes32, MigrationData));
        if (migrationData.toId() != migrationId) revert InvalidMigration();

        emit Receipt(migrationId, token, amount);

        bool isAccepted = this.selfSettle(migrationId, token, amount, migrationData);
        if (!isAccepted) revert();
    }
} 