// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "@forge-std/Script.sol";
import {AcrossV3Settler} from "../src/AcrossV3Settler.sol";

/*
    forge script script/DeployAcrossV3Settler.s.sol:DeployAcrossV3Settler \
    --rpc-url <rpc_endpoints> \
    --broadcast \
    --verify \
    --sig 'run(string,uint24,uint8,address)' <ENV> <initialOwner>
*/

contract DeployAcrossV3Settler is Script {
    function run(string memory env, address initialOwner) public {
        vm.broadcast(vm.envUint("PRIVATE_KEY"));

        AcrossV3Settler settler = new AcrossV3Settler(
            initialOwner,
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_V3_POSITION_MANAGER"))),
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_UNIVERSAL_ROUTER"))),
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_PERMIT2"))),
            vm.envAddress(string(abi.encodePacked(env, "_ACROSS_SPOKE_POOL")))
        );

        console.log("AcrossV3Settler deployed at:", address(settler));
    }

    // add this to be excluded from coverage report
    function test() public {}
}
