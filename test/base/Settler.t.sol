// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {Settler} from "../../src/base/Settler.sol";
import {ISettler} from "../../src/interfaces/ISettler.sol";
import {MigrationId, MigrationIdLibrary} from "../../src/types/MigrationId.sol";
import {MigrationMode, MigrationModes} from "../../src/types/MigrationMode.sol";
import {BaseTest} from "../utils/BaseTest.sol";

contract SettlerTest is BaseTest {
    function setUp() public override {
        super.setUp();
    }

    function _mockBaseSettlementParams(MigrationMode mode, address recipient)
        private
        pure
        returns (ISettler.BaseSettlementParams memory params)
    {
        params =
            ISettler.BaseSettlementParams(MigrationIdLibrary.from(0, address(0), mode, 0), recipient, 0, address(0));
    }

    // fee functions

    function test_setProtocolShareBps_fails_ifNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER), address(settler));

        vm.prank(USER);
        settler.setProtocolShareBps(0);
    }

    function test_fuzz_setProtocolShareBps(uint16 protocolShareBps) public {
        if (protocolShareBps > 10_000) {
            vm.expectRevert(abi.encodeWithSelector(Settler.InvalidProtocolShareBps.selector, protocolShareBps));

            vm.prank(OWNER);
            settler.setProtocolShareBps(protocolShareBps);
        } else {
            vm.expectEmit(false, false, false, true);
            emit Settler.ProtocolShareBpsUpdated(protocolShareBps);

            vm.prank(OWNER);
            settler.setProtocolShareBps(protocolShareBps);

            assertEq(settler.protocolShareBps(), protocolShareBps);
        }
    }

    function test_setProtocolShareOfSenderFeePct_fails_ifNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER), address(settler));

        vm.prank(USER);
        settler.setProtocolShareOfSenderFeePct(0);
    }

    function test_fuzz_setProtocolShareOfSenderFeePct(uint8 protocolShareOfSenderFeePct) public {
        if (protocolShareOfSenderFeePct > 100) {
            vm.expectRevert(
                abi.encodeWithSelector(Settler.InvalidProtocolShareOfSenderFeePct.selector, protocolShareOfSenderFeePct)
            );

            vm.prank(OWNER);
            settler.setProtocolShareOfSenderFeePct(protocolShareOfSenderFeePct);
        } else {
            vm.expectEmit(false, false, false, true);
            emit Settler.ProtocolShareOfSenderFeePctUpdated(protocolShareOfSenderFeePct);

            vm.prank(OWNER);
            settler.setProtocolShareOfSenderFeePct(protocolShareOfSenderFeePct);

            assertEq(settler.protocolShareOfSenderFeePct(), protocolShareOfSenderFeePct);
        }
    }

    function test_setProtocolFeeRecipient_fails_ifNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER), address(settler));

        vm.prank(USER);
        settler.setProtocolFeeRecipient(address(0));
    }

    function test_setProtocolFeeRecipient_fails_ifZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Settler.InvalidProtocolFeeRecipient.selector, address(0)));

        vm.prank(OWNER);
        settler.setProtocolFeeRecipient(address(0));
    }

    function test_fuzz_setProtocolFeeRecipient(address protocolFeeRecipient) public {
        vm.assume(protocolFeeRecipient != address(0));

        vm.expectEmit(false, false, false, true);
        emit Settler.ProtocolFeeRecipientUpdated(protocolFeeRecipient);

        vm.prank(OWNER);
        settler.setProtocolFeeRecipient(protocolFeeRecipient);

        assertEq(settler.protocolFeeRecipient(), protocolFeeRecipient);
    }

    // settle(), other than single or dual routes

    function test_settle_fails_ifNotSelf() public {
        vm.expectRevert(abi.encodeWithSelector(ISettler.NotSelf.selector), address(settler));
        vm.prank(USER);
        settler.settle(address(0), 0, "");
    }

    function test_settle_fails_ifTokenAmountMissing() public {
        vm.expectRevert(abi.encodeWithSelector(ISettler.TokenAmountMissing.selector, address(0)), address(settler));
        settler.wrappedSettle(address(0), 0, "");
    }

    function test_settle_fails_ifInvalidSenderShareBps() public {
        bytes memory data =
            abi.encode(ISettler.BaseSettlementParams(MigrationId.wrap(0), address(0), 10_001, address(0)));

        vm.expectRevert(abi.encodeWithSelector(ISettler.InvalidSenderShareBps.selector, 10_001), address(settler));
        settler.wrappedSettle(address(0), 100, data);
    }

    // settle(), single & dual routes
    function test_settle_succeeds_singleRoute() public {
        ISettler.BaseSettlementParams memory params = _mockBaseSettlementParams(MigrationModes.SINGLE, USER);

        vm.expectEmit(true, true, true, true);
        emit ISettler.Migrated(params.migrationId, USER, weth, 100);
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(params.migrationId, USER, 0);

        settler.wrappedSettle(weth, 100, abi.encode(params));
    }

    function test_settle_fails_ifSettlementDataMismatch() public {
        ISettler.BaseSettlementParams memory params1 = _mockBaseSettlementParams(MigrationModes.DUAL, USER);
        ISettler.BaseSettlementParams memory params2 = _mockBaseSettlementParams(MigrationModes.DUAL, OWNER);

        vm.expectEmit(true, true, true, true);
        emit ISettler.Migrated(params1.migrationId, USER, weth, 100);

        settler.wrappedSettle(weth, 100, abi.encode(params1));

        vm.expectEmit(true, true, true, true);
        emit ISettler.Migrated(params1.migrationId, OWNER, usdc, 200);
        vm.expectRevert(abi.encodeWithSelector(ISettler.SettlementDataMismatch.selector), address(settler));

        settler.wrappedSettle(usdc, 200, abi.encode(params2));
    }

    function test_settle_succeeds_dualRoute() public {
        ISettler.BaseSettlementParams memory params = _mockBaseSettlementParams(MigrationModes.DUAL, USER);

        vm.expectEmit(true, true, true, true);
        emit ISettler.Migrated(params.migrationId, USER, weth, 100);

        settler.wrappedSettle(weth, 100, abi.encode(params));

        vm.expectEmit(true, true, true, true);
        emit ISettler.Migrated(params.migrationId, USER, usdc, 200);
        vm.expectEmit(true, true, false, true);
        emit ISettler.Settlement(params.migrationId, USER, 0);

        settler.wrappedSettle(usdc, 200, abi.encode(params));
    }

    // withdraw() & _refund()

    function test_fuzz_withdraw(bool isNative, bool isRecipient, uint256 amount) public {
        address token = isNative ? address(0) : weth;
        vm.assume(amount > 0);
        if (isNative) {
            deal(address(settler), amount);
        } else {
            deal(token, address(settler), amount);
        }
        settler.setSettlementCache(MigrationId.wrap(0), USER, token, amount);

        if (!isRecipient) {
            vm.expectRevert(abi.encodeWithSelector(ISettler.NotRecipient.selector), address(settler));
        } else {
            vm.expectEmit(true, true, true, true);
            emit ISettler.Refund(MigrationId.wrap(0), USER, token, amount);
        }

        if (isRecipient) vm.prank(USER);
        settler.withdraw(MigrationId.wrap(0));
    }

    function test_fuzz__refund(bool isNative, bool onlyRecipient, bool isRecipient, uint256 amount) public {
        address token = isNative ? address(0) : weth;
        vm.assume(amount > 0);
        if (isNative) {
            deal(address(settler), amount);
        } else {
            deal(token, address(settler), amount);
        }
        settler.setSettlementCache(MigrationId.wrap(0), USER, token, amount);

        if (onlyRecipient && !isRecipient) {
            vm.expectRevert(abi.encodeWithSelector(ISettler.NotRecipient.selector), address(settler));
        } else {
            vm.expectEmit(true, true, true, true);
            emit ISettler.Refund(MigrationId.wrap(0), USER, token, amount);
        }

        if (isRecipient) vm.prank(USER);
        settler.refund(MigrationId.wrap(0), onlyRecipient);
    }

    // _calculateFees() & _payFees()

    function test__calculateFees_fails_ifMaxFeeExceeded() public {
        uint16 protocolShareBps = 5_000;
        uint16 senderShareBps = 5_001;
        vm.prank(OWNER);
        settler.setProtocolShareBps(protocolShareBps);

        vm.expectRevert(abi.encodeWithSelector(ISettler.MaxFeeExceeded.selector, protocolShareBps, senderShareBps));

        settler.calculateFees(1 ether, senderShareBps);
    }

    function test_fuzz__calculateFees(uint16 protocolShareBps, uint8 protocolShareOfSenderFeePct, uint16 senderShareBps)
        public
    {
        vm.assume(protocolShareBps + uint256(senderShareBps) <= 10_000);
        vm.assume(protocolShareOfSenderFeePct <= 100);

        vm.startPrank(OWNER);
        settler.setProtocolShareBps(protocolShareBps);
        settler.setProtocolShareOfSenderFeePct(protocolShareOfSenderFeePct);
        vm.stopPrank();

        (uint256 protocolFee, uint256 senderFee) = settler.calculateFees(1 ether, senderShareBps);

        assertEq(
            protocolFee + senderFee,
            1 ether * uint256(protocolShareBps) / 10_000 + 1 ether * uint256(senderShareBps) / 10_000
        );
    }

    function test_fuzz__payFees(bool isNative, uint256 protocolFee, uint256 senderFee) public {
        vm.assume(protocolFee < type(uint128).max && senderFee < type(uint128).max);

        address token = isNative ? address(0) : weth;
        if (isNative) {
            deal(address(settler), protocolFee + senderFee);
        } else {
            deal(token, address(settler), protocolFee + senderFee);
        }

        vm.expectEmit(true, false, false, true);
        emit ISettler.FeePayment(token, protocolFee, senderFee);

        settler.payFees(token, protocolFee, senderFee);
    }

    // _transfer()

    function test_fuzz_transfer(bool isNative, uint256 balance, uint256 amount) public {
        vm.assume(amount < type(uint128).max);

        if (isNative) {
            deal(address(settler), balance);
        } else {
            deal(weth, address(settler), balance);
        }

        if (balance < amount) {
            if (isNative) {
                vm.expectRevert(abi.encodeWithSelector(ISettler.NativeAssetTransferFailed.selector, USER, amount), USER);
            } else {
                vm.expectRevert();
            }
        }

        settler.transfer(isNative ? address(0) : weth, USER, amount);
    }
}
