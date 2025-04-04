// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ProtocolFees} from "../../src/base/ProtocolFees.sol";

contract MockProtocolFees is ProtocolFees {
    constructor(address initialOwner) ProtocolFees(initialOwner) {}

    // add this to be excluded from coverage report
    function test() public {}
}
