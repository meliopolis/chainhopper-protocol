This repo contains contracts for migrating a Uniswap v3 LP position across chains.


## `LPMigratorSingleToken`

On Source chain: This contract receives an LP position, unwraps it, converts it to ETH, and sends it to the bridge.
On Destination chain: This contract receives ETH, converts it to the necessary tokens for specified LP position, and wraps it into an LP position.


## `LPMigratorDualToken`

This contract won't convert to ETH and will attempt to send both tokens via a bridge and combine them on other side.

Note: Limited to native tokens on both chains.