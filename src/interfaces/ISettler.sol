// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MigrationData} from "../types/MigrationData.sol";
import {MigrationMode} from "../types/MigrationMode.sol";

/// @title ISettler
/// @notice Interface for the Settler contract
interface ISettler {
    /// @notice Error thrown when the caller is not self
    error NotSelf();
    /// @notice Error thrown when the recipient is not the expected recipient
    error NotRecipient();
    /// @notice Error thrown when the tokens are the same between two halves of a dual migration
    error SameToken();
    /// @notice Error thrown when the mode is unsupported
    error UnsupportedMode(MigrationMode mode);
    /// @notice Error thrown when the native token transfer fails
    error NativeTokenTransferFailed(address recipient, uint256 amount);
    /// @notice Error thrown when total fee exceeds the maximum allowed fee
    error MaxFeeExceeded(uint16 protocolShareBps, uint16 senderShareBps);

    /// @notice Event emitted when a receipt is issued
    event Receipt(bytes32 indexed migrationId, address indexed token, uint256 amount);
    /// @notice Event emitted when a settlement is completed
    event Settlement(bytes32 indexed migrationId, address indexed recipient, uint256 positionId);
    /// @notice Event emitted when fees are collected
    event FeePayment(bytes32 indexed migrationId, address indexed token, uint256 protocolFee, uint256 senderFee);
    /// @notice Event emitted when a refund is issued
    event Refund(bytes32 indexed migrationId, address indexed recipient, address indexed token, uint256 amount);

    /// @notice Struct for settlement parameters
    /// @param recipient The recipient of the settlement
    /// @param senderShareBps The sender share of the fees in bps
    /// @param senderFeeRecipient The recipient of the sender fees
    /// @param mintParams The mint params
    struct SettlementParams {
        address recipient;
        uint16 senderShareBps;
        address senderFeeRecipient;
        bytes mintParams;
    }

    /// @notice Function to settle a migration
    /// @param migrationId The migration ID
    /// @dev This function is only callable by the contract itself
    /// @param token The token to settle
    /// @param amount The amount received from the migration
    /// @param migrationData The migration data
    /// @return isAccepted Whether the migration was accepted
    function selfSettle(bytes32 migrationId, address token, uint256 amount, MigrationData memory migrationData)
        external
        returns (bool);

    /// @notice Function to withdraw a migration
    /// @dev this is needed in case one half of a dual migration is received and other half fails
    /// @param migrationId The migration ID
    function withdraw(bytes32 migrationId) external;
}
