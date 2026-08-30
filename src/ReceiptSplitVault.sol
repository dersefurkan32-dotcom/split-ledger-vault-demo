// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal ERC-20 used only as the vault's asset.
contract MockAsset {
    string public constant name = "Mock Asset";
    string public constant symbol = "MOCK";
    uint8 public constant decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "ALLOWANCE");
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(balanceOf[from] >= amount, "BALANCE");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }
}

/// @notice Intentionally incorrect vault: two ledgers, one pile of assets.
///
/// Ledger A: `shares[user]`
/// Ledger B: `receipts[id] = {owner, amount, spent}`
///
/// `deposit` credits BOTH. Each withdraw path only burns ONE.
/// Teaching contract — not for production.
contract ReceiptSplitVault {
    struct Receipt {
        address owner;
        uint256 amount;
        bool spent;
    }

    MockAsset public immutable asset;
    mapping(address => uint256) public shares;
    Receipt[] public receipts;

    constructor(MockAsset asset_) {
        asset = asset_;
    }

    function receiptCount() external view returns (uint256) {
        return receipts.length;
    }

    function deposit(uint256 amount) external returns (uint256 id) {
        require(amount > 0, "ZERO");
        asset.transferFrom(msg.sender, address(this), amount);
        shares[msg.sender] += amount;
        id = receipts.length;
        receipts.push(Receipt({owner: msg.sender, amount: amount, spent: false}));
    }

    /// Burns ledger A only. Receipts remain spendable.
    function withdrawShares(uint256 amount) external {
        require(shares[msg.sender] >= amount, "SHARES");
        shares[msg.sender] -= amount;
        asset.transfer(msg.sender, amount);
    }

    /// Burns ledger B only. Shares remain withdrawable.
    function redeemReceipt(uint256 id) external {
        require(id < receipts.length, "ID");
        Receipt storage r = receipts[id];
        require(!r.spent, "SPENT");
        require(r.owner == msg.sender, "OWNER");
        r.spent = true;
        asset.transfer(msg.sender, r.amount);
    }
}

/// Same deposit API, one identity. Redeem burns the receipt and the share
/// credit together. `withdrawShares` is removed so there is only one exit.
contract ReceiptBoundVault {
    struct Receipt {
        address owner;
        uint256 amount;
        bool spent;
    }

    MockAsset public immutable asset;
    mapping(address => uint256) public shares;
    Receipt[] public receipts;

    constructor(MockAsset asset_) {
        asset = asset_;
    }

    function receiptCount() external view returns (uint256) {
        return receipts.length;
    }

    function deposit(uint256 amount) external returns (uint256 id) {
        require(amount > 0, "ZERO");
        asset.transferFrom(msg.sender, address(this), amount);
        shares[msg.sender] += amount;
        id = receipts.length;
        receipts.push(Receipt({owner: msg.sender, amount: amount, spent: false}));
    }

    function redeemReceipt(uint256 id) external {
        require(id < receipts.length, "ID");
        Receipt storage r = receipts[id];
        require(!r.spent, "SPENT");
        require(r.owner == msg.sender, "OWNER");
        require(shares[msg.sender] >= r.amount, "SHARES");
        r.spent = true;
        shares[msg.sender] -= r.amount;
        asset.transfer(msg.sender, r.amount);
    }
}
