// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockAsset} from "../src/ReceiptSplitVault.sol";
import {
    IEpochQueue,
    EpochQueueVaultVulnerable,
    EpochQueueVaultBound
} from "../src/EpochQueueVault.sol";

/// @notice Handler that drives random request / advance / claim sequences at
/// the queue. The handler is the keeper (it deploys the vault) and the only
/// user, so conservation is tracked with plain ghost counters. Standalone on
/// purpose — no forge-std dependency, the same handler ports to echidna-style
/// harnesses.
contract EpochQueueHandler {
    IEpochQueue public vault;
    MockAsset public asset;
    uint256 public deposited;
    uint256 public withdrawn;
    /// Per-request ghosts: what each request was funded with vs. paid out.
    /// Token-level conservation cannot catch a cursor bug (the vault balance
    /// floors at zero and the last claim just reverts) — the leak lives in
    /// per-request accounting, so that is what the invariant checks.
    uint256[] public requestedPerRequest;
    uint256[] public claimedPerRequest;

    constructor(MockAsset asset_, bool vulnerable) {
        asset = asset_;
        vault = vulnerable
            ? IEpochQueue(address(new EpochQueueVaultVulnerable(asset_, address(this))))
            : IEpochQueue(address(new EpochQueueVaultBound(asset_, address(this))));
        asset.mint(address(this), type(uint128).max);
        asset.approve(address(vault), type(uint256).max);
    }

    function request(uint96 amount) external {
        amount = uint96(boundAmount(amount, 1, 50 ether));
        vault.request(amount);
        deposited += amount;
        requestedPerRequest.push(amount);
        claimedPerRequest.push(0);
    }

    /// The only action that matures requests.
    function advance() external {
        vault.advanceEpoch();
    }

    /// Claim a bounded slice of a random request. Early returns stand in for
    /// the revert paths (unknown id, immature, exhausted, not ours).
    function claim(uint256 id, uint96 amount) external {
        uint256 n = vault.requestCount();
        if (n == 0) return;
        id = id % n;
        if (!vault.mature(id)) return;
        uint256 rem = vault.remaining(id);
        if (rem == 0) return;
        amount = uint96(boundAmount(amount, 1, rem));
        vault.claim(id, amount);
        withdrawn += amount;
        claimedPerRequest[id] += amount;
    }

    function requestsTracked() external view returns (uint256) {
        return requestedPerRequest.length;
    }

    function claimedOf(uint256 id) external view returns (uint256) {
        return claimedPerRequest[id];
    }

    function requestedOf(uint256 id) external view returns (uint256) {
        return requestedPerRequest[id];
    }

    /// On the cursor-less vault `remaining` never shrinks, so the fuzzer can
    /// keep claiming the same matured request — the kill shows up in the
    /// per-request invariant, not in a revert.
    function boundAmount(uint256 x, uint256 lo, uint256 hi) internal pure returns (uint256) {
        if (hi <= lo) return lo;
        return lo + (x % (hi - lo + 1));
    }
}

/// Conservation invariants. Abstract so it never runs by itself; subclasses
/// pick the vault variant. After every call:
///   1. withdrawn ≤ deposited — no value created
///   2. vault balance == deposited − withdrawn — ledger and backing never diverge
abstract contract EpochQueueInvariantBase is Test {
    EpochQueueHandler internal handler;

    function _vulnerable() internal pure virtual returns (bool);

    /// @dev Subclasses can gate the suite behind an env flag (keeps the
    /// killed-bug variant out of default runs).
    function _gatedEnv() internal pure virtual returns (string memory) {
        return "";
    }

    function setUp() public {
        string memory gate = _gatedEnv();
        if (bytes(gate).length != 0) {
            vm.skip(!vm.envOr(gate, false), "gated: set env flag to run");
        }
        handler = new EpochQueueHandler(new MockAsset(), _vulnerable());
        targetContract(address(handler));
    }

    function invariant_withdrawals_cannot_exceed_deposits() public view {
        assertLe(handler.withdrawn(), handler.deposited());
    }

    function invariant_vault_balance_matches_ledger() public view {
        uint256 backing = handler.asset().balanceOf(address(handler.vault()));
        assertEq(backing, handler.deposited() - handler.withdrawn());
    }

    /// The cursor property: no request pays out more than it was funded with.
    /// This is the one the cursor-less queue breaks — token-level
    /// conservation above still holds while it happens.
    function invariant_no_request_overpays() public view {
        for (uint256 i = 0; i < handler.requestsTracked(); i++) {
            assertLe(handler.claimedOf(i), handler.requestedOf(i));
        }
    }
}

/// The cursor-bound queue. Both invariants MUST hold. Default CI runs this.
contract EpochQueueInvariant is EpochQueueInvariantBase {
    function _vulnerable() internal pure override returns (bool) {
        return false;
    }
}

/// The cursor-less queue. Same invariants, same handler — expected to FAIL.
/// Gated behind DEMO_RUN_KILLED so default runs stay green.
contract VulnerableEpochQueueInvariant is EpochQueueInvariantBase {
    function _vulnerable() internal pure override returns (bool) {
        return true;
    }

    function _gatedEnv() internal pure override returns (string memory) {
        return "DEMO_RUN_KILLED";
    }
}
