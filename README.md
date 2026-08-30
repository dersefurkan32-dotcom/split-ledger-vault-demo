# vault-attack-suite-demo

[![test](https://github.com/dersefurkan32-dotcom/vault-attack-suite-demo/actions/workflows/ci.yml/badge.svg)](https://github.com/dersefurkan32-dotcom/vault-attack-suite-demo/actions/workflows/ci.yml)

**I don't sell audit PDFs. I ship Foundry repos that try to empty your vault before users do.**

This repo is the public sample of what an engagement delivers: a runnable attack
suite for one bug class — *split-ledger identity* — where two ledgers credit the
same deposit and each withdrawal path burns only one.

## The bug class

`ReceiptSplitVault` tracks deposits twice:

- Ledger A: `shares[user]`
- Ledger B: `receipts[id] = {owner, amount, spent}`

`deposit()` credits **both**. `withdrawShares()` burns only A.
`redeemReceipt()` burns only B. One deposit, two independent claims on the
same assets.

This is the class behind real production losses: receipt/id-based withdrawal
systems, queue cursors, fast/slow paths, and trusted-forwarder flows where the
protocol forgets which identity actually moves the money.

## The attack (30 seconds)

```bash
forge test --match-contract AttackSuite -vv
```

```
[PASS] test_double_pay_via_split_ledgers()
    attacker deposited 100, extracted 200
    victim's 100 is gone; victim's share record still says 100 — backing is 0
```

## The fix, proven the same way

`ReceiptBoundVault` binds both ledgers to one identity: redeem burns the
receipt **and** the share credit.

```bash
forge test --match-contract BoundLedgerInvariant -vv
```

Stateful fuzzing (`runs = 64, depth = 12`) drives random
deposit/withdraw/redeem sequences at the bound vault. Two invariants must hold
after every call:

1. `withdrawn ≤ deposited` — no value created
2. `vault balance == deposited − withdrawn` — ledger and balance never diverge

They hold. The same invariant dropped on the split vault fails immediately —
that failure is the product.

## What a real engagement adds on top of this sample

- **Fork tests** against your live deployment (or pinned commit) — real state,
  real config, no mocks
- Invariants on **your** money-moving identity: receipt id, epoch index,
  match id, withdrawal cursor, forwarder sender
- **Upgrade-diff pass** if you shipped in the last 30 days
- Every finding delivered as a failing-then-fixed test. `forge test` is the report.

## Run it

```bash
forge test            # full suite: 4/4
forge test -vv        # with the drain trace
```

Requires [Foundry](https://getfoundry.sh). No RPC, no keys — fully local.

---

*Pre-ship attack tests for vaults and matching engines. 7 days, you keep the
tests. Contact: Telegram [@FURY_Fn](https://t.me/FURY_Fn) ·
dersefurkan32@gmail.com*
