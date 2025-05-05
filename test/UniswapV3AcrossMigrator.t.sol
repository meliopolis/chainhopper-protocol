// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Test.sol";
import {TestContext} from "./utils/TestContext.sol";
import {IMigrator} from "../src/interfaces/IMigrator.sol";
import {IAcrossMigrator} from "../src/interfaces/IAcrossMigrator.sol";
import {ISettler} from "../src/interfaces/ISettler.sol";
import {IUniswapV3Settler} from "../src/interfaces/IUniswapV3Settler.sol";
import {UniswapV3AcrossMigrator} from "../src/UniswapV3AcrossMigrator.sol";
import {UniswapV3Helpers} from "./utils/UniswapV3Helpers.sol";
import {IERC721} from "@openzeppelin/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {INonfungiblePositionManager} from "../src/interfaces/external/INonfungiblePositionManager.sol";
import {IUniswapV3PoolEvents} from "@uniswap-v3-core/interfaces/pool/IUniswapV3PoolEvents.sol";
import {V3SpokePoolInterface} from "@across/interfaces/V3SpokePoolInterface.sol";
import {MigrationModes, MigrationMode} from "../src/types/MigrationMode.sol";
import {AcrossHelpers} from "./utils/AcrossHelpers.sol";
import {MigrationHelpers} from "./utils/MigrationHelpers.sol";

contract UniswapV3AcrossMigratorTest is TestContext, UniswapV3Helpers {
    string public constant CHAIN_NAME = "BASE";
    address public settler = address(123);
    uint256 public maxFees = 10_000_000;
    UniswapV3AcrossMigrator public migrator;
    uint256 public sourceChainId = 8453;
    uint256 public destinationChainId = 130;

    function setUp() public {
        _loadChain(CHAIN_NAME);

        vm.prank(owner);
        migrator =
            new UniswapV3AcrossMigrator(owner, v3PositionManager, universalRouter, permit2, acrossSpokePool, weth);
        // update chainSettler
        vm.prank(owner);
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = destinationChainId;
        address[] memory settlers = new address[](1);
        settlers[0] = address(settler);
        bool[] memory values = new bool[](1);
        values[0] = true;
        migrator.setChainSettlers(chainIds, settlers, values);
    }

    /*
    TokenPairs to include in tests:
    - weth/usdc (token0: weth/default basetoken, token1: usdc/second basetoken for dual token paths)
    - erc20/weth (token0: erc20 and token1: weth/basetoken)
    - usdc/usdt (non-weth token pair with usdc as base token)

    Ranges to include in tests:
    - below tickLower
    - between tickLower and tickUpper (in-range)
    - above tickUpper

    Paths to include in tests:
    - Single token path
    - Dual token path (only applicable to both tokens being base tokens and in range)
    */

    /**
     * SINGLE TOKEN PATHS ***
     */
    function test_onERC721Received_Token0WETHBaseToken_InRange() public {
        vm.recordLogs();
        address token0 = weth;
        address token1 = usdc;
        (uint256 tokenId, uint256 amount0, uint256 amount1) =
            mintV3Position(v3PositionManager, user, token0, token1, -250000, -100000, 500);

        // verify posToken0 is baseToken
        (,, address posToken0,,,,,,,,,) =
            INonfungiblePositionManager(v3PositionManager).positions(tokenId);
        assertEq(posToken0, token0);

        IMigrator.MigrationParams memory migrationParams =
            MigrationHelpers.generateMigrationParams(token0, address(settler));

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v3PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false, address(v3PositionManager));
        emit INonfungiblePositionManager.DecreaseLiquidity(tokenId, 0, 0, 0);

        // collect
        vm.expectEmit(true, false, false, false, address(v3PositionManager));
        emit INonfungiblePositionManager.Collect(tokenId, address(0), 0, 0);

        // Swap
        vm.expectEmit(true, true, false, false);
        emit IUniswapV3PoolEvents.Swap(
            address(universalRouter),
            address(migrator),
            0,
            int256(amount1 - 1),
            3354541111262869343027788,
            1836257047182020178,
            -201406
        );

        // bridge
        vm.expectEmit(true, false, false, false);
        emit V3SpokePoolInterface.FundsDeposited(
            bytes32(uint256(uint160(token0))),
            bytes32(uint256(uint160(token0))),
            79,
            0,
            destinationChainId,
            1,
            uint32(block.timestamp),
            uint32(block.timestamp + 3000),
            0,
            bytes32(bytes20(user)),
            bytes32(bytes20(user)),
            bytes32(0),
            ""
        );

        vm.expectEmit(false, false, false, false);
        emit IMigrator.MigrationStarted(
            bytes32(0), tokenId, destinationChainId, address(settler), MigrationModes.SINGLE, user, token0, 0
        );
        vm.prank(user);
        INonfungiblePositionManager(v3PositionManager).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(migrationParams)
        );

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log memory swapEvent = findSwapEvent(entries);
        uint256 swapOutAmount = parseSwapEvent(swapEvent.data);
        Vm.Log memory fundsDepositedEvent = AcrossHelpers.findFundsDepositedEvent(entries);

        (bytes32 inputToken, bytes32 outputToken, uint256 inputAmount, uint256 outputAmount) =
            AcrossHelpers.parseFundsDepositedEvent(fundsDepositedEvent.data);
        assertEq(inputToken, bytes32(uint256(uint160(token0))));
        assertEq(outputToken, bytes32(uint256(uint160(weth))));
        assertEq(inputAmount, amount0 + swapOutAmount - 1); // -1 for rounding error
        assertEq(outputAmount, amount0 + swapOutAmount - 1 - maxFees); // -1 for rounding error
    }

    function test_onERC721Received_Token0WETHBaseToken_BelowTickLower() public {}

    function test_onERC721Received_Token0WETHBaseToken_AboveTickUpper() public {}

    function test_onERC721Received_Token1WETHBaseToken_InRange() public {}

    function test_onERC721Received_Token1WETHBaseToken_BelowTickLower() public {}

    function test_onERC721Received_Token1WETHBaseToken_AboveTickUpper() public {}

    function test_onERC721Received_Token0USDCBaseToken_NoWETH_InRange() public {}

    function test_onERC721Received_Token0USDCBaseToken_NoWETH_BelowTickLower() public {}

    function test_onERC721Received_Token0USDCBaseToken_NoWETH_AboveTickUpper() public {}

    /**
     * DUAL TOKEN PATHS ***
     */
    function test_onERC721Received_Token0WETHBaseToken_Token1USDCBaseToken_InRange() public {}

    function test() public override(TestContext, UniswapV3Helpers) {}
}
