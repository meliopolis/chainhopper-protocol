// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "lib/forge-std/src/Test.sol";
import {SettlerMock} from "./mocks/SettlerMock.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract SettlerTest is Test {
    SettlerMock public settler;
    address public protocolFeeRecipient = address(456);
    uint24 public protocolFeeBps = 10;
    uint8 public protocolShareOfSenderFeeInPercent = 20;
    address public owner = address(1);
    address public user = address(2);
    address public baseToken = vm.envAddress("BASE_WETH");

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_MAINNET_RPC_URL"), 25394775);
        vm.prank(owner);
        settler = new SettlerMock(protocolFeeBps, protocolFeeRecipient, protocolShareOfSenderFeeInPercent);
    }

    function generateSettlementParams(uint24 senderFeeBps, address senderFeeRecipient, bytes32 migrationId)
        public
        pure
        returns (bytes memory)
    {
        return abi.encode(migrationId, senderFeeBps, senderFeeRecipient);
    }

    /*
    * Setters
    */

    function test_setProtocolFeeBpsFailsIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        settler.setProtocolFeeBps(5);
    }

    function test_setProtocolFeeBpsSucceedsWhenOwner() public {
        vm.prank(owner);
        settler.setProtocolFeeBps(1);
        assertEq(settler.protocolFeeBps(), 1);
    }

    function test_setProtocolFeeRecipientFailsIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        settler.setProtocolFeeRecipient(address(0x4));
        assertEq(settler.protocolFeeRecipient(), protocolFeeRecipient);
    }

    function test_setProtocolFeeRecipientSucceedsWhenOwner() public {
        vm.prank(owner);
        settler.setProtocolFeeRecipient(address(0x4));
        assertEq(settler.protocolFeeRecipient(), address(0x4));
    }

    function test_setProtocolShareOfSenderFeeInPercentFailsIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        settler.setProtocolShareOfSenderFeeInPercent(50);
        assertEq(settler.protocolShareOfSenderFeeInPercent(), 20);
    }

    function test_setProtocolShareOfSenderFeeInPercentSucceedsWhenOwner() public {
        vm.prank(owner);
        settler.setProtocolShareOfSenderFeeInPercent(50);
        assertEq(settler.protocolShareOfSenderFeeInPercent(), 50);
    }

    /*
     * _calculateFees() tests
     */

    function test__calculateFees_allThreeZero() public {
        vm.prank(owner);
        settler.setProtocolFeeBps(0);
        vm.prank(owner);
        settler.setProtocolShareOfSenderFeeInPercent(0);
        bytes memory params = this.generateSettlementParams(0, address(0), bytes32(0));
        (uint256 netSenderFeeAmount, uint256 totalProtocolFeeAmount) = settler.exposed_calculateFees(1 ether, params);
        assertEq(netSenderFeeAmount, 0);
        assertEq(totalProtocolFeeAmount, 0);
    }

    function test_calculateFees_protocolFeeZero_senderFeeShareZero_senderFeeNonZero() public {
        vm.prank(owner);
        settler.setProtocolFeeBps(0);
        vm.prank(owner);
        settler.setProtocolShareOfSenderFeeInPercent(0);
        bytes memory params = this.generateSettlementParams(15, address(1), bytes32(0));
        (uint256 netSenderFeeAmount, uint256 totalProtocolFeeAmount) = settler.exposed_calculateFees(1 ether, params);
        assertEq(netSenderFeeAmount, 0.0015 ether);
        assertEq(totalProtocolFeeAmount, 0);
    }

    function test_calculateFees_protocolFeeZero_senderFeeShareNonZero_senderFeeZero() public {
        vm.prank(owner);
        settler.setProtocolFeeBps(0);
        vm.prank(owner);
        settler.setProtocolShareOfSenderFeeInPercent(20);
        bytes memory params = this.generateSettlementParams(0, address(0), bytes32(0));
        (uint256 netSenderFeeAmount, uint256 totalProtocolFeeAmount) = settler.exposed_calculateFees(1 ether, params);
        assertEq(netSenderFeeAmount, 0);
        assertEq(totalProtocolFeeAmount, 0);
    }

    function test_calculateFees_protocolFeeZero_senderFeeShareNonZero_senderFeeNonZero() public {
        vm.prank(owner);
        settler.setProtocolFeeBps(0);
        vm.prank(owner);
        settler.setProtocolShareOfSenderFeeInPercent(20);
        bytes memory params = this.generateSettlementParams(15, address(1), bytes32(0));
        (uint256 netSenderFeeAmount, uint256 totalProtocolFeeAmount) = settler.exposed_calculateFees(1 ether, params);
        assertEq(netSenderFeeAmount, 0.0012 ether);
        assertEq(totalProtocolFeeAmount, 0.0003 ether);
    }

    function test_calculateFees_protocolFeeNonZero_senderFeeShareZero_senderFeeZero() public {
        vm.prank(owner);
        settler.setProtocolShareOfSenderFeeInPercent(0);
        bytes memory params = this.generateSettlementParams(0, address(0), bytes32(0));
        (uint256 netSenderFeeAmount, uint256 totalProtocolFeeAmount) = settler.exposed_calculateFees(1 ether, params);
        assertEq(netSenderFeeAmount, 0);
        assertEq(totalProtocolFeeAmount, 0.001 ether);
    }

    function test_calculateFees_protocolFeeNonZero_senderFeeShareZero_senderFeeNonZero() public {
        vm.prank(owner);
        settler.setProtocolShareOfSenderFeeInPercent(0);
        bytes memory params = this.generateSettlementParams(15, address(1), bytes32(0));
        (uint256 netSenderFeeAmount, uint256 totalProtocolFeeAmount) = settler.exposed_calculateFees(1 ether, params);
        assertEq(netSenderFeeAmount, 0.0015 ether);
        assertEq(totalProtocolFeeAmount, 0.001 ether);
    }

    function test_calculateFees_protocolFeeNonZero_senderFeeShareNonZero_senderFeeZero() public view {
        bytes memory params = this.generateSettlementParams(0, address(0), bytes32(0));
        (uint256 netSenderFeeAmount, uint256 totalProtocolFeeAmount) = settler.exposed_calculateFees(1 ether, params);
        assertEq(netSenderFeeAmount, 0);
        assertEq(totalProtocolFeeAmount, 0.001 ether);
    }

    function test_calculateFees_protocolFeeNonZero_senderFeeShareNonZero_senderFeeNonZero() public view {
        bytes memory params = this.generateSettlementParams(15, address(1), bytes32(0));
        (uint256 netSenderFeeAmount, uint256 totalProtocolFeeAmount) = settler.exposed_calculateFees(1 ether, params);
        assertEq(netSenderFeeAmount, 0.0012 ether);
        assertEq(totalProtocolFeeAmount, 0.0013 ether);
    }

    /*
     * Settle() tests
     */

    function test_settleTransfersProtocolFeeWhenSenderFeeZero() public {
        deal(baseToken, address(settler), 1 ether);
        bytes memory params = this.generateSettlementParams(0, address(0), bytes32(0));
        vm.expectEmit(true, false, false, false, baseToken);
        emit IERC20.Transfer(address(settler), protocolFeeRecipient, 0.001 ether);
        uint256 tokenId = settler.settle(baseToken, 1 ether, params);
        assertEq(tokenId, 0.999 ether);
    }

    function test_settleTransfersSenderFeeWhenProtocolFeeZero() public {
        vm.prank(owner);
        settler.setProtocolFeeBps(0);
        vm.prank(owner);
        settler.setProtocolShareOfSenderFeeInPercent(0);
        deal(baseToken, address(settler), 1 ether);
        bytes memory params = this.generateSettlementParams(15, address(1), bytes32(0));
        vm.expectEmit(true, false, false, false, baseToken);
        emit IERC20.Transfer(address(settler), address(1), 0.0015 ether);
        uint256 tokenId = settler.settle(baseToken, 1 ether, params);
        assertEq(tokenId, 0.9985 ether);
    }

    function test_settleTransfersBothFeesWhenBothAreNonZero() public {
        deal(baseToken, address(settler), 1 ether);
        bytes memory params = this.generateSettlementParams(15, address(1), bytes32(0));
        vm.expectEmit(true, false, false, false, baseToken);
        emit IERC20.Transfer(address(settler), protocolFeeRecipient, 0.001 ether);
        vm.expectEmit(true, false, false, false, baseToken);
        emit IERC20.Transfer(address(settler), address(1), 0.0015 ether);
        uint256 tokenId = settler.settle(baseToken, 1 ether, params);
        assertEq(tokenId, 0.9975 ether);
    }

    function test_settle_MigrationId_NoFeesTransferred() public {
        bytes memory params = this.generateSettlementParams(15, address(1), bytes32("1111"));
        uint256 tokenId = settler.settle(baseToken, 1 ether, params);
        assertEq(tokenId, 1 ether);
    }
}
