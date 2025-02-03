// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IV3Settler} from "./interfaces/IV3Settler.sol";
import {AcrossSettler} from "./base/AcrossSettler.sol";
import {Settler} from "./base/Settler.sol";
import {ISwapRouter} from "./interfaces/external/IUniswapV3.sol";
import {IUniswapV3PositionManager} from "./interfaces/external/IUniswapV3.sol";
import {UniswapV3Library} from "./libraries/UniswapV3Library.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract AcrossV3Settler is IV3Settler, AcrossSettler {
    using UniswapV3Library for ISwapRouter;
    using UniswapV3Library for IUniswapV3PositionManager;
    using SafeERC20 for IERC20;

    struct PartialSettlement {
        address token;
        uint256 amount;
        V3SettlementParams settlementParams;
    }

    ISwapRouter public immutable swapRouter;
    IUniswapV3PositionManager private immutable positionManager;
    mapping(bytes32 => PartialSettlement) public partialSettlements;

    constructor(
        address _spokePool,
        address _protocolFeeRecipient,
        uint24 _protocolFeeBps,
        uint8 _protocolShareOfSenderFeeInPercent,
        address _swapRouter,
        address _positionManager
    ) AcrossSettler(_spokePool) Settler(_protocolFeeBps, _protocolFeeRecipient, _protocolShareOfSenderFeeInPercent) {
        swapRouter = ISwapRouter(_swapRouter);
        positionManager = IUniswapV3PositionManager(_positionManager);
    }

    function _getSenderFees(bytes memory message) internal view virtual override returns (uint24, address) {
        (, bytes memory settlementMessage) = abi.decode(message, (bytes32, bytes));
        (V3SettlementParams memory settlementParams) = abi.decode(settlementMessage, (V3SettlementParams));
        return (settlementParams.senderFeeBps, settlementParams.senderFeeRecipient);
    }

    function _getRecipient(bytes memory message) internal view virtual override returns (address) {
        (, bytes memory settlementMessage) = abi.decode(message, (bytes32, bytes));
        (V3SettlementParams memory settlementParams) = abi.decode(settlementMessage, (V3SettlementParams));
        return settlementParams.recipient;
    }

    function _refund(bytes32 migrationId) override internal {
        PartialSettlement memory partialSettlement = partialSettlements[migrationId];
        if (partialSettlement.token != address(0)) {
            IERC20(partialSettlement.token).transfer(
                partialSettlement.settlementParams.recipient, partialSettlement.amount
            );
            delete partialSettlements[migrationId];
        }
    }

    function compareSettlementParams(V3SettlementParams memory a, V3SettlementParams memory b)
        external
        pure
        returns (bool)
    {
        return a.recipient == b.recipient && a.token0 == b.token0 && a.token1 == b.token1 && a.feeTier == b.feeTier
            && a.tickLower == b.tickLower && a.tickUpper == b.tickUpper && a.amount0Min == b.amount0Min
            && a.amount1Min == b.amount1Min && a.senderFeeBps == b.senderFeeBps
            && a.senderFeeRecipient == b.senderFeeRecipient;
    }

    function _settle(address token, uint256 amount, bytes memory message) internal virtual override returns (uint256) {
        (bytes32 migrationId, bytes memory settlementMessage) = abi.decode(message, (bytes32, bytes));
        (V3SettlementParams memory settlementParams) = abi.decode(settlementMessage, (V3SettlementParams));

        if (settlementParams.amount0Min == 0 && settlementParams.amount1Min == 0) {
            revert AtLeastOneAmountMustBeGreaterThanZero();
        }

        // detect if it's a single token or dual token migration
        if (migrationId == bytes32(0)) {
            // single token migration

            if (token != settlementParams.token0 && token != settlementParams.token1) {
                revert BridgedTokenMustBeUsedInPosition();
            }

            // determine if a swap is needed
            uint256 totalFeesInBps = protocolFeeBps + settlementParams.senderFeeBps;
            uint256 amountToTrade = token == settlementParams.token0
                ? amount - (settlementParams.amount0Min * (10000 - totalFeesInBps)) / 10000
                : amount - (settlementParams.amount1Min * (10000 - totalFeesInBps)) / 10000;
            uint256 amountOut = 0;
            if (amountToTrade > 0) {
                // swap the base token for the other token
                amountOut = swapRouter.swap(
                    token,
                    settlementParams.token0 == token ? settlementParams.token1 : settlementParams.token0,
                    settlementParams.feeTier,
                    amountToTrade,
                    0
                );
            }

            uint256 amount0Desired = 0;
            uint256 amount1Desired = 0;

            if (token == settlementParams.token0) {
                amount0Desired = settlementParams.amount0Min * (10000 - protocolFeeBps) / 10000;
                amount1Desired = amountOut;
            } else if (token == settlementParams.token1) {
                amount0Desired = amountOut;
                amount1Desired = settlementParams.amount1Min * (10000 - protocolFeeBps) / 10000;
            }
            (uint256 tokenId,, uint256 amount0Paid, uint256 amount1Paid) = positionManager.mintPosition(
                settlementParams.token0,
                settlementParams.token1,
                settlementParams.feeTier,
                settlementParams.tickLower,
                settlementParams.tickUpper,
                amount0Desired,
                amount1Desired,
                settlementParams.recipient
            );
            // refund any leftovers
            if (amount0Paid < amount0Desired) {
                IERC20(settlementParams.token0).safeTransfer(settlementParams.recipient, amount0Desired - amount0Paid);
            }
            if (amount1Paid < amount1Desired) {
                IERC20(settlementParams.token1).safeTransfer(settlementParams.recipient, amount1Desired - amount1Paid);
            }
            emit FullySettled(
                migrationId,
                settlementParams.recipient,
                tokenId,
                amount0Paid,
                amount1Paid,
                amount0Desired - amount0Paid,
                amount1Desired - amount1Paid
            );
            return tokenId;
        } else {
            PartialSettlement memory partialSettlement = partialSettlements[migrationId];

            // case 1: first of the two pieces arrives
            if (partialSettlement.token == address(0)) {
                partialSettlements[migrationId] = PartialSettlement(token, amount, settlementParams);
                emit PartiallySettled(migrationId, settlementParams.recipient, token, amount);
                return 0;
            } else {
                // case 2: second of the two pieces arrives

                // verify that partialSettlement and current token are both present in the settlementParams
                if (
                    (
                        partialSettlement.token != settlementParams.token0
                            && partialSettlement.token != settlementParams.token1
                    ) || (token != settlementParams.token0 && token != settlementParams.token1)
                ) {
                    revert BridgedTokenMustBeUsedInPosition();
                }

                if (partialSettlement.token == token) revert BridgedTokensMustBeDifferent();

                // verify that settlementParams match up with the partial settlement
                if (!this.compareSettlementParams(settlementParams, partialSettlement.settlementParams)) {
                    revert SettlementParamsDoNotMatch();
                }

                // match up amounts to tokens
                (uint256 amount0, uint256 amount1) = token == settlementParams.token0
                    ? (amount, partialSettlement.amount)
                    : (partialSettlement.amount, amount);

                (uint256 senderFeeAmount0, uint256 protocolFeeAmount0) = _calculateFees(amount0, message);
                (uint256 senderFeeAmount1, uint256 protocolFeeAmount1) = _calculateFees(amount1, message);
                uint256 amount0Desired = amount0 - senderFeeAmount0 - protocolFeeAmount0;
                uint256 amount1Desired = amount1 - senderFeeAmount1 - protocolFeeAmount1;
                // mint the new position
                (uint256 tokenId,, uint256 amount0Paid, uint256 amount1Paid) = positionManager.mintPosition(
                    settlementParams.token0,
                    settlementParams.token1,
                    settlementParams.feeTier,
                    settlementParams.tickLower,
                    settlementParams.tickUpper,
                    amount0Desired,
                    amount1Desired,
                    settlementParams.recipient
                );

                // refund any leftovers
                if (amount0Paid < amount0Desired) {
                    IERC20(settlementParams.token0).safeTransfer(
                        settlementParams.recipient, amount0Desired - amount0Paid
                    );
                }
                if (amount1Paid < amount1Desired) {
                    IERC20(settlementParams.token1).safeTransfer(
                        settlementParams.recipient, amount1Desired - amount1Paid
                    );
                }

                // clear partial settlement
                delete partialSettlements[migrationId];

                // transfer fees to the protocol and sender
                if (protocolFeeAmount0 > 0) {
                    IERC20(settlementParams.token0).transfer(protocolFeeRecipient, protocolFeeAmount0);
                }
                if (protocolFeeAmount1 > 0) {
                    IERC20(settlementParams.token1).transfer(protocolFeeRecipient, protocolFeeAmount1);
                }
                if (senderFeeAmount0 > 0) {
                    IERC20(settlementParams.token0).transfer(settlementParams.senderFeeRecipient, senderFeeAmount0);
                }
                if (senderFeeAmount1 > 0) {
                    IERC20(settlementParams.token1).transfer(settlementParams.senderFeeRecipient, senderFeeAmount1);
                }
                emit FullySettled(
                    migrationId,
                    settlementParams.recipient,
                    tokenId,
                    amount0Paid,
                    amount1Paid,
                    amount0Desired - amount0Paid,
                    amount1Desired - amount1Paid
                );
                return tokenId;
            }
        }
    }

    function withdraw(bytes32 migrationId) external {
        _refund(migrationId);
    }
}
