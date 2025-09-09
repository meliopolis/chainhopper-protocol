// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "@forge-std/Script.sol";
import {UniswapV4DirectMigrator} from "../src/UniswapV4DirectMigrator.sol";
import {ChainSettlerHelper} from "./ChainSettlerHelper.s.sol";

/*
    forge script script/DeployUniswapV4DirectMigrator.s.sol:DeployUniswapV4DirectMigrator \
    --rpc-url <rpc_endpoints> \
    --etherscan-api-key <etherscan_api_key> \
    --broadcast \
    --verify \
    --sig 'run(string,address,string)' <ENV> <initialOwner> <file>
*/

contract DeployUniswapV4DirectMigrator is Script, ChainSettlerHelper {
    function run(string memory env, address initialOwner) public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        // deploy the migrator
        UniswapV4DirectMigrator migrator = new UniswapV4DirectMigrator(
            initialOwner,
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_V4_POSITION_MANAGER"))),
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_UNIVERSAL_ROUTER"))),
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_PERMIT2"))),
            vm.envAddress(string(abi.encodePacked(env, "_WETH")))
        );

        // For Direct migrators, only set the settlers from the current chain
        (uint256[] memory chainIds, address[] memory chainSettlers, bool[] memory values) =
            ChainSettlerHelper.getDirectSettlersArrays(vm.toString(block.chainid));
        migrator.setChainSettlers(chainIds, chainSettlers, values);

        // set a new owner if needed
        address finalOwner = vm.envAddress("DEPLOY_FINAL_OWNER");
        if (finalOwner != address(0) && finalOwner != initialOwner) {
            migrator.transferOwnership(finalOwner);
        }

        console.log("UniswapV4DirectMigrator deployed at:", address(migrator));

        vm.stopBroadcast();
    }

    // add this to be excluded from coverage report
    function test() public override {}
}
