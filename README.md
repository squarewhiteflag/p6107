# Chain Fate Arena

Chain Fate Arena is an implementation of **SC6107 Option 4: On-Chain Verifiable Random Game Platform**.

It contains a Foundry smart-contract project, a Vite/React MetaMask frontend, tests, deployment scripts, and course documentation. The platform implements two games on one treasury:

- **Oracle Dice**: players commit a hidden seed, receive VRF-style randomness, reveal the seed, and are paid automatically if the final roll wins.
- **Epoch Raffle**: players buy tickets, commit hidden seeds, reveal during a timed window, and the contract finalizes the winner with automatic payout.

## Option 4 Feature Coverage

- Verifiable randomness flow with `requestRandomness -> rawFulfillRandomness` callback.
- Local VRF-style coordinator that stores a transparent `proofHash` for demos.
- Request retry paths for dice and raffle if randomness stalls.
- Two games: dice and time-based raffle.
- ETH and ERC-20 betting through `address(0)` and demo `FATE` token.
- House treasury, reserved payout accounting, reveal bonds, and pooled raffle pots.
- Automatic payout on dice reveal and raffle finalization.
- Minimum/maximum bet limits and configurable house edge.
- Anti-cheating through seed commitments, reveal deadlines, slashing, and stale-callback protection.
- Emergency pause and owner-only configuration.

## Project Structure

```text
Random_Game_Platfom/
├── src/
│   ├── ChainFateArena.sol
│   ├── interfaces/
│   └── mocks/
├── test/
├── script/
├── frontend/
├── docs/
├── foundry.toml
└── package.json
```

## Core Contracts

- `src/ChainFateArena.sol`
  Main platform contract for token configuration, dice bets, raffle rounds, bankroll accounting, seed reveal, slashing, and payouts.
- `src/ChainlinkVRFCoordinatorAdapter.sol`
  Chainlink VRF v2.5 subscription adapter. It implements the same `IRandomnessCoordinator` interface as the local mock, requests one VRF word, and forwards verified callbacks to `ChainFateArena`.
- `src/mocks/MockVRFCoordinator.sol`
  VRF-like local oracle for fast Anvil tests and demos.
- `src/mocks/MockERC20.sol`
  Mintable OpenZeppelin ERC-20 `FATE` token for ERC-20 betting demos.
- OpenZeppelin Contracts 5.x
  `Ownable`, `Pausable`, `ReentrancyGuard`, `ERC20`, and `SafeERC20` provide the standard security and token primitives.

## Local Commands

```bash
forge build
forge test
forge coverage
npm --prefix frontend install
npm --prefix frontend run build
```

## Local Demo

Start Anvil:

```bash
anvil
```

Deploy contracts:

```bash
forge script script/DeployChainFateArena.s.sol:DeployChainFateArena \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast
```

Copy the deployed `ChainFateArena`, `MockVRFCoordinator`, and `MockERC20` addresses into `frontend/config.js`.

Run the React frontend:

```bash
npm --prefix frontend run dev
```

Open:

```text
http://127.0.0.1:8014/
```

## Chainlink VRF Testnet Deployment

For Sepolia or another supported network, create and fund a Chainlink VRF v2.5 subscription, then deploy:

```bash
PRIVATE_KEY=0x... \
VRF_SUBSCRIPTION_ID=123 \
forge script script/DeployChainlinkVRFChainFateArena.s.sol:DeployChainlinkVRFChainFateArena \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --broadcast \
  --verify
```

After deployment, add the deployed `ChainlinkVRFCoordinatorAdapter` address as an approved consumer in the Chainlink VRF subscription manager. Use the deployed `ChainFateArena` and `MockERC20` addresses in `frontend/config.js`; leave `coordinatorAddress` empty unless you are running the local mock fulfill panel.

## Documentation

- [Architecture](./docs/architecture.md)
- [Security Analysis](./docs/security-analysis.md)
- [Gas Optimization](./docs/gas-optimization.md)
- [Deployment Guide](./docs/deployment-guide.md)
- [User Guide](./docs/user-guide.md)
- [Option 4 Compliance](./docs/option-4-compliance.md)
- [Test and Coverage Report](./docs/test-report.md)
- [Slither Static Analysis Report](./docs/slither-report.md)

## Test Coverage

The Foundry test suite covers:

- dice win, loss, wrong reveal, retry, and expired reveal slashing
- raffle purchase, seed reveal, finalization, fee accounting, and bond slashing
- ERC-20 betting path
- pause and owner-only controls
- fuzz tests for dice roll bounds and raffle ticket accounting
- invariant-style solvency check for reserved liabilities

## Academic Integrity Notes

The implementation is original for this course project. It uses OpenZeppelin Contracts 5.x for standard owner, pause, reentrancy, ERC-20, and safe-transfer primitives, plus original game logic for commit-reveal, VRF-style callbacks, treasury accounting, and settlement.
