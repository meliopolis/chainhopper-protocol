// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "@forge-std/Test.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {IMigrator} from "../../src/interfaces/IMigrator.sol";
import {MockMigrator} from "../mocks/MockMigrator.sol";

contract MigratorTest is Test {
    string constant ENV = "BASE";
    address constant USER = address(0x123);
    address constant OWNER = address(0x456);

    MockMigrator migrator;
    address private weth;
    address private usdc;
    address private uni;
    uint32[] private chainIds = [1, 2, 3];
    address[] private settlers = [address(0x789), address(0xabc), address(0xdef)];

    function setUp() public {
        vm.createSelectFork(vm.envString(string(abi.encodePacked(ENV, "_RPC_URL"))));
        weth = vm.envAddress(string(abi.encodePacked(ENV, "_WETH")));
        usdc = vm.envAddress(string(abi.encodePacked(ENV, "_USDC")));
        uni = vm.envAddress(string(abi.encodePacked(ENV, "_UNI")));

        vm.startPrank(OWNER);
        migrator = new MockMigrator();
        migrator.flipChainSettlers(chainIds, settlers);
        vm.stopPrank();
    }

    /*
     *  Chain Settler Functions  
     */

    function test_flipChainSettlers_Fails_IfNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));

        vm.prank(USER);
        migrator.flipChainSettlers(chainIds, settlers);
    }

    function test_flipChainSettlers_Fails_IfLengthMismatch() public {
        vm.expectRevert(abi.encodeWithSelector(IMigrator.ChainIdsAndSettlersLengthMismatch.selector));

        vm.prank(OWNER);
        migrator.flipChainSettlers(chainIds, new address[](chainIds.length - 1));
    }

    function test_isChainSettlerSupported_Succeeds() public view {
        for (uint256 i = 0; i < chainIds.length; i++) {
            assertEq(migrator.isChainSettlerSupported(chainIds[i], settlers[i]), true);
            assertEq(migrator.isChainSettlerSupported(chainIds[i], settlers[(i + 1) % settlers.length]), false);
        }
    }

    function test_flipChainSettlers_Succeeds() public {
        vm.prank(OWNER);
        migrator.flipChainSettlers(chainIds, settlers);

        for (uint256 i = 0; i < chainIds.length; i++) {
            assertEq(migrator.isChainSettlerSupported(chainIds[i], settlers[i]), false);
            assertEq(migrator.isChainSettlerSupported(chainIds[i], settlers[(i + 1) % settlers.length]), false);
        }
    }

    /*
     *  Migrate Functions (code path other than single or dual routes)
     */

    function test__migrate_Fails_IfChainSettlerNotSupported() public {
        IMigrator.TokenRoute[] memory tokenRoutes = new IMigrator.TokenRoute[](0);
        bytes memory data = abi.encode(IMigrator.MigrationParams(chainIds[0], settlers[1], tokenRoutes, 0, ""));

        vm.expectRevert(abi.encodeWithSelector(IMigrator.ChainSettlerNotSupported.selector, chainIds[0], settlers[1]));
        migrator.migrate(USER, 0, data);
    }

    function test__migrate_Fails_IfAmountsAreAllZero() public {
        IMigrator.TokenRoute[] memory tokenRoutes = new IMigrator.TokenRoute[](0);
        bytes memory data = abi.encode(IMigrator.MigrationParams(chainIds[0], settlers[0], tokenRoutes, 0, ""));

        vm.expectRevert(abi.encodeWithSelector(IMigrator.AmountsCannotAllBeZero.selector));
        migrator.migrate(USER, 0, data);
    }

    function test__migrate_Fails_IfMissingTokenRoutes() public {
        IMigrator.TokenRoute[] memory tokenRoutes = new IMigrator.TokenRoute[](0);
        bytes memory data = abi.encode(IMigrator.MigrationParams(chainIds[0], settlers[0], tokenRoutes, 0, ""));

        migrator.dealLiquidity(weth, usdc, 100, 200);

        vm.expectRevert(abi.encodeWithSelector(IMigrator.MissingTokenRoutes.selector));
        migrator.migrate(USER, 0, data);
    }

    function test__migrate_Fails_IfTooManyTokenRoutes() public {
        IMigrator.TokenRoute[] memory tokenRoutes = new IMigrator.TokenRoute[](3);
        bytes memory data = abi.encode(IMigrator.MigrationParams(chainIds[0], settlers[0], tokenRoutes, 0, ""));

        migrator.dealLiquidity(weth, usdc, 100, 200);

        vm.expectRevert(abi.encodeWithSelector(IMigrator.TooManyTokenRoutes.selector));
        migrator.migrate(USER, 0, data);
    }

    /*
     *  Migrate Functions (single routes)
     */

    function test__migrate_Fails_IfTokensNotRouted() public {
        IMigrator.TokenRoute[] memory tokenRoutes = new IMigrator.TokenRoute[](1);
        tokenRoutes[0] = IMigrator.TokenRoute(uni, "");
        bytes memory data = abi.encode(IMigrator.MigrationParams(chainIds[0], settlers[0], tokenRoutes, 0, ""));

        migrator.dealLiquidity(weth, usdc, 100, 200);

        vm.expectRevert(abi.encodeWithSelector(IMigrator.TokensNotRouted.selector));
        migrator.migrate(USER, 0, data);
    }

    function test__migrate_Succeeds_Token0Route_Token0Liquidity() public {
        IMigrator.TokenRoute[] memory tokenRoutes = new IMigrator.TokenRoute[](1);
        tokenRoutes[0] = IMigrator.TokenRoute(weth, "");
        bytes memory data = abi.encode(IMigrator.MigrationParams(chainIds[0], settlers[0], tokenRoutes, 0, ""));

        migrator.dealLiquidity(weth, usdc, 100, 0);

        vm.expectEmit(true, true, true, true);
        emit IMigrator.Migrated(bytes32(0), chainIds[0], settlers[0], USER, weth, 100);

        migrator.migrate(USER, 0, data);
    }

    function test__migrate_Succeeds_Token0Route_BothLiquidity() public {
        IMigrator.TokenRoute[] memory tokenRoutes = new IMigrator.TokenRoute[](1);
        tokenRoutes[0] = IMigrator.TokenRoute(weth, "");
        bytes memory data = abi.encode(IMigrator.MigrationParams(chainIds[0], settlers[0], tokenRoutes, 0, ""));

        migrator.dealLiquidity(weth, usdc, 100, 200);

        vm.expectEmit(true, true, true, true);
        emit IMigrator.Migrated(bytes32(0), chainIds[0], settlers[0], USER, weth, 100);

        migrator.migrate(USER, 0, data);
    }

    function test__migrate_Succeeds_Token1Route_Token1Liquidity() public {
        IMigrator.TokenRoute[] memory tokenRoutes = new IMigrator.TokenRoute[](1);
        tokenRoutes[0] = IMigrator.TokenRoute(usdc, "");
        bytes memory data = abi.encode(IMigrator.MigrationParams(chainIds[0], settlers[0], tokenRoutes, 0, ""));

        migrator.dealLiquidity(weth, usdc, 0, 200);

        vm.expectEmit(true, true, true, true);
        emit IMigrator.Migrated(bytes32(0), chainIds[0], settlers[0], USER, usdc, 200);

        migrator.migrate(USER, 0, data);
    }

    function test__migrate_Succeeds_Token1Route_BothLiquidity() public {
        IMigrator.TokenRoute[] memory tokenRoutes = new IMigrator.TokenRoute[](1);
        tokenRoutes[0] = IMigrator.TokenRoute(usdc, "");
        bytes memory data = abi.encode(IMigrator.MigrationParams(chainIds[0], settlers[0], tokenRoutes, 0, ""));

        migrator.dealLiquidity(weth, usdc, 100, 200);

        vm.expectEmit(true, true, true, true);
        emit IMigrator.Migrated(bytes32(0), chainIds[0], settlers[0], USER, usdc, 200);

        migrator.migrate(USER, 0, data);
    }

    /*
     *  Migrate Functions (dual routes)
     */

    function test__migrate_Fails_IfAmount0IsZero() public {
        IMigrator.TokenRoute[] memory tokenRoutes = new IMigrator.TokenRoute[](2);
        tokenRoutes[0] = IMigrator.TokenRoute(weth, "");
        tokenRoutes[0] = IMigrator.TokenRoute(usdc, "");
        bytes memory data = abi.encode(IMigrator.MigrationParams(chainIds[0], settlers[0], tokenRoutes, 0, ""));

        migrator.dealLiquidity(weth, usdc, 0, 200);

        vm.expectRevert(abi.encodeWithSelector(IMigrator.AmountCannotBeZero.selector, weth));
        migrator.migrate(USER, 0, data);
    }

    function test__migrate_Fails_IfAmount1IsZero() public {
        IMigrator.TokenRoute[] memory tokenRoutes = new IMigrator.TokenRoute[](2);
        tokenRoutes[0] = IMigrator.TokenRoute(weth, "");
        tokenRoutes[0] = IMigrator.TokenRoute(usdc, "");
        bytes memory data = abi.encode(IMigrator.MigrationParams(chainIds[0], settlers[0], tokenRoutes, 0, ""));

        migrator.dealLiquidity(weth, usdc, 100, 0);

        vm.expectRevert(abi.encodeWithSelector(IMigrator.AmountCannotBeZero.selector, usdc));
        migrator.migrate(USER, 0, data);
    }

    function test__migrate_Fails_IfToken0NotRouted() public {
        IMigrator.TokenRoute[] memory tokenRoutes = new IMigrator.TokenRoute[](2);
        tokenRoutes[0] = IMigrator.TokenRoute(uni, "");
        tokenRoutes[1] = IMigrator.TokenRoute(usdc, "");
        bytes memory data = abi.encode(IMigrator.MigrationParams(chainIds[0], settlers[0], tokenRoutes, 0, ""));

        migrator.dealLiquidity(weth, usdc, 100, 200);

        vm.expectRevert(abi.encodeWithSelector(IMigrator.TokenNotRouted.selector, weth));
        migrator.migrate(USER, 0, data);
    }

    function test__migrate_Fails_IfToken1NotRouted() public {
        IMigrator.TokenRoute[] memory tokenRoutes = new IMigrator.TokenRoute[](2);
        tokenRoutes[0] = IMigrator.TokenRoute(weth, "");
        tokenRoutes[1] = IMigrator.TokenRoute(uni, "");
        bytes memory data = abi.encode(IMigrator.MigrationParams(chainIds[0], settlers[0], tokenRoutes, 0, ""));

        migrator.dealLiquidity(weth, usdc, 100, 200);

        vm.expectRevert(abi.encodeWithSelector(IMigrator.TokenNotRouted.selector, usdc));
        migrator.migrate(USER, 0, data);
    }

    function test__migrate_Succeeds_BothTokenRoutes() public {
        IMigrator.TokenRoute[] memory tokenRoutes = new IMigrator.TokenRoute[](2);
        tokenRoutes[0] = IMigrator.TokenRoute(weth, "");
        tokenRoutes[1] = IMigrator.TokenRoute(usdc, "");
        bytes memory data = abi.encode(IMigrator.MigrationParams(chainIds[0], settlers[0], tokenRoutes, 0, ""));

        bytes32 migrationId = keccak256(abi.encodePacked(block.chainid, migrator, uint256(1)));
        migrator.dealLiquidity(weth, usdc, 100, 200);

        vm.expectEmit(true, true, true, true);
        emit IMigrator.Migrated(migrationId, chainIds[0], settlers[0], USER, weth, 100);
        vm.expectEmit(true, true, true, true);
        emit IMigrator.Migrated(migrationId, chainIds[0], settlers[0], USER, usdc, 200);

        migrator.migrate(USER, 0, data);
    }

    function test__migrate_Succeeds_FlippedTokenRoutes() public {
        IMigrator.TokenRoute[] memory tokenRoutes = new IMigrator.TokenRoute[](2);
        tokenRoutes[0] = IMigrator.TokenRoute(usdc, "");
        tokenRoutes[1] = IMigrator.TokenRoute(weth, "");
        bytes memory data = abi.encode(IMigrator.MigrationParams(chainIds[0], settlers[0], tokenRoutes, 0, ""));

        bytes32 migrationId = keccak256(abi.encodePacked(block.chainid, migrator, uint256(1)));
        migrator.dealLiquidity(weth, usdc, 100, 200);

        vm.expectEmit(true, true, true, true);
        emit IMigrator.Migrated(migrationId, chainIds[0], settlers[0], USER, usdc, 200);
        vm.expectEmit(true, true, true, true);
        emit IMigrator.Migrated(migrationId, chainIds[0], settlers[0], USER, weth, 100);

        migrator.migrate(USER, 0, data);
    }
}
