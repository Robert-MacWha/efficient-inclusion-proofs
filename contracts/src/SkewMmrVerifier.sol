// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {SkewMmr} from "./SkewMmr.sol";

/// @title Skew-MMR frontier verifier
/// @notice Commits to the frontier on every append so a caller can pass the roots in
///         calldata and have them checked against a single storage word.
contract SkewMmrVerifier is SkewMmr {
    uint256 public constant HISTORY_SIZE = 64;

    /// @dev `history[count % HISTORY_SIZE]` commits to the frontier at `count`.
    bytes32[HISTORY_SIZE] public history;

    error BadFrontier();
    error UnknownFrontier();

    /// @dev Warms up storage with non-zero values to avoid cold SSTOREs.
    constructor() {
        for (uint256 i = 0; i < HISTORY_SIZE; ++i) {
            history[i] = bytes32(uint256(1));
        }
    }

    function append(bytes32 element) public override returns (bytes32 top) {
        top = super.append(element);

        uint256 s = state;
        history[_count(s) % HISTORY_SIZE] = _commit(top, s);
    }

    /// @notice Reverts unless `frontier` and `histState` were the roots and state this MMR held
    ///         at `_count(histState)`.
    function verifyFrontier(uint256 histState, bytes32[] calldata frontier) public view {
        if (frontier.length != _depth(histState)) revert BadFrontier();

        bytes32 chain = SkewMmr.IV;
        for (uint256 i = 0; i < frontier.length; ++i) {
            chain = _link(chain, frontier[i]);
        }

        if (history[_count(histState) % HISTORY_SIZE] != _commit(chain, histState)) {
            revert UnknownFrontier();
        }
    }

    /// @dev Binds the frontier to the state it was reached at.
    function _commit(bytes32 top, uint256 s) private pure returns (bytes32) {
        return _link(top, bytes32(s));
    }
}
