# Security policy

This repository is a **local teaching lab**. `ReceiptSplitVault` is intentionally incorrect. It is not a production protocol and it is not a target.

## Authorized use only

- Run `forge test` on this repo, on a local Foundry EVM.
- Do not send transactions to public networks from this code.
- Do not use the PoC against third-party deployments unless you have written authorization (bug bounty, audit contract, or owner permission).

## Reporting a problem in *this* lab

If you find an issue in the **bound** vault, the tests, or the CI — for example an invariant that does not actually hold — email **dersefurkan32@gmail.com** with:

- a short description
- `forge` version
- a command that reproduces it

Do not open a public issue for a vulnerability in a client system. Those belong in the client's disclosure channel.

## What this repo is not

It is not a scanner, not a live exploit pack, and not permission to test other people's vaults.
