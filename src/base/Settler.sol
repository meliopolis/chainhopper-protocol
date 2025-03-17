// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable2Step, Ownable} from "@openzeppelin/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ISettler} from "../interfaces/ISettler.sol";

abstract contract Settler is ISettler, Ownable2Step {
    using SafeERC20 for IERC20;

    struct PartialSettlement {
        address token;
        uint256 amount;
        address recipient;
        bytes message;
    }

    uint24 private protocolFeeBps;
    uint8 private protocolShareOfSenderFeeInPercent;
    address private protocolFeeRecipient;
    mapping(bytes32 => PartialSettlement) private partialSettlements;

    constructor(uint24 _protocolFeeBps, uint8 _protocolShareOfSenderFeeInPercent, address _protocolFeeRecipient)
        Ownable(msg.sender)
    {
        protocolFeeBps = _protocolFeeBps;
        protocolShareOfSenderFeeInPercent = _protocolShareOfSenderFeeInPercent;
        protocolFeeRecipient = _protocolFeeRecipient;
    }

    function setProtocolFeeBps(uint24 _protocolFeeBps) external onlyOwner {
        protocolFeeBps = _protocolFeeBps;
    }

    function setProtocolShareOfSenderFeeInPercent(uint8 _protocolShareOfSenderFeeInPercent) external onlyOwner {
        protocolShareOfSenderFeeInPercent = _protocolShareOfSenderFeeInPercent;
    }

    function setProtocolFeeRecipient(address _protocolFeeRecipient) external onlyOwner {
        protocolFeeRecipient = _protocolFeeRecipient;
    }

    function settle(address token, uint256 amount, bytes memory message) external returns (uint256) {
        if (msg.sender != address(this)) revert NotSelf();
        if (amount == 0) revert AmountCannotBeZero();

        BaseSettlementParams memory baseParams = abi.decode(message, (BaseSettlementParams));

        if (baseParams.migrationId == bytes32(0)) {
            (uint256 protocolFee, uint256 senderFee) = _calculateFees(amount, baseParams.senderFeeBps);

            (
                uint256 positionId,
                address token0,
                address token1,
                uint256 amount0Used,
                uint256 amount1Used,
                uint256 amount0Refunded,
                uint256 amount1Refunded
            ) = _settle(token, amount - protocolFee - senderFee, message);
            _transferFees(token, protocolFee, senderFee, baseParams.senderFeeRecipient);

            emit FullySettled(
                baseParams.migrationId,
                baseParams.recipient,
                positionId,
                token0,
                token1,
                amount0Used,
                amount1Used,
                amount0Refunded,
                amount1Refunded
            );

            return positionId;
        } else {
            PartialSettlement memory partialSettlement = partialSettlements[baseParams.migrationId];

            if (partialSettlement.amount == 0) {
                partialSettlements[baseParams.migrationId] =
                    PartialSettlement(token, amount, baseParams.recipient, message);

                emit PartiallySettled(baseParams.migrationId, baseParams.recipient, token, amount);

                return 0;
            } else {
                if (token == partialSettlement.token) revert SettlementTokensIdentical();
                if (keccak256(message) != keccak256(partialSettlement.message)) revert SettlementMessagesMismatch();

                delete partialSettlements[baseParams.migrationId];

                (uint256 protocolFeeA, uint256 senderFeeA) = _calculateFees(amount, baseParams.senderFeeBps);
                (uint256 protocolFeeB, uint256 senderFeeB) =
                    _calculateFees(partialSettlement.amount, baseParams.senderFeeBps);
                uint256 amountA = amount - protocolFeeA - senderFeeA;
                uint256 amountB = partialSettlement.amount - protocolFeeB - senderFeeB;

                (
                    uint256 positionId,
                    address token0,
                    address token1,
                    uint256 amount0Used,
                    uint256 amount1Used,
                    uint256 amount0Refunded,
                    uint256 amount1Refunded
                ) = _settle(token, partialSettlement.token, amountA, amountB, message);
                _transferFees(token, protocolFeeA, senderFeeA, baseParams.senderFeeRecipient);
                _transferFees(partialSettlement.token, protocolFeeB, senderFeeB, baseParams.senderFeeRecipient);

                emit FullySettled(
                    baseParams.migrationId,
                    baseParams.recipient,
                    positionId,
                    token0,
                    token1,
                    amount0Used,
                    amount1Used,
                    amount0Refunded,
                    amount1Refunded
                );

                return positionId;
            }
        }
    }

    function withdraw(bytes32 migrationId) external {
        _refund(migrationId, true);
    }

    function _refund(bytes32 migrationId, bool onlyRecipient) internal {
        PartialSettlement memory partialSettlement = partialSettlements[migrationId];

        if (partialSettlement.amount > 0) {
            if (onlyRecipient && msg.sender != partialSettlement.recipient) revert NotRecipient();

            delete partialSettlements[migrationId];

            _transfer(partialSettlement.token, partialSettlement.amount, partialSettlement.recipient);

            emit Refunded(migrationId, partialSettlement.recipient, partialSettlement.token, partialSettlement.amount);
        }
    }

    function _settle(address token, uint256 amount, bytes memory message)
        internal
        virtual
        returns (
            uint256 positionId,
            address token0,
            address token1,
            uint256 amount0Used,
            uint256 amount1Used,
            uint256 amount0Refunded,
            uint256 amount1Refunded
        );

    function _settle(address tokenA, address tokenB, uint256 amountA, uint256 amountB, bytes memory message)
        internal
        virtual
        returns (
            uint256 positionId,
            address token0,
            address token1,
            uint256 amount0Used,
            uint256 amount1Used,
            uint256 amount0Refunded,
            uint256 amount1Refunded
        );

    function _transfer(address token, uint256 amount, address recipient) internal {
        IERC20(token).safeTransfer(recipient, amount);
    }

    function _calculateFees(uint256 amount, uint24 senderFeeBps)
        private
        view
        returns (uint256 protocolFee, uint256 senderFee)
    {
        protocolFee = (amount * protocolFeeBps) / 10000;
        senderFee = (amount * senderFeeBps) / 10000;

        if (protocolShareOfSenderFeeInPercent > 0) {
            uint256 protocolShareOfSenderFee = (senderFee * protocolShareOfSenderFeeInPercent) / 100;
            protocolFee += protocolShareOfSenderFee;
            senderFee -= protocolShareOfSenderFee;
        }
    }

    function _transferFees(address token, uint256 protocolFee, uint256 senderFee, address senderFeeRecipient) private {
        if (protocolFee > 0) {
            _transfer(token, protocolFee, protocolFeeRecipient);
        }

        if (senderFee > 0) {
            _transfer(token, senderFee, senderFeeRecipient);
        }
    }
}
