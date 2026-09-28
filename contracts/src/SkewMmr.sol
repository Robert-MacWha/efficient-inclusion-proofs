// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

/// @title Skew-binary MMR
/// @notice Append-only set commitment with worst-case O(1) appends.
contract SkewMmr {
    uint256 public constant MAX_DEPTH = 26;

    /// @dev Initial value for the tree folding chain.
    bytes32 internal constant IV = bytes32(0);

    /// @dev The frontier: tree roots, smallest-ranked last. Entries above `depth` are undefined.
    bytes32[MAX_DEPTH] public roots;

    /// @dev 0..25  - `rank`s
    ///      26     - unused, set at construction so the slot is never zero
    ///      27     - `depth`
    ///      28..31 - `count`
    uint256 public state;

    /// @dev `chains[i]` folds `roots[0..i]`. Entries above `depth` are undefined.
    bytes32[MAX_DEPTH] private chains;

    error TooDeep();

    /// @dev Warms up storage with non-zero values to avoid cold SSTOREs.
    constructor() {
        state = 1 << 208;
        for (uint256 i = 0; i < MAX_DEPTH; ++i) {
            roots[i] = bytes32(uint256(1));
            chains[i] = bytes32(uint256(1));
        }
    }

    /// @notice Append an element to the MMR.
    /// @return top The chain folding every root of the resulting frontier.
    ///
    /// @dev Maximum of 1 hash per append. Follows skew-binary carry rules:
    ///      1. If the two smallest trees have the same rank, merge them into a tree of rank+1.
    ///      2. Otherwise, append the new element as a tree of rank 0.
    ///
    ///      Either branch writes `roots[tree]`, and `chains[tree - 1]` is stable across it.
    function append(bytes32 element) public virtual returns (bytes32 top) {
        uint256 s = state;
        uint256 d = _depth(s);
        uint256 tree;
        uint256 rank;
        bytes32 root;

        if (d >= 2 && _rank(s, d - 1) == _rank(s, d - 2)) {
            //? poseidon2_3(a, b, c) = ~20k gas
            root = keccak256(abi.encode(element, roots[d - 1], roots[d - 2]));
            roots[d - 2] = root;

            tree = d - 2;
            rank = _rank(s, d - 1) + 1;
            d -= 1;
            s = _setRank(s, d, 0);
        } else {
            if (d == MAX_DEPTH) revert TooDeep();

            root = element;
            roots[d] = root;

            tree = d;
            rank = 0;
            d += 1;
        }

        top = _link(tree >= 1 ? chains[tree - 1] : IV, root);
        chains[tree] = top;

        s = _setRank(s, tree, rank);
        s = _setDepth(s, d);
        state = _incrementCount(s);
    }

    function ranks(uint256 tree) external view returns (uint8) {
        return uint8(_rank(state, tree));
    }

    function depth() external view returns (uint256) {
        return _depth(state);
    }

    function count() external view returns (uint256) {
        return _count(state);
    }

    function _link(bytes32 prev, bytes32 root) internal pure returns (bytes32 chain) {
        assembly ("memory-safe") {
            mstore(0x00, prev)
            mstore(0x20, root)
            chain := keccak256(0x00, 0x40)
        }
    }

    function _rank(uint256 s, uint256 tree) internal pure returns (uint256) {
        return (s >> (8 * tree)) & 0xff;
    }

    function _setRank(uint256 s, uint256 tree, uint256 rank) internal pure returns (uint256) {
        uint256 offset = 8 * tree;
        return (s & ~(uint256(0xff) << offset)) | (rank << offset);
    }

    function _depth(uint256 s) internal pure returns (uint256) {
        return (s >> 216) & 0xff;
    }

    function _setDepth(uint256 s, uint256 d) internal pure returns (uint256) {
        return (s & ~(uint256(0xff) << 216)) | (d << 216);
    }

    function _count(uint256 s) internal pure returns (uint256) {
        return s >> 224;
    }

    function _incrementCount(uint256 s) internal pure returns (uint256) {
        return s + (uint256(1) << 224);
    }
}
