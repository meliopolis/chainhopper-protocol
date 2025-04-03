// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.24;

// import {Test} from "@forge-std/Test.sol";
// import {V3SpokePoolInterface as IAcrossSpokePool} from "@across/interfaces/V3SpokePoolInterface.sol";
// import {IAcrossMigrator} from "../../src/interfaces/IAcrossMigrator.sol";
// import {IMigrator} from "../../src/interfaces/IMigrator.sol";
// import {MockAcrossMigrator} from "../mocks/MockAcrossMigrator.sol";

// contract AcrossMigratorTest is Test {
//     string constant ENV = "BASE";
//     address constant USER = address(0x123);

//     MockAcrossMigrator migrator;
//     address private token;

//     function setUp() public {
//         vm.createSelectFork(vm.envString(string(abi.encodePacked(ENV, "_RPC_URL"))));
//         token = vm.envAddress(string(abi.encodePacked(ENV, "_WETH")));

//         migrator = new MockAcrossMigrator(vm.envAddress(string(abi.encodePacked(ENV, "_ACROSS_SPOKE_POOL"))), token);
//     }

//     function test_bridge_Succeeds() public {
//         IAcrossMigrator.Route memory route =
//             IAcrossMigrator.Route(address(0), 0, 0, uint32(block.timestamp), 0, address(0), 0);
//         IMigrator.TokenRoute memory tokenRoute = IMigrator.TokenRoute(token, abi.encode(route));

//         vm.expectEmit(true, false, true, true);
//         emit IAcrossSpokePool.FundsDeposited(
//             bytes32(uint256(uint160(token))),
//             bytes32(0),
//             0,
//             0,
//             1,
//             0,
//             uint32(block.timestamp),
//             uint32(block.timestamp),
//             0,
//             bytes32(uint256(uint160(USER))),
//             bytes32(0),
//             bytes32(0),
//             ""
//         );

//         migrator.mockBridge(USER, 1, address(0), tokenRoute.token, 0, true, tokenRoute.route, "");
//     }
// }
