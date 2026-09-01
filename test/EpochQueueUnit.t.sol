// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockAsset} from "../src/ReceiptSplitVault.sol";
import {EpochQueueVaultBound} from "../src/EpochQueueVault.sol";

/// Deterministic checks and fuzz around the cursor-bound queue: maturity,
/// ownership, partial-claim accounting, keeper gating.
contract EpochQueueUnit is Test {
    MockAsset internal asset;
    EpochQueueVaultBound internal vault; // keeper = this contract
    address internal alice = address(0xA1);
    address internal bob = address(0xB0B);

    function setUp() public {
        asset = new MockAsset();
        vault = new EpochQueueVaultBound(asset, address(this));
        asset.mint(alice, 1000 ether);
        asset.mint(bob, 1000 ether);
        vm.prank(alice);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        asset.approve(address(vault), type(uint256).max);
    }

    function test_request_zero_reverts() public {
        vm.prank(alice);
        vm.expectRevert(bytes("ZERO"));
        vault.request(0);
    }

    function test_immature_claim_reverts() public {
        vm.prank(alice);
        uint256 id = vault.request(10 ether);
        vm.prank(alice);
        vm.expectRevert(bytes("NOT_MATURE"));
        vault.claim(id, 10 ether);
    }

    function test_claim_by_stranger_reverts() public {
        vm.prank(alice);
        uint256 id = vault.request(10 ether);
        vault.advanceEpoch();
        vm.prank(bob);
        vm.expectRevert(bytes("OWNER"));
        vault.claim(id, 1 ether);
    }

    function test_claim_unknown_id_reverts() public {
        vm.prank(alice);
        vm.expectRevert(); // out-of-bounds array read
        vault.claim(7, 1 ether);
    }

    function test_advance_epoch_only_keeper() public {
        vm.prank(alice);
        vm.expectRevert(bytes("NOT_KEEPER"));
        vault.advanceEpoch();
    }

    /// Partial claims are tracked: the third claim exceeds the remaining
    /// cursor and reverts, the exact remainder succeeds.
    function test_partial_claims_consume_cursor() public {
        vm.prank(alice);
        uint256 id = vault.request(100 ether);
        vault.advanceEpoch();

        vm.startPrank(alice);
        vault.claim(id, 60 ether);
        vm.expectRevert(bytes("AMOUNT"));
        vault.claim(id, 41 ether);
        vault.claim(id, 40 ether);
        vm.expectRevert(bytes("AMOUNT"));
        vault.claim(id, 1);
        vm.stopPrank();

        assertEq(asset.balanceOf(alice), 1000 ether, "alice recovered exactly her deposit");
        assertEq(vault.remaining(id), 0);
    }

    /// Fuzz: any number of requests, vault balance always equals the sum of
    /// unmatured plus unclaimed amounts — the ledger never leaves the asset.
    function testFuzz_requests_conserve_balance(uint96 a, uint96 b, uint96 c) public {
        a = uint96(bound(a, 1, 100 ether));
        b = uint96(bound(b, 1, 100 ether));
        c = uint96(bound(c, 1, 100 ether));

        vm.prank(alice);
        uint256 idA = vault.request(a);
        vm.prank(bob);
        vault.request(b);
        vm.prank(alice);
        vault.request(c);

        assertEq(asset.balanceOf(address(vault)), uint256(a) + b + c);

        vault.advanceEpoch();
        vm.prank(alice);
        vault.claim(idA, a);

        assertEq(asset.balanceOf(address(vault)), uint256(b) + c, "balance tracks unpaid requests");
        assertEq(vault.remaining(idA), 0);
    }
}
