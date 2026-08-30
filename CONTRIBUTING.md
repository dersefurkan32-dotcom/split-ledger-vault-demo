# Contributing

This is a small private lab. Changes should keep the teaching story intact: one split-ledger PoC, one bound vault, invariants that stay green.

## Setup

Install [Foundry](https://getfoundry.sh). Then:

```bash
forge fmt
forge test -vv
```

## Rules

- Do not weaken or delete the directed PoC (`test_double_pay_via_split_ledgers`).
- Do not change revert strings (`ZERO`, `SHARES`, `SPENT`, `OWNER`, `ID`, `BALANCE`, `ALLOWANCE`) without updating tests in the same change.
- Do not add RPC, private keys, or live-network scripts.
- Run `forge fmt --check` and `forge test` before pushing.
- Commit messages: short imperative (`Add edge-case tests for redeem`).

## Pull requests

Open against `main`. Describe what changed and the exact `forge test` command you ran.
