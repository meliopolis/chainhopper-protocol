// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {DualTokensV3Settler} from "../src/DualTokensV3Settler.sol";
import {DualTokensV4Settler} from "../src/DualTokensV4Settler.sol";
import {SingleTokenV3Settler} from "../src/SingleTokenV3Settler.sol";

/*
forge script script/01_DeploySettlers.s.sol:DeployAllSettlers \
    --sig "run(string)" {CHAIN_NAME} \
    --rpc-url {CHAIN_RPC_URL} \
    --broadcast \
    --via-ir \
    --slow \
    --verify \
    --etherscan-api-key {ETHERSCAN_API_KEY}
*/

contract DeployAllSettlers is Script {
    function run(string memory chain) public {
        (new DeployDualTokensV3Settler()).run(chain);
        (new DeployDualTokensV4Settler()).run(chain);
        (new DeploySingleTokenV3Settler()).run(chain);
    }
}

contract DeployDualTokensV3Settler is Script {
    function run(string memory chain) public {
        address deployer = vm.envAddress(string(abi.encodePacked(chain, "_DEPLOYER")));
        address positionManager = vm.envAddress(string(abi.encodePacked(chain, "_UNISWAP_V3_POSITION_MANAGER")));
        address spokePool = vm.envAddress(string(abi.encodePacked(chain, "_ACROSS_V3_SPOKE_POOL")));

        console.log("Deploying DualTokensV3Settler on", chain, "using", deployer);
        console.log("  -- PositionManager: ", positionManager);
        console.log("  -- SpokePool: ", spokePool);
        vm.startBroadcast(deployer);

        try new DualTokensV3Settler(positionManager, spokePool) returns (DualTokensV3Settler settler) {
            console.log("DualTokensV3Settler deployed at: ", address(settler));
        } catch {
            console.log("Failed to deploy DualTokensV3Settler");
        }

        vm.stopBroadcast();
        console.log();
    }
}

contract DeployDualTokensV4Settler is Script {
    function run(string memory chain) public {
        address deployer = vm.envAddress(string(abi.encodePacked(chain, "_DEPLOYER")));
        address positionManager = vm.envAddress(string(abi.encodePacked(chain, "_UNISWAP_V4_POSITION_MANAGER")));
        address spokePool = vm.envAddress(string(abi.encodePacked(chain, "_ACROSS_V3_SPOKE_POOL")));

        console.log("Deploying DualTokensV4Settler on", chain, "using", deployer);
        console.log("  -- PositionManager: ", positionManager);
        console.log("  -- SpokePool: ", spokePool);
        vm.startBroadcast(deployer);

        try new DualTokensV4Settler(positionManager, spokePool) returns (DualTokensV4Settler settler) {
            console.log("DualTokensV4Settler deployed at: ", address(settler));
        } catch {
            console.log("Failed to deploy DualTokensV4Settler");
        }

        vm.stopBroadcast();
        console.log();
    }
}

contract DeploySingleTokenV3Settler is Script {
    function run(string memory chain) public {
        address deployer = vm.envAddress(string(abi.encodePacked(chain, "_DEPLOYER")));
        address positionManager = vm.envAddress(string(abi.encodePacked(chain, "_UNISWAP_V3_POSITION_MANAGER")));
        address spokePool = vm.envAddress(string(abi.encodePacked(chain, "_ACROSS_V3_SPOKE_POOL")));
        address swapRouter = vm.envAddress(string(abi.encodePacked(chain, "_UNISWAP_V3_SWAP_ROUTER")));

        console.log("Deploying SingleTokenV3Settler on", chain, "using", deployer);
        console.log("  -- PositionManager: ", positionManager);
        console.log("  -- SpokePool: ", spokePool);
        console.log("  -- SwapRouter: ", swapRouter);
        vm.startBroadcast(deployer);

        try new SingleTokenV3Settler(positionManager, spokePool, swapRouter) returns (SingleTokenV3Settler settler) {
            console.log("SingleTokenV3Settler deployed at: ", address(settler));
        } catch {
            console.log("Failed to deploy SingleTokenV3Settler");
        }

        vm.stopBroadcast();
        console.log();
    }
}
