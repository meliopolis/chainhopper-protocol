// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {UniswapV4AcrossSettler} from "../src/UniswapV4AcrossSettler.sol";

/*
    forge script script/DeployUniswapV4AcrossSettler.s.sol:DeployUniswapV4AcrossSettler \
    --rpc-url <rpc_endpoints> \
    --etherscan-api-key <etherscan_api_key> \
    --broadcast \
    --verify \
    --sig 'run(string,address)' <ENV> <initialOwner>
*/

contract DeployUniswapV4AcrossSettler is Script {
    function run(string memory env, address initialOwner) public {
        vm.broadcast(vm.envUint("PRIVATE_KEY"));

        UniswapV4AcrossSettler settler = new UniswapV4AcrossSettler(
            initialOwner,
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_V4_POSITION_MANAGER"))),
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_UNIVERSAL_ROUTER"))),
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_PERMIT2"))),
            vm.envAddress(string(abi.encodePacked(env, "_ACROSS_SPOKE_POOL"))),
            vm.envAddress(string(abi.encodePacked(env, "_WETH")))
        );

        console.log("UniswapV4AcrossSettler deployed at:", address(settler));
    }

    // add this to be excluded from coverage report
    function test() public {}
}
