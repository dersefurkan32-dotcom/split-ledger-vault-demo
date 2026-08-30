# Split-ledger vault lab

[![ci](https://github.com/dersefurkan32-dotcom/split-ledger-vault-demo/actions/workflows/ci.yml/badge.svg)](https://github.com/dersefurkan32-dotcom/split-ledger-vault-demo/actions/workflows/ci.yml)

Local Foundry lab for one money-moving identity bug: **two ledgers credit the same deposit, and each withdrawal path burns only one.**

This is a delivery sample, not a live exploit. The vulnerable vault is a teaching contract. The patched vault is proven with the same tests and with stateful invariants.

## Bug class

`ReceiptSplitVault` records a deposit twice:

| Ledger | Storage | Withdrawal path |
| --- | --- | --- |
| A | `shares[user]` | `withdrawShares` burns only A |
| B | `receipts[id] = {owner, amount, spent}` | `redeemReceipt` burns only B |

One deposit, two independent claims on the same asset pile. This is the same shape as production losses in receipt-id withdrawals, queue cursors, fast/slow paths, and trusted-forwarder flows where the protocol forgets which identity actually moves the money.

## Reproduce (local only)

Requires [Foundry](https://getfoundry.sh). No RPC, no keys, no live transactions.

```bash
forge test            # full suite
forge test -vv        # with traces
```

Directed PoC — 100 deposited, 200 extracted:

```bash
forge test --match-contract SplitLedgerPoC -vv
```

```
[PASS] test_double_pay_via_split_ledgers()
    attacker deposited 100, extracted 200
    victim share record still says 100 — backing is 0
```

## The fix, proven the same way

`ReceiptBoundVault` binds both ledgers to one identity: redeem burns the receipt **and** the share credit. `withdrawShares` is removed.

```bash
forge test --match-contract BoundLedgerInvariant -vv
```

Stateful fuzzing (`runs = 64`, `depth = 12`) drives random deposit/redeem sequences. After every call:

1. `withdrawn ≤ deposited` — no value created
2. `vault balance == deposited − withdrawn` — ledger and backing never diverge

Both hold on the bound vault. The directed PoC shows the split vault violating the same conservation rule.

## Layout

```
src/ReceiptSplitVault.sol   # MockAsset + split vault + bound vault
test/SplitLedgerPoC.t.sol   # directed PoC and edge cases
test/Invariant.t.sol        # handler + bound-vault invariants
```

## What a full engagement adds

- Fork tests against a pinned commit or live deployment (authorized scope only)
- Invariants on the actual money-moving identity: receipt id, epoch index, match id, withdrawal cursor, forwarder sender
- Upgrade-diff pass if production shipped recently
- Every finding delivered as a failing-then-fixed test. `forge test` is the report.

## Scope and use

Authorized research and teaching only. Do not point this suite at systems you do not own or are not contracted to test. See [SECURITY.md](SECURITY.md).

## License

MIT. See [LICENSE](LICENSE).

---

Vault and matching-engine pre-ship tests. Contact: Telegram [@FURY_Fn](https://t.me/FURY_Fn) · dersefurkan32@gmail.com
