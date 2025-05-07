// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console, Vm} from "lib/forge-std/src/Test.sol";
import {INonfungiblePositionManager} from "../../src/interfaces/external/INonfungiblePositionManager.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IStateView} from "@uniswap-v4-periphery/interfaces/IStateView.sol";
import {PoolKey} from "@uniswap-v4-core/types/PoolKey.sol";
import {PoolIdLibrary} from "@uniswap-v4-core/types/PoolId.sol";
import {Currency} from "@uniswap-v4-core/types/Currency.sol";
import {IPositionManager} from "@uniswap-v4-periphery/interfaces/IPositionManager.sol";
import {Actions} from "@uniswap-v4-periphery/libraries/Actions.sol";
import {IPermit2} from "@uniswap-permit2/interfaces/IPermit2.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {SqrtPriceMath} from "@uniswap-v4-core/libraries/SqrtPriceMath.sol";
import {TickMath} from "@uniswap-v4-core/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap-v4-core/interfaces/IPoolManager.sol";

contract UniswapV4Helpers is Test {
    using SafeERC20 for IERC20;

    function getCurrentTick(address stateViewAddr, PoolKey memory poolKey) public view returns (int24) {
        IStateView stateView = IStateView(stateViewAddr);
        (, int24 currentTick,,) = stateView.getSlot0(PoolIdLibrary.toId(poolKey));
        return currentTick;
    }

    // mint a big v4 position with WETH to populate the pool
    // this is needed as there aren't many WETH pools with liquidity; almost all native
    function mintBigV4PositionToPopulatePool(
        address nftPositionManager,
        address permit2,
        address user,
        PoolKey memory poolKey,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) public {
        uint256 amount0Desired = 1_000_000_000_000_000_000_000_000;
        uint256 amount1Desired = 10_000_000_000_000_000_000_000;
        // give user weth and usdc
        deal(Currency.unwrap(poolKey.currency0), address(this), amount0Desired);
        deal(Currency.unwrap(poolKey.currency1), address(this), amount1Desired);
        // handle permit2 approval
        IERC20(Currency.unwrap(poolKey.currency0)).forceApprove(address(permit2), type(uint256).max);
        IPermit2(permit2).approve(
            Currency.unwrap(poolKey.currency0),
            address(nftPositionManager),
            uint160(amount0Desired),
            uint48(block.timestamp + 10)
        );
        IERC20(Currency.unwrap(poolKey.currency1)).forceApprove(address(permit2), type(uint256).max);
        IPermit2(permit2).approve(
            Currency.unwrap(poolKey.currency1),
            address(nftPositionManager),
            uint160(amount1Desired),
            uint48(block.timestamp + 10)
        );

        // uint128 liquidity = 1_000_000_000_000_000;

        // mint v4 position
        bytes memory actions =
            abi.encodePacked(bytes1(uint8(Actions.MINT_POSITION)), bytes1(uint8(Actions.SETTLE_PAIR)));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(poolKey, tickLower, tickUpper, liquidity, amount0Desired, amount1Desired, user, "");
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);
        IPositionManager(nftPositionManager).modifyLiquidities{value: 0}(abi.encode(actions, params), block.timestamp);
    }

    // only works for an in-range position
    function getAmount0(
        address stateViewAddr,
        PoolKey memory poolKey,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) public view returns (uint256) {
        IStateView stateView = IStateView(stateViewAddr);
        (uint160 sqrtPriceX96,,,) = stateView.getSlot0(PoolIdLibrary.toId(poolKey));
        uint160 sqrtPriceX96Lower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceX96Upper = TickMath.getSqrtPriceAtTick(tickUpper);
        return SqrtPriceMath.getAmount0Delta(
            sqrtPriceX96Upper, sqrtPriceX96 > sqrtPriceX96Lower ? sqrtPriceX96 : sqrtPriceX96Lower, liquidity, true
        );
    }

    function findSwapEvents(Vm.Log[] memory logs) public view returns (Vm.Log[] memory) {
        bytes32 topic0 = keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)");
        Vm.Log[] memory swapEvents = new Vm.Log[](1); // only have one swap event

        for (uint256 i = 0; i < logs.length; i++) {
            // skip events emitted by this contract
            if (logs[i].topics[0] == topic0 && logs[i].emitter != address(this)) {
                swapEvents[0] = logs[i];
                return swapEvents;
            }
        }
        return new Vm.Log[](0);
    }

    function findModifyLiquidityEvent(Vm.Log[] memory logs) public view returns (Vm.Log memory) {
        bytes32 topic0 = keccak256("ModifyLiquidity(bytes32,address,int24,int24,int256,bytes32)");

        for (uint256 i = 0; i < logs.length; i++) {
            // skip events emitted by this contract
            if (logs[i].topics[0] == topic0 && logs[i].emitter != address(this)) {
                return logs[i];
            }
        }
        revert();
    }

    function parseModifyLiquidityEvent(bytes memory data)
        public
        pure
        returns (int24 tickLower, int24 tickUpper, uint256 liquidity)
    {
        (tickLower, tickUpper, liquidity) = abi.decode(data, (int24, int24, uint256));
    }

    function parseSwapEvent(bytes memory data) public pure returns (uint256) {
        (int128 outputAmount0, int128 outputAmount1) = abi.decode(data, (int128, int128));
        if (outputAmount0 < 0) {
            return uint256(uint128(outputAmount0 * -1));
        }
        return uint256(uint128(outputAmount1 * -1));
    }

    function parseSwapEventForBothAmounts(bytes memory data)
        public
        pure
        returns (uint256 amountIn, uint256 amountOut)
    {
        (int128 outputAmount0, int128 outputAmount1) = abi.decode(data, (int128, int128));
        // note that this swap event for for v4, where the signs are flipped
        // negative amount means amountIn
        if (outputAmount0 < 0) {
            amountOut = uint256(uint128(outputAmount1));
            amountIn = uint256(uint128(outputAmount0 * -1));
        } else {
            amountOut = uint256(uint128(outputAmount0));
            amountIn = uint256(uint128(outputAmount1 * -1));
        }
        return (amountIn, amountOut);
    }

    function findTransferToPoolEventsAfterModifyLiquidity(Vm.Log[] memory logs, address poolManager)
        public
        view
        returns (Vm.Log[] memory)
    {
        bytes32 topic0 = keccak256("Transfer(address,address,uint256)");
        bytes32 modifyLiquidityTopic0 = keccak256("ModifyLiquidity(bytes32,address,int24,int24,int256,bytes32)");
        // First count the number of matching events
        uint256 matchingEventsCount = 0;
        bool foundModifyLiquidity = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == modifyLiquidityTopic0 && logs[i].emitter != address(this)) {
                foundModifyLiquidity = true;
                continue;
            }
            if (
                foundModifyLiquidity && logs[i].topics[0] == topic0 && logs[i].emitter != address(this)
                    && logs[i].topics[2] == bytes32(uint256(uint160(poolManager)))
                    && logs[i].topics[1] != bytes32(uint256(uint160(address(0))))
            ) {
                matchingEventsCount++;
            }
        }

        // Create array of exact size needed
        Vm.Log[] memory transferEvents = new Vm.Log[](matchingEventsCount);
        uint256 transferEventsIndex = 0;
        foundModifyLiquidity = false;
        // Fill the array with matching events
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == modifyLiquidityTopic0 && logs[i].emitter != address(this)) {
                foundModifyLiquidity = true;
            }
            if (
                foundModifyLiquidity && logs[i].topics[0] == topic0 && logs[i].emitter != address(this)
                    && logs[i].topics[2] == bytes32(uint256(uint160(poolManager)))
                    && logs[i].topics[1] != bytes32(uint256(uint160(address(0))))
            ) {
                transferEvents[transferEventsIndex] = logs[i];
                transferEventsIndex++;
            }
        }
        return transferEvents;
    }

    function parseTransferToPoolManagerEvents(Vm.Log[] memory logs, PoolKey memory poolKey)
        public
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        for (uint256 i = 0; i < logs.length; i++) {
            uint256 amount = abi.decode(logs[i].data, (uint256));
            if (logs[i].emitter == Currency.unwrap(poolKey.currency0)) {
                amount0 += amount;
            } else if (logs[i].emitter == Currency.unwrap(poolKey.currency1)) {
                amount1 += amount;
            }
        }
        return (amount0, amount1);
    }

    // add this to be excluded from coverage report
    function test() public virtual {}
}
