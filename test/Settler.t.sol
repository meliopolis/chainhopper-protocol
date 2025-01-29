// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "lib/forge-std/src/Test.sol";
import {SettlerMock} from "./mocks/SettlerMock.sol";

contract SettlerTest is Test {
    SettlerMock public settler;
    address public protocolFeeRecipient = address(1);
    uint24 public protocolFeeBps = 10;
    uint8 public protocolShareOfSenderFeeInPercent = 20;

    function setUp() public {
        settler = new SettlerMock(protocolFeeBps, protocolFeeRecipient, protocolShareOfSenderFeeInPercent);
    }
}
