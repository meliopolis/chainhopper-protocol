// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.24;

// import {Ownable} from "@openzeppelin/access/Ownable.sol";
// import {Migrator} from "../../src/base/Migrator.sol";
// import {IMigrator} from "../../src/interfaces/IMigrator.sol";
// import {MigrationId, MigrationIdLibrary} from "../../src/types/MigrationId.sol";
// import {MigrationMode, MigrationModes} from "../../src/types/MigrationMode.sol";
// import {BaseTest} from "../utils/BaseTest.sol";

// contract MigratorTest is BaseTest {
//     uint32[] private chainIds = [123, 456, 789];
//     address[] private settlers = [address(0x123), address(0x456), address(0x789)];
//     bool[] private values = [true, true, true];

//     function setUp() public override {
//         super.setUp();

//         vm.prank(OWNER);
//         migrator.setChainSettlers(chainIds, settlers, values);
//     }

//     function _mockTokenRoutes(uint256 count) private view returns (IMigrator.TokenRoute[] memory tokenRoutes) {
//         tokenRoutes = new IMigrator.TokenRoute[](count);
//         if (count > 0) tokenRoutes[0] = IMigrator.TokenRoute(weth, "");
//         if (count > 1) tokenRoutes[1] = IMigrator.TokenRoute(usdc, "");
//         if (count > 2) tokenRoutes[2] = IMigrator.TokenRoute(usdt, "");
//     }

//     function _mockMigrationParams(uint256 tokeRouteCount)
//         private
//         view
//         returns (IMigrator.MigrationParams memory params)
//     {
//         params = IMigrator.MigrationParams(chainIds[0], settlers[0], _mockTokenRoutes(tokeRouteCount), "");
//     }

//     function _mockNextMigrationId(MigrationMode mode) private view returns (MigrationId migrationId) {
//         migrationId = MigrationIdLibrary.from(uint32(block.chainid), address(migrator), mode, migrator.lastNonce() + 1);
//     }

//     // setChainSettlers()

//     function test_setChainSettlers_fails_ifNotOwner() public {
//         vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER), address(migrator));

//         vm.prank(USER);
//         migrator.setChainSettlers(chainIds, settlers, values);
//     }

//     function test_fuzz_setChainSettlers(uint32[] memory _chainIds, address[] memory _settlers, bool[] memory _values)
//         public
//     {
//         if (_values.length != _chainIds.length || _values.length != _settlers.length) {
//             vm.expectRevert(Migrator.ParamsLengthMismatch.selector, address(migrator));

//             vm.prank(OWNER);
//             migrator.setChainSettlers(_chainIds, _settlers, _values);
//         } else {
//             for (uint256 i = 0; i < _values.length; i++) {
//                 vm.expectEmit(true, true, false, true);
//                 emit Migrator.ChainSettlerUpdated(_chainIds[i], _settlers[i], _values[i]);
//             }

//             vm.prank(OWNER);
//             migrator.setChainSettlers(_chainIds, _settlers, _values);

//             for (uint256 i = 0; i < _values.length; i++) {
//                 assertTrue(migrator.chainSettlers(_chainIds[i], _settlers[i]) == _values[i]);
//             }
//         }
//     }

//     // _migrate(), other than single or dual routes

//     function test__migrate_fails_ifDestinationProtocolNotFound() public {
//         bytes memory data = abi.encode(IMigrator.MigrationParams(0, address(0), _mockTokenRoutes(0), ""));

//         vm.expectRevert(abi.encodeWithSelector(IMigrator.ChainSettlerNotFound.selector, 0, 0), address(migrator));
//         migrator.migrate(USER, 0, data);
//     }

//     function test__migrate_fails_ifTokenRoutesMissing() public {
//         bytes memory data = abi.encode(_mockMigrationParams(0));

//         vm.expectRevert(abi.encodeWithSelector(IMigrator.TokenRoutesMissing.selector), address(migrator));
//         migrator.migrate(USER, 0, data);
//     }

//     function test__migrate_fails_ifTokenRoutesTooMany() public {
//         bytes memory data = abi.encode(_mockMigrationParams(3));

//         vm.expectRevert(abi.encodeWithSelector(IMigrator.TokenRoutesTooMany.selector), address(migrator));
//         migrator.migrate(USER, 0, data);
//     }

//     // _migrate(), single route

//     function test__migrate_fails_ifTokkensNotRouted() public {
//         migrator.setLiquidity(usdc, usdt, 0, 0);
//         bytes memory data = abi.encode(_mockMigrationParams(1));

//         vm.expectRevert(abi.encodeWithSelector(IMigrator.TokensNotRouted.selector, usdc, usdt), address(migrator));
//         migrator.migrate(USER, 0, data);
//     }

//     function test__migrate_fails_ifTokenAmountMissing() public {
//         migrator.setLiquidity(weth, usdc, 0, 0);
//         bytes memory data = abi.encode(_mockMigrationParams(1));

