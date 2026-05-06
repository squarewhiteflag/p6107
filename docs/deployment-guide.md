# Deployment Guide

## Local Anvil Deployment

Start a local chain:

```bash
anvil
```

Deploy:

```bash
forge script script/DeployChainFateArena.s.sol:DeployChainFateArena \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast
```

The script deploys:

- `MockVRFCoordinator`
- `ChainFateArena`
- `MockERC20` as `FATE`
- one SepoliaETH/native test ETH raffle round
- one FATE raffle round
- initial bankroll liquidity for both tokens

## Frontend Configuration

Edit `frontend/config.js`:

```js
window.CHAIN_FATE_CONFIG = {
  arenaAddress: "0x...",
  coordinatorAddress: "0x...",
  fateTokenAddress: "0x...",
  defaultRoundIds: [1, 2]
};
```

Install and run the Vite/React frontend:

```bash
npm --prefix frontend install
npm --prefix frontend run dev
```

Open:

```text
http://127.0.0.1:8014/
```

## Sepolia or Other EVM Testnet

For a public testnet, prefer the Chainlink VRF v2.5 adapter path:

- create and fund a Chainlink VRF v2.5 subscription
- deploy `ChainlinkVRFCoordinatorAdapter`
- deploy `ChainFateArena` with the adapter address
- call `adapter.setConsumer(arena, true)` or use the provided deployment script
- add the adapter address as a consumer in the Chainlink VRF subscription manager
- seed the game bankroll with SepoliaETH/native test ETH or a demo ERC-20
- update `frontend/config.js` with deployed addresses

Use a secure private key flow:

```bash
PRIVATE_KEY=0x... \
VRF_SUBSCRIPTION_ID=123 \
forge script script/DeployChainlinkVRFChainFateArena.s.sol:DeployChainlinkVRFChainFateArena \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --broadcast \
  --verify
```

Optional VRF environment variables:

```bash
VRF_COORDINATOR=0x...              # defaults to Sepolia coordinator
VRF_KEY_HASH=0x...                 # defaults to Sepolia gas lane from Chainlink docs
VRF_CALLBACK_GAS_LIMIT=500000
VRF_REQUEST_CONFIRMATIONS=3
VRF_NATIVE_PAYMENT=0               # 0 = LINK balance, 1 = native token balance
INITIAL_ETH_BANKROLL=100000000000000000
INITIAL_FATE_BANKROLL=10000000000000000000000
```

Do not use the hardcoded Anvil private key outside local demos.

For real Chainlink deployments, the frontend's `Mock VRF` fulfill panel is not used. Chainlink fulfills asynchronously after the request is accepted and the subscription has enough balance.
