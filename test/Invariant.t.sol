// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ReceiptSplitVault, ReceiptBoundVault, MockAsset} from "../src/ReceiptSplitVault.sol";

/// Drop-in conservation handler: track deposits vs withdrawals.
/// If withdrawals ever exceed deposits, the vault is tracking the wrong identity.
/// Kept as a template for client vaults. Default CI fuzzes the bound vault only.
contract SplitHandler {
    ReceiptSplitVault public vault;
    MockAsset public asset;
    uint256 public deposited;
    uint256 public withdrawn;

    constructor(ReceiptSplitVault vault_, MockAsset asset_) {
        vault = vault_;
        asset = asset_;
        asset.mint(address(this), type(uint128).max);
        asset.approve(address(vault_), type(uint256).max);
    }

    function deposit(uint96 amount) external {
        amount = uint96(boundAmount(amount, 1, 50 ether));
        vault.deposit(amount);
        deposited += amount;
    }

    function withdrawShares(uint96 amount) external {
        uint256 shares = vault.shares(address(this));
        if (shares == 0) return;
        amount = uint96(boundAmount(amount, 1, shares));
        vault.withdrawShares(amount);
        withdrawn += amount;
    }

    function redeemReceipt(uint256 id) external {
        uint256 n = vault.receiptCount();
        if (n == 0) return;
        id = id % n;
        (address owner, uint256 amount, bool spent) = vault.receipts(id);
        if (spent || owner != address(this)) return;
        vault.redeemReceipt(id);
        withdrawn += amount;
    }

    function boundAmount(uint256 x, uint256 lo, uint256 hi) internal pure returns (uint256) {
        if (hi <= lo) return lo;
        return lo + (x % (hi - lo + 1));
    }
}

contract BoundHandler {
    ReceiptBoundVault public vault;
    MockAsset public asset;
    uint256 public deposited;
    uint256 public withdrawn;

    constructor(ReceiptBoundVault vault_, MockAsset asset_) {
        vault = vault_;
        asset = asset_;
        asset.mint(address(this), type(uint128).max);
        asset.approve(address(vault_), type(uint256).max);
    }

    function deposit(uint96 amount) external {
        amount = uint96(boundAmount(amount, 1, 50 ether));
        vault.deposit(amount);
        deposited += amount;
    }

    function redeemReceipt(uint256 id) external {
        uint256 n = vault.receiptCount();
        if (n == 0) return;
        id = id % n;
        (address owner, uint256 amount, bool spent) = vault.receipts(id);
        if (spent || owner != address(this)) return;
        vault.redeemReceipt(id);
        withdrawn += amount;
    }

    function boundAmount(uint256 x, uint256 lo, uint256 hi) internal pure returns (uint256) {
        if (hi <= lo) return lo;
        return lo + (x % (hi - lo + 1));
    }
}

/// Conservation invariants on the bound vault. These MUST hold.
contract BoundLedgerInvariant is Test {
    BoundHandler internal handler;

    function setUp() public {
        MockAsset asset = new MockAsset();
        ReceiptBoundVault vault = new ReceiptBoundVault(asset);
        handler = new BoundHandler(vault, asset);
        targetContract(address(handler));
    }

    function invariant_withdrawals_cannot_exceed_deposits() public view {
        assertLe(handler.withdrawn(), handler.deposited());
    }

    function invariant_vault_covers_unredeemed_shares() public view {
        uint256 backing = handler.asset().balanceOf(address(handler.vault()));
        assertEq(backing, handler.deposited() - handler.withdrawn());
    }
}
