# User Guide

## Wallet Setup

1. Add the local Anvil network or target testnet to MetaMask.
2. Put deployed addresses in `frontend/config.js`.
3. Connect the wallet from the dashboard.
4. Approve FATE before using ERC-20 gameplay.

The frontend labels the native test currency as `SepoliaETH`. It is still the EVM native token path (`address(0)`) in the contract, but the label makes clear that demos should use Sepolia or Anvil test funds, not mainnet ETH.

## Oracle Dice

1. Select SepoliaETH or FATE.
2. Enter wager, reveal bond, and roll-under target.
3. Submit `Commit Dice Bet`.
4. Fulfill the request through the Mock VRF panel during local demos.
5. Use the Reveal Center to reveal the saved seed.

Winning dice bets receive:

```text
quoted payout + reveal bond
```

Losing dice bets receive:

```text
reveal bond only
```

If the seed is not revealed before the deadline, the wager and bond are slashed.

## Epoch Raffle

1. Choose a round id.
2. Enter ticket count and reveal bond.
3. Submit `Buy Tickets`.
4. Draw the raffle after the close time.
5. Fulfill randomness.
6. Reveal saved seeds before the reveal deadline.
7. Finalize the raffle.

The winner receives the pot minus the configured house fee. Unrevealed entry bonds are slashed.

## Mock VRF Panel

For local demos only:

- enter a request id
- optionally enter a deterministic random word
- submit `Fulfill`

The contract stores the resulting proof hash on the dice bet or raffle round.

For Chainlink VRF deployments, do not use this panel. Chainlink fulfills requests asynchronously after the subscription accepts the request. Refresh the dashboard and reveal once the bet or round reports `ready true`.

## Reveal Seed Storage

The frontend stores generated reveal seeds in browser local storage. This is convenient for demos. For a real deployment, users should export or back up seeds because losing the seed means losing the reveal bond.
