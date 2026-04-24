# Security Analysis

## Threat Model

The platform holds ETH and ERC-20 funds, so the important threats are:

- unfair randomness or spoofed callbacks
- reentrancy during payouts
- owner withdrawal of active liabilities
- users manipulating reveal phases
- stalled oracle requests
- stale callback settlement after retries

## Implemented Controls

### Callback Restriction

`rawFulfillRandomness` is protected by `onlyCoordinator`, so arbitrary users cannot inject random words.

### Chainlink VRF v2.5 Adapter

`ChainlinkVRFCoordinatorAdapter` inherits Chainlink `VRFConsumerBaseV2Plus`, requests randomness with `VRFV2PlusClient`, and only receives fulfillment through Chainlink's verified `rawFulfillRandomWords` path. The adapter forwards one verified random word to the game contract through the existing `IRandomnessCoordinator` interface.

The adapter also uses an owner-controlled allowlist so arbitrary contracts cannot spend the VRF subscription through this adapter.

### Commit-Reveal

Players commit to `keccak256(player, seed)` before randomness is requested. After the coordinator callback, they reveal the seed. This prevents post-randomness seed selection.

### Time-Locked Reveals

Dice and raffle reveals have explicit deadlines:

- dice: `diceRevealPeriod`
- raffle: `raffleRevealPeriod`

After the deadline, unrevealed dice bets or raffle entries can be slashed.

### Bond Slashing

Reveal bonds make the commitment scheme economically meaningful. A player who refuses to reveal loses their bond.

### Stale Callback Protection

Each dice bet and raffle round stores its current request id. If an old request later fulfills after a retry, the contract ignores it.

### Reentrancy Guard

Functions that transfer funds use OpenZeppelin Contracts 5.x `ReentrancyGuard`. The randomness retry/draw paths are also guarded because they call an external coordinator.

### OpenZeppelin Security Primitives

The project now imports OpenZeppelin Contracts 5.x for `Ownable`, `Pausable`, `ReentrancyGuard`, `ERC20`, and `SafeERC20` instead of maintaining local copies of these primitives.

### Liability Reservation

The contract reserves active dice payouts, reveal bonds, and raffle pots. Treasury withdrawals only use realized `treasuryBalance`.

### Emergency Pause

The owner can pause new gameplay, retry, and draw actions while preserving reveal and finalization paths needed to settle existing games.

## Static Analysis

Executed command:

```bash
/Users/zhy/Library/Python/3.13/bin/slither . --exclude-dependencies
```

The current Slither pass reports no unresolved arithmetic, access-control bypass, or unguarded external-entry reentrancy issue in the game settlement paths. Remaining findings are documented in `docs/slither-report.md` and are either expected for this design or related to the local mock/oracle boundary.

## Known Limitations

- The local `MockVRFCoordinator` is still available for Anvil tests and demos, but the testnet/mainnet path should use `ChainlinkVRFCoordinatorAdapter`.
- Admin ownership is centralized.
- Raffle finalization is linear in the number of entries.
- The frontend stores reveal seeds in browser local storage. Users must keep backups for real deployments.
- The local mock coordinator is synchronous during fulfillment and should only be used for local demos/tests.

## Production Hardening

- For production, use `ChainlinkVRFCoordinatorAdapter` with a funded subscription and monitor request fulfillment.
- Move ownership to a multisig and add timelocks for parameter changes.
- Add per-round entry caps to bound raffle finalization gas.
- Add monitoring for stuck randomness requests and high treasury deltas.
- Run Slither, Echidna/Medusa invariants, and an external audit before mainnet use.
