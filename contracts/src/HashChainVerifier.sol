// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {HashChain} from "./HashChain.sol";

/// @title Hash chain accumulator verifier
/// @notice Commits to the accumulators on every append so a caller can pass them in calldata
///         and have them checked against a single storage word.
contract HashChainVerifier is HashChain {
    uint256 public constant HISTORY_SIZE = 64;

    /// @dev `history[count % HISTORY_SIZE]` commits to the accumulators at `count`.
    bytes32[HISTORY_SIZE] public history;

    error BadAccumulators();
    error UnknownAccumulators();

    /// @dev Warms up storage with non-zero values to avoid cold SSTOREs.
    constructor() {
        for (uint256 i = 0; i < HISTORY_SIZE; ++i) {
            history[i] = bytes32(uint256(1));
        }
    }

    function append(bytes32 element) public override returns (bytes32 top) {
        top = super.append(element);

        uint256 c = count();
        history[c % HISTORY_SIZE] = _commit(top, c);
    }

    /// @notice Reverts unless `open` were the accumulators this chain held at `at`.
    function verifyAccumulators(uint256 at, bytes32[] calldata open) public view {
        if (open.length != DEPTH) revert BadAccumulators();

        bytes32 top = IV;
        for (uint256 l = DEPTH; l > 0; --l) {
            top = _link(top, open[l - 1]);
        }

        if (history[at % HISTORY_SIZE] != _commit(top, at)) revert UnknownAccumulators();
    }

    function _commit(bytes32 top, uint256 c) private pure returns (bytes32) {
        return _link(top, bytes32(c));
    }
}
