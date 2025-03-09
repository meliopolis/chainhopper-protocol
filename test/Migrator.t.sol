// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "@forge-std/Test.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";
import {IERC721Errors} from "@openzeppelin/interfaces/draft-IERC6093.sol";
import {INonfungiblePositionManager} from "@uniswap-v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {UniswapV3Helpers} from "./utils/UniswapV3Helpers.t.sol";
import {BaseMigrator} from "./mocks/Migrator.sol";
import {BasicNft} from "./mocks/BasicNft.sol";
import {IMigrator} from "../src/interfaces/IMigrator.sol";

contract MigratorTest is Test, UniswapV3Helpers {
    BaseMigrator public migrator;
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
        migrator = new BaseMigrator(nftPositionManager);
        vm.stopPrank();
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
        nft.safeTransferFrom(user, address(migrator), 0, abi.encode(""));
    }

    function test_ERC721Received() public {
        uint256 tokenId = mintV3Position(nftPositionManager, user, baseToken, usdc, -200000, -199900, 500);
        vm.prank(user);
        INonfungiblePositionManager(nftPositionManager).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode("")
        );
    }
}
