// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {DualTokensMigrator} from "../src/DualTokensMigrator.sol";

contract DualTokensMigratorDeployer is Script {
    string private CHAIN = vm.envString("CHAIN");
    address private DEPLOYER = vm.envAddress(string(abi.encodePacked(CHAIN, "_DEPLOYER")));
    address private UNISWAP_V3_POSITION_MANAGER =
        vm.envAddress(string(abi.encodePacked(CHAIN, "_UNISWAP_V3_POSITION_MANAGER")));
    address private ACROSS_V3_SPOKE_POOL = vm.envAddress(string(abi.encodePacked(CHAIN, "_ACROSS_V3_SPOKE_POOL")));

    function run() external {
        console.log("Deploying DualTokensMigrator on ", CHAIN, " using ", DEPLOYER);

        vm.startBroadcast(DEPLOYER);

        try new DualTokensMigrator(UNISWAP_V3_POSITION_MANAGER, ACROSS_V3_SPOKE_POOL) returns (
            DualTokensMigrator migrator
        ) {
            console.log("DualTokensMigrator deployed at: ", address(migrator));
        } catch {
            console.log("Failed to deploy DualTokensMigrator");
        }

        vm.stopBroadcast();
    }
}
