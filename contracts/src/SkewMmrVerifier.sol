// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {LibSkewMmr} from "./lib/LibSkewMmr.sol";
import {LibSkewMmrVerifier} from "./lib/LibSkewMmrVerifier.sol";

/// @title Skew-MMR frontier verifier
/// @notice Commits to the frontier on every append so a caller can pass it in calldata
///         and have it checked against a single storage word.
contract SkewMmrVerifier {
    using LibSkewMmr for LibSkewMmr.State;

    uint256 public constant HISTORY_SIZE = 64;

    LibSkewMmr.State private mmr;

    /// @dev `history[count % HISTORY_SIZE]` commits to the frontier at `count`.
    bytes32[HISTORY_SIZE] public history;

    error UnknownFrontier();

    /// @dev Caps the MMR and warms up storage with non-zero values to avoid cold SSTOREs.
    constructor(uint256 maxDepth) {
        mmr.init(maxDepth);
        mmr.prewarm();
        for (uint256 i = 0; i < HISTORY_SIZE; ++i) {
            history[i] = bytes32(uint256(1));
        }
    }

    function append(bytes32 element) public {
        bytes32 commitment = LibSkewMmrVerifier.append(mmr, element, _hash);

        history[mmr.count() % HISTORY_SIZE] = commitment;
    }

    /// @notice Reverts unless `frontier` and `histState` were the frontier and state this MMR
    ///         held at `_count(histState)`.
    function verifyFrontier(uint256 histState, bytes32[] calldata frontier) public view {
        bytes32 commitment = LibSkewMmrVerifier.frontierCommitment(histState, frontier);

        if (history[LibSkewMmr._count(histState) % HISTORY_SIZE] != commitment) {
            revert UnknownFrontier();
        }
    }

    function MAX_DEPTH() external view returns (uint256) {
        return mmr.maxDepth;
    }

    function state() external view returns (uint256) {
        return mmr.state;
    }

    function ranks(uint256 tree) external view returns (uint8) {
        return mmr.ranks(tree);
    }

    function roots(uint256 tree) external view returns (bytes32) {
        return mmr.roots[tree];
    }

    function depth() external view returns (uint256) {
        return mmr.depth();
    }

    function count() external view returns (uint256) {
        return mmr.count();
    }

    function _hash(bytes32 a, bytes32 b, bytes32 c) internal pure returns (bytes32) {
        return keccak256(abi.encode(a, b, c));
    }
}
