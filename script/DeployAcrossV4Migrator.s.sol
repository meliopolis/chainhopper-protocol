// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "@forge-std/Script.sol";
import {AcrossV4Migrator} from "../src/AcrossV4Migrator.sol";

/*
    forge script script/DeployAcrossV4Migrator.s.sol:DeployAcrossV4Migrator \
    --rpc-url sepolia \
    --broadcast \
    --verify \
    --sig 'run(string)' SEPOLIA
*/

contract DeployAcrossV4Migrator is Script {
    function run(string memory env) public {
        vm.broadcast(vm.envUint("PRIVATE_KEY"));

        AcrossV4Migrator migrator = new AcrossV4Migrator(
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_V4_POSITION_MANAGER"))),
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_UNIVERSAL_ROUTER"))),
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_PERMIT2"))),
            vm.envAddress(string(abi.encodePacked(env, "_ACROSS_SPOKE_POOL")))
        );

        console.log("AcrossV4Migrator deployed at:", address(migrator));
    }

    // add this to be excluded from coverage report
    function test() public {}
}
