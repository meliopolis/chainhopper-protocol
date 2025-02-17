// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {console} from "forge-std/console.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IHooks, IPositionManager, IPoolManager} from "../interfaces/external/IUniswapV4.sol";

type Currency is address;

type PoolId is bytes32;

struct PoolKey {
    Currency currency0;
    Currency currency1;
    uint24 fee;
    int24 tickSpacing;
    IHooks hooks;
}

using UniswapV4Library for PoolKey global;

library UniswapV4Library {
    function mintPosition(
        IPositionManager self,
        address token0,
        address token1,
        uint24 fee,
        int24 tickSpacing,
        address hooks,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        address recipient
    ) internal returns (uint256 positionId, uint128 liquidity, uint256 amount0, uint256 amount1) {
        // record balance before minting
        uint256 balance0 = token0 == address(0) ? address(this).balance : IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        // mint new position w/ deltas, let Uni handle the liquidity math
        bytes memory actions = abi.encodePacked(
            bytes1(uint8(Actions.SETTLE)),
            bytes1(uint8(Actions.SETTLE)),
            bytes1(uint8(Actions.MINT_POSITION_FROM_DELTAS)),
            bytes1(uint8(Actions.TAKE_PAIR))
        );
        bytes[] memory params = new bytes[](4);
        params[0] = abi.encode(Currency.wrap(token0), amount0Desired, true);
        params[1] = abi.encode(Currency.wrap(token1), amount1Desired, true);
        params[2] = abi.encode(
            PoolKey({
                currency0: Currency.wrap(token0),
                currency1: Currency.wrap(token1),
                fee: fee,
                tickSpacing: tickSpacing,
                hooks: IHooks(hooks)
            }),
            tickLower,
            tickUpper,
            amount0Desired,
            amount1Desired,
            recipient,
            bytes("")
        );
        params[3] = abi.encode(Currency.wrap(token0), Currency.wrap(token1), address(this));

        positionId = self.nextTokenId();
        try self.modifyLiquidities{value: token0 == address(0) ? amount0Desired : 0}(
            abi.encode(actions, params), block.timestamp
        ) {
            liquidity = self.getPositionLiquidity(positionId);
            // amounts used
            amount0 =
                balance0 - (token0 == address(0) ? address(this).balance : IERC20(token0).balanceOf(address(this)));
            amount1 = balance1 - IERC20(token1).balanceOf(address(this));
        } catch {
            positionId = 0;
        }
    }

    function toId(PoolKey memory poolKey) internal pure returns (PoolId poolId) {
        assembly ("memory-safe") {
            // 0xa0 represents the total size of the poolKey struct (5 slots of 32 bytes)
            poolId := keccak256(poolKey, 0xa0)
        }
    }
}

library Actions {
    uint256 internal constant SETTLE = 0x0b;
    uint256 internal constant SWAP_EXACT_IN_SINGLE = 0x06;
    uint256 internal constant MINT_POSITION_FROM_DELTAS = 0x05;
    uint256 internal constant SETTLE_ALL = 0x0c;
    uint256 internal constant TAKE_ALL = 0x0f;
    uint256 internal constant TAKE_PAIR = 0x11;
}

library StateLibrary {
    bytes32 public constant POOLS_SLOT = bytes32(uint256(6));
    uint256 public constant LIQUIDITY_OFFSET = 3;

    function getLiquidity(IPoolManager manager, PoolId poolId) internal view returns (uint128 liquidity) {
        // slot key of Pool.State value: `pools[poolId]`
        bytes32 stateSlot = _getPoolStateSlot(poolId);

        // Pool.State: `uint128 liquidity`
        bytes32 slot = bytes32(uint256(stateSlot) + LIQUIDITY_OFFSET);

        liquidity = uint128(uint256(manager.extsload(slot)));
    }

    function getSlot0(IPoolManager manager, PoolId poolId)
        internal
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee)
    {
        // slot key of Pool.State value: `pools[poolId]`
        bytes32 stateSlot = _getPoolStateSlot(poolId);

        bytes32 data = manager.extsload(stateSlot);

        //   24 bits  |24bits|24bits      |24 bits|160 bits
        // 0x000000   |000bb8|000000      |ffff75 |0000000000000000fe3aa841ba359daa0ea9eff7
        // ---------- | fee  |protocolfee | tick  | sqrtPriceX96
        assembly ("memory-safe") {
            // bottom 160 bits of data
            sqrtPriceX96 := and(data, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            // next 24 bits of data
            tick := signextend(2, shr(160, data))
            // next 24 bits of data
            protocolFee := and(shr(184, data), 0xFFFFFF)
            // last 24 bits of data
            lpFee := and(shr(208, data), 0xFFFFFF)
        }
    }

    function _getPoolStateSlot(PoolId poolId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(PoolId.unwrap(poolId), POOLS_SLOT));
    }
}
