This repo contains contracts for migrating a Uniswap v3 LP position across chains.


## `SingleTokenV3V3Migrator`

On Source chain: This contract receives an LP position, unwraps it, converts it to ETH, and sends it to the bridge.

## `SingleTokenV3Settler`

On Destination chain: This contract receives ETH, converts it to the necessary tokens for specified LP position, and wraps it into an LP position.

## `DualTokenV3V3Migrator`

(Not ready yet) This contract receives an LP position, unwraps it and sends both tokens to the bridge.

## `DualTokenV3Settler`

(Not ready yet) This contract receives ETH and another token from the bridge, and attempts to create an LP position.

## Tests

To run tests, you can use the following command:

```bash
forge test
```
