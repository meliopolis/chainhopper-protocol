// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {UniswapV3AcrossMigrator} from "../src/UniswapV3AcrossMigrator.sol";

/*
    forge script script/DeployUniswapV3AcrossMigrator.s.sol:DeployUniswapV3AcrossMigrator \
    --rpc-url <rpc_endpoints> \
    --broadcast \
    --etherscan-api-key <etherscan_api_key> \
    --verify \
    --sig 'run(string,address)' <ENV> <initialOwner>
*/

contract DeployUniswapV3AcrossMigrator is Script {
    function run(string memory env, address initialOwner) public {
        vm.broadcast(vm.envUint("PRIVATE_KEY"));

        UniswapV3AcrossMigrator migrator = new UniswapV3AcrossMigrator(
            initialOwner,
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_V3_POSITION_MANAGER"))),
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_UNIVERSAL_ROUTER"))),
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_PERMIT2"))),
            vm.envAddress(string(abi.encodePacked(env, "_ACROSS_SPOKE_POOL"))),
            vm.envAddress(string(abi.encodePacked(env, "_WETH")))
        );

        console.log("UniswapV3AcrossMigrator deployed at:", address(migrator));
    }

    // add this to be excluded from coverage report
    function test() public {}
}
