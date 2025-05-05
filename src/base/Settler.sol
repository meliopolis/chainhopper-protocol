// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
import {ISettler} from "../interfaces/ISettler.sol";
import {MigrationId} from "../types/MigrationId.sol";
import {MigrationModes} from "../types/MigrationMode.sol";
import {ProtocolFees} from "./ProtocolFees.sol";

/// @title Settler
/// @notice Abstract contract for settling migrations
abstract contract Settler is ISettler, ProtocolFees, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Struct for settlement cache
    /// @param recipient The recipient of the settlement
    /// @param token The token to settle
    /// @param amount The amount to settle
    /// @param data keccak256 hash of the data to settle
    struct SettlementCache {
        address recipient;
        address token;
        uint256 amount;
        bytes data;
    }

    /// @notice Mapping of migration ids to settlement caches
    mapping(MigrationId => SettlementCache) internal settlementCaches;

    /// @notice Constructor for the Settler contract
    /// @param initialOwner The initial owner of the contract
    constructor(address initialOwner) ProtocolFees(initialOwner) {}

    /// @notice Function to settle a migration
    /// @param token The token to settle
    /// @param amount The amount received from the migration
    /// @param data The data to settle
    /// @return migrationId The migration id
    /// @return recipient The recipient of the settlement
    function selfSettle(address token, uint256 amount, bytes memory data)
        external
        virtual
        nonReentrant
        returns (MigrationId, address)
    {
        // must be called by the contract itself, for wrapping in a try/catch
        if (msg.sender != address(this)) revert NotSelf();
        if (amount == 0) revert MissingAmount(token);

        (MigrationId migrationId, bytes memory settlementParamsBytes) = abi.decode(data, (MigrationId, bytes));
        (ISettler.SettlementParams memory settlementParams) =
            abi.decode(settlementParamsBytes, (ISettler.SettlementParams));

        if (migrationId.mode() == MigrationModes.SINGLE) {
            // calculate fees
            (uint256 protocolFee, uint256 senderFee) = _calculateFees(amount, settlementParams.senderShareBps);

            // mint position using single token
            uint256 positionId = _mintPosition(
                token, amount - protocolFee - senderFee, settlementParams.recipient, settlementParams.mintParams
            );

            // transfer fees after minting position to prevent reentrancy
            _payFees(migrationId, token, protocolFee, senderFee, settlementParams.senderFeeRecipient);

            emit Settlement(migrationId, settlementParams.recipient, positionId);
        } else if (migrationId.mode() == MigrationModes.DUAL) {
            SettlementCache memory settlementCache = settlementCaches[migrationId];

            if (settlementCache.amount == 0) {
                // cache settlement to wait for the other half
                settlementCaches[migrationId] =
                    SettlementCache({recipient: settlementParams.recipient, token: token, amount: amount, data: data});
            } else {
                if (token == settlementCache.token) revert SameToken();
                if (keccak256(data) != keccak256(settlementCache.data)) revert MismatchingData();

                // delete settlement cache to prevent reentrancy
                delete settlementCaches[migrationId];

                // calculate fees
                (uint256 protocolFeeA, uint256 senderFeeA) = _calculateFees(amount, settlementParams.senderShareBps);
                (uint256 protocolFeeB, uint256 senderFeeB) =
                    _calculateFees(settlementCache.amount, settlementParams.senderShareBps);

                // mint position using dual tokens
                uint256 positionId = _mintPosition(
                    token,
                    settlementCache.token,
                    amount - protocolFeeA - senderFeeA,
                    settlementCache.amount - protocolFeeB - senderFeeB,
                    settlementParams.recipient,
                    settlementParams.mintParams
                );

                // transfer fees after minting position to prevent reentrancy
                _payFees(migrationId, token, protocolFeeA, senderFeeA, settlementParams.senderFeeRecipient);
                _payFees(
                    migrationId, settlementCache.token, protocolFeeB, senderFeeB, settlementParams.senderFeeRecipient
                );

                emit Settlement(migrationId, settlementParams.recipient, positionId);
            }
        } else {
            revert UnsupportedMode(migrationId.mode());
        }

        return (migrationId, settlementParams.recipient);
    }

    /// @notice Function to withdraw a migration
    /// @param migrationId The migration id
    function withdraw(MigrationId migrationId) external nonReentrant {
        _refund(migrationId, true);
    }

    /// @notice Internal function to calculate fees
    /// @param amount The amount to calculate fees for
    /// @param senderShareBps The sender share bps
    /// @return protocolFee The protocol fee
    /// @return senderFee The sender fee
    function _calculateFees(uint256 amount, uint16 senderShareBps)
        internal
        view
        returns (uint256 protocolFee, uint256 senderFee)
    {
        if (protocolShareBps + senderShareBps > MAX_SHARE_BPS) revert MaxFeeExceeded(protocolShareBps, senderShareBps);

        protocolFee = (amount * protocolShareBps) / 10000;
        senderFee = (amount * senderShareBps) / 10000;

        if (protocolShareOfSenderFeePct > 0) {
            uint256 protocolFeeFromSenderFee = (senderFee * protocolShareOfSenderFeePct) / 100;
            protocolFee += protocolFeeFromSenderFee;
            senderFee -= protocolFeeFromSenderFee;
        }
    }

    /// @notice Internal function to pay fees
    /// @param migrationId The migration id
    /// @param token The token to pay fees for
    /// @param protocolFee The protocol fee
    /// @param senderFee The sender fee
    /// @param senderFeeRecipient The recipient of the sender fee
    function _payFees(
        MigrationId migrationId,
        address token,
        uint256 protocolFee,
        uint256 senderFee,
        address senderFeeRecipient
    ) internal {
        if (protocolFee > 0) _transfer(token, protocolFeeRecipient, protocolFee);
        if (senderFee > 0) _transfer(token, senderFeeRecipient, senderFee);

        emit FeePayment(migrationId, token, protocolFee, senderFee);
    }

    /// @notice Internal function to refund a migration
    /// @param migrationId The migration id
    /// @param onlyRecipient Whether to only refund the recipient
    function _refund(MigrationId migrationId, bool onlyRecipient) internal {
        SettlementCache memory settlementCache = settlementCaches[migrationId];

        if (settlementCache.amount > 0) {
            if (onlyRecipient && msg.sender != settlementCache.recipient) revert NotRecipient();

            // delete settlement cache before transfer to prevent reentrancy
            delete settlementCaches[migrationId];
            _transfer(settlementCache.token, settlementCache.recipient, settlementCache.amount);

            emit Refund(migrationId, settlementCache.recipient, settlementCache.token, settlementCache.amount);
        }
    }

    /// @notice Internal function to transfer a token
    /// @param token The token to transfer
    /// @param recipient The recipient of the transfer
    /// @param amount The amount to transfer
    function _transfer(address token, address recipient, uint256 amount) internal {
        if (token == address(0)) {
            (bool success,) = recipient.call{value: amount}("");
            if (!success) revert NativeTokenTransferFailed(recipient, amount);
        } else {
            IERC20(token).safeTransfer(recipient, amount);
        }
    }

    /// @notice Internal function to mint a position
    /// @param token The token to mint
    /// @param amount The amount to mint
    /// @param recipient The recipient of the minted token
    /// @param data mint params
    function _mintPosition(address token, uint256 amount, address recipient, bytes memory data)
        internal
        virtual
        returns (uint256 positionId);

    function _mintPosition(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        address recipient,
        bytes memory data
    ) internal virtual returns (uint256 positionId);
}
