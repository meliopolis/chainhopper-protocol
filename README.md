# Hopper Protocol: Migrate Uniswap LP positions cross-chain

## Overview

Hopper migrates Uniswap v3 and v4 LP positions between different EVM chains with a single click.

To move a Uniswap LP position manually from say Arbitrum to Unichain requires several steps:
1. Burn position on Arbitrum (to collect all assets in the pool and fees)
2. Swap to a single token (like WETH)
3. Bridge WETH to Unichain
4. Swap back into the "other token" (like USDC)
5. Mint position

This assumes you have gas on Unichain, otherwise an extra step to procure gas token.

Hopper allows all of these steps to be combined in a single transaction, using Across Protocol as the bridge.

## Core Components

### Migrators

Migrators are responsible for initiating the migration process. They:
- Receive the LP position token (the NFT)
- Swap one token for another (if needed)
- Send token(s) to the bridge with a message to construct LP position on destination chain

Key Migrator contracts:
- `Migrator.sol`: Abstract base contract for all migrators
- `AcrossMigrator.sol`: Base migrator implementation for Across Protocol
- `UniswapV3AcrossMigrator.sol`: Deployed migrator to receive Uniswap **v3** Positions
- `UniswapV4AcrossMigrator.sol`: Deployed migrator to receive Uniswap **v4** Positions

### Settlers

Settlers handle the receiving end of migrations. They:
- Process incoming tokens from a bridge
- Swap (if needed)
- Create new positions in specified protocols (e.g., Uniswap V3/V4)
- Handle fee calculations and distributions

Key Settler contracts:
- `Settler.sol`: Base contract with common settlement logic
- `AcrossV3Settler.sol`: Handles settlements into Uniswap V3 positions
- `AcrossV4Settler.sol`: Handles settlements into Uniswap V4 positions
- `UniswapV3AcrossSettler.sol`: Deployed settler to create Uniswap **v3** Positions
- `UniswapV4AcrossSettler.sol`: Deployed settler to create Uniswap **v4** Positions


## Key Features

- Support for both single and dual token migrations
  - Single token migration: swaps "other token" (like USDC) into WETH and migrates a single token between chains
  - Dual token migration: sends both tokens separately via a bridge and combines on other end. Note that this is only possible when both tokens are supported by Across.
- Support to mint a pool if it doesn't exist
- Native token (ETH) handling with automatic wrapping/unwrapping
- Fee management system with protocol and sender fees
  - support for fee-share with external Frontends/interfaces
- Partial settlement support for dual-token migrations
- Comprehensive migration ID system for tracking migrations

## Usage

Check `script/` for deployment instructions

## Testing

To run tests, you can use the following command:

```bash
forge test
```

## Coverage 

We strive for 100% test coverage. Foundry currently doesn't recognize test coverage for inline `assembly` calls in Solidity, thus our coverage for `MigrationId.sol` lags below our target (though the test cases fully cover it).

```bash
forge coverage --ir-minimum
```

## Future work

We plan to support:
- additional bridges
- additional DEXes

## Comments/Questions

Feel free to open issues or DM me on [X](https://x.com/aseemsood_).