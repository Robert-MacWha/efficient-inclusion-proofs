// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {LibSkewMmr} from "./lib/LibSkewMmr.sol";
import {LibSkewMmrWithHistory} from "./lib/LibSkewMmrWithHistory.sol";

/// @title Skew-MMR frontier verifier
/// @notice Commits to the frontier on every append so a caller can pass it in calldata
///         and have it checked against a single storage word.
contract SkewMmrVerifier {
    using LibSkewMmrWithHistory for LibSkewMmrWithHistory.State;
    using LibSkewMmr for LibSkewMmr.State;

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
        mmr.append(element, _hash);
    }

    function verifyFrontier(uint256 histState, bytes32[] calldata frontier) public view {
        mmr.verifyFrontier(histState, frontier);
    }

    function MAX_DEPTH() external pure returns (uint256) {
        return LibSkewMmr.MAX_DEPTH;
    }

    function state() external view returns (uint256) {
        return mmr.mmr.state;
    }

    function ranks(uint256 tree) external view returns (uint8) {
        return mmr.mmr.ranks(tree);
    }

    function roots(uint256 tree) external view returns (bytes32) {
        return mmr.mmr.roots[tree];
    }

    function depth() external view returns (uint256) {
        return mmr.mmr.depth();
    }

    function count() external view returns (uint256) {
        return mmr.mmr.count();
    }

    function _hash(bytes32 a, bytes32 b, bytes32 c) internal pure returns (bytes32) {
        return keccak256(abi.encode(a, b, c));
    }
}
