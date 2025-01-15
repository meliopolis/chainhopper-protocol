// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {DualTokensV3V3Migrator} from "../src/DualTokensV3V3Migrator.sol";
import {DualTokensV3V4Migrator} from "../src/DualTokensV3V4Migrator.sol";
import {SingleTokenV3V3Migrator} from "../src/SingleTokenV3V3Migrator.sol";

/*
forge script script/02_DeployMigrators.s.sol:DeployAllMigrators \
    --sig "run(string)" {CHAIN_NAME} \
    --rpc-url {CHAIN_RPC_URL} \
    --broadcast \
    --via-ir \
    --slow \
    --verify \
    --etherscan-api-key {ETHERSCAN_API_KEY}
*/

contract DeployAllMigrators is Script {
    function run(string memory chain) public {
        (new DeployDualTokensV3V3Migrator()).run(chain);
        (new DeployDualTokensV3V4Migrator()).run(chain);
        (new DeploySingleTokenV3V3Migrator()).run(chain);
    }
}

contract DeployDualTokensV3V3Migrator is Script {
    function run(string memory chain) public {
        address deployer = vm.envAddress(string(abi.encodePacked(chain, "_DEPLOYER")));
        address positionManager = vm.envAddress(string(abi.encodePacked(chain, "_UNISWAP_V3_POSITION_MANAGER")));
        address spokePool = vm.envAddress(string(abi.encodePacked(chain, "_ACROSS_V3_SPOKE_POOL")));

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

contract DeployDualTokensV3V4Migrator is Script {
    function run(string memory chain) public {
        address deployer = vm.envAddress(string(abi.encodePacked(chain, "_DEPLOYER")));
        address positionManager = vm.envAddress(string(abi.encodePacked(chain, "_UNISWAP_V3_POSITION_MANAGER")));
        address spokePool = vm.envAddress(string(abi.encodePacked(chain, "_ACROSS_V3_SPOKE_POOL")));

        console.log("Deploying DualTokensV3V4Migrator on", chain, "using", deployer);
        console.log("  -- PositionManager: ", positionManager);
        console.log("  -- SpokePool: ", spokePool);
        vm.startBroadcast(deployer);

        try new DualTokensV3V4Migrator(positionManager, spokePool) returns (DualTokensV3V4Migrator migrator) {
            console.log("DualTokensV3V3Migrator deployed at: ", address(migrator));
        } catch {
            console.log("Failed to deploy DualTokensV3V3Migrator");
        }

        vm.stopBroadcast();
        console.log();
    }
}

contract DeploySingleTokenV3V3Migrator is Script {
    function run(string memory chain) public {
        address deployer = vm.envAddress(string(abi.encodePacked(chain, "_DEPLOYER")));
        address positionManager = vm.envAddress(string(abi.encodePacked(chain, "_UNISWAP_V3_POSITION_MANAGER")));
        address spokePool = vm.envAddress(string(abi.encodePacked(chain, "_ACROSS_V3_SPOKE_POOL")));
        address swapRouter = vm.envAddress(string(abi.encodePacked(chain, "_UNISWAP_V3_SWAP_ROUTER")));

        console.log("Deploying SingleTokenV3V3Migrator on", chain, "using", deployer);
        console.log("  -- PositionManager: ", positionManager);
        console.log("  -- SpokePool: ", spokePool);
        console.log("  -- SwapRouter: ", swapRouter);
        vm.startBroadcast(deployer);

        try new SingleTokenV3V3Migrator(positionManager, spokePool, swapRouter) returns (
            SingleTokenV3V3Migrator migrator
        ) {
            console.log("SingleTokenV3V3Migrator deployed at: ", address(migrator));
        } catch {
            console.log("Failed to deploy SingleTokenV3V3Migrator");
        }

        vm.stopBroadcast();
        console.log();
    }
}
