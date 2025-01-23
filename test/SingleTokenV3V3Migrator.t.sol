// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {LPMigratorSingleToken} from "../src/LPMigratorSingleToken.sol";
import {MockSpokePool} from "./mocks/MockSpokePool.sol";
import {CustomERC20Mock} from "./mocks/CustomERC20Mock.sol";
import {BasicNft} from "./mocks/BasicNFT.sol";
import {ERC721} from "lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {IERC721Errors} from "lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import {INonfungiblePositionManager} from "../src/interfaces/external/INonfungiblePositionManager.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {ILPMigrator} from "../src/interfaces/ILPMigrator.sol";
import {LPMigratorSingleTokenHarness} from "./LPMigratorSingleTokenHarness.sol";
import {IUniswapV3Factory} from "lib/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract SingleTokenV3V3MigratorTest is Test {
    LPMigratorSingleTokenHarness public migrator;
    address public user = address(0x1);
    address public nftPositionManager = vm.envAddress("BASE_NFT_POSITION_MANAGER");
    address public baseToken = vm.envAddress("BASE_WETH");
    address public spokePool = vm.envAddress("BASE_SPOKE_POOL");
    address public swapRouter = vm.envAddress("BASE_SWAP_ROUTER");
    address public usdc = vm.envAddress("BASE_USDC");

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_MAINNET_RPC_URL"), 25394775);

        // Deploy migrator
        migrator = new LPMigratorSingleTokenHarness(nftPositionManager, baseToken, swapRouter, spokePool);
    }

    function mintV3Position(address token0, address token1, int24 tickLower, int24 tickUpper, uint24 fee)
        public
        returns (uint256)
    {
        // give user eth and usdc
        deal(token0, user, 10_000_000_000_000_000_000_000);
        deal(token1, user, 10_000_000_000);
        // mint v3 position
        vm.prank(user);
        IERC20(token0).approve(nftPositionManager, 1_000_000_000_000_000_000_000);
        vm.prank(user);
        IERC20(token1).approve(nftPositionManager, 1000_000_000);

        vm.prank(user);
        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: 1_000_000_000_000_000_000_000,
            amount1Desired: 1000_000_000,
            amount0Min: 0,
            amount1Min: 0,
            recipient: user,
            deadline: block.timestamp
        });
        (uint256 tokenId,,,) = INonfungiblePositionManager(nftPositionManager).mint(mintParams);
        // return position id
        return tokenId;
    }

    function withdrawLiquidity(uint256 tokenId) public {
        (,,,,,,, uint128 liquidity,,,,) = INonfungiblePositionManager(nftPositionManager).positions(tokenId);
        vm.prank(user);
        INonfungiblePositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = INonfungiblePositionManager
            .DecreaseLiquidityParams({
            tokenId: tokenId,
            liquidity: liquidity,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });
        INonfungiblePositionManager(nftPositionManager).decreaseLiquidity(decreaseLiquidityParams);
    }

    function generateMigrationParams() public view returns (ILPMigrator.MigrationParams memory) {
        ILPMigrator.MintParams memory mintParams = ILPMigrator.MintParams({
            token0: address(baseToken),
            token1: address(usdc),
            fee: 500,
            tickLower: -200000,
            tickUpper: -100000,
            amount0Min: 0,
            amount1Min: 0,
            recipient: user,
            percentToken0: 0
        });
        return ILPMigrator.MigrationParams({
            recipient: user,
            quoteTimestamp: uint32(block.timestamp),
            fillDeadlineBuffer: uint32(21600), // pulled from spokePool.fillDeadlineBuffer()
            exclusivityDeadline: uint32(0),
            maxFees: 0,
            outputToken: vm.envAddress("ARBITRUM_WETH"),
            exclusiveRelayer: address(0),
            destinationChainId: 42161,
            mintParams: abi.encode(mintParams)
        });
    }

    function test_msgSenderIsNotNFTPositionManager() public {
        BasicNft nft = new BasicNft();
        vm.prank(user);
        nft.mintNft();
        console.log("nftOwner", user);
        console.log("migrator", address(migrator));
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ILPMigrator.SenderIsNotNFTPositionManager.selector));
        migrator.exposed_migratePosition(user, 0, generateMigrationParams());
    }

    function test_LiquidityIsZero() public {
        uint256 tokenId = mintV3Position(baseToken, usdc, -200000, -100000, 500);
        console.log("tokenId", tokenId);
        withdrawLiquidity(tokenId);
        vm.prank(nftPositionManager);
        vm.expectRevert(abi.encodeWithSelector(ILPMigrator.LiquidityIsZero.selector));
        migrator.exposed_migratePosition(user, tokenId, generateMigrationParams());
    }

    function test_positionDoesNotContainBaseToken() public {
        // picking a random token that is not baseToken
        uint256 tokenId = mintV3Position(usdc, address(0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2), -100, 100, 100);
        (,, address token0, address token1,,,,,,,,) = INonfungiblePositionManager(nftPositionManager).positions(tokenId);
        assertNotEq(token0, baseToken);
        assertNotEq(token1, baseToken);
        vm.prank(nftPositionManager);
        vm.expectRevert(abi.encodeWithSelector(ILPMigrator.NoBaseTokenFound.selector));
        migrator.exposed_migratePosition(user, tokenId, generateMigrationParams());
    }

    function test_MigratorReceivesPositionInRangeWithToken0BaseToken() public {
        uint256 tokenId = mintV3Position(baseToken, usdc, -200000, -100000, 500);
        // verify token0 is baseToken
        (,, address token0,,,,,,,,,) = INonfungiblePositionManager(nftPositionManager).positions(tokenId);
        assertEq(token0, baseToken);
        // todo: verify position is in range
        vm.prank(user);
        INonfungiblePositionManager(nftPositionManager).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(generateMigrationParams())
        );
    }

    function test_MigratorReceivesPositionInRangeWithToken1BaseToken() public {
        // todo: implement
    }

    function test_MigratorReceivesPositionBelowPoolTickWithToken0BaseToken() public {
        IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(baseToken, usdc, 500));
        (, int24 tick,,,,,) = pool.slot0();
        // todo can make this dynamic; need to calculate ticks based tickSpacing
        uint256 tokenId = mintV3Position(baseToken, usdc, -200000, -199900, 500);
        assertLt(-199900, tick);
        // verify token0 is baseToken
        (,, address token0,,,,,,,,,) = INonfungiblePositionManager(nftPositionManager).positions(tokenId);
        assertEq(token0, baseToken);
        vm.prank(user);
        INonfungiblePositionManager(nftPositionManager).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(generateMigrationParams())
        );
    }

    function test_MigratorReceivesPositionBelowPoolTickWithToken1BaseToken() public {
        // todo: implement
    }

    function test_MigratorReceivesPositionAbovePoolTickWithToken0BaseToken() public {
        IUniswapV3Factory factory = IUniswapV3Factory(INonfungiblePositionManager(nftPositionManager).factory());
        IUniswapV3Pool pool = IUniswapV3Pool(factory.getPool(baseToken, usdc, 500));
        (, int24 tick,,,,,) = pool.slot0();
        // todo can make this dynamic; need to calculate ticks based on tickSpacing
        uint256 tokenId = mintV3Position(baseToken, usdc, -180000, -179900, 500);
        assertGt(-180000, tick);
        // verify token0 is baseToken
        (,, address token0,,,,,,,,,) = INonfungiblePositionManager(nftPositionManager).positions(tokenId);
        assertEq(token0, baseToken);
        vm.prank(user);
        INonfungiblePositionManager(nftPositionManager).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(generateMigrationParams())
        );
    }

    function test_MigratorReceivesPositionAbovePoolTickWithToken1BaseToken() public {
        // todo: implement
    }
}
