// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {LibSkewMmr} from "./lib/LibSkewMmr.sol";

/// @title Skew-MMR frontier verifier
/// @notice Commits to the frontier on every append so a caller can pass it in calldata
///         and have it checked against a single storage word.
contract SkewMmrWithHistory {
    using LibSkewMmr for LibSkewMmr.State;

    LibSkewMmr.State internal mmr;

    /// @dev `history[count % HISTORY_SIZE]` commits to the frontier at `count`.
    mapping(uint256 => bytes32) public history;
    uint256 public immutable HISTORY_SIZE;
    /// @dev The number of trees this MMR is capped at, never above `LibSkewMmr.MAX_TREES`.
    uint256 public immutable MAX_DEPTH;

    error UnknownFrontier();

    /// @dev Caps the MMR and warms up storage with non-zero values to avoid cold SSTOREs.
    constructor(uint256 maxDepth, uint256 historySize) {
        if (maxDepth > LibSkewMmr.MAX_TREES) revert LibSkewMmr.TooDeep();
        MAX_DEPTH = maxDepth;
        HISTORY_SIZE = historySize;
    }

    function _append(bytes32 element) internal {
        bytes32 top = mmr.append(element, _hash);
        if (mmr.depth > MAX_DEPTH) revert LibSkewMmr.TooDeep();

        history[mmr.count % HISTORY_SIZE] = top;
    }

    /// Appends without committing the new frontier to `history`.
    /// @dev Follow a batch of these with `_recordHistory` so the
    ///      final frontier is committed.
    function _appendWithoutHistory(bytes32 element) internal {
        mmr.append(element, _hash);
        if (mmr.depth > MAX_DEPTH) revert LibSkewMmr.TooDeep();
    }

    /// @dev Commits the current frontier to `history`.
    function _recordHistory() internal {
        history[mmr.count % HISTORY_SIZE] = mmr.root();
    }

    /// @notice Returns true if `frontier` is the frontier this MMR held at `histCount`.
    function verifyFrontier(uint256 histCount, bytes32[] calldata frontier) public view returns (bool) {
        return history[histCount % HISTORY_SIZE] == LibSkewMmr.fold(frontier);
    }

    /// @notice Bit `k` is set when the frontier holds a tree of rank `k`.
    function ranks() external view returns (uint64) {
        return mmr.ranks;
    }

    /// @notice Whether the two smallest trees have the same rank.
    function doubled() external view returns (bool) {
        return mmr.doubled;
    }

    function roots(uint256 tree) external view returns (bytes32) {
        return mmr.roots[tree];
    }

    function depth() external view returns (uint256) {
        return mmr.depth;
    }

    function count() external view returns (uint256) {
        return mmr.count;
    }

    function _hash(bytes32 a, bytes32 b, bytes32 c) internal view virtual returns (bytes32) {
        return keccak256(abi.encode(a, b, c));
    }
}
