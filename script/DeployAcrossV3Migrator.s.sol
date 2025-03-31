// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "@forge-std/Script.sol";
import {AcrossV3Migrator} from "../src/AcrossV3Migrator.sol";

/*
    forge script script/DeployAcrossV3Migrator.s.sol:DeployAcrossV3Migrator \
    --rpc-url <rpc_endpoints> \
    --broadcast \
    --etherscan-api-key <etherscan_api_key> \
    --verify \
    --sig 'run(string)' <ENV> <initialOwner>
*/

contract DeployAcrossV3Migrator is Script {
    function run(string memory env, address initialOwner) public {
        vm.broadcast(vm.envUint("PRIVATE_KEY"));

        AcrossV3Migrator migrator = new AcrossV3Migrator(
            initialOwner,
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_V3_POSITION_MANAGER"))),
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_UNIVERSAL_ROUTER"))),
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_PERMIT2"))),
            vm.envAddress(string(abi.encodePacked(env, "_ACROSS_SPOKE_POOL")))
        );

        console.log("AcrossV3Migrator deployed at:", address(migrator));
    }

    // add this to be excluded from coverage report
    function test() public {}
}
