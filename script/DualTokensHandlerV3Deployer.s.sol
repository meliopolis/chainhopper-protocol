// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {DualTokensHandlerV3} from "../src/DualTokensHandlerV3.sol";

contract DualTokensHandlerV3Deployer is Script {
    string private CHAIN = vm.envString("CHAIN");
    address private DEPLOYER = vm.envAddress(string(abi.encodePacked(CHAIN, "_DEPLOYER")));
    address private UNISWAP_V3_POSITION_MANAGER =
        vm.envAddress(string(abi.encodePacked(CHAIN, "_UNISWAP_V3_POSITION_MANAGER")));
    address private ACROSS_V3_SPOKE_POOL = vm.envAddress(string(abi.encodePacked(CHAIN, "_ACROSS_V3_SPOKE_POOL")));

    function run() external {
        console.log("Deploying DualTokensHandlerV3 on ", CHAIN, " using ", DEPLOYER);

        vm.startBroadcast(DEPLOYER);

        try new DualTokensHandlerV3(UNISWAP_V3_POSITION_MANAGER, ACROSS_V3_SPOKE_POOL) returns (
            DualTokensHandlerV3 handler
        ) {
            console.log("DualTokensHandlerV3 deployed at: ", address(handler));
        } catch {
            console.log("Failed to deploy DualTokensHandlerV3");
        }

        vm.stopBroadcast();
    }
}
