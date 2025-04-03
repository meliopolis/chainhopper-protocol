// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {UniswapV3AcrossSettler} from "../src/UniswapV3AcrossSettler.sol";

/*
    forge script script/DeployUniswapV3AcrossSettler.s.sol:DeployUniswapV3AcrossSettler \
    --rpc-url <rpc_endpoints> \
    --etherscan-api-key <etherscan_api_key> \
    --broadcast \
    --verify \
    --sig 'run(string, address)' <ENV> <initialOwner>
*/

contract DeployUniswapV3AcrossSettler is Script {
    function run(string memory env, address initialOwner) public {
        vm.broadcast(vm.envUint("PRIVATE_KEY"));

        UniswapV3AcrossSettler settler = new UniswapV3AcrossSettler(
            initialOwner,
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_V3_POSITION_MANAGER"))),
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_UNIVERSAL_ROUTER"))),
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_PERMIT2"))),
            vm.envAddress(string(abi.encodePacked(env, "_ACROSS_SPOKE_POOL")))
        );

        console.log("UniswapV3AcrossSettler deployed at:", address(settler));
    }

    // add this to be excluded from coverage report
    function test() public {}
}
