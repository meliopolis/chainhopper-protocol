// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {UniswapV4AcrossMigrator} from "../src/UniswapV4AcrossMigrator.sol";

/*
    forge script script/DeployUniswapV4AcrossMigrator.s.sol:DeployUniswapV4AcrossMigrator \
    --rpc-url <rpc_endpoints> \
    --etherscan-api-key <etherscan_api_key> \
    --broadcast \
    --verify \
    --sig 'run(string, address)' <ENV> <initialOwner>
*/

contract DeployUniswapV4AcrossMigrator is Script {
    function run(string memory env, address initialOwner) public {
        vm.broadcast(vm.envUint("PRIVATE_KEY"));

        UniswapV4AcrossMigrator migrator = new UniswapV4AcrossMigrator(
            initialOwner,
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_V4_POSITION_MANAGER"))),
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_UNIVERSAL_ROUTER"))),
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_PERMIT2"))),
            vm.envAddress(string(abi.encodePacked(env, "_ACROSS_SPOKE_POOL"))),
            vm.envAddress(string(abi.encodePacked(env, "_WETH")))
        );

        console.log("AcrossV4Migrator deployed at:", address(migrator));
    }

    // add this to be excluded from coverage report
    function test() public {}
}
