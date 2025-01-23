// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IUniswapV3Factory} from "../interfaces/IUniswapV3Factory.sol";
import {INonfungiblePositionManager} from "src/interfaces/external/INonfungiblePositionManager.sol";
import {UniswapV3Bytecodes} from "./UniswapV3Bytecodes.sol";
import {WETH9} from "../mocks/WETH9.sol";
import {ISwapRouter} from "lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";

contract DeployV3 is Test {
    IUniswapV3Factory public factory;
    INonfungiblePositionManager public nftManager;
    ISwapRouter public swapRouter;
    WETH9 public weth9;

    function deployV3() public {
        // deploy weth9
        weth9 = new WETH9();

        // deploy factory
        bytes memory factoryBytecode = UniswapV3Bytecodes.FACTORY_BYTECODE;
        console.log("Factory bytecode length:", factoryBytecode.length);

        // Simple deployment without assembly
        address factoryAddress;
        assembly {
            factoryAddress :=
                create(
                    0, // no ether to send
                    add(factoryBytecode, 0x20), // actual bytecode starts after length prefix
                    mload(factoryBytecode) // load length of bytecode
                )
        }

        require(factoryAddress != address(0), "Factory deployment failed");
        factory = IUniswapV3Factory(factoryAddress);
        // deploy nftManager
        // Prepare constructor arguments
        bytes memory constructorArgs = abi.encode(address(0), address(weth9), address(0));

        // Concatenate bytecode and constructor args
        bytes memory bytecode = abi.encodePacked(UniswapV3Bytecodes.NFT_MANAGER_BYTECODE, constructorArgs);

        address nftManagerAddress;
        assembly {
            nftManagerAddress := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(nftManagerAddress != address(0), "NFTManager deployment failed");
        nftManager = INonfungiblePositionManager(nftManagerAddress);
        // deploy swapRouter
        bytes memory constructorArgsSwapRouter = abi.encode(
            address(0), // factorv2
            address(factory), // factoryv3
            address(nftManager),
            address(weth9)
        );
        bytes memory swapRouterBytecode =
            abi.encodePacked(UniswapV3Bytecodes.SWAP_ROUTER_02_BYTECODE, constructorArgsSwapRouter);
        address swapRouterAddress;
        assembly {
            swapRouterAddress := create(0, add(swapRouterBytecode, 0x20), mload(swapRouterBytecode))
        }
        require(swapRouterAddress != address(0), "SwapRouter deployment failed");
        swapRouter = ISwapRouter(swapRouterAddress);
        // deploy spokePool
        // spokePool = new V3SpokePoolInterface(address(factory));
        // deploy migrator
    }
}
