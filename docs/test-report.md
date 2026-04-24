# Test and Coverage Report

Generated locally on Foundry `1.5.1-stable`.

## Commands

```bash
forge build
forge test -vv
forge coverage --report summary
npm --prefix frontend install
npm --prefix frontend run build
/Users/zhy/Library/Python/3.13/bin/slither . --exclude-dependencies
```

## Results

- Build: successful.
- Tests: 14 passed, 0 failed.
- Coverage summary including scripts and imported Chainlink base contracts: 310 / 421 lines, **73.63% line coverage**.
- Core game contract coverage: 222 / 256 lines, **86.72% line coverage**.
- Chainlink adapter contract coverage: 29 / 33 lines, **87.88% line coverage**.
- Frontend Vite/React production build: successful.
- Slither static analysis: completed; residual design findings are documented in `slither-report.md`.
- Chainlink adapter integration tests: successful.

## Notes

- `forge test` without verbosity triggered a Foundry macOS proxy/signature lookup panic in this environment. `forge test -vv` ran successfully and consistently.
- `forge snapshot --snap .gas-snapshot` triggered a Foundry macOS proxy/signature lookup panic in this environment. `forge test -vv --gas-report` completed and is used for gas evidence.
