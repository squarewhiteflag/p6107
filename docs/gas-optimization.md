# Gas Optimization

## Implemented Choices

### Packed Integer Sizes

The contract uses smaller integer widths where values are naturally bounded:

- `uint64` for timestamps and `uint256` for Chainlink-compatible request ids
- `uint32` for ticket counts and winning tickets
- `uint128` for wagers, bonds, ticket prices, and pots
- `uint8` for dice roll thresholds

This reduces storage use for game records.

### Liability Buckets

Reserved funds are tracked per token in aggregate mappings. This avoids scanning active games when calculating available bankroll.

### Single Randomness Request Per Game Action

Dice and raffle draw flows request one random word and reuse it through settlement. There is no polling loop.

### Stale Callback No-Op

Stale callbacks return early rather than reverting. This keeps retry handling simple and avoids blocking the coordinator if an old request eventually arrives.

### Memory Config Reads

Token configuration is copied into memory where it is reused for payout and fee calculations.

## Gas-Sensitive Functions

- `commitDiceBet`: ERC-20 transfers and VRF request dominate.
- `revealDiceSeed`: payout transfer plus settlement state writes.
- `buyRaffleTickets`: entry write and accounting updates.
- `finalizeRaffle`: loops over all entries to slash unrevealed bonds and find the winning ticket.

## Measured Commands

```bash
forge test --gas-report
forge test -vv --gas-report
```

## Latest Gas Report

Measured after the OpenZeppelin migration with `forge test -vv --gas-report`.

| Operation | Average Gas | Notes |
| --- | ---: | --- |
| `commitDiceBet` | 280,909 | Includes payment collection and mock randomness request. |
| `revealDiceSeed` | 61,455 | Includes settlement, accounting, and payout/refund. |
| `buyRaffleTickets` | 218,532 | Includes payment, entry write, and liability reservation. |
| `drawRaffle` | 123,365 | Includes guarded coordinator request. |
| `revealRaffleSeed` | 77,891 | Includes aggregate seed update and bond refund. |
| `finalizeRaffle` | 103,137 | Current tests use small rounds; production should cap round size. |

`forge snapshot --snap .gas-snapshot` currently triggers a Foundry macOS system proxy panic in this environment, so the reproducible gas evidence is the `forge test -vv --gas-report` output.

## Future Optimizations

- Add a maximum entries-per-round cap.
- Replace linear winner lookup with an indexed cumulative tree for large raffles.
- Split dice and raffle modules if code size becomes a constraint.
- Use unchecked increments in loops after bounds are formally justified.
- Replace local mock/demo code with production dependencies only in deployment builds.
