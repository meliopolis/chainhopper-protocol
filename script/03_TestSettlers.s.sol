// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {IUniswapV3PositionManager} from "../src/interfaces/external/IUniswapV3.sol";
import {IDualTokensV3Settler} from "../src/interfaces/IDualTokensV3Settler.sol";
import {IAcrossV3SpokePoolMessageHandler} from "../src/interfaces/external/IAcrossV3.sol";

contract TestDualTokensV3Settler is Script, StdCheats {
    function run(string memory chain, address settler) public {
        address deployer = vm.envAddress(string(abi.encodePacked(chain, "_DEPLOYER")));
        address positionManager = vm.envAddress(string(abi.encodePacked(chain, "_UNISWAP_V3_POSITION_MANAGER")));
        address spokePool = vm.envAddress(string(abi.encodePacked(chain, "_ACROSS_V3_SPOKE_POOL")));
        address usdc = vm.envAddress(string(abi.encodePacked(chain, "_USDC")));
        address weth = vm.envAddress(string(abi.encodePacked(chain, "_WETH")));

        deal(usdc, settler, 10000e6);
        deal(weth, settler, 10 ether);

        bytes memory message = abi.encode(
            IDualTokensV3Settler.SettlementParams({
                counterpartKey: bytes32("1"),
                recipient: deployer,
                token0: usdc,
                token1: weth,
                fee: 500,
                tickLower: -600,
                tickUpper: 600
            })
        );

        console.log("Testing TestDualTokensV3Settler at", settler, "on", chain);
        vm.startPrank(spokePool);

        IUniswapV3PositionManager npm = IUniswapV3PositionManager(positionManager);
        uint256 balanceBefore = npm.balanceOf(deployer);

        IAcrossV3SpokePoolMessageHandler(settler).handleV3AcrossMessage(usdc, 1000e6, address(0), message);
        IAcrossV3SpokePoolMessageHandler(settler).handleV3AcrossMessage(weth, 1 ether, address(0), message);

        uint256 balanceAfter = npm.balanceOf(deployer);
        uint256 tokenId = npm.tokenOfOwnerByIndex(deployer, balanceAfter - 1);
        console.log(" -- Position count before, after, new token id:", balanceBefore, balanceAfter, tokenId);

        vm.stopPrank();
        console.log();
    }
}
