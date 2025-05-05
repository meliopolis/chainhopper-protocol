// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.24;

// import {Test} from "@forge-std/Test.sol";
// import {Ownable} from "@openzeppelin/access/Ownable.sol";
// import {ChainSettlers} from "../../src/base/ChainSettlers.sol";

// contract ChainSettlersTest is Test {
//     address user = makeAddr("user");
//     address owner = makeAddr("owner");

//     ChainSettlers chainSettlers;

//     function setUp() public {
//         chainSettlers = new ChainSettlers(owner);
//     }

//     function test_setChainSettlers_fails_ifNotOwner() public {
//         vm.expectRevert(
//             abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user), address(chainSettlers)
//         );

//         vm.prank(user);
//         chainSettlers.setChainSettlers(new uint32[](0), new address[](0), new bool[](0));
//     }

//     function test_setChainSettlers_fails_ifParamsLengthMismatch() public {
//         vm.startPrank(owner);

//         vm.expectRevert(abi.encodeWithSelector(ChainSettlers.ChainSettlersParamsLengthMismatch.selector));
//         chainSettlers.setChainSettlers(new uint32[](1), new address[](0), new bool[](0));

//         vm.expectRevert(abi.encodeWithSelector(ChainSettlers.ChainSettlersParamsLengthMismatch.selector));
//         chainSettlers.setChainSettlers(new uint32[](0), new address[](1), new bool[](0));

//         vm.expectRevert(abi.encodeWithSelector(ChainSettlers.ChainSettlersParamsLengthMismatch.selector));
//         chainSettlers.setChainSettlers(new uint32[](0), new address[](0), new bool[](1));

//         vm.stopPrank();
//     }

//     function test_fuzz_setChainSettlers(uint32[3] memory chainIds, address[3] memory settlers, bool[3] memory values)
//         public
//     {
//         uint32[] memory _chainIds = new uint32[](chainIds.length);
//         address[] memory _settlers = new address[](settlers.length);
//         bool[] memory _values = new bool[](values.length);

//         for (uint256 i = 0; i < chainIds.length; i++) {
//             _chainIds[i] = chainIds[i];
//             _settlers[i] = settlers[i];
//             _values[i] = values[i];

//             vm.expectEmit(true, true, true, true);
//             emit ChainSettlers.ChainSettlerUpdated(_chainIds[i], _settlers[i], _values[i]);
//         }

//         vm.prank(owner);
//         chainSettlers.setChainSettlers(_chainIds, _settlers, _values);
//     }
// }
