// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "@forge-std/Test.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {ProtocolFees} from "../../src/base/ProtocolFees.sol";

contract ProtocolFeesTest is Test {
    address user = makeAddr("user");
    address owner = makeAddr("owner");

    ProtocolFees protocolFees;

    function setUp() public {
        protocolFees = new ProtocolFees(owner);
    }

    function test_setProtocolFees_fails_ifNotOwner() public {
        vm.startPrank(user);

        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user), address(protocolFees)
        );
        protocolFees.setProtocolShareBps(0);

        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user), address(protocolFees)
        );
        protocolFees.setProtocolShareOfSenderFeePct(0);

        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user), address(protocolFees)
        );
        protocolFees.setProtocolFeeRecipient(address(0));

        vm.stopPrank();
    }

    function test_fuzz_setProtocolFees(
        uint16 protocolShareBps,
        uint8 protocolShareOfSenderFeePct,
        address protocolFeeRecipient
    ) public {
        vm.startPrank(owner);

        if (protocolShareBps > protocolFees.MAX_PROTOCOL_SHARE_BPS()) {
            vm.expectRevert(
                abi.encodeWithSelector(ProtocolFees.InvalidProtocolShareBps.selector, protocolShareBps),
                address(protocolFees)
            );
        } else {
            vm.expectEmit(true, true, true, true, address(protocolFees));
            emit ProtocolFees.ProtocolShareBpsUpdated(uint16(protocolShareBps));
        }
        protocolFees.setProtocolShareBps(protocolShareBps);

        if (protocolShareOfSenderFeePct > protocolFees.MAX_PROTOCOL_SHARE_OF_SENDER_FEE_PCT()) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    ProtocolFees.InvalidProtocolShareOfSenderFeePct.selector, protocolShareOfSenderFeePct
                ),
                address(protocolFees)
            );
        } else {
            vm.expectEmit(true, true, true, true, address(protocolFees));
            emit ProtocolFees.ProtocolShareOfSenderFeePctUpdated(uint8(protocolShareOfSenderFeePct));
        }
        protocolFees.setProtocolShareOfSenderFeePct(protocolShareOfSenderFeePct);

        if (protocolFeeRecipient != address(0)) {
            vm.expectEmit(true, true, true, true, address(protocolFees));
            emit ProtocolFees.ProtocolFeeRecipientUpdated(protocolFeeRecipient);
            protocolFees.setProtocolFeeRecipient(protocolFeeRecipient);
        }

        vm.expectRevert(
            abi.encodeWithSelector(ProtocolFees.InvalidProtocolFeeRecipient.selector, address(0)), address(protocolFees)
        );
        protocolFees.setProtocolFeeRecipient(address(0));

        vm.stopPrank();
    }
}
