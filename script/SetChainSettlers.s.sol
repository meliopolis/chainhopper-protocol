// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "@forge-std/Script.sol";
import {Migrator} from "../src/base/Migrator.sol";

/*
    forge script script/SetChainSettlers.s.sol:SetChainSettlers \
    --rpc-url <rpc_endpoints> \
    --broadcast \
    --verify \
    --sig 'run(address)' <MIGRATOR ADDRESS>
*/

contract SetChainSettlers is Script {
    function run(address migrator) public {
        uint32[] memory chainIds = new uint32[](2);
        // TODO:

        address[] memory settlers = new address[](2);
        // TODO:

        vm.broadcast(vm.envUint("PRIVATE_KEY"));

        Migrator(migrator).flipChainSettlers(chainIds, settlers);
    }

    // add this to be excluded from coverage report
    function test() public {}
}
