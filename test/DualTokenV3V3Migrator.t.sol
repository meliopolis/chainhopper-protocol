// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "lib/forge-std/src/Test.sol";
import {IERC721} from "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {AcrossV3Migrator} from "src/base/AcrossV3Migrator.sol";
import {IAcrossV3SpokePool} from "src/interfaces/external/IAcrossV3.sol";
import {IUniswapV3PositionManager} from "src/interfaces/external/IUniswapV3.sol";
import {IDualTokensV3V3Migrator} from "src/interfaces/IDualTokensV3V3Migrator.sol";
import {UniswapV3Library} from "src/libraries/UniswapV3Library.sol";
import {DualTokensV3V3Migrator} from "src/DualTokensV3V3Migrator.sol";

contract DualTokensV3V3MigratorTest is Test {
    uint256 private constant DESTINATION_CHAIN_ID = 42161;
    address private constant SETTLER = address(0x456);
    address private constant RECIPIENT = address(0x789);

    address private USDC = vm.envAddress("BASE_USDC");
    address private WETH = vm.envAddress("BASE_WETH");
    address private positionManager = vm.envAddress("BASE_NFT_POSITION_MANAGER");
    address private spokePool = vm.envAddress("BASE_SPOKE_POOL");

    uint256 private positionAbovePrice;
    uint256 private positionEnclosingPrice;
    uint256 private positionBelowPrice;
    DualTokensV3V3Migrator private migrator;
    IDualTokensV3V3Migrator.MigrationParams private migrationParams;

    using UniswapV3Library for IUniswapV3PositionManager;

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_MAINNET_RPC_URL"), 25394775);

        deal(WETH, address(this), 100 * 1e18);
        deal(USDC, address(this), 100_000 * 1e6);

        migrator = new DualTokensV3V3Migrator(address(positionManager), address(spokePool));
        migrator.setChainSettler(DESTINATION_CHAIN_ID, SETTLER);

        (, int24 tick) = IUniswapV3PositionManager(positionManager).getCurrentSqrtPriceAndTick(WETH, USDC, 3000);
        (positionAbovePrice,,,) = IUniswapV3PositionManager(positionManager).mintPosition(
            WETH, USDC, 500, tick - 1200, tick - 600, 10 * 1e18, 10_000 * 1e6, address(this)
        );
        IERC721(positionManager).approve(address(migrator), positionAbovePrice);
        (positionEnclosingPrice,,,) = IUniswapV3PositionManager(positionManager).mintPosition(
            WETH, USDC, 500, tick - 600, tick + 600, 10 * 1e18, 10_000 * 1e6, address(this)
        );
        IERC721(positionManager).approve(address(migrator), positionEnclosingPrice);
        (positionBelowPrice,,,) = IUniswapV3PositionManager(positionManager).mintPosition(
            WETH, USDC, 500, tick + 600, tick + 1200, 10 * 1e18, 10_000 * 1e6, address(this)
        );
        IERC721(positionManager).approve(address(migrator), positionBelowPrice);

        migrationParams = IDualTokensV3V3Migrator.MigrationParams({
            destinationChainId: DESTINATION_CHAIN_ID,
            recipient: RECIPIENT,
            token0: WETH,
            token1: USDC,
            fee: 500,
            tickLower: -600,
            tickUpper: 600,
            tokensFlipped: false,
            minOutputAmount0: 0,
            minOutputAmount1: 0,
            fillDeadlineOffset: 0
        });
    }

    function test_fuzz_msgSenderIsNotPositionManager(address msgSender) public {
        vm.assume(msgSender != positionManager);

        vm.expectRevert(AcrossV3Migrator.NotPositionManager.selector);
        migrator.onERC721Received(address(0), address(0), 0, "");
    }

    function test_fuzz_chainSetterNotSet(uint256 chainId) public {
        vm.assume(chainId != DESTINATION_CHAIN_ID);
        migrationParams.destinationChainId = chainId;

        vm.prank(positionManager);

        vm.expectRevert(DualTokensV3V3Migrator.DestinationChainSettlerNotFound.selector);
        migrator.onERC721Received(address(0), address(0), 0, abi.encode(migrationParams));
    }

    function test_migragePositionBelowPrice() public {
        vm.prank(positionManager);

        vm.expectEmit(true, true, true, false, address(migrator));
        emit IDualTokensV3V3Migrator.Migrate(
            bytes32(0),
            positionBelowPrice,
            DESTINATION_CHAIN_ID,
            address(this),
            WETH,
            USDC,
            10 * 1e18,
            10_000 * 1e6,
            SETTLER,
            RECIPIENT,
            WETH,
            USDC,
            10 * 1e18,
            10_000 * 1e6,
            500,
            -600,
            600
        );
        migrator.onERC721Received(address(0), address(this), positionBelowPrice, abi.encode(migrationParams));
    }

    function test_migragePositionEnclosingPrice() public {
        vm.prank(positionManager);

        vm.expectEmit(true, true, true, false, address(migrator));
        emit IDualTokensV3V3Migrator.Migrate(
            keccak256(
                abi.encode(8453, positionManager, positionEnclosingPrice, migrator, DESTINATION_CHAIN_ID, SETTLER, 1)
            ),
            positionEnclosingPrice,
            DESTINATION_CHAIN_ID,
            address(this),
            WETH,
            USDC,
            10 * 1e18,
            10_000 * 1e6,
            SETTLER,
            RECIPIENT,
            WETH,
            USDC,
            10 * 1e18,
            10_000 * 1e6,
            500,
            -600,
            600
        );
        migrator.onERC721Received(address(0), address(this), positionEnclosingPrice, abi.encode(migrationParams));
    }

    function test_migragePositionAbovePrice() public {
        vm.prank(positionManager);

        vm.expectEmit(true, true, true, false, address(migrator));
        emit IDualTokensV3V3Migrator.Migrate(
            bytes32(0),
            positionAbovePrice,
            DESTINATION_CHAIN_ID,
            address(this),
            WETH,
            USDC,
            10 * 1e18,
            10_000 * 1e6,
            SETTLER,
            RECIPIENT,
            WETH,
            USDC,
            10 * 1e18,
            10_000 * 1e6,
            500,
            -600,
            600
        );
        migrator.onERC721Received(address(0), address(this), positionAbovePrice, abi.encode(migrationParams));
    }
}
