// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MockAsset} from "./ReceiptSplitVault.sol";

/// @notice Queue surface the epoch-handler drives. Both the cursor-less and
/// the cursor-bound variant implement it, so the same handler and the same
/// conservation invariants run against either one.
interface IEpochQueue {
    function requestCount() external view returns (uint256);
    function currentEpoch() external view returns (uint256);
    function remaining(uint256 id) external view returns (uint256);
    function mature(uint256 id) external view returns (bool);
    function request(uint256 amount) external returns (uint256 id);
    function claim(uint256 id, uint256 amount) external;
    function advanceEpoch() external;
}

/// @notice Intentionally incorrect withdrawal queue: requests mature when the
/// epoch advances, but `claim` pays up to the FULL request amount on every
/// call — the claimed cursor is never written.
///
/// This is the queue-cursor shape of the identity class: the protocol tracks
/// what a request is worth, not what it has already paid. claim(id, amount)
/// is callable until the vault is empty, and the last claimants revert on
/// an empty vault. Teaching contract — not for production.
contract EpochQueueVaultVulnerable is IEpochQueue {
    struct Request {
        address owner;
        uint96 amount;
        uint64 epoch;
    }

    MockAsset public immutable asset;
    address public immutable keeper;
    uint256 public currentEpoch;
    Request[] public requests;

    constructor(MockAsset asset_, address keeper_) {
        asset = asset_;
        keeper = keeper_;
    }

    function requestCount() external view returns (uint256) {
        return requests.length;
    }

    /// @dev The bug: "remaining" ignores what was already paid.
    function remaining(uint256 id) external view returns (uint256) {
        return requests[id].amount;
    }

    function mature(uint256 id) external view returns (bool) {
        return requests[id].epoch < currentEpoch;
    }

    function request(uint256 amount) external returns (uint256 id) {
        require(amount > 0, "ZERO");
        asset.transferFrom(msg.sender, address(this), amount);
        id = requests.length;
        requests.push(
            Request({owner: msg.sender, amount: uint96(amount), epoch: uint64(currentEpoch)})
        );
    }

    /// Burns nothing. The same request can be claimed at full value again.
    function claim(uint256 id, uint256 amount) external {
        require(id < requests.length, "ID");
        Request storage r = requests[id];
        require(r.owner == msg.sender, "OWNER");
        require(r.epoch < currentEpoch, "NOT_MATURE");
        require(amount <= r.amount, "AMOUNT");
        asset.transfer(msg.sender, amount);
    }

    function advanceEpoch() external {
        require(msg.sender == keeper, "NOT_KEEPER");
        currentEpoch++;
    }
}

/// Same queue API, one honest cursor: every request records what it has paid,
/// and a claim can never exceed the remainder. The conservation invariants
/// that catch the cursor-less vault hold here by construction.
contract EpochQueueVaultBound is IEpochQueue {
    struct Request {
        address owner;
        uint96 amount;
        uint64 epoch;
        uint96 claimed;
    }

    MockAsset public immutable asset;
    address public immutable keeper;
    uint256 public currentEpoch;
    Request[] public requests;

    constructor(MockAsset asset_, address keeper_) {
        asset = asset_;
        keeper = keeper_;
    }

    function requestCount() external view returns (uint256) {
        return requests.length;
    }

    function remaining(uint256 id) external view returns (uint256) {
        Request storage r = requests[id];
        return r.amount - r.claimed;
    }

    function mature(uint256 id) external view returns (bool) {
        return requests[id].epoch < currentEpoch;
    }

    function request(uint256 amount) external returns (uint256 id) {
        require(amount > 0, "ZERO");
        asset.transferFrom(msg.sender, address(this), amount);
        id = requests.length;
        requests.push(
            Request({
                owner: msg.sender, amount: uint96(amount), epoch: uint64(currentEpoch), claimed: 0
            })
        );
    }

    function claim(uint256 id, uint256 amount) external {
        require(id < requests.length, "ID");
        Request storage r = requests[id];
        require(r.owner == msg.sender, "OWNER");
        require(r.epoch < currentEpoch, "NOT_MATURE");
        require(r.claimed + amount <= r.amount, "AMOUNT");
        r.claimed += uint96(amount);
        asset.transfer(msg.sender, amount);
    }

    function advanceEpoch() external {
        require(msg.sender == keeper, "NOT_KEEPER");
        currentEpoch++;
    }
}
