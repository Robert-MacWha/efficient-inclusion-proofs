// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @title Recursive hash chain
/// @notice Append-only set commitment with amortised O(1) appends.
contract HashChain {
    uint256 internal constant LOG_BATCH = 5;
    uint256 public constant BATCH = 1 << LOG_BATCH;
    uint256 public constant DEPTH = 5;
    uint256 public constant CAPACITY = BATCH ** DEPTH;

    /// @dev The initial value of a chain.
    bytes32 internal constant IV = bytes32(0);

    /// @dev `chains[l]` is the open chain at level `l`. An entry whose batch is empty is
    ///      stale, so reads go through `_open`.
    bytes32[DEPTH] public chains;

    /// @dev Folds `chains[DEPTH - 1 .. 1]`, leaving `chains[0]` to be folded in last. Only a
    ///      carry out of level 0 disturbs it.
    bytes32 public upper;

    /// @dev `count + 1`, so the slot is never zero.
    uint256 internal packed;

    error Full();

    /// @dev Warms up storage with non-zero values to avoid cold SSTOREs.
    constructor() {
        packed = 1;
        for (uint256 l = 0; l < DEPTH; ++l) {
            chains[l] = bytes32(uint256(1));
        }
        upper = _fold(0);
    }

    /// @notice Append an element to the chain.
    /// @return top The chain folding every accumulator.
    function append(bytes32 element) public virtual returns (bytes32 top) {
        uint256 c = count();
        if (c == CAPACITY) revert Full();

        bytes32 carry = element;
        uint256 l;
        for (; l < DEPTH; ++l) {
            uint256 pos = _position(c, l);
            carry = _chain(_open(l, pos), carry);

            if (l == DEPTH - 1 || pos != BATCH - 1) {
                chains[l] = carry;
                break;
            }
        }

        bytes32 folded = upper;
        if (l > 0) {
            folded = _fold(c + 1);
            upper = folded;
        }

        packed = c + 2;
        top = _link(folded, l == 0 ? carry : IV);
    }

    /// @notice The open chain at each level, which combined commit to every element.
    function accumulators() public view returns (bytes32[DEPTH] memory open) {
        uint256 c = count();
        for (uint256 l = 0; l < DEPTH; ++l) {
            open[l] = _open(l, _position(c, l));
        }
    }

    function count() public view returns (uint256) {
        return packed - 1;
    }

    function _fold(uint256 c) internal view returns (bytes32 folded) {
        folded = IV;
        for (uint256 l = DEPTH - 1; l > 0; --l) {
            folded = _link(folded, _open(l, _position(c, l)));
        }
    }

    function _chain(bytes32 chain, bytes32 element) internal pure returns (bytes32 next) {
        // TODO: Replace with an algebraic hash function for in-circuit compatibility.
        assembly ("memory-safe") {
            mstore(0x00, chain)
            mstore(0x20, element)
            next := keccak256(0x00, 0x40)
        }
    }

    function _link(bytes32 commitment, bytes32 word) internal pure returns (bytes32 next) {
        assembly ("memory-safe") {
            mstore(0x00, commitment)
            mstore(0x20, word)
            next := keccak256(0x00, 0x40)
        }
    }

    function _open(uint256 l, uint256 pos) internal view returns (bytes32) {
        return pos == 0 ? IV : chains[l];
    }

    function _position(uint256 c, uint256 l) internal pure returns (uint256) {
        return (c >> (LOG_BATCH * l)) % BATCH;
    }
}
