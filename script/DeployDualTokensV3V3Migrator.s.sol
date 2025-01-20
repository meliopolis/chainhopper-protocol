// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {DualTokensV3V3Migrator} from "../src/DualTokensV3V3Migrator.sol";

/*
forge script script/DeployDualTokensV3V3Migrator.s.sol:DeployDualTokensV3V3Migrator \
    --sig "run(string)" {CHAIN_NAME} \
    --rpc-url {CHAIN_RPC_URL} \
    --broadcast \
    --via-ir \
    --slow \
    --verify \
    --etherscan-api-key {ETHERSCAN_API_KEY}
*/

contract DeployDualTokensV3V3Migrator is Script {
    function run(string memory chain) public {
        address deployer = vm.envAddress("PUBLIC_KEY");
        address positionManager = vm.envAddress(string(abi.encodePacked(chain, "_NFT_POSITION_MANAGER")));
        address spokePool = vm.envAddress(string(abi.encodePacked(chain, "_SPOKE_POOL")));

        console.log("Deploying DualTokensV3V3Migrator on", chain, "using", deployer);
        console.log("  -- PositionManager: ", positionManager);
        console.log("  -- SpokePool: ", spokePool);
        vm.startBroadcast(deployer);

        try new DualTokensV3V3Migrator(positionManager, spokePool) returns (DualTokensV3V3Migrator migrator) {
            console.log("DualTokensV3V3Migrator deployed at: ", address(migrator));
        } catch {
            console.log("Failed to deploy DualTokensV3V3Migrator");
        }

        vm.stopBroadcast();
        console.log();
    }
}
