This repo contains contracts for migrating a Uniswap v3 LP position across chains.

## `AcrossV3Migrator`

This contract receives an V3 LP position on the source chain, burns it, and sends one (or two) tokens to the destination chain with parameters to mint a new LP position. 

## `AcrossV3Settler`

This contract receives one (or two tokens) on the destination chain. If it received only one token and it needs the other token (because position requires both tokens), swaps some of the first token to the second token. Then it creates an LP position and gives it to the recipient.

## `AcrossV4Migrator`

TODO - implement receiving a Uniswap v4 position

## `AcrossV4Settler`

TODO - implement creating a Uniswap v4 position

## Tests

To run tests, you can use the following command:

```bash
forge test
```

## Coverage 

Currently, the contracts have 100% coverage for the single-token path - meaning only one token is sent across chains. Dual-token path is implemented but not fully tested on the `AcrossV3Settler` contract.

```bash
forge coverage --ir-minimum
```

## Comments/Questions

Feel free to open issues or DM me on [X](https://x.com/aseemsood_).