// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ChainSettlers} from "../../src/base/ChainSettlers.sol";

contract MockChainSettlers is ChainSettlers {
    constructor(address initialOwner) ChainSettlers(initialOwner) {}

    // add this to be excluded from coverage report
    function test() public {}
}
