// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {LibSkewMmrWithHistory} from "./lib/LibSkewMmrWithHistory.sol";

/// @title Skew-MMR frontier verifier
/// @notice Commits to the frontier on every append so a caller can pass it in calldata
///         and have it checked against a single storage word.
contract SkewMmrVerifier {
    using LibSkewMmrWithHistory for LibSkewMmrWithHistory.State;

    uint256 public constant HISTORY_SIZE = 64;

    LibSkewMmrWithHistory.State private mmr;

    /// @dev `history[count % HISTORY_SIZE]` commits to the frontier at `count`.
    bytes32[HISTORY_SIZE] public history;

    error BadFrontier();
    error UnknownFrontier();

    /// @dev Warms up storage with non-zero values to avoid cold SSTOREs.
    constructor() {
        mmr.prewarm();
    }

    function append(bytes32 element) public {
        mmr.append(element);
    }

    function verifyFrontier(uint256 histState, bytes32[] calldata frontier) public view {
        mmr.verifyFrontier(histState, frontier);
    }

    function MAX_DEPTH() external pure returns (uint256) {
        return LibSkewMmrWithHistory.MAX_DEPTH();
    }

    function state() external view returns (uint256) {
        return mmr.mmr.state;
    }

    function ranks(uint256 tree) external view returns (uint8) {
        return mmr.ranks(tree);
    }

    function roots(uint256 tree) external view returns (bytes32) {
        return mmr.roots(tree);
    }

    function depth() external view returns (uint256) {
        return mmr.depth();
    }

    function count() external view returns (uint256) {
        return mmr.count();
    }
}
