// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
import {ISettler} from "../interfaces/ISettler.sol";
import {MigrationData} from "../types/MigrationData.sol";
import {MigrationMode, MigrationModes} from "../types/MigrationMode.sol";
import {ProtocolFees} from "./ProtocolFees.sol";

/// @title Settler
/// @notice Abstract contract for settling migrations
abstract contract Settler is ISettler, ProtocolFees, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Struct for settlement cache
    /// @param recipient The recipient of the settlement
    /// @param token The token to settle
    /// @param amount The amount to settle
    struct SettlementCache {
        address recipient;
        address token;
        uint256 amount;
    }

    /// @notice Constant for conversions between unit and percentage
    uint256 internal constant UNIT_IN_PERCENTS = 100;
    /// @notice Constant for conversions between unit and basis points
    uint256 internal constant UNIT_IN_BASIS_POINTS = 10_000;
    /// @notice Constant for conversions between unit and milli basis points
    uint256 internal constant UNIT_IN_MILLI_BASIS_POINTS = 10_000_000;

    /// @notice Mapping of migration hashes to settlement caches
    mapping(bytes32 => SettlementCache) internal settlementCaches;

    /// @notice Constructor for the Settler contract
    /// @param initialOwner The initial owner of the contract
    constructor(address initialOwner) ProtocolFees(initialOwner) {}

    /// @notice Function to settle a migration
    /// @param token The token to settle
    /// @param amount The amount received from the migration
    /// @param data The data to settle
    /// @return migrationHash The migration hash
    /// @return recipient The recipient of the settlement
    function selfSettle(address token, uint256 amount, bytes memory data)
        external
        virtual
        nonReentrant
        returns (bytes32, address)
    {
        // must be called by the contract itself, for wrapping in a try/catch
        if (msg.sender != address(this)) revert NotSelf();
        if (amount == 0) revert MissingAmount(token);

        (bytes32 migrationHash, MigrationData memory migrationData) = abi.decode(data, (bytes32, MigrationData));
        if (migrationData.toHash() != migrationHash) revert InvalidMigration();
        SettlementParams memory settlementParams = abi.decode(migrationData.settlementData, (SettlementParams));

        if (migrationData.mode == MigrationModes.SINGLE) {
            // calculate fees
            (uint256 protocolFee, uint256 senderFee) = _calculateFees(amount, settlementParams.senderShareBps);

            // mint position using single token
            uint256 positionId = _mintPosition(
                token, amount - protocolFee - senderFee, settlementParams.recipient, settlementParams.mintParams
            );

            // transfer fees after minting position to prevent reentrancy
            _payFees(migrationHash, token, protocolFee, senderFee, settlementParams.senderFeeRecipient);

            emit Settlement(migrationHash, settlementParams.recipient, positionId);
        } else if (migrationData.mode == MigrationModes.DUAL) {
            (address token0, address token1, uint256 amount0Min, uint256 amount1Min) =
                abi.decode(migrationData.routesData, (address, address, uint256, uint256));
            if (token == token0) {
                if (amount < amount0Min) revert AmountTooLow(token, amount, amount0Min);
            } else if (token == token1) {
                if (amount < amount1Min) revert AmountTooLow(token, amount, amount1Min);
            } else {
                revert UnexpectedToken(token);
            }

            SettlementCache memory settlementCache = settlementCaches[migrationHash];

            if (settlementCache.amount == 0) {
                // cache settlement to wait for the other half
                settlementCaches[migrationHash] =
                    SettlementCache({recipient: settlementParams.recipient, token: token, amount: amount});
            } else {
                if (token == settlementCache.token) revert SameToken();

                // delete settlement cache to prevent reentrancy
                delete settlementCaches[migrationHash];

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
                _payFees(migrationHash, token, protocolFeeA, senderFeeA, settlementParams.senderFeeRecipient);
                _payFees(
                    migrationHash, settlementCache.token, protocolFeeB, senderFeeB, settlementParams.senderFeeRecipient
                );

                emit Settlement(migrationHash, settlementParams.recipient, positionId);
            }
        } else {
            revert UnsupportedMode(migrationData.mode);
        }

        return (migrationHash, settlementParams.recipient);
    }

    /// @notice Function to withdraw a migration
    /// @param migrationHash The migration hash
    function withdraw(bytes32 migrationHash) external nonReentrant {
        _refund(migrationHash, true);
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

        protocolFee = (amount * protocolShareBps) / UNIT_IN_BASIS_POINTS;
        senderFee = (amount * senderShareBps) / UNIT_IN_BASIS_POINTS;

        if (protocolShareOfSenderFeePct > 0) {
            uint256 protocolFeeFromSenderFee = (senderFee * protocolShareOfSenderFeePct) / UNIT_IN_PERCENTS;
            protocolFee += protocolFeeFromSenderFee;
            senderFee -= protocolFeeFromSenderFee;
        }
    }

    /// @notice Internal function to pay fees
    /// @param migrationHash The migration hash
    /// @param token The token to pay fees for
    /// @param protocolFee The protocol fee
    /// @param senderFee The sender fee
    /// @param senderFeeRecipient The recipient of the sender fee
    function _payFees(
        bytes32 migrationHash,
        address token,
        uint256 protocolFee,
        uint256 senderFee,
        address senderFeeRecipient
    ) internal {
        if (protocolFee > 0) IERC20(token).safeTransfer(protocolFeeRecipient, protocolFee);
        if (senderFee > 0) IERC20(token).safeTransfer(senderFeeRecipient, senderFee);

        emit FeePayment(migrationHash, token, protocolFee, senderFee);
    }

    /// @notice Internal function to refund a migration
    /// @param migrationHash The migration hash
    /// @param onlyRecipient Whether to only refund the recipient
    function _refund(bytes32 migrationHash, bool onlyRecipient) internal {
        SettlementCache memory settlementCache = settlementCaches[migrationHash];

        if (settlementCache.amount > 0) {
            if (onlyRecipient && msg.sender != settlementCache.recipient) revert NotRecipient();

            // delete settlement cache before transfer to prevent reentrancy
            delete settlementCaches[migrationHash];
            IERC20(settlementCache.token).safeTransfer(settlementCache.recipient, settlementCache.amount);

            emit Refund(migrationHash, settlementCache.recipient, settlementCache.token, settlementCache.amount);
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
