# ChainHopper Protocol: Migrate Uniswap LP positions cross-chain

This project was generously funded via a [Uniswap Foundation Grant](https://x.com/UniswapFND). 

## Overview

ChainHopper migrates Uniswap v3 and v4 LP positions between different EVM chains with a single click.

To move a Uniswap LP position manually requires several steps. Let's say we are moving from Arbitrum to Unichain:
1. Burn position on Arbitrum (to collect all assets in the pool *and* fees)
2. Swap to a single token (like WETH)
3. Bridge WETH to Unichain
4. Swap back into the "other token" (like USDC)
5. Mint position

This assumes you have gas on Unichain, otherwise an extra step to procure gas token.

ChainHopper allows all of these steps to be combined in a single transaction, using Across Protocol as the bridge.

## Getting started

1. Integrate it directly in your products using our SDK: [ChainHopper SDK](https://github.com/meliopolis/chainhopper-sdk/)

2. A demo frontend coming soon!

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
- `AcrossSettler.sol`: Receives tokens from Across
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

## Audit Report

You can find the audit report in `docs/`.

## Usage

While you can access the contracts directly at the deployed addresses, we recommend starting with our SDK: [ChainHopper SDK](https://github.com/meliopolis/chainhopper-sdk).

## Testing

Tests are run against a hard fork of `Base`. You'll need to add `BASE_RPC_URL` to `.env`. 

```bash
cp .env.example .env
```

and update `BASE_RPC_URL`.

To run tests, you can use the following command:

```bash
forge test
```

This will run unit tests as well as full e2e tests for all major contracts.

## Deploying

Contracts are currently deployed on 5 chains: Mainnet, Unichain, Base, Optimism and Arbitrum. You can find the deployment addresses in either the `broadcast/` directory, in the [SDK](https://github.com/meliopolis/chainhopper-sdk/blob/main/src/chains.ts) or by running `bash_scripts/get_deployed_addresses.sh`. 

You can also deploy all the contracts directly via scripts in `bash_scripts/` or individually via `script/`. The scripts are setup to deploy via an EOA and then switch ownership to another address (like a SAFE).

## Future work

We are exploring additional bridges like Wormhole and Op Stack interop.

Additionally, we are also exploring if more of the calcs (like how much to swap on destination chain) can be done on-chain in Solidity.

## Comments/Questions

Feel free to open issues or DM me on [X](https://x.com/aseemsood_).