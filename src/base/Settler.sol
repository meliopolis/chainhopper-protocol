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
        bytes data;
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

    function settle(address token, uint256 amount, bytes memory data) external {
        if (msg.sender != address(this)) revert NotSelf();
        if (amount == 0) revert AmountCannotBeZero();

        BaseSettlementParams memory baseParams = abi.decode(data, (BaseSettlementParams));
        if (baseParams.migrationId == bytes32(0)) {
            // calculate fees on the token to be settled
            (uint256 protocolFee, uint256 senderFee) = _calculateFees(amount, baseParams.senderFeeBps);

            // settle (implemented in child position manager contract) with single token
            (uint256 positionId, address token0, address token1, uint128 liquidity) =
                _settle(token, amount - protocolFee - senderFee, data);

            // transfer fees, after settle to prevent reentrancy
            _transferFees(token, protocolFee, senderFee, baseParams.senderFeeRecipient);

            emit FullySettled(baseParams.migrationId, baseParams.recipient, positionId, token0, token1, liquidity);
        } else {
            PartialSettlement memory partialSettlement = partialSettlements[baseParams.migrationId];
            if (partialSettlement.amount == 0) {
                // store the partial settlement to wait for the other half
                partialSettlements[baseParams.migrationId] =
                    PartialSettlement(token, amount, baseParams.recipient, data);

                emit PartiallySettled(baseParams.migrationId, baseParams.recipient, token, amount);
            } else {
                if (token == partialSettlement.token) revert SettlementTokensCannotBeTheSame();
                if (keccak256(data) != keccak256(partialSettlement.data)) revert SettlementDataMismatch();

                // delete the partial settlement to prevent reentrancy
                delete partialSettlements[baseParams.migrationId];

                // calculate fees on the tokens to be settled
                (uint256 protocolFeeA, uint256 senderFeeA) = _calculateFees(amount, baseParams.senderFeeBps);
                (uint256 protocolFeeB, uint256 senderFeeB) =
                    _calculateFees(partialSettlement.amount, baseParams.senderFeeBps);

                // settle (implemented in child position manager contract) with dual tokens
                (uint256 positionId, address token0, address token1, uint128 liquidity) = _settle(
                    token,
                    partialSettlement.token,
                    amount - protocolFeeA - senderFeeA,
                    partialSettlement.amount - protocolFeeB - senderFeeB,
                    data
                );

                // transfer fees, after settle to prevent reentrancy
                _transferFees(token, protocolFeeA, senderFeeA, baseParams.senderFeeRecipient);
                _transferFees(partialSettlement.token, protocolFeeB, senderFeeB, baseParams.senderFeeRecipient);

                emit FullySettled(baseParams.migrationId, baseParams.recipient, positionId, token0, token1, liquidity);
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

            // delete the partial settlement to prevent reentrancy, then transfer the token
            delete partialSettlements[migrationId];
            IERC20(partialSettlement.token).safeTransfer(partialSettlement.recipient, partialSettlement.amount);

            emit Refunded(migrationId, partialSettlement.recipient, partialSettlement.token, partialSettlement.amount);
        }
    }

    function _settle(address token, uint256 amount, bytes memory data)
        internal
        virtual
        returns (uint256 positionId, address token0, address token1, uint128 liquidity);

    function _settle(address tokenA, address tokenB, uint256 amountA, uint256 amountB, bytes memory data)
        internal
        virtual
        returns (uint256 positionId, address token0, address token1, uint128 liquidity);

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
        if (protocolFee > 0) IERC20(token).safeTransfer(protocolFeeRecipient, protocolFee);
        if (senderFee > 0) IERC20(token).safeTransfer(senderFeeRecipient, senderFee);
    }
}
