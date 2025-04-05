// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ISettler} from "../interfaces/ISettler.sol";
import {MigrationId} from "../types/MigrationId.sol";
import {MigrationModes} from "../types/MigrationMode.sol";
import {ProtocolFees} from "./ProtocolFees.sol";

abstract contract Settler is ISettler, ProtocolFees {
    using SafeERC20 for IERC20;

    struct SettlementCache {
        address recipient;
        address token;
        uint256 amount;
        bytes data;
    }

    mapping(MigrationId => SettlementCache) internal settlementCaches;

    constructor(address initialOwner) ProtocolFees(initialOwner) {}

    function selfSettle(address token, uint256 amount, bytes memory data)
        external
        virtual
        returns (MigrationId, address)
    {
        // must be called by the contract itself, for wrapping in a try/catch
        if (msg.sender != address(this)) revert NotSelf();
        if (amount == 0) revert MissingAmount(token);

        (MigrationId migrationId, SettlementParams memory settlementParams) =
            abi.decode(data, (MigrationId, SettlementParams));

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
                settlementCaches[migrationId] = SettlementCache(token, settlementParams.recipient, amount, data);
            } else {
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

    function withdraw(MigrationId migrationId) external {
        _refund(migrationId, true);
    }

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

    function _transfer(address token, address recipient, uint256 amount) internal {
        if (token == address(0)) {
            (bool success,) = recipient.call{value: amount}("");
            if (!success) revert NativeTokenTransferFailed(recipient, amount);
        } else {
            IERC20(token).safeTransfer(recipient, amount);
        }
    }

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
