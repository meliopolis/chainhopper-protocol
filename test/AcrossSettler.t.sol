// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {AcrossSettlerMock} from "./mocks/AcrossSettlerMock.sol";

contract AcrossSettlerTest is Test {
    AcrossSettlerMock acrossSettler;
    address spokePool = address(456);

    function setUp() public {
        acrossSettler = new AcrossSettlerMock(spokePool);
    }

    function test_handleV3AcrossMessageCallsSettleAndReverts() public {
        vm.prank(spokePool);
        vm.expectCall(
            address(acrossSettler), abi.encodeWithSelector(acrossSettler.settle.selector, address(0), 100, "")
        );
        vm.expectRevert(); // reverts because message is empty
        acrossSettler.handleV3AcrossMessage(address(0), 100, address(0), "");
    }

      function test_handleV3AcrossMessageCallsSettleAndSucceeds() public {
        bytes memory message = abi.encode(bytes32(0), bytes(""));
        vm.prank(spokePool);
        vm.expectCall(
            address(acrossSettler), abi.encodeWithSelector(acrossSettler.settle.selector, address(0), 100, message)
        );
        acrossSettler.handleV3AcrossMessage(address(0), 100, address(0), message);
    }
}
