// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "@forge-std/Script.sol";
import {stdJson} from "@forge-std/StdJson.sol";
import {AerodromeAcrossMigrator} from "../src/AerodromeAcrossMigrator.sol";
import {ChainSettlerHelper} from "./ChainSettlerHelper.s.sol";

/*
    forge script script/DeployAerodromeAcrossMigrator.s.sol:DeployAerodromeAcrossMigrator \
    --rpc-url <rpc_endpoints> \
    --etherscan-api-key <etherscan_api_key> \
    --broadcast \
    --verify \
    --sig 'run(string,address)' <ENV> <initialOwner>
*/

contract DeployAerodromeAcrossMigrator is Script, ChainSettlerHelper {
    function run(string memory env, address initialOwner) public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        AerodromeAcrossMigrator migrator = new AerodromeAcrossMigrator(
            initialOwner,
            vm.envAddress(string(abi.encodePacked(env, "_AERODROME_POSITION_MANAGER"))),
            vm.envAddress(string(abi.encodePacked(env, "_AERODROME_UNIVERSAL_ROUTER"))),
            vm.envAddress(string(abi.encodePacked(env, "_UNISWAP_PERMIT2"))),
            vm.envAddress(string(abi.encodePacked(env, "_ACROSS_SPOKE_POOL"))),
            vm.envAddress(string(abi.encodePacked(env, "_WETH")))
        );

        (uint256[] memory chainIds, address[] memory chainSettlers, bool[] memory values) =
            ChainSettlerHelper.getAcrossSettlersArrays("DEPLOY_CHAIN_IDS");
        if (chainIds.length > 0) {
            migrator.setChainSettlers(chainIds, chainSettlers, values);
        }

        // set a new owner if needed
        address finalOwner = vm.envAddress("DEPLOY_FINAL_OWNER");
        if (finalOwner != address(0) && finalOwner != initialOwner) {
            migrator.transferOwnership(finalOwner);
        }

        console.log("AerodromeAcrossMigrator deployed at:", address(migrator));

        vm.stopBroadcast();
    }

    // add this to be excluded from coverage report
    function test() public override {}
}
