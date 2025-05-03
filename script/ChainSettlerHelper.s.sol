// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "@forge-std/Script.sol";
import {stdJson} from "@forge-std/StdJson.sol";

contract ChainSettlerHelper is Script {
    using stdJson for string;

    function getContractAddress(string memory chainId, string memory contractName) public view returns (address) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/broadcast/", contractName, ".s.sol/", chainId, "/run-latest.json");
        string memory json = vm.readFile(path);
        if (bytes(json).length == 0) {
            return address(0);
        }
        bytes memory parsedAddress = json.parseRaw(".transactions[0].contractAddress");
        address contractAddress = abi.decode(parsedAddress, (address));
        if (contractAddress == address(0)) {
            revert("Contract not found");
        }
        return contractAddress;
    }

    function getChainSettlersArrays(string memory env)
        public
        view
        returns (uint256[] memory, address[] memory, bool[] memory)
    {
        string[] memory chainIds = vm.envString(env, ",");
        uint256 chainSettlersCount = (chainIds.length - 1) * 2;
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
        }

        for (uint256 i = 0; i < chainIdsUint.length; i++) {
            console.logUint(chainIdsUint[i]);
            console.logAddress(chainSettlers[i]);
        }
        return (chainIdsUint, chainSettlers, values);
    }

    function test() public virtual {}
}
