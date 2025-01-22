// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IUniswapV3Factory} from "../interfaces/IUniswapV3Factory.sol";
import {INonfungiblePositionManager} from "src/interfaces/external/INonfungiblePositionManager.sol";
// import {NonfungibleTokenPositionDescriptor} from "@uniswap/v3-periphery/contracts/NonfungibleTokenPositionDescriptor.sol";
import {UniswapV3Bytecodes} from "./UniswapV3Bytecodes.sol";
import {WETH9} from "../mocks/WETH9.sol";


contract DeployV3 is Test {
 
  IUniswapV3Factory public factory;
  INonfungiblePositionManager public nftManager;
  // SwapRouter public swapRouter;
  WETH9 public weth9;

  function deployV3() public {
    // todo: implement
    // deploy weth9
    weth9 = new WETH9();
    // deploy factory
    bytes memory factoryBytecode = UniswapV3Bytecodes.FACTORY_BYTECODE;
    address factoryAddress;
        assembly {
            factoryAddress := create(0, add(factoryBytecode, 0x20), mload(factoryBytecode))
        }
        require(factoryAddress != address(0), "Factory deployment failed");
        
        // Create interface instance
    factory = IUniswapV3Factory(factoryAddress);
    // deploy nftManager
    // NonfungibleTokenPositionDescriptor nftDescriptor = new NonfungibleTokenPositionDescriptor(address(weth9), Bytes("ETH"));
    // Prepare constructor arguments
    bytes memory constructorArgs = abi.encode(
        address(factory),
        address(weth9),
        address(0)
    );

    // Concatenate bytecode and constructor args
    bytes memory bytecode = abi.encodePacked(UniswapV3Bytecodes.NFT_MANAGER_BYTECODE, constructorArgs);
    
    address nftManagerAddress;
    assembly {
        nftManagerAddress := create(0, add(bytecode, 0x20), mload(bytecode))
    }
    require(nftManagerAddress != address(0), "NFTManager deployment failed");
    nftManager = INonfungiblePositionManager(nftManagerAddress);
    // deploy swapRouter
    swapRouter = new SwapRouter(address(factory));
    // deploy spokePool
    // spokePool = new V3SpokePoolInterface(address(factory));
    // deploy migrator
  }
}
