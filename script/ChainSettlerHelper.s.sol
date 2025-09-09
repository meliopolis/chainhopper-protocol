// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "@forge-std/Script.sol";
import {stdJson} from "@forge-std/StdJson.sol";

contract ChainSettlerHelper is Script {
    using stdJson for string;

    function getContractAddress(string memory chainId, string memory contractName) public view returns (address) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/broadcast/", contractName, ".s.sol/", chainId, "/run-latest.json");
        string memory fileString = vm.readFile(path);
        if (bytes(fileString).length == 0) {
            return address(0);
        }
        bytes memory parsedDeployedContractName = fileString.parseRaw(".transactions[0].contractName");
        string memory deployedContractName = abi.decode(parsedDeployedContractName, (string));
        bytes memory parsedAddress;
        if (keccak256(abi.encodePacked(deployedContractName)) == keccak256(abi.encodePacked("UniswapV4Library"))) {
            // this is for v4Settler because it deploys a library first
            parsedAddress = fileString.parseRaw(".transactions[1].contractAddress");
        } else {
            parsedAddress = fileString.parseRaw(".transactions[0].contractAddress");
        }
        address contractAddress = abi.decode(parsedAddress, (address));
        if (contractAddress == address(0)) {
            revert("Contract not found");
        }
        return contractAddress;
    }

    function getAcrossSettlersArrays(string memory env)
        public
        view
        returns (uint256[] memory, address[] memory, bool[] memory)
    {
        string[] memory chainIds = vm.envString(env, ",");
        // Calculate total settlers count (2 per chain, +1 for BASE Aerodrome)
        uint256 baseCount = 0;
        for (uint256 i = 0; i < chainIds.length; i++) {
            if (vm.parseUint(chainIds[i]) == 8453 && vm.parseUint(chainIds[i]) != block.chainid) {
                baseCount = 1;
                break;
            }
        }
        uint256 chainSettlersCount = (chainIds.length - 1) * 2 + baseCount;
        uint256[] memory chainIdsUint = new uint256[](chainSettlersCount);
        address[] memory chainSettlers = new address[](chainSettlersCount);
        bool[] memory values = new bool[](chainSettlersCount);
        uint256 counter = 0;
        for (uint256 i = 0; i < chainIds.length; i++) {
            uint256 currentChainId = vm.parseUint(chainIds[i]);
            // skip the current chain
            if (currentChainId == block.chainid) {
                continue;
            }
            address UniswapV3AcrossSettler = getContractAddress(chainIds[i], "DeployUniswapV3AcrossSettler");
            address UniswapV4AcrossSettler = getContractAddress(chainIds[i], "DeployUniswapV4AcrossSettler");

            if (UniswapV3AcrossSettler == address(0) || UniswapV4AcrossSettler == address(0)) {
                revert("UniswapV3AcrossSettler or UniswapV4AcrossSettler not found");
            }

            chainIdsUint[counter] = currentChainId;
            chainSettlers[counter] = UniswapV3AcrossSettler;
            values[counter] = true;

            chainIdsUint[counter + 1] = currentChainId;
            chainSettlers[counter + 1] = UniswapV4AcrossSettler;
            values[counter + 1] = true;
            counter += 2;

            // Add Aerodrome Settler for BASE chain (chain ID 8453)
            if (currentChainId == 8453) {
                address AerodromeAcrossSettler = getContractAddress(chainIds[i], "DeployAerodromeAcrossSettler");
                if (AerodromeAcrossSettler != address(0)) {
                    chainIdsUint[counter] = currentChainId;
                    chainSettlers[counter] = AerodromeAcrossSettler;
                    values[counter] = true;
                    counter += 1;
                }
            }
        }

        for (uint256 i = 0; i < chainIdsUint.length; i++) {
            console.logUint(chainIdsUint[i]);
            console.logAddress(chainSettlers[i]);
        }
        return (chainIdsUint, chainSettlers, values);
    }

    function getDirectSettlersArrays(string memory chainId)
        public
        view
        returns (uint256[] memory, address[] memory, bool[] memory)
    {
        uint256 currentChainId = vm.parseUint(chainId);
        uint256[] memory chainIdsUint = new uint256[](2);
        address[] memory chainSettlers = new address[](2);
        bool[] memory values = new bool[](2);

        address UniswapV3DirectSettler = getContractAddress(chainId, "DeployUniswapV3DirectSettler");
        address UniswapV4DirectSettler = getContractAddress(chainId, "DeployUniswapV4DirectSettler");
        if (UniswapV3DirectSettler == address(0) || UniswapV4DirectSettler == address(0)) {
            revert("UniswapV3DirectSettler or UniswapV4DirectSettler not found");
        }

        chainIdsUint[0] = currentChainId;
        chainSettlers[0] = UniswapV3DirectSettler;
        values[0] = true;

        chainIdsUint[1] = currentChainId;
        chainSettlers[1] = UniswapV4DirectSettler;
        values[1] = true;

        for (uint256 i = 0; i < chainIdsUint.length; i++) {
            console.logUint(chainIdsUint[i]);
            console.logAddress(chainSettlers[i]);
        }
        return (chainIdsUint, chainSettlers, values);
    }

    function test() public virtual {}
}
