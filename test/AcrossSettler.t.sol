// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {AcrossSettlerMock} from "./mocks/AcrossSettlerMock.sol";

contract AcrossSettlerTest is Test {
    AcrossSettlerMock acrossSettler;
    address spokePool = address(456);

    function setUp() public {
        acrossSettler = new AcrossSettlerMock(spokePool);
    }

    function test_handleV3AcrossMessageCallsSettleOuter() public {
        vm.prank(spokePool);
        vm.expectCall(
            address(acrossSettler), abi.encodeWithSelector(acrossSettler.settleOuter.selector, address(0), 100, "")
        );
        acrossSettler.handleV3AcrossMessage(address(0), 100, address(0), "");
    }
}
