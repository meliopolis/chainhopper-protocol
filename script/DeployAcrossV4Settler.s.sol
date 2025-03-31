// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "@forge-std/Script.sol";
import {AcrossV4Settler} from "../src/AcrossV4Settler.sol";

/*
    forge script script/DeployAcrossV4Settler.s.sol:DeployAcrossV4Settler \
    --rpc-url <rpc_endpoints> \
    --broadcast \
    --verify \
    --sig 'run(string,uint24,uint8,address)' <ENV> <initialOwner>
*/

contract DeployAcrossV4Settler is Script {
    function run(string memory env, address initialOwner) public {
        vm.broadcast(vm.envUint("PRIVATE_KEY"));

        AcrossV4Settler settler = new AcrossV4Settler(
            initialOwner,
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_V4_POSITION_MANAGER"))),
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_UNIVERSAL_ROUTER"))),
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_PERMIT2"))),
            vm.envAddress(string(abi.encodePacked(env, "_ACROSS_SPOKE_POOL"))),
            vm.envAddress(string(abi.encodePacked(env, "_WETH")))
        );

        console.log("AcrossV4Settler deployed at:", address(settler));
    }

    // add this to be excluded from coverage report
    function test() public {}
}
