# Option 4 Compliance Checklist

## Verifiable Randomness

- `IRandomnessCoordinator` abstracts a Chainlink VRF-style request and uses `uint256` request ids to match Chainlink VRF v2.5.
- `ChainlinkVRFCoordinatorAdapter` integrates Chainlink VRF v2.5 subscription requests through `VRFConsumerBaseV2Plus` and `VRFV2PlusClient`.
- `MockVRFCoordinator` supports asynchronous fulfillment and emits proof hashes.
- `ChainFateArena.rawFulfillRandomness` is callback-only and coordinator-restricted.
- Dice and raffle both store `vrfWord` and `proofHash`.
- Retry functions handle delayed randomness:
  - `retryDiceRandomness`
  - `retryRaffleRandomness`

## Game Implementations

- `Oracle Dice`
  - multiplier payout based on roll-under probability
  - player seed reveal mixed with VRF word
  - automatic settlement and payout on reveal

- `Epoch Raffle`
  - time-based ticket sales
  - VRF draw after close
  - reveal phase for committed seeds
  - finalization pays the winning ticket owner

## Betting and Treasury

- SepoliaETH/native test ETH betting through `address(0)`.
- ERC-20 betting through `MockERC20` FATE token.
- Configurable `minBet`, `maxBet`, and `houseEdgeBps`.
- Reserved accounting for:
  - dice payouts
  - reveal bonds
  - raffle pots
- Realized fees and slashed funds go to `treasuryBalance`.

## Anti-Cheating and Fairness

- Seed commitments are made before oracle fulfillment.
- Reveals are time-limited.
- Missing reveals are slashed.
- Stale callbacks are ignored after retries.
- The frontend displays proof hashes for fulfilled randomness.

## Testing

The suite includes unit, fuzz, and invariant-style tests:

- dice win/loss
- wrong seed rejection
- stalled randomness retry
- expired dice slashing
- raffle seed reveal and finalization
- unrevealed raffle bond slashing
- ERC-20 gameplay
- pause and owner controls
- fuzzed dice bounds
- fuzzed ticket accounting
- solvency invariant

## Bonus-Ready Extensions

The current platform can be extended with:

- NFT badges for winners
- ENS display names
- multiplayer turn-based games
- Chainlink VRF v2.5 adapter
- round caps and richer analytics dashboard
