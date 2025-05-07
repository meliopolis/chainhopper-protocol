// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/token/ERC721/IERC721Receiver.sol";
import {IPoolManager} from "@uniswap-v4-core/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap-v4-core/types/Currency.sol";
import {PoolKey} from "@uniswap-v4-core/types/PoolKey.sol";
import {IUniswapV4Migrator} from "../../src/interfaces/IUniswapV4Migrator.sol";
import {IUniswapV4Settler} from "../../src/interfaces/IUniswapV4Settler.sol";
import {MockUniswapV4Migrator} from "../mocks/MockUniswapV4Migrator.sol";
import {MockUniswapV4Settler} from "../mocks/MockUniswapV4Settler.sol";
import {TestContext} from "../utils/TestContext.sol";

contract UniswapV4MigratorTest is TestContext {
    string public constant SRC_CHAIN_NAME = "BASE";
    string public constant DEST_CHAIN_NAME = "";

    MockUniswapV4Migrator migrator;
    MockUniswapV4Settler settler;

    function setUp() public {
        _loadChain(SRC_CHAIN_NAME, DEST_CHAIN_NAME);

        migrator =
            new MockUniswapV4Migrator(owner, address(v4PositionManager), address(universalRouter), address(permit2));
        settler = new MockUniswapV4Settler(
            owner, address(v4PositionManager), address(universalRouter), address(permit2), weth
        );
    }

    function test_onERC721Received_fails_ifNotPositionManager() public {
        vm.expectRevert(IUniswapV4Migrator.NotPositionManager.selector);

        vm.prank(user);
        migrator.onERC721Received(address(0), address(0), 0, "");
    }

    function test_fuzz_onERC721Received(address from, uint256 tokenId, bytes memory data) public {
        vm.prank(address(v4PositionManager));
        bytes4 selector = migrator.onERC721Received(address(0), from, tokenId, data);
        assertEq(selector, IERC721Receiver.onERC721Received.selector);
    }

    function test_fuzz_liquidate(bool isNativePosition) public {
        PoolKey memory poolKey = isNativePosition ? v4NativePoolKey : v4TokenPoolKey;

        isNativePosition ? deal(address(settler), 100) : deal(Currency.unwrap(poolKey.currency0), address(settler), 100);
        deal(Currency.unwrap(poolKey.currency1), address(settler), 100);

        uint256 positionId = settler.mintPosition(
            Currency.unwrap(poolKey.currency0),
            Currency.unwrap(v4NativePoolKey.currency1),
            100,
            100,
            address(migrator),
            abi.encode(
                IUniswapV4Settler.MintParams(
                    Currency.unwrap(poolKey.currency0),
                    Currency.unwrap(poolKey.currency1),
                    poolKey.fee,
                    poolKey.tickSpacing,
                    address(0),
                    1_000_000_000_000,
                    -600,
                    600,
                    5_000_000,
                    0,
                    0
                )
            )
        );

        vm.expectEmit(true, true, true, true);
        emit IERC721.Transfer(address(migrator), address(0), positionId);

        vm.expectEmit(true, true, false, false);
        emit IPoolManager.ModifyLiquidity(poolKey.toId(), address(v4PositionManager), 0, 0, 0, "");

        migrator.liquidate(positionId);
    }

    function test_fuzz_swap(bool isNativePosition, bool zeroForOne) public {
        PoolKey memory poolKey = isNativePosition ? v4NativePoolKey : v4TokenPoolKey;

        if (zeroForOne) {
            isNativePosition
                ? deal(address(migrator), 100)
                : deal(Currency.unwrap(poolKey.currency0), address(migrator), 100);
        } else {
            deal(Currency.unwrap(poolKey.currency1), address(migrator), 100);
        }

        migrator.swap(abi.encode(isNativePosition ? v4NativePoolKey : v4TokenPoolKey), zeroForOne, 100);
    }
}