//         vm.expectRevert(abi.encodeWithSelector(IMigrator.TokenAmountMissing.selector, weth), address(migrator));
//         migrator.migrate(USER, 0, data);
//     }

//     function test__migrate_succeeds_token0ViaToken0() public {
//         migrator.setLiquidity(weth, usdc, 100, 0);
//         bytes memory data = abi.encode(_mockMigrationParams(1));

//         vm.expectEmit(true, true, true, true);
//         emit IMigrator.Migration(_mockNextMigrationId(MigrationModes.SINGLE), 0, weth, USER, 100);
//         migrator.migrate(USER, 0, data);
//     }

//     function test__migrate_succeeds_token1ViaToken0() public {
//         migrator.setLiquidity(weth, usdc, 0, 100);
//         bytes memory data = abi.encode(_mockMigrationParams(1));

//         vm.expectEmit(true, true, true, true);
//         emit IMigrator.Migration(_mockNextMigrationId(MigrationModes.SINGLE), 0, weth, USER, 100);
//         migrator.migrate(USER, 0, data);
//     }

//     function test__migrate_succeeds_token0ViaToken1() public {
//         migrator.setLiquidity(usdc, weth, 100, 0);
//         bytes memory data = abi.encode(_mockMigrationParams(1));

//         vm.expectEmit(true, true, true, true);
//         emit IMigrator.Migration(_mockNextMigrationId(MigrationModes.SINGLE), 0, weth, USER, 100);
//         migrator.migrate(USER, 0, data);
//     }

//     function test__migrate_succeeds_token1ViaToken1() public {
//         migrator.setLiquidity(usdc, weth, 0, 100);
//         bytes memory data = abi.encode(_mockMigrationParams(1));

//         vm.expectEmit(true, true, true, true);
//         emit IMigrator.Migration(_mockNextMigrationId(MigrationModes.SINGLE), 0, weth, USER, 100);
//         migrator.migrate(USER, 0, data);
//     }

//     // _migrate(), dual routes

//     function test__migrate_fails_token0NotRouted() public {
//         migrator.setLiquidity(usdt, usdc, 0, 0);
//         bytes memory data = abi.encode(_mockMigrationParams(2));

//         vm.expectRevert(abi.encodeWithSelector(IMigrator.TokenNotRouted.selector, usdt), address(migrator));
//         migrator.migrate(USER, 0, data);
//     }

//     function test__migrate_fails_token1NotRouted() public {
//         migrator.setLiquidity(weth, usdt, 0, 0);
//         bytes memory data = abi.encode(_mockMigrationParams(2));

//         vm.expectRevert(abi.encodeWithSelector(IMigrator.TokenNotRouted.selector, usdt), address(migrator));
//         migrator.migrate(USER, 0, data);
//     }

//     function test__migrate_fails_token0AmountMissing() public {
//         migrator.setLiquidity(weth, usdc, 0, 100);
//         bytes memory data = abi.encode(_mockMigrationParams(2));

//         vm.expectRevert(abi.encodeWithSelector(IMigrator.TokenAmountMissing.selector, weth), address(migrator));
//         migrator.migrate(USER, 0, data);
//     }

//     function test__migrate_fails_token1AmountMissing() public {
//         migrator.setLiquidity(weth, usdc, 100, 0);
//         bytes memory data = abi.encode(_mockMigrationParams(2));

//         vm.expectRevert(abi.encodeWithSelector(IMigrator.TokenAmountMissing.selector, usdc), address(migrator));
//         migrator.migrate(USER, 0, data);
//     }

//     function test__migrate_succeeds_bothTokens() public {
//         migrator.setLiquidity(weth, usdc, 100, 200);
//         bytes memory data = abi.encode(_mockMigrationParams(2));

//         vm.expectEmit(true, true, true, true);
//         emit IMigrator.Migration(_mockNextMigrationId(MigrationModes.DUAL), 0, weth, USER, 100);
//         vm.expectEmit(true, true, true, true);
//         emit IMigrator.Migration(_mockNextMigrationId(MigrationModes.DUAL), 0, usdc, USER, 200);

//         migrator.migrate(USER, 0, data);
//     }

//     function test__migrate_succeeds_flippedTokens() public {
//         migrator.setLiquidity(usdc, weth, 200, 100);
//         bytes memory data = abi.encode(_mockMigrationParams(2));

//         vm.expectEmit(true, true, true, true);
//         emit IMigrator.Migration(_mockNextMigrationId(MigrationModes.DUAL), 0, weth, USER, 100);
//         vm.expectEmit(true, true, true, true);
//         emit IMigrator.Migration(_mockNextMigrationId(MigrationModes.DUAL), 0, usdc, USER, 200);

//         migrator.migrate(USER, 0, data);
//     }
// }
