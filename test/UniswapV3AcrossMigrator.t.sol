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
import {MigrationId, MigrationIdLibrary} from "../src/types/MigrationId.sol";
import {MigrationModes, MigrationMode} from "../src/types/MigrationMode.sol";
import {AcrossHelpers} from "./utils/AcrossHelpers.sol";

contract UniswapV3AcrossMigratorTest is TestContext, UniswapV3Helpers, AcrossHelpers {
    string public constant CHAIN_NAME = "BASE";
    address public settler = address(123);
    uint256 public maxFees = 10_000_000;
    UniswapV3AcrossMigrator public migrator;

    function setUp() public {
        _loadChain(CHAIN_NAME);

        vm.prank(owner);
        migrator =
            new UniswapV3AcrossMigrator(owner, v3PositionManager, universalRouter, permit2, acrossSpokePool, weth);
        // update chainSettler
        vm.prank(owner);
        uint32[] memory chainIds = new uint32[](1);
        chainIds[0] = uint32(130);
        address[] memory settlers = new address[](1);
        settlers[0] = address(settler);
        bool[] memory values = new bool[](1);
        values[0] = true;
        migrator.setChainSettlers(chainIds, settlers, values);
    }

    function generateMigrationParams() public view returns (IMigrator.MigrationParams memory) {
        ISettler.SettlementParams memory settlementParams = ISettler.SettlementParams({
            recipient: user,
            senderShareBps: 0,
            senderFeeRecipient: address(0),
            mintParams: abi.encode(
                IUniswapV3Settler.MintParams({
                    token0: address(weth),
                    token1: address(usdc),
                    fee: 500,
                    sqrtPriceX96: 0,
                    tickLower: -250000,
                    tickUpper: -100000,
                    swapAmountInMilliBps: 0,
                    amount0Min: 0,
                    amount1Min: 0
                })
            )
        });
        IAcrossMigrator.Route memory route = IAcrossMigrator.Route({
            outputToken: address(weth),
            maxFees: maxFees,
            quoteTimestamp: uint32(block.timestamp),
            fillDeadlineOffset: 21600,
            exclusiveRelayer: address(0),
            exclusivityDeadline: 0
        });
        IMigrator.TokenRoute memory tokenRoute =
            IMigrator.TokenRoute({token: address(weth), amountOutMin: 0, route: abi.encode(route)});
        IMigrator.TokenRoute[] memory tokenRoutes = new IMigrator.TokenRoute[](1);
        tokenRoutes[0] = tokenRoute;
        return IMigrator.MigrationParams({
            chainId: 130,
            settler: settler,
            tokenRoutes: tokenRoutes,
            settlementParams: abi.encode(settlementParams)
        });
    }

    /*
    TokenPairs to include in tests:
    - weth/usdc (token0: weth and basetoken)
    - usdc/weth (token1: weth and basetoken)
    - usdc/usdt (non-weth base token)

    Ranges to include in tests:
    - below tickLower
    - between tickLower and tickUpper
    - above tickUpper

    Paths to include in tests:
    - Single token path
    - Dual token path (only applicable to both tokens being base tokens and in range)
    */

    /**
     * SINGLE TOKEN PATHS ***
     */
    function test_onERC721Received_Token0BaseToken_InRange() public {
        vm.recordLogs();
        address token0 = weth;
        address token1 = usdc;
        uint256 tokenId = mintV3Position(v3PositionManager, user, token0, token1, -250000, -100000, 500);
        // verify posToken0 is baseToken
        (,, address posToken0,,,,,,,,,) = INonfungiblePositionManager(v3PositionManager).positions(tokenId);
        assertEq(posToken0, token0);

        // Transfer Position from user to migrator
        vm.expectEmit(false, false, false, false);
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false);
        emit INonfungiblePositionManager.DecreaseLiquidity(tokenId, 0, 0, 0);

        // collect
        vm.expectEmit(true, false, false, false);
        emit INonfungiblePositionManager.Collect(tokenId, address(0), 0, 0);

        // Swap
        vm.expectEmit(true, true, false, false);
        emit IUniswapV3PoolEvents.Swap(address(universalRouter), address(migrator), 0, 1, 0, 0, 0);

        // bridge
        vm.expectEmit(true, true, false, false, address(token0));
        emit IERC20.Approval(address(migrator), acrossSpokePool, 0);
        vm.expectEmit(true, false, false, false);
        emit V3SpokePoolInterface.FundsDeposited(
            bytes32(bytes20(token0)),
            bytes32(bytes20(token1)),
            0,
            0,
            130,
            1,
            1737578897,
            1737578997,
            0,
            bytes32(bytes20(user)),
            bytes32(bytes20(user)),
            bytes32(0),
            ""
        );

        MigrationId id = MigrationIdLibrary.from(8453, address(migrator), MigrationModes.SINGLE, 0);
        vm.expectEmit(false, false, false, false);
        emit IMigrator.MigrationStarted(id, tokenId, weth, user, 0);

        vm.prank(user);
        INonfungiblePositionManager(v3PositionManager).safeTransferFrom(
            user, address(migrator), tokenId, abi.encode(generateMigrationParams())
        );

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log memory fundsDepositedEvent = findFundsDepositedEvent(entries);
        (bytes32 inputToken, bytes32 outputToken, uint256 inputAmount, uint256 outputAmount) =
            parseFundsDepositedEvent(fundsDepositedEvent.data);
        assertEq(inputToken, bytes32(uint256(uint160(token0))));
        assertEq(outputToken, bytes32(uint256(uint160(weth))));
        assertEq(inputAmount - outputAmount, maxFees);
    }

    function test_onERC721Received_Token0BaseToken_BelowTickLower() public {}

    function test_onERC721Received_Token0BaseToken_AboveTickUpper() public {}

    function test_onERC721Received_Token1BaseToken_InRange() public {}

    function test_onERC721Received_Token1BaseToken_BelowTickLower() public {}

    function test_onERC721Received_Token1BaseToken_AboveTickUpper() public {}

    /**
     * DUAL TOKEN PATHS ***
     */
    function test_onERC721Received_BothTokensBaseTokens_InRange() public {}

    function test() public override(TestContext, UniswapV3Helpers) {}
}
