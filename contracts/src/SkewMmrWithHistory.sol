// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {LibSkewMmr} from "./lib/LibSkewMmr.sol";
import {LibSkewMmrVerifier} from "./lib/LibSkewMmrVerifier.sol";

/// @title Skew-MMR frontier verifier
/// @notice Commits to the frontier on every append so a caller can pass it in calldata
///         and have it checked against a single storage word.
contract SkewMmrWithHistory {
    using LibSkewMmr for LibSkewMmr.State;

    LibSkewMmr.State internal mmr;

    /// @dev `history[count % HISTORY_SIZE]` commits to the frontier at `count`.
    mapping(uint256 => bytes32) public history;
    uint256 public immutable HISTORY_SIZE;

    error UnknownFrontier();

    /// @dev Caps the MMR and warms up storage with non-zero values to avoid cold SSTOREs.
    constructor(uint256 maxDepth, uint256 historySize) {
        mmr.init(maxDepth);
        HISTORY_SIZE = historySize;
    }

    function _append(bytes32 element) internal {
        bytes32 commitment = LibSkewMmrVerifier.append(mmr, element, _hash);

        history[mmr.count % HISTORY_SIZE] = commitment;
    }

    /// @notice Returns true if `frontier` is the frontier this MMR held at `histCount`.
    function verifyFrontier(uint256 histRanks, uint256 histDepth, uint256 histCount, bytes32[] calldata frontier)
        public
        view
        returns (bool)
    {
        bytes32 commitment = LibSkewMmrVerifier.frontierCommitment(histRanks, histDepth, histCount, frontier);

        if (history[histCount % HISTORY_SIZE] != commitment) {
            return false;
        }
        return true;
    }

    function MAX_DEPTH() external view returns (uint256) {
        return mmr.maxDepth;
    }

    function packedRanks() external view returns (uint256) {
        return mmr.packedRanks;
    }

    function ranks(uint256 tree) external view returns (uint8) {
        return mmr.ranks(tree);
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

    function _hash(bytes32 a, bytes32 b, bytes32 c) internal pure virtual returns (bytes32) {
        return keccak256(abi.encode(a, b, c));
    }
}
