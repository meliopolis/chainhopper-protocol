// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {SingleTokenV3V3Migrator} from "../src/SingleTokenV3V3Migrator.sol";
import {CustomERC20Mock} from "./mocks/CustomERC20Mock.sol";
import {BasicNft} from "./mocks/BasicNFT.sol";
import {ERC721} from "lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {IERC721} from "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {IERC721Errors} from "lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import {INonfungiblePositionManager} from "../src/interfaces/external/INonfungiblePositionManager.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {ISingleTokenV3Settler} from "../src/interfaces/ISingleTokenV3Settler.sol";
import {SingleTokenV3V3MigratorHarness} from "./SingleTokenV3V3MigratorHarness.sol";
import {IUniswapV3Factory} from "lib/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3PoolEvents} from "lib/v3-core/contracts/interfaces/pool/IUniswapV3PoolEvents.sol";
import {V3SpokePoolInterface} from "../src/interfaces/external/ISpokePool.sol";
import {UniswapV3Helpers} from "./utils/UniswapV3Helpers.t.sol";
import {ISingleTokenV3V3Migrator} from "../src/interfaces/ISingleTokenV3V3Migrator.sol";

contract SingleTokenV3V3MigratorTest is Test, UniswapV3Helpers {
    SingleTokenV3V3MigratorHarness public migratorHarness;
    SingleTokenV3V3Migrator public migrator;
    address public user = address(0x1);
    address public nftPositionManager = vm.envAddress("BASE_NFT_POSITION_MANAGER");
    address public baseToken = vm.envAddress("BASE_WETH");
    address public spokePool = vm.envAddress("BASE_SPOKE_POOL");
    address public swapRouter = vm.envAddress("BASE_SWAP_ROUTER");
    address public usdc = vm.envAddress("BASE_USDC");
    address public virtualToken = address(0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b); // sorts before baseToken

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_MAINNET_RPC_URL"), 25394775);

        // Deploy migrator and harness
        migrator = new SingleTokenV3V3Migrator(nftPositionManager, baseToken, swapRouter, spokePool);
        migratorHarness = new SingleTokenV3V3MigratorHarness(nftPositionManager, baseToken, swapRouter, spokePool);
    }

    function generateMigrationParams() public view returns (ISingleTokenV3V3Migrator.MigrationParams memory) {
        ISingleTokenV3V3Migrator.SettlementParams memory settlementParams = ISingleTokenV3V3Migrator.SettlementParams({
            token0: address(baseToken),
            token1: address(usdc),
            feeTier: 500,
            tickLower: -200000,
            tickUpper: -100000,
            amount0Min: 0,
            amount1Min: 0,
            recipient: user
        });
        return ISingleTokenV3V3Migrator.MigrationParams({
            recipient: user,
            quoteTimestamp: uint32(block.timestamp),
            fillDeadlineBuffer: uint32(21600), // pulled from spokePool.fillDeadlineBuffer()
            exclusivityDeadline: uint32(0),
            maxFees: 0,
            outputToken: vm.envAddress("ARBITRUM_WETH"),
            exclusiveRelayer: address(0),
            destinationChainId: 42161,
            settlementParams: abi.encode(settlementParams)
        });
    }

    function test_msgSenderIsNotNFTPositionManager() public {
        BasicNft nft = new BasicNft();
        vm.prank(user);
        nft.mintNft();
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ISingleTokenV3V3Migrator.SenderIsNotNFTPositionManager.selector));
        migratorHarness.exposed_migratePosition(user, 0, generateMigrationParams());
    }

    function test_LiquidityIsZero() public {
        uint256 tokenId = mintV3Position(nftPositionManager, user, baseToken, usdc, -200000, -100000, 500);
        console.log("tokenId", tokenId);
        withdrawLiquidity(nftPositionManager, user, tokenId);
        vm.prank(nftPositionManager);
        vm.expectRevert(abi.encodeWithSelector(ISingleTokenV3V3Migrator.LiquidityIsZero.selector));
        migratorHarness.exposed_migratePosition(user, tokenId, generateMigrationParams());
    }

    function test_positionWithoutBaseToken() public {
        // picking a random token that is not baseToken
        uint256 tokenId = mintV3Position(
            nftPositionManager, user, usdc, address(0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2), -100, 100, 100
        );
        (,, address token0, address token1,,,,,,,,) = INonfungiblePositionManager(nftPositionManager).positions(tokenId);
        assertNotEq(token0, baseToken);
        assertNotEq(token1, baseToken);
        vm.prank(nftPositionManager);
        vm.expectRevert(abi.encodeWithSelector(ISingleTokenV3V3Migrator.NoBaseTokenFound.selector));
        migratorHarness.exposed_migratePosition(user, tokenId, generateMigrationParams());
    }

    function test_MigratorReceivesPositionInRange_withToken0BaseToken() public {
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

        vm.prank(user);
        INonfungiblePositionManager(nftPositionManager).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(generateMigrationParams())
        );
    }

    function test_MigratorReceivesPositionBelowPoolTick_withToken0BaseToken() public {
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

        vm.prank(user);
        INonfungiblePositionManager(nftPositionManager).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(generateMigrationParams())
        );
    }

    function test_MigratorReceivesPositionAbovePoolTick_withToken0BaseToken() public {
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

        vm.prank(user);
        INonfungiblePositionManager(nftPositionManager).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(generateMigrationParams())
        );
    }

    function test_MigratorReceivesPositionInRange_withToken1BaseToken() public {
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

        vm.prank(user);
        INonfungiblePositionManager(nftPositionManager).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(generateMigrationParams())
        );
    }

    function test_MigratorReceivesPositionBelowPoolTick_withToken1BaseToken() public {
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

        vm.prank(user);
        INonfungiblePositionManager(nftPositionManager).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(generateMigrationParams())
        );
    }

    function test_MigratorReceivesPositionAbovePoolTick_withToken1BaseToken() public {
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

        vm.prank(user);
        INonfungiblePositionManager(nftPositionManager).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(generateMigrationParams())
        );
    }
}
