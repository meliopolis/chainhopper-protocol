// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC721} from "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {IERC721Errors} from "lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import {INonfungiblePositionManager} from "../src/interfaces/external/INonfungiblePositionManager.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {ISingleTokenV3Settler} from "../src/interfaces/ISingleTokenV3Settler.sol";
import {IUniswapV3Factory} from "lib/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3PoolEvents} from "lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolEvents.sol";
import {V3SpokePoolInterface} from "../src/interfaces/external/ISpokePool.sol";
import {UniswapV3Helpers} from "./utils/UniswapV3Helpers.t.sol";
import {AcrossV3MigratorHarness} from "./AcrossV3MigratorHarness.sol";
import {AcrossV3Migrator} from "../src/AcrossV3Migrator.sol";
import {IV3Settler} from "../src/interfaces/IV3Settler.sol";
import {IAcrossMigrator} from "../src/interfaces/IAcrossMigrator.sol";
import {IMigrator} from "../src/interfaces/IMigrator.sol";
import {BasicNft} from "./mocks/BasicNft.sol";
contract AcrossV3MigratorTest is Test, UniswapV3Helpers {
    AcrossV3MigratorHarness public migratorHarness;
    AcrossV3Migrator public migrator;
    address public user = address(0x1);
    address public owner = address(0x2);
    address public nftPositionManager = vm.envAddress("BASE_NFT_POSITION_MANAGER");
    address public spokePool = vm.envAddress("BASE_SPOKE_POOL");
    address public swapRouter = vm.envAddress("BASE_SWAP_ROUTER");
    address public baseToken = vm.envAddress("BASE_WETH");
    address public usdc = vm.envAddress("BASE_USDC");
    address public virtualToken = address(0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b); // sorts before baseToken
    address public destinationChainSettler = address(0x123);

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_MAINNET_RPC_URL"), 25394775);

        // Deploy migrator and harness
        vm.startPrank(owner);
        migrator = new AcrossV3Migrator(nftPositionManager, spokePool, swapRouter);
        migrator.addChainSettler(42161, destinationChainSettler);
        migratorHarness = new AcrossV3MigratorHarness(nftPositionManager, spokePool, swapRouter);
        migratorHarness.addChainSettler(42161, destinationChainSettler);
        vm.stopPrank();
    }

    function generateAcrossMigrationParams(uint8 numRoutes)
        public
        view
        returns (IAcrossMigrator.AcrossMigrationParams memory)
    {
        IV3Settler.V3SettlementParams memory settlementParams = IV3Settler.V3SettlementParams({
            recipient: user,
            token0: address(baseToken),
            token1: address(usdc),
            feeTier: 500,
            tickLower: -200000,
            tickUpper: -100000,
            amount0Min: 0,
            amount1Min: 0,
            senderFeeBps: 0,
            senderFeeRecipient: address(0)
        });
        IMigrator.BaseMigrationParams memory baseParams = IMigrator.BaseMigrationParams({
            recipient: destinationChainSettler,
            settlementParams: abi.encode(settlementParams),
            destinationChainId: 42161
        });
        IAcrossMigrator.AcrossRoute[] memory acrossRoutes = new IAcrossMigrator.AcrossRoute[](numRoutes);
        if (numRoutes > 0) {
            acrossRoutes[0] = IAcrossMigrator.AcrossRoute({
                inputToken: address(baseToken),
                outputToken: vm.envAddress("ARBITRUM_WETH"),
                maxFees: 0,
                quoteTimestamp: uint32(block.timestamp),
                fillDeadlineOffset: uint32(21600),
                exclusiveRelayer: address(0),
                exclusivityDeadline: uint32(0)
            });
        }
        if (numRoutes > 1) {
            acrossRoutes[1] = IAcrossMigrator.AcrossRoute({
                inputToken: address(usdc),
                outputToken: vm.envAddress("ARBITRUM_USDC"),
                maxFees: 0,
                quoteTimestamp: uint32(block.timestamp),
                fillDeadlineOffset: uint32(21600),
                exclusiveRelayer: address(0),
                exclusivityDeadline: uint32(0)
            });
        }
        if (numRoutes > 2) {
            acrossRoutes[2] = IAcrossMigrator.AcrossRoute({
                inputToken: address(usdc),
                outputToken: vm.envAddress("ARBITRUM_USDC"),
                maxFees: 0,
                quoteTimestamp: uint32(block.timestamp),
                fillDeadlineOffset: uint32(21600),
                exclusiveRelayer: address(0),
                exclusivityDeadline: uint32(0)
            });
        }
        return IAcrossMigrator.AcrossMigrationParams({baseParams: baseParams, acrossRoutes: acrossRoutes});
    }

    /*
     * Owner functions
     */

    function test_addChainSettlerFailsIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        migrator.addChainSettler(42161, address(0x456));
    }

    function test_addChainSettler() public {
        vm.prank(owner);
        migrator.addChainSettler(42161, address(0x456));
        assertEq(migrator.isChainSettler(42161, address(0x456)), true);
    }

    function test_removeChainSettlerFailsIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        migrator.removeChainSettler(42161, address(0x456));
    }

    function test_removeChainSettler() public {
        vm.prank(owner);
        migrator.removeChainSettler(42161, address(0x456));
        assertEq(migrator.isChainSettler(42161, address(0x456)), false);
    }

    /*
    * Error cases
    */

    function test_msgSenderIsNotNFTPositionManager() public {
        BasicNft nft = new BasicNft();
        vm.prank(user);
        nft.mintNft();
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IMigrator.NotPositionManager.selector));
        nft.safeTransferFrom(user, address(migrator), 0, abi.encode(generateAcrossMigrationParams(1)));
    }

    function test_failsIfDestinationChainSettlerNotFound() public {
        vm.prank(owner);
        migratorHarness.removeChainSettler(42161, destinationChainSettler);
        vm.expectRevert(abi.encodeWithSelector(IMigrator.DestinationChainSettlerNotFound.selector));
        migratorHarness.exposed_migrate(user, 0, abi.encode(generateAcrossMigrationParams(1)));
    }

    function test_failsIfNoAcrossRoutesFound() public {
        vm.expectRevert(abi.encodeWithSelector(IAcrossMigrator.NoAcrossRoutesFound.selector));
        migratorHarness.exposed_migrate(user, 0, abi.encode(generateAcrossMigrationParams(0)));
    }

    function test_failsIfTooManyAcrossRoutes() public {
        vm.expectRevert(abi.encodeWithSelector(IAcrossMigrator.TooManyAcrossRoutes.selector));
        migratorHarness.exposed_migrate(user, 0, abi.encode(generateAcrossMigrationParams(3)));
    }

    /*
    SingleToken tests
    */

    function test_failsIfRoute0InputTokenNotFound() public {
        // minting a position without routeInputToken
        uint256 tokenId = mintV3Position(
            nftPositionManager, user, usdc, address(0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2), -100, 100, 100
        );
        vm.prank(user);
        INonfungiblePositionManager(nftPositionManager).safeTransferFrom(
            user, address(migratorHarness), tokenId, abi.encode(generateAcrossMigrationParams(1))
        );
        vm.expectRevert(abi.encodeWithSelector(IAcrossMigrator.RouteInputTokenNotFound.selector, 0));
        migratorHarness.exposed_migrate(user, tokenId, abi.encode(generateAcrossMigrationParams(1)));
    }

    function test_singleToken_positionInRange_withToken0AsRouteInputToken() public {
        address token0 = baseToken;
        address token1 = usdc;
        uint256 tokenId = mintV3Position(nftPositionManager, user, baseToken, usdc, -200000, -100000, 500);
        // verify posToken0 is baseToken
        (,, address posToken0,,,,,,,,,) = INonfungiblePositionManager(nftPositionManager).positions(tokenId);
        assertEq(posToken0, token0);

        // Transfer Position from user to migrator
        vm.expectEmit(false, false, false, false);
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Burn(address(nftPositionManager), 0, 0, 0, 0, 0);
        vm.expectEmit(true, false, false, false);
        emit INonfungiblePositionManager.DecreaseLiquidity(tokenId, 0, 0, 0);

        // collect
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Collect(nftPositionManager, address(migrator), 0, 0, 0, 0);
        vm.expectEmit(true, false, false, false);
        emit INonfungiblePositionManager.Collect(tokenId, address(0), 0, 0);

        // Swap
        vm.expectEmit(true, true, false, false, address(token1));
        emit IERC20.Approval(address(migrator), swapRouter, 0);
        vm.expectEmit(true, true, false, false);
        emit IUniswapV3PoolEvents.Swap(address(swapRouter), address(migrator), 0, 1, 0, 0, 0);

        // bridge
        vm.expectEmit(true, true, false, false, address(token0));
        emit IERC20.Approval(address(migrator), spokePool, 0);
        vm.expectEmit(true, false, false, false);
        emit V3SpokePoolInterface.V3FundsDeposited(
            address(0), address(0), 0, 0, 42161, 1, 1737578897, 1737578997, 0, user, user, address(0), ""
        );
        vm.expectEmit(true, true, false, false, address(migrator));
        emit IAcrossMigrator.PositionSent(tokenId, 42161, destinationChainSettler, "");

        vm.prank(user);
        INonfungiblePositionManager(nftPositionManager).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(generateAcrossMigrationParams(1))
        );
    }

    function test_singleToken_positionBelowPoolTick_withToken0AsRouteInputToken() public {
        address token0 = baseToken;
        address token1 = usdc;
        IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(token0, token1, 500));
        (, int24 tick,,,,,) = pool.slot0();
        // todo can make this dynamic; need to calculate ticks based tickSpacing
        uint256 tokenId = mintV3Position(nftPositionManager, user, baseToken, usdc, -200000, -199900, 500);
        assertLt(-199900, tick);
        // verify posToken0 is baseToken
        (,, address posToken0,,,,,,,,,) = INonfungiblePositionManager(nftPositionManager).positions(tokenId);
        assertEq(posToken0, token0);

        // Transfer Position from user to migrator
        vm.expectEmit(false, false, false, false);
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Burn(address(nftPositionManager), 0, 0, 0, 0, 0);
        vm.expectEmit(true, false, false, false);
        emit INonfungiblePositionManager.DecreaseLiquidity(tokenId, 0, 0, 0);

        // collect
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Collect(nftPositionManager, address(migrator), 0, 0, 0, 0);
        vm.expectEmit(true, false, false, false);
        emit INonfungiblePositionManager.Collect(tokenId, address(0), 0, 0);

        // Swap
        vm.expectEmit(true, true, false, false, address(token1));
        emit IERC20.Approval(address(migrator), swapRouter, 0);
        vm.expectEmit(true, true, false, false);
        emit IUniswapV3PoolEvents.Swap(address(swapRouter), address(migrator), 0, 1, 0, 0, 0);

        // bridge
        vm.expectEmit(true, true, false, false, address(token0));
        emit IERC20.Approval(address(migrator), spokePool, 0);
        vm.expectEmit(true, false, false, false);
        emit V3SpokePoolInterface.V3FundsDeposited(
            address(0), address(0), 0, 0, 42161, 1, 1737578897, 1737578997, 0, user, user, address(0), ""
        );
        vm.expectEmit(true, true, false, false, address(migrator));
        emit IAcrossMigrator.PositionSent(tokenId, 42161, destinationChainSettler, "");

        vm.prank(user);
        INonfungiblePositionManager(nftPositionManager).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(generateAcrossMigrationParams(1))
        );
    }

    function test_singleToken_positionAbovePoolTick_withToken0AsRouteInputToken() public {
        address token0 = baseToken;
        address token1 = usdc;
        IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(token0, token1, 500));
        (, int24 tick,,,,,) = pool.slot0();
        // todo can make this dynamic; need to calculate ticks based on tickSpacing
        uint256 tokenId = mintV3Position(nftPositionManager, user, token0, token1, -180000, -179900, 500);
        assertGt(-180000, tick);
        // verify posToken0 is baseToken
        (,, address posToken0,,,,,,,,,) = INonfungiblePositionManager(nftPositionManager).positions(tokenId);
        assertEq(posToken0, token0);

        // Transfer Position from user to migrator
        vm.expectEmit(false, false, false, false);
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Burn(address(nftPositionManager), 0, 0, 0, 0, 0);
        vm.expectEmit(true, false, false, false);
        emit INonfungiblePositionManager.DecreaseLiquidity(tokenId, 0, 0, 0);

        // collect
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Collect(nftPositionManager, address(migrator), 0, 0, 0, 0);
        vm.expectEmit(true, false, false, false);
        emit INonfungiblePositionManager.Collect(tokenId, address(0), 0, 0);

        // Swap not needed, only basetoken in this position

        // bridge
        vm.expectEmit(true, true, false, false, address(token0));
        emit IERC20.Approval(address(migrator), spokePool, 0);
        vm.expectEmit(true, false, false, false);
        emit V3SpokePoolInterface.V3FundsDeposited(
            address(0), address(0), 0, 0, 42161, 1, 1737578897, 1737578997, 0, user, user, address(0), ""
        );
        vm.expectEmit(true, true, false, false, address(migrator));
        emit IAcrossMigrator.PositionSent(tokenId, 42161, destinationChainSettler, "");

        vm.prank(user);
        INonfungiblePositionManager(nftPositionManager).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(generateAcrossMigrationParams(1))
        );
    }

    function test_singleToken_positionInRange_withToken1AsRouteInputToken() public {
        address token0 = virtualToken;
        address token1 = baseToken;
        uint256 tokenId = mintV3Position(nftPositionManager, user, token0, token1, -200040, -60000, 3000);
        // verify posToken1 is baseToken
        (,,, address posToken1,,,,,,,,) = INonfungiblePositionManager(nftPositionManager).positions(tokenId);
        assertEq(posToken1, baseToken);

        // Transfer Position from user to migrator
        vm.expectEmit(false, false, false, false);
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Burn(address(nftPositionManager), 0, 0, 0, 0, 0);
        vm.expectEmit(true, false, false, false);
        emit INonfungiblePositionManager.DecreaseLiquidity(tokenId, 0, 0, 0);

        // collect
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Collect(nftPositionManager, address(migrator), 0, 0, 0, 0);
        vm.expectEmit(true, false, false, false);
        emit INonfungiblePositionManager.Collect(tokenId, address(0), 0, 0);

        // // Swap
        vm.expectEmit(true, true, false, false, address(token0));
        emit IERC20.Approval(address(migrator), swapRouter, 0);
        vm.expectEmit(true, true, false, false);
        emit IUniswapV3PoolEvents.Swap(address(swapRouter), address(migrator), 0, 1, 0, 0, 0);

        // bridge
        vm.expectEmit(true, true, false, false, address(token1));
        emit IERC20.Approval(address(migrator), spokePool, 0);
        vm.expectEmit(true, false, false, false);
        emit V3SpokePoolInterface.V3FundsDeposited(
            address(0), address(0), 0, 0, 42161, 1, 1737578897, 1737578997, 0, user, user, address(0), ""
        );
        vm.expectEmit(true, true, false, false, address(migrator));
        emit IAcrossMigrator.PositionSent(tokenId, 42161, destinationChainSettler, "");

        vm.prank(user);
        INonfungiblePositionManager(nftPositionManager).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(generateAcrossMigrationParams(1))
        );
    }

    function test_singleToken_positionBelowPoolTick_withToken1AsRouteInputToken() public {
        address token0 = virtualToken;
        address token1 = baseToken;
        IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(token0, token1, 3000));
        (, int24 tick,,,,,) = pool.slot0();
        // todo can make this dynamic; need to calculate ticks based tickSpacing
        uint256 tokenId = mintV3Position(nftPositionManager, user, token0, token1, -81000, -78000, 3000);
        assertLt(-78000, tick);
        // verify posToken1 is baseToken
        (,,, address posToken1,,,,,,,,) = INonfungiblePositionManager(nftPositionManager).positions(tokenId);
        assertEq(posToken1, baseToken);

        // Transfer Position from user to migrator
        vm.expectEmit(false, false, false, false);
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Burn(address(nftPositionManager), 0, 0, 0, 0, 0);
        vm.expectEmit(true, false, false, false);
        emit INonfungiblePositionManager.DecreaseLiquidity(tokenId, 0, 0, 0);

        // collect
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Collect(nftPositionManager, address(migrator), 0, 0, 0, 0);
        vm.expectEmit(true, false, false, false);
        emit INonfungiblePositionManager.Collect(tokenId, address(0), 0, 0);

        // Swap not needed, only basetoken in this position

        // bridge
        vm.expectEmit(true, true, false, false, address(token1));
        emit IERC20.Approval(address(migrator), spokePool, 0);
        vm.expectEmit(true, false, false, false);
        emit V3SpokePoolInterface.V3FundsDeposited(
            address(0), address(0), 0, 0, 42161, 1, 1737578897, 1737578997, 0, user, user, address(0), ""
        );
        vm.expectEmit(true, true, false, false, address(migrator));
        emit IAcrossMigrator.PositionSent(tokenId, 42161, destinationChainSettler, "");

        vm.prank(user);
        INonfungiblePositionManager(nftPositionManager).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(generateAcrossMigrationParams(1))
        );
    }

    function test_singleToken_positionAbovePoolTick_withToken1AsRouteInputToken() public {
        address token0 = virtualToken;
        address token1 = baseToken;
        IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(token0, token1, 3000));
        (, int24 tick,,,,,) = pool.slot0();
        // todo can make this dynamic; need to calculate ticks based on tickSpacing
        uint256 tokenId = mintV3Position(nftPositionManager, user, token0, token1, -60000, -48000, 3000);
        assertGt(-60000, tick);
        // verify posToken1 is baseToken
        (,,, address posToken1,,,,,,,,) = INonfungiblePositionManager(nftPositionManager).positions(tokenId);
        assertEq(posToken1, baseToken);

        // Transfer Position from user to migrator
        vm.expectEmit(false, false, false, false);
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Burn(address(nftPositionManager), 0, 0, 0, 0, 0);
        vm.expectEmit(true, false, false, false);
        emit INonfungiblePositionManager.DecreaseLiquidity(tokenId, 0, 0, 0);

        // collect
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Collect(nftPositionManager, address(migrator), 0, 0, 0, 0);
        vm.expectEmit(true, false, false, false);
        emit INonfungiblePositionManager.Collect(tokenId, address(0), 0, 0);

        // Swap
        vm.expectEmit(true, true, false, false, address(token0));
        emit IERC20.Approval(address(migrator), swapRouter, 0);
        vm.expectEmit(true, true, false, false);
        emit IUniswapV3PoolEvents.Swap(address(swapRouter), address(migrator), 0, 1, 0, 0, 0);

        // bridge
        vm.expectEmit(true, true, false, false, address(token1));
        emit IERC20.Approval(address(migrator), spokePool, 0);
        vm.expectEmit(true, false, false, false);
        emit V3SpokePoolInterface.V3FundsDeposited(
            address(0), address(0), 0, 0, 42161, 1, 1737578897, 1737578997, 0, user, user, address(0), ""
        );
        vm.expectEmit(true, true, false, false, address(migrator));
        emit IAcrossMigrator.PositionSent(tokenId, 42161, destinationChainSettler, "");

        vm.prank(user);
        INonfungiblePositionManager(nftPositionManager).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(generateAcrossMigrationParams(1))
        );
    }

    /*
    DualToken tests
    */

    function test_dualToken_failsIfUnusedExtraRoute() public {
        // mint a one-sided position
        address token0 = baseToken;
        address token1 = usdc;
        uint256 tokenId = mintV3Position(nftPositionManager, user, token0, token1, -180000, -179900, 500);
        vm.prank(user);
        INonfungiblePositionManager(nftPositionManager).safeTransferFrom(
            user, address(migratorHarness), tokenId, abi.encode(generateAcrossMigrationParams(1))
        );
        vm.expectRevert(abi.encodeWithSelector(IAcrossMigrator.UnusedExtraRoute.selector));
        migratorHarness.exposed_migrate(user, tokenId, abi.encode(generateAcrossMigrationParams(2)));
    }

    function test_dualToken_failsIfToken0IsNotRouteInputToken() public {
        address token0 = virtualToken;
        address token1 = baseToken;
        uint256 tokenId = mintV3Position(nftPositionManager, user, token0, token1, -200040, -60000, 3000);
        vm.prank(user);
        INonfungiblePositionManager(nftPositionManager).safeTransferFrom(
            user, address(migratorHarness), tokenId, abi.encode(generateAcrossMigrationParams(2))
        );
        vm.expectRevert(abi.encodeWithSelector(IAcrossMigrator.RouteInputTokenNotFound.selector, 0));
        migratorHarness.exposed_migrate(user, tokenId, abi.encode(generateAcrossMigrationParams(2)));
    }

    function test_dualToken_failsIfToken1IsNotRouteInputToken() public {
        address token0 = baseToken;
        address token1 = 0x940181a94A35A4569E4529A3CDfB74e38FD98631; // aerodome token
        uint256 tokenId = mintV3Position(nftPositionManager, user, token0, token1, 60000, 90000, 3000);
        vm.prank(user);
        INonfungiblePositionManager(nftPositionManager).safeTransferFrom(
            user, address(migratorHarness), tokenId, abi.encode(generateAcrossMigrationParams(2))
        );
        vm.expectRevert(abi.encodeWithSelector(IAcrossMigrator.RouteInputTokenNotFound.selector, 1));
        migratorHarness.exposed_migrate(user, tokenId, abi.encode(generateAcrossMigrationParams(2)));
    }

    function test_dualToken_positionInRange() public {
        address token0 = baseToken;
        address token1 = usdc;
        uint256 tokenId = mintV3Position(nftPositionManager, user, token0, token1, -200000, -100000, 500);
        // verify posToken0 is baseToken
        (,, address posToken0,,,,,,,,,) = INonfungiblePositionManager(nftPositionManager).positions(tokenId);
        assertEq(posToken0, token0);

        // Transfer Position from user to migrator
        vm.expectEmit(false, false, false, false);
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Burn(address(nftPositionManager), 0, 0, 0, 0, 0);
        vm.expectEmit(true, false, false, false);
        emit INonfungiblePositionManager.DecreaseLiquidity(tokenId, 0, 0, 0);

        // collect
        vm.expectEmit(true, false, false, false);
        emit IUniswapV3PoolEvents.Collect(nftPositionManager, address(migrator), 0, 0, 0, 0);
        vm.expectEmit(true, false, false, false);
        emit INonfungiblePositionManager.Collect(tokenId, address(0), 0, 0);

        // bridge
        vm.expectEmit(true, true, false, false, address(token0));
        emit IERC20.Approval(address(migrator), spokePool, 0);
        vm.expectEmit(true, false, false, false);
        emit V3SpokePoolInterface.V3FundsDeposited(
            address(0), address(0), 0, 0, 42161, 1, 1737578897, 1737578997, 0, user, user, address(0), ""
        );
        vm.expectEmit(true, true, false, false, address(token1));
        emit IERC20.Approval(address(migrator), spokePool, 0);
        vm.expectEmit(true, false, false, false);
        emit V3SpokePoolInterface.V3FundsDeposited(
            address(0), address(0), 0, 0, 42161, 1, 1737578897, 1737578997, 0, user, user, address(0), ""
        );
        vm.expectEmit(true, true, false, false, address(migrator));
        emit IAcrossMigrator.PositionSent(tokenId, 42161, destinationChainSettler, "");

        vm.prank(user);
        INonfungiblePositionManager(nftPositionManager).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(generateAcrossMigrationParams(2))
        );
    }
}
