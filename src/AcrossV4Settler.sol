// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {console} from "forge-std/console.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {AcrossSettler} from "./base/AcrossSettler.sol";
import {Settler} from "./base/Settler.sol";
import {IPositionManager} from "./interfaces/external/IUniswapV4.sol";
import {IUniversalRouter} from "./interfaces/external/IUniversalRouter.sol";
import {IV4Settler} from "./interfaces/IV4Settler.sol";
import {IPermit2} from "./interfaces/external/IPermit2.sol";
import {IWETH} from "./interfaces/external/IWETH.sol";
import {UniswapV4Library} from "./libraries/UniswapV4Library.sol";
import {UniversalRouterLibrary} from "./libraries/UniversalRouterLibrary.sol";

contract AcrossV4Settler is IV4Settler, AcrossSettler {
    struct AmountBreakdown {
        uint256 senderFee;
        uint256 protocolFee;
        uint256 netAmount;
    }

    struct PartialSettlement {
        address token;
        uint256 amount;
        V4SettlementParams settlementParams;
    }

    using SafeERC20 for IERC20;
    using UniswapV4Library for IPositionManager;
    using UniversalRouterLibrary for IUniversalRouter;

    IPermit2 private immutable permit2;
    IWETH private immutable weth;
    IUniversalRouter private immutable universalRouter;
    IPositionManager private immutable positionManager;
    mapping(bytes32 => PartialSettlement) public partialSettlements;

    constructor(
        address _spokePool,
        address _protocolFeeRecipient,
        uint24 _protocolFeeBps,
        uint8 _protocolShareOfSenderFeeInPercent,
        address _universalRouter,
        address _positionManager,
        address _weth,
        address _permit2
    ) AcrossSettler(_spokePool) Settler(_protocolFeeBps, _protocolFeeRecipient, _protocolShareOfSenderFeeInPercent) {
        universalRouter = IUniversalRouter(_universalRouter);
        positionManager = IPositionManager(_positionManager);
        weth = IWETH(_weth);
        permit2 = IPermit2(_permit2);
    }

    function _getRecipient(bytes memory message) internal view virtual override returns (address) {
        (, bytes memory settlementMessage) = abi.decode(message, (bytes32, bytes));
        (V4SettlementParams memory settlementParams) = abi.decode(settlementMessage, (V4SettlementParams));
        return settlementParams.recipient;
    }

    function _getSenderFees(bytes memory message) internal view virtual override returns (uint24, address) {
        (, bytes memory settlementMessage) = abi.decode(message, (bytes32, bytes));
        (V4SettlementParams memory settlementParams) = abi.decode(settlementMessage, (V4SettlementParams));
        return (settlementParams.senderFeeBps, settlementParams.senderFeeRecipient);
    }

    function _refund(bytes32 migrationId) internal override {
        PartialSettlement memory partialSettlement = partialSettlements[migrationId];
        if (partialSettlement.token != address(0)) {
            IERC20(partialSettlement.token).safeTransfer(
                partialSettlement.settlementParams.recipient, partialSettlement.amount
            );
            delete partialSettlements[migrationId];
        }
    }

    function _settle(address token, uint256 amount, bytes memory message) internal virtual override returns (uint256) {
        (bytes32 migrationId, bytes memory settlementMessage) = abi.decode(message, (bytes32, bytes));
        (V4SettlementParams memory settlementParams) = abi.decode(settlementMessage, (V4SettlementParams));

        if (settlementParams.amount0Min == 0 && settlementParams.amount1Min == 0) {
            revert AtLeastOneAmountMustBeGreaterThanZero();
        }

        if (migrationId == bytes32(0)) {
            if (_ethable(token) != settlementParams.token0 && token != settlementParams.token1) {
                revert BridgedTokenMustBeUsedInPosition();
            }

            if (token == address(weth) && settlementParams.token0 == address(0)) {
                weth.withdraw(amount);
            }

            uint256 amountOut;
            {
                uint256 totalFeesInBps = protocolFeeBps + settlementParams.senderFeeBps;
                uint256 amountToTrade = token == settlementParams.token0
                    ? amount - (settlementParams.amount0Min * (10000 - totalFeesInBps)) / 10000
                    : amount - (settlementParams.amount1Min * (10000 - totalFeesInBps)) / 10000;

                if (amountToTrade > 0) {
                    amountOut = universalRouter.swap(
                        settlementParams.token0,
                        settlementParams.token1,
                        settlementParams.feeTier,
                        settlementParams.tickSpacing,
                        settlementParams.hooks,
                        token == settlementParams.token0,
                        amountToTrade
                    );
                }
            }

            uint256 amount0Desired = 0;
            uint256 amount1Desired = 0;

            if ((token == address(weth) && settlementParams.token0 == address(0)) || token == settlementParams.token0) {
                amount0Desired = settlementParams.amount0Min * (10000 - protocolFeeBps) / 10000;
                amount1Desired = amountOut;
            } else if (token == settlementParams.token1) {
                amount0Desired = amountOut;
                amount1Desired = settlementParams.amount1Min * (10000 - protocolFeeBps) / 10000;
            }

            if (settlementParams.token0 != address(0)) {
                IERC20(settlementParams.token0).approve(address(permit2), amount0Desired);
                permit2.approve(settlementParams.token0, address(positionManager), uint160(amount0Desired), 0);
            }
            IERC20(settlementParams.token1).approve(address(permit2), amount1Desired);
            permit2.approve(settlementParams.token1, address(positionManager), uint160(amount1Desired), 0);

            (uint256 tokenId,, uint256 amount0Paid, uint256 amount1Paid) = positionManager.mintPosition(
                settlementParams.token0,
                settlementParams.token1,
                settlementParams.feeTier,
                settlementParams.tickSpacing,
                settlementParams.hooks,
                settlementParams.tickLower,
                settlementParams.tickUpper,
                amount0Desired,
                amount1Desired,
                settlementParams.recipient
            );

            if (amount0Paid < amount0Desired) {
                if (settlementParams.token0 == address(0)) {
                    weth.deposit{value: amount0Desired - amount0Paid}();
                    IERC20(address(weth)).safeTransfer(settlementParams.recipient, amount0Desired - amount0Paid);
                } else {
                    IERC20(settlementParams.token0).safeTransfer(
                        settlementParams.recipient, amount0Desired - amount0Paid
                    );
                }
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

            if (partialSettlement.token == address(0)) {
                partialSettlements[migrationId] = PartialSettlement(token, amount, settlementParams);
                emit PartiallySettled(migrationId, settlementParams.recipient, token, amount);
                return 0;
            } else {
                if (
                    (
                        _ethable(partialSettlement.token) != settlementParams.token0
                            && partialSettlement.token != settlementParams.token1
                    ) || (_ethable(token) != settlementParams.token0 && token != settlementParams.token1)
                ) {
                    revert BridgedTokenMustBeUsedInPosition();
                }

                if (partialSettlement.token == token) revert BridgedTokensMustBeDifferent();

                if (!this.compareSettlementParams(settlementParams, partialSettlement.settlementParams)) {
                    revert SettlementParamsDoNotMatch();
                }

                delete partialSettlements[migrationId];

                AmountBreakdown memory amount0 =
                    _breakdownAmount(token == settlementParams.token0 ? amount : partialSettlement.amount, message);
                AmountBreakdown memory amount1 =
                    _breakdownAmount(token == settlementParams.token0 ? partialSettlement.amount : amount, message);

                if (settlementParams.token0 == address(0)) {
                    weth.withdraw(amount0.netAmount);
                } else {
                    IERC20(settlementParams.token0).approve(address(permit2), amount0.netAmount);
                    permit2.approve(settlementParams.token0, address(positionManager), uint160(amount0.netAmount), 0);
                }
                IERC20(settlementParams.token1).approve(address(permit2), amount1.netAmount);
                permit2.approve(settlementParams.token1, address(positionManager), uint160(amount1.netAmount), 0);

                (uint256 tokenId,, uint256 amount0Paid, uint256 amount1Paid) = positionManager.mintPosition(
                    settlementParams.token0,
                    settlementParams.token1,
                    settlementParams.feeTier,
                    settlementParams.tickSpacing,
                    settlementParams.hooks,
                    settlementParams.tickLower,
                    settlementParams.tickUpper,
                    amount0.netAmount,
                    amount1.netAmount,
                    settlementParams.recipient
                );

                if (amount0Paid < amount0.netAmount) {
                    if (settlementParams.token0 == address(0)) {
                        weth.deposit{value: amount0.netAmount - amount0Paid}();
                    }

                    IERC20(settlementParams.token0 == address(0) ? address(weth) : settlementParams.token0).safeTransfer(
                        settlementParams.recipient, amount0.netAmount - amount0Paid
                    );
                }
                if (amount1Paid < amount1.netAmount) {
                    IERC20(settlementParams.token1).safeTransfer(
                        settlementParams.recipient, amount1.netAmount - amount1Paid
                    );
                }

                if (amount0.protocolFee > 0) {
                    IERC20(settlementParams.token0 == address(0) ? address(weth) : settlementParams.token0).transfer(
                        protocolFeeRecipient, amount0.protocolFee
                    );
                }
                if (amount1.protocolFee > 0) {
                    IERC20(settlementParams.token1).transfer(protocolFeeRecipient, amount1.protocolFee);
                }
                if (amount0.senderFee > 0) {
                    IERC20(settlementParams.token0 == address(0) ? address(weth) : settlementParams.token0).transfer(
                        settlementParams.senderFeeRecipient, amount0.senderFee
                    );
                }
                if (amount1.senderFee > 0) {
                    IERC20(settlementParams.token1).transfer(settlementParams.senderFeeRecipient, amount1.senderFee);
                }

                emit FullySettled(
                    migrationId,
                    settlementParams.recipient,
                    tokenId,
                    amount0Paid,
                    amount1Paid,
                    amount0.netAmount - amount0Paid,
                    amount1.netAmount - amount1Paid
                );

                return tokenId;
            }
        }
    }

    function compareSettlementParams(V4SettlementParams memory a, V4SettlementParams memory b)
        external
        pure
        returns (bool)
    {
        return a.recipient == b.recipient && a.token0 == b.token0 && a.token1 == b.token1 && a.feeTier == b.feeTier
            && a.tickSpacing == b.tickSpacing && a.hooks == b.hooks && a.tickLower == b.tickLower
            && a.tickUpper == b.tickUpper && a.amount0Min == b.amount0Min && a.amount1Min == b.amount1Min
            && a.senderFeeBps == b.senderFeeBps && a.senderFeeRecipient == b.senderFeeRecipient;
    }

    function _ethable(address token) internal view returns (address) {
        return token == address(weth) ? address(0) : token;
    }

    function _breakdownAmount(uint256 amount, bytes memory message) private view returns (AmountBreakdown memory) {
        (uint256 senderFeeAmount, uint256 protocolFeeAmount) = _calculateFees(amount, message);

        return AmountBreakdown({
            senderFee: senderFeeAmount,
            protocolFee: protocolFeeAmount,
            netAmount: amount - senderFeeAmount - protocolFeeAmount
        });
    }

    function withdraw(bytes32 migrationId) external {
        _refund(migrationId);
    }

    receive() external payable {
        emit Receive(msg.sender, msg.value);
    }
}
