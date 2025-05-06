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
import {MigrationData} from "../src/types/MigrationData.sol";

contract UniswapV3AcrossMigratorTest is TestContext, UniswapV3Helpers {
    string public constant SRC_CHAIN_NAME = "BASE";
    string public constant DEST_CHAIN_NAME = "UNICHAIN";
    address public settler = address(123);
    uint256 public maxFees = 10_000_000;
    UniswapV3AcrossMigrator public migrator;
    uint256 public sourceChainId = 8453;
    uint256 public destinationChainId = 130;

    function setUp() public {
        _loadChain(SRC_CHAIN_NAME, DEST_CHAIN_NAME);

        vm.prank(owner);
        migrator = new UniswapV3AcrossMigrator(
            owner,
            address(v3PositionManager),
            address(universalRouter),
            address(permit2),
            address(acrossSpokePool),
            weth
        );
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
    - usdt/weth (token0: usdt and token1: weth/basetoken)
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
        // current tick is ~ -201000
        (uint256 tokenId, uint256 amount0,) =
            mintV3Position(address(v3PositionManager), user, token0, token1, -250000, -100000, 500);

        // verify posToken0 is baseToken
        (,, address posToken0,,,,,,,,,) = v3PositionManager.positions(tokenId);
        assertEq(posToken0, token0);

        IMigrator.MigrationParams memory migrationParams =
            MigrationHelpers.generateMigrationParams(token0, address(settler), amount0 - maxFees);

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 migrationHash = migrationData.toHash();
        bytes memory data = abi.encode(migrationHash, migrationData);

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
        emit IUniswapV3PoolEvents.Swap(address(universalRouter), address(migrator), 0, 0, 0, 0, 0);

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

        vm.expectEmit(true, true, true, false);
        emit IMigrator.MigrationStarted(
            migrationHash, tokenId, destinationChainId, address(settler), MigrationModes.SINGLE, user, token0, 0
        );
        vm.prank(user);
        v3PositionManager.safeTransferFrom(user, address(migrator), tokenId, abi.encode(migrationParams));

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log[] memory swapEvents = findSwapEvents(entries);
        uint256 swapOutAmount = parseSwapEvent(swapEvents[0].data);
        Vm.Log memory fundsDepositedEvent = AcrossHelpers.findFundsDepositedEvent(entries);

        (bytes32 inputToken, bytes32 outputToken, uint256 inputAmount, uint256 outputAmount, bytes memory message) =
            AcrossHelpers.parseFundsDepositedEvent(fundsDepositedEvent.data);
        assertEq(inputToken, bytes32(uint256(uint160(token0))));
        assertEq(outputToken, bytes32(uint256(uint160(weth))));
        assertEq(inputAmount, amount0 + swapOutAmount - 1); // -1 for rounding error
        assertEq(outputAmount, amount0 + swapOutAmount - 1 - maxFees); // -1 for rounding error
        assertEq(message, data);
    }

    function test_onERC721Received_Token0WETHBaseToken_BelowTickLower() public {
        vm.recordLogs();
        address token0 = weth;
        address token1 = usdc;
        // current tick is ~ -201000

        (uint256 tokenId, uint256 amount0,) =
            mintV3Position(address(v3PositionManager), user, token0, token1, -250000, -210000, 500);
        // only token1 is used

        // verify posToken0 is baseToken
        (,, address posToken0,,,,,,,,,) = v3PositionManager.positions(tokenId);
        assertEq(posToken0, token0);

        IMigrator.MigrationParams memory migrationParams =
            MigrationHelpers.generateMigrationParams(token0, address(settler), maxFees);

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 migrationHash = migrationData.toHash();
        bytes memory data = abi.encode(migrationHash, migrationData);

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
        emit IUniswapV3PoolEvents.Swap(address(universalRouter), address(migrator), 0, 0, 0, 0, 0);

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

        vm.expectEmit(false, true, true, false);
        emit IMigrator.MigrationStarted(
            bytes32(0), tokenId, destinationChainId, address(settler), MigrationModes.SINGLE, user, token0, 0
        );
        vm.prank(user);
        v3PositionManager.safeTransferFrom(user, address(migrator), tokenId, abi.encode(migrationParams));

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log[] memory swapEvents = findSwapEvents(entries);
        uint256 swapOutAmount = parseSwapEvent(swapEvents[0].data);
        Vm.Log memory fundsDepositedEvent = AcrossHelpers.findFundsDepositedEvent(entries);

        (bytes32 inputToken, bytes32 outputToken, uint256 inputAmount, uint256 outputAmount, bytes memory message) =
            AcrossHelpers.parseFundsDepositedEvent(fundsDepositedEvent.data);
        assertEq(inputToken, bytes32(uint256(uint160(token0))));
        assertEq(outputToken, bytes32(uint256(uint160(weth))));
        assertEq(inputAmount, amount0 + swapOutAmount);
        assertEq(outputAmount, amount0 + swapOutAmount - maxFees);
        assertEq(message, data);
    }

    function test_onERC721Received_Token0WETHBaseToken_AboveTickUpper() public {
        vm.recordLogs();
        address token0 = weth;
        address token1 = usdc;
        // current tick is ~ -201000
        (uint256 tokenId, uint256 amount0,) =
            mintV3Position(address(v3PositionManager), user, token0, token1, -150000, -100000, 500);

        // only token0 is used, so no swap is needed

        // verify posToken0 is baseToken
        (,, address posToken0,,,,,,,,,) = v3PositionManager.positions(tokenId);
        assertEq(posToken0, token0);

        IMigrator.MigrationParams memory migrationParams =
            MigrationHelpers.generateMigrationParams(token0, address(settler), amount0 - maxFees - 1);

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 migrationHash = migrationData.toHash();
        bytes memory data = abi.encode(migrationHash, migrationData);

        // Transfer Position from user to migrator
        vm.expectEmit(true, true, false, false, address(v3PositionManager));
        emit IERC721.Transfer(user, address(migrator), tokenId);

        // Burn
        vm.expectEmit(true, false, false, false, address(v3PositionManager));
        emit INonfungiblePositionManager.DecreaseLiquidity(tokenId, 0, 0, 0);

        // collect
        vm.expectEmit(true, false, false, false, address(v3PositionManager));
        emit INonfungiblePositionManager.Collect(tokenId, address(0), 0, 0);

        // swap
        // not needed

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

        vm.expectEmit(false, true, true, false);
        emit IMigrator.MigrationStarted(
            bytes32(0), tokenId, destinationChainId, address(settler), MigrationModes.SINGLE, user, token0, 0
        );
        vm.prank(user);
        v3PositionManager.safeTransferFrom(user, address(migrator), tokenId, abi.encode(migrationParams));

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 swapOutAmount = 0;
        Vm.Log memory fundsDepositedEvent = AcrossHelpers.findFundsDepositedEvent(entries);

        (bytes32 inputToken, bytes32 outputToken, uint256 inputAmount, uint256 outputAmount, bytes memory message) =
            AcrossHelpers.parseFundsDepositedEvent(fundsDepositedEvent.data);
        assertEq(inputToken, bytes32(uint256(uint160(token0))));
        assertEq(outputToken, bytes32(uint256(uint160(weth))));
        assertEq(inputAmount, amount0 + swapOutAmount - 1); // -1 for rounding error
        assertEq(outputAmount, amount0 + swapOutAmount - 1 - maxFees); // -1 for rounding error
        assertEq(message, data);
    }

    function test_onERC721Received_Token1WETHBaseToken_InRange() public {
        vm.recordLogs();
        address token0 = virtualToken;
        address token1 = weth;
        (uint256 tokenId,, uint256 amount1) =
            mintV3Position(address(v3PositionManager), user, token0, token1, -200000, -5000, 500);

        // verify posToken0 is baseToken
        (,,, address posToken1,,,,,,,,) = v3PositionManager.positions(tokenId);
        assertEq(posToken1, token1);

        IMigrator.MigrationParams memory migrationParams =
            MigrationHelpers.generateMigrationParams(token1, address(settler), amount1 - maxFees - 1);

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 migrationHash = migrationData.toHash();
        bytes memory data = abi.encode(migrationHash, migrationData);

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
        emit IUniswapV3PoolEvents.Swap(address(universalRouter), address(migrator), 0, 0, 0, 0, 0);

        // bridge
        vm.expectEmit(true, false, false, false);
        emit V3SpokePoolInterface.FundsDeposited(
            bytes32(uint256(uint160(token0))),
            bytes32(uint256(uint160(token0))),
            0,
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

        vm.expectEmit(false, true, true, false);
        emit IMigrator.MigrationStarted(
            bytes32(0), tokenId, destinationChainId, address(settler), MigrationModes.SINGLE, user, token1, 0
        );
        vm.prank(user);
        v3PositionManager.safeTransferFrom(user, address(migrator), tokenId, abi.encode(migrationParams));

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log[] memory swapEvents = findSwapEvents(entries);
        uint256 swapOutAmount = parseSwapEvent(swapEvents[0].data);
        Vm.Log memory fundsDepositedEvent = AcrossHelpers.findFundsDepositedEvent(entries);

        (bytes32 inputToken, bytes32 outputToken, uint256 inputAmount, uint256 outputAmount, bytes memory message) =
            AcrossHelpers.parseFundsDepositedEvent(fundsDepositedEvent.data);
        assertEq(inputToken, bytes32(uint256(uint160(token1))));
        assertEq(outputToken, bytes32(uint256(uint160(weth))));
        assertEq(inputAmount, amount1 + swapOutAmount - 1); // -1 for rounding error
        assertEq(outputAmount, amount1 + swapOutAmount - 1 - maxFees); // -1 for rounding error
        assertEq(message, data);
    }

    function test_onERC721Received_Token1WETHBaseToken_BelowTickLower() public {
        vm.recordLogs();
        address token0 = virtualToken;
        address token1 = weth;
        (uint256 tokenId,, uint256 amount1) =
            mintV3Position(address(v3PositionManager), user, token0, token1, -200000, -100000, 500);

        // only token1 is used; no swap is needed

        // verify posToken0 is baseToken
        (,,, address posToken1,,,,,,,,) = v3PositionManager.positions(tokenId);
        assertEq(posToken1, token1);

        IMigrator.MigrationParams memory migrationParams =
            MigrationHelpers.generateMigrationParams(token1, address(settler), amount1 - maxFees - 1);

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 migrationHash = migrationData.toHash();
        bytes memory data = abi.encode(migrationHash, migrationData);

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
        // not needed

        // bridge
        vm.expectEmit(true, false, false, false);
        emit V3SpokePoolInterface.FundsDeposited(
            bytes32(uint256(uint160(token0))),
            bytes32(uint256(uint160(token0))),
            0,
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

        vm.expectEmit(false, true, true, false);
        emit IMigrator.MigrationStarted(
            bytes32(0), tokenId, destinationChainId, address(settler), MigrationModes.SINGLE, user, token1, 0
        );
        vm.prank(user);
        v3PositionManager.safeTransferFrom(user, address(migrator), tokenId, abi.encode(migrationParams));

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 swapOutAmount = 0;
        Vm.Log memory fundsDepositedEvent = AcrossHelpers.findFundsDepositedEvent(entries);

        (bytes32 inputToken, bytes32 outputToken, uint256 inputAmount, uint256 outputAmount, bytes memory message) =
            AcrossHelpers.parseFundsDepositedEvent(fundsDepositedEvent.data);
        assertEq(inputToken, bytes32(uint256(uint160(token1))));
        assertEq(outputToken, bytes32(uint256(uint160(weth))));
        assertEq(inputAmount, amount1 + swapOutAmount - 1); // -1 for rounding error
        assertEq(outputAmount, amount1 + swapOutAmount - 1 - maxFees); // -1 for rounding error
        assertEq(message, data);
    }

    function test_onERC721Received_Token1WETHBaseToken_AboveTickUpper() public {
        vm.recordLogs();
        address token0 = virtualToken;
        address token1 = weth;
        (uint256 tokenId,, uint256 amount1) =
            mintV3Position(address(v3PositionManager), user, token0, token1, -200000, -5000, 500);

        // only token0 is used

        // verify posToken0 is baseToken
        (,,, address posToken1,,,,,,,,) = v3PositionManager.positions(tokenId);
        assertEq(posToken1, token1);

        IMigrator.MigrationParams memory migrationParams =
            MigrationHelpers.generateMigrationParams(token1, address(settler), amount1 - maxFees - 1);

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 migrationHash = migrationData.toHash();
        bytes memory data = abi.encode(migrationHash, migrationData);

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
        emit IUniswapV3PoolEvents.Swap(address(universalRouter), address(migrator), 0, 0, 0, 0, 0);

        // bridge
        vm.expectEmit(true, false, false, false);
        emit V3SpokePoolInterface.FundsDeposited(
            bytes32(uint256(uint160(token0))),
            bytes32(uint256(uint160(token0))),
            0,
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

        vm.expectEmit(false, true, true, false);
        emit IMigrator.MigrationStarted(
            bytes32(0), tokenId, destinationChainId, address(settler), MigrationModes.SINGLE, user, token1, 0
        );
        vm.prank(user);
        v3PositionManager.safeTransferFrom(user, address(migrator), tokenId, abi.encode(migrationParams));

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log[] memory swapEvents = findSwapEvents(entries);
        uint256 swapOutAmount = parseSwapEvent(swapEvents[0].data);
        Vm.Log memory fundsDepositedEvent = AcrossHelpers.findFundsDepositedEvent(entries);

        (bytes32 inputToken, bytes32 outputToken, uint256 inputAmount, uint256 outputAmount, bytes memory message) =
            AcrossHelpers.parseFundsDepositedEvent(fundsDepositedEvent.data);
        assertEq(inputToken, bytes32(uint256(uint160(token1))));
        assertEq(outputToken, bytes32(uint256(uint160(weth))));
        assertEq(inputAmount, amount1 + swapOutAmount - 1); // -1 for rounding error
        assertEq(outputAmount, amount1 + swapOutAmount - 1 - maxFees); // -1 for rounding error
        assertEq(message, data);
    }

    function test_onERC721Received_Token0USDCBaseToken_NoWETH_InRange() public {
        vm.recordLogs();
        address token0 = usdc;
        address token1 = usdt;
        // current tick is ~ -201000
        (uint256 tokenId, uint256 amount0,) =
            mintV3Position(address(v3PositionManager), user, token0, token1, -5000, 5000, 100);

        // verify posToken0 is baseToken
        (,, address posToken0,,,,,,,,,) = v3PositionManager.positions(tokenId);
        assertEq(posToken0, token0);

        IMigrator.MigrationParams memory migrationParams =
            MigrationHelpers.generateMigrationParams(token0, destChainUsdc, amount0 - maxFees - 1, address(settler));

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 migrationHash = migrationData.toHash();
        bytes memory data = abi.encode(migrationHash, migrationData);

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
        emit IUniswapV3PoolEvents.Swap(address(universalRouter), address(migrator), 0, 0, 0, 0, 0);

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

        vm.expectEmit(false, true, true, false);
        emit IMigrator.MigrationStarted(
            bytes32(0), tokenId, destinationChainId, address(settler), MigrationModes.SINGLE, user, token0, 0
        );
        vm.prank(user);
        v3PositionManager.safeTransferFrom(user, address(migrator), tokenId, abi.encode(migrationParams));

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log[] memory swapEvents = findSwapEvents(entries);
        uint256 swapOutAmount = parseSwapEvent(swapEvents[0].data);
        Vm.Log memory fundsDepositedEvent = AcrossHelpers.findFundsDepositedEvent(entries);

        (bytes32 inputToken, bytes32 outputToken, uint256 inputAmount, uint256 outputAmount, bytes memory message) =
            AcrossHelpers.parseFundsDepositedEvent(fundsDepositedEvent.data);
        assertEq(inputToken, bytes32(uint256(uint160(token0))));
        assertEq(outputToken, bytes32(uint256(uint160(destChainUsdc))));
        assertEq(inputAmount, amount0 + swapOutAmount - 1);
        assertEq(outputAmount, amount0 + swapOutAmount - 1 - maxFees);
        assertEq(message, data);
    }

    function test_onERC721Received_Token0USDCBaseToken_NoWETH_BelowTickLower() public {
        vm.recordLogs();
        address token0 = usdc;
        address token1 = usdt;
        // current tick is ~ -201000
        (uint256 tokenId, uint256 amount0,) =
            mintV3Position(address(v3PositionManager), user, token0, token1, -1000, -100, 100);

        // only token1 is used

        // verify posToken0 is baseToken
        (,, address posToken0,,,,,,,,,) = v3PositionManager.positions(tokenId);
        assertEq(posToken0, token0);

        IMigrator.MigrationParams memory migrationParams =
            MigrationHelpers.generateMigrationParams(token0, destChainUsdc, maxFees, address(settler));

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 migrationHash = migrationData.toHash();
        bytes memory data = abi.encode(migrationHash, migrationData);

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
        emit IUniswapV3PoolEvents.Swap(address(universalRouter), address(migrator), 0, 0, 0, 0, 0);

        // bridge
        vm.expectEmit(true, false, false, false);
        emit V3SpokePoolInterface.FundsDeposited(
            bytes32(uint256(uint160(token0))),
            bytes32(uint256(uint160(token0))),
            0,
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

        vm.expectEmit(false, true, true, false);
        emit IMigrator.MigrationStarted(
            bytes32(0), tokenId, destinationChainId, address(settler), MigrationModes.SINGLE, user, token0, 0
        );
        vm.prank(user);
        v3PositionManager.safeTransferFrom(user, address(migrator), tokenId, abi.encode(migrationParams));

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log[] memory swapEvents = findSwapEvents(entries);
        uint256 swapOutAmount = parseSwapEvent(swapEvents[0].data);
        Vm.Log memory fundsDepositedEvent = AcrossHelpers.findFundsDepositedEvent(entries);

        (bytes32 inputToken, bytes32 outputToken, uint256 inputAmount, uint256 outputAmount, bytes memory message) =
            AcrossHelpers.parseFundsDepositedEvent(fundsDepositedEvent.data);
        assertEq(inputToken, bytes32(uint256(uint160(token0))));
        assertEq(outputToken, bytes32(uint256(uint160(destChainUsdc))));
        assertEq(inputAmount, amount0 + swapOutAmount);
        assertEq(outputAmount, amount0 + swapOutAmount - maxFees);
        assertEq(message, data);
    }

    function test_onERC721Received_Token0USDCBaseToken_NoWETH_AboveTickUpper() public {
        vm.recordLogs();
        address token0 = usdc;
        address token1 = usdt;
        // current tick is ~ -201000
        (uint256 tokenId, uint256 amount0,) =
            mintV3Position(address(v3PositionManager), user, token0, token1, 100, 500, 100);

        // only token0 is used; no swap is needed

        // verify posToken0 is baseToken
        (,, address posToken0,,,,,,,,,) = v3PositionManager.positions(tokenId);
        assertEq(posToken0, token0);

        IMigrator.MigrationParams memory migrationParams =
            MigrationHelpers.generateMigrationParams(token0, destChainUsdc, amount0 - maxFees - 1, address(settler));

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.SINGLE,
            routesData: "",
            settlementData: ""
        });
        bytes32 migrationHash = migrationData.toHash();
        bytes memory data = abi.encode(migrationHash, migrationData);

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
        // not needed

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

        vm.expectEmit(false, true, true, false);
        emit IMigrator.MigrationStarted(
            bytes32(0), tokenId, destinationChainId, address(settler), MigrationModes.SINGLE, user, token0, 0
        );
        vm.prank(user);
        v3PositionManager.safeTransferFrom(user, address(migrator), tokenId, abi.encode(migrationParams));

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 swapOutAmount = 0;
        Vm.Log memory fundsDepositedEvent = AcrossHelpers.findFundsDepositedEvent(entries);

        (bytes32 inputToken, bytes32 outputToken, uint256 inputAmount, uint256 outputAmount, bytes memory message) =
            AcrossHelpers.parseFundsDepositedEvent(fundsDepositedEvent.data);
        assertEq(inputToken, bytes32(uint256(uint160(token0))));
        assertEq(outputToken, bytes32(uint256(uint160(destChainUsdc))));
        assertEq(inputAmount, amount0 + swapOutAmount - 1);
        assertEq(outputAmount, amount0 + swapOutAmount - 1 - maxFees);
        assertEq(message, data);
    }

    /**
     * DUAL TOKEN PATHS ***
     */
    function test_onERC721Received_Token0WETHBaseToken_Token1USDCBaseToken_InRange() public {
        vm.recordLogs();
        address token0 = weth;
        address token1 = usdc;
        // current tick is ~ -201000
        (uint256 tokenId, uint256 amount0, uint256 amount1) =
            mintV3Position(address(v3PositionManager), user, token0, token1, -250000, -100000, 500);

        // verify posToken0 is baseToken
        (,, address posToken0, address posToken1,,,,,,,,) = v3PositionManager.positions(tokenId);
        assertEq(posToken0, token0);
        assertEq(posToken1, token1);

        IMigrator.MigrationParams memory migrationParams = MigrationHelpers.generateMigrationParams(
            token0, token1, token0, destChainUsdc, amount0 - maxFees - 1, amount1 - maxFees - 1, address(settler)
        );

        MigrationData memory migrationData = MigrationData({
            sourceChainId: block.chainid,
            migrator: address(migrator),
            nonce: 1,
            mode: MigrationModes.DUAL,
            routesData: abi.encode(token0, token1, amount0 - maxFees - 1, amount1 - maxFees - 1),
            settlementData: ""
        });
        bytes32 migrationHash = migrationData.toHash();
        bytes memory data = abi.encode(migrationHash, migrationData);

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
        // no swap as it's dual token path

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

        vm.expectEmit(true, false, false, false);
        emit V3SpokePoolInterface.FundsDeposited(
            bytes32(uint256(uint160(token1))),
            bytes32(uint256(uint160(destChainUsdc))),
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

        vm.expectEmit(false, true, true, false);
        emit IMigrator.MigrationStarted(
            bytes32(0), tokenId, destinationChainId, address(settler), MigrationModes.DUAL, user, token0, 0
        );
        vm.expectEmit(false, true, true, false);
        emit IMigrator.MigrationStarted(
            bytes32(0), tokenId, destinationChainId, address(settler), MigrationModes.DUAL, user, token1, 0
        );
        vm.prank(user);
        v3PositionManager.safeTransferFrom(user, address(migrator), tokenId, abi.encode(migrationParams));

        // verify diff between input and output amount is equal to maxFees
        Vm.Log[] memory entries = vm.getRecordedLogs();
        Vm.Log[] memory fundsDepositedEvents = AcrossHelpers.findFundsDepositedEvents(entries);

        (bytes32 inputToken0, bytes32 outputToken0, uint256 inputAmount0, uint256 outputAmount0, bytes memory message0)
        = AcrossHelpers.parseFundsDepositedEvent(fundsDepositedEvents[0].data);
        assertEq(inputToken0, bytes32(uint256(uint160(token0))));
        assertEq(outputToken0, bytes32(uint256(uint160(weth))));
        assertEq(inputAmount0, amount0 - 1); // -1 for rounding error
        assertEq(outputAmount0, amount0 - 1 - maxFees); // -1 for rounding error
        assertEq(message0, data);
        (bytes32 inputToken1, bytes32 outputToken1, uint256 inputAmount1, uint256 outputAmount1, bytes memory message1)
        = AcrossHelpers.parseFundsDepositedEvent(fundsDepositedEvents[1].data);
        assertEq(inputToken1, bytes32(uint256(uint160(token1))));
        assertEq(outputToken1, bytes32(uint256(uint160(destChainUsdc))));
        assertEq(inputAmount1, amount1 - 1); // -1 for rounding error
        assertEq(outputAmount1, amount1 - 1 - maxFees); // -1 for rounding error
        assertEq(message1, data);
    }

    function test() public override(TestContext, UniswapV3Helpers) {}
}
