// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {AcrossV3Migrator} from "../src/AcrossV3Migrator.sol";

/*
forge script script/ManageChainSettlers.s.sol:ManageChainSettlerScript \
    --rpc-url $UNICHAIN_MAINNET_RPC_URL \
    --private-key $PRIVATE_KEY \
    -vvvvv \
    --slow \
    --sig 'run(address)' $UNICHAIN_MIGRATOR
*/
contract ManageChainSettlerScript is Script {
    function run(address migrator) public {
        vm.startBroadcast(vm.envAddress("PUBLIC_KEY"));
        AcrossV3Migrator(migrator).addChainSettler(8453, 0x691F0E6833362c9B96c0292bcd5Ce74f46300786);
        AcrossV3Migrator(migrator).addChainSettler(42161, 0xD5C28d7932F44d2edD9fA6E62bc827B9aa543978);
        vm.stopBroadcast();
    }
}
