// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable2Step, Ownable} from "@openzeppelin/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ISettler} from "../interfaces/ISettler.sol";
import {MigrationId} from "../types/MigrationId.sol";
import {MigrationModes} from "../types/MigrationMode.sol";

abstract contract Settler is ISettler, Ownable2Step {
    using SafeERC20 for IERC20;

    error InvalidProtocolShareBps(uint16 protocolShareBps);
    error InvalidProtocolShareOfSenderFeePct(uint8 protocolShareOfSenderFeePct);
    error InvalidProtocolFeeRecipient(address protocolFeeRecipient);

    event ProtocolShareBpsUpdated(uint16 protocolShareBps);
    event ProtocolShareOfSenderFeePctUpdated(uint8 protocolShareOfSenderFeePct);
    event ProtocolFeeRecipientUpdated(address protocolFeeRecipient);

    struct SettlementCache {
        address recipient;
        address token;
        uint256 amount;
        bytes data;
    }

    uint16 private constant MAX_BPS = 10_000;
    uint8 private constant MAX_PCT = 100;

    uint16 public protocolShareBps;
    uint8 public protocolShareOfSenderFeePct;
    address public protocolFeeRecipient;
    mapping(MigrationId => SettlementCache) internal settlementCaches;

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setProtocolShareBps(uint16 _protocolShareBps) external onlyOwner {
        if (_protocolShareBps > MAX_BPS) revert InvalidProtocolShareBps(_protocolShareBps);

        protocolShareBps = _protocolShareBps;

        emit ProtocolShareBpsUpdated(_protocolShareBps);
    }

    function setProtocolShareOfSenderFeePct(uint8 _protocolShareOfSenderFeePct) external onlyOwner {
        if (_protocolShareOfSenderFeePct > MAX_PCT) {
            revert InvalidProtocolShareOfSenderFeePct(_protocolShareOfSenderFeePct);
        }

        protocolShareOfSenderFeePct = _protocolShareOfSenderFeePct;

        emit ProtocolShareOfSenderFeePctUpdated(_protocolShareOfSenderFeePct);
    }

    function setProtocolFeeRecipient(address _protocolFeeRecipient) external onlyOwner {
        if (_protocolFeeRecipient == address(0)) revert InvalidProtocolFeeRecipient(_protocolFeeRecipient);

        protocolFeeRecipient = _protocolFeeRecipient;

        emit ProtocolFeeRecipientUpdated(_protocolFeeRecipient);
    }

    function settle(address token, uint256 amount, bytes memory data) external virtual {
        // must be called by the contract itself, for wrapping in a try/catch
        if (msg.sender != address(this)) revert NotSelf();
        if (amount == 0) revert TokenAmountMissing(token);

        BaseSettlementParams memory baseParams = abi.decode(data, (BaseSettlementParams));
        if (baseParams.senderShareBps > MAX_BPS) revert InvalidSenderShareBps(baseParams.senderShareBps);

        emit Migrated(baseParams.migrationId, baseParams.recipient, token, amount);

        if (baseParams.migrationId.mode() == MigrationModes.SINGLE) {
            // calculate fees
            (uint256 protocolFee, uint256 senderFee) = _calculateFees(amount, baseParams.senderShareBps);

            // settle using single token
            uint256 positionId = _settleSingle(token, amount - protocolFee - senderFee, data);

            // transfer fees after settlement to prevent reentrancy
            _payFees(token, protocolFee, senderFee, baseParams.senderFeeRecipient);

            emit Settlement(baseParams.migrationId, baseParams.recipient, positionId);
        } else {
            SettlementCache memory settlementCache = settlementCaches[baseParams.migrationId];
            if (settlementCache.amount == 0) {
                // cache settlement to wait for the other half
                settlementCaches[baseParams.migrationId] = SettlementCache(token, baseParams.recipient, amount, data);
            } else {
                if (keccak256(data) != keccak256(settlementCache.data)) revert SettlementDataMismatch();

                // delete settlement cache to prevent reentrancy
                delete settlementCaches[baseParams.migrationId];

                // calculate fees
                (uint256 protocolFeeA, uint256 senderFeeA) = _calculateFees(amount, baseParams.senderShareBps);
                (uint256 protocolFeeB, uint256 senderFeeB) =
                    _calculateFees(settlementCache.amount, baseParams.senderShareBps);

                // settle using dual tokens
                uint256 positionId = _settleDual(
                    token,
                    settlementCache.token,
                    amount - protocolFeeA - senderFeeA,
                    settlementCache.amount - protocolFeeB - senderFeeB,
                    data
                );

                // transfer fees after settlement to prevent reentrancy
                _payFees(token, protocolFeeA, senderFeeA, baseParams.senderFeeRecipient);
                _payFees(settlementCache.token, protocolFeeB, senderFeeB, baseParams.senderFeeRecipient);

                emit Settlement(baseParams.migrationId, baseParams.recipient, positionId);
            }
        }
    }

    function withdraw(MigrationId migrationId) external {
        _refund(migrationId, true);
    }

    function _calculateFees(uint256 amount, uint16 senderShareBps)
        internal
        view
        returns (uint256 protocolFee, uint256 senderFee)
    {
        if (protocolShareBps + senderShareBps > MAX_BPS) revert MaxFeeExceeded(protocolShareBps, senderShareBps);

        protocolFee = (amount * protocolShareBps) / 10000;
        senderFee = (amount * senderShareBps) / 10000;

        if (protocolShareOfSenderFeePct > 0) {
            uint256 additionalProtocolFee = (senderFee * protocolShareOfSenderFeePct) / 100;
            protocolFee += additionalProtocolFee;
            senderFee -= additionalProtocolFee;
        }
    }

    function _payFees(address token, uint256 protocolFee, uint256 senderFee, address senderFeeRecipient) internal {
        if (protocolFee > 0) _transfer(token, protocolFeeRecipient, protocolFee);
        if (senderFee > 0) _transfer(token, senderFeeRecipient, senderFee);

        emit FeePayment(token, protocolFee, senderFee);
    }

    function _refund(MigrationId migrationId, bool onlyRecipient) internal {
        SettlementCache memory settlementCache = settlementCaches[migrationId];
        if (settlementCache.amount > 0) {
            if (onlyRecipient && msg.sender != settlementCache.recipient) revert NotRecipient();

            // delete settlement cache before trnasfer to prevent reentrancy
            delete settlementCaches[migrationId];
            _transfer(settlementCache.token, settlementCache.recipient, settlementCache.amount);

            emit Refund(migrationId, settlementCache.recipient, settlementCache.token, settlementCache.amount);
        }
    }

    function _transfer(address token, address recipient, uint256 amount) internal {
        if (token == address(0)) {
            (bool success,) = recipient.call{value: amount}("");
            if (!success) revert NativeAssetTransferFailed(recipient, amount);
        } else {
            IERC20(token).safeTransfer(recipient, amount);
        }
    }

    function _settleSingle(address token, uint256 amount, bytes memory data)
        internal
        virtual
        returns (uint256 positionId);

    function _settleDual(address tokenA, address tokenB, uint256 amountA, uint256 amountB, bytes memory data)
        internal
        virtual
        returns (uint256 positionId);
}
