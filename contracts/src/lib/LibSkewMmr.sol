// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

library LibSkewMmr {
    /// The number of ranks `packedRanks` holds, and the ceiling on `maxDepth` that follows from it.
    uint256 internal constant MAX_TREES = 42;

    uint256 internal constant RANK_BITS = 6;
    uint256 internal constant RANK_MASK = (1 << RANK_BITS) - 1;

    /// @dev Initial value for the tree folding chain.
    bytes32 internal constant IV = bytes32(0);

    struct State {
        /// @dev The frontier: tree roots, smallest-ranked last. Entries above `depth` are undefined.
        bytes32[MAX_TREES] roots;

        /// @dev The `rank` of tree `i` sits at bits `6i..6i+6`. Ranks at or above `depth` are zero.
        uint256 packedRanks;

        uint8 depth;
        uint64 count;

        /// @dev `chains[i]` folds `roots[0..i]`. Entries above `depth` are undefined.
        bytes32[MAX_TREES] chains;
    }

    error TooDeep();

    /// @notice Append an element to the MMR.
    /// @return top The chain folding every root of the resulting frontier.
    ///
    /// @param element The new elelment to append to the MMR.
    /// @param hash Merges a new element with the two roots it subsumes into a new tree root.
    ///
    /// @dev Maximum of 1 hash per append. Follows skew-binary carry rules:
    ///      1. If the two smallest trees have the same rank, merge them into a tree of rank+1.
    ///      2. Otherwise, append the new element as a tree of rank 0.
    ///
    ///      Either branch writes `roots[tree]`, and `chains[tree - 1]` is stable across it.
    function append(
        State storage self,
        bytes32 element,
        function(bytes32, bytes32, bytes32) internal view returns (bytes32) hash
    ) internal returns (bytes32 top) {
        uint256 r = self.packedRanks;
        uint256 d = self.depth;
        uint256 tree;
        uint256 rank;
        bytes32 treeRoot;

        if (d >= 2 && _rank(r, d - 1) == _rank(r, d - 2)) {
            treeRoot = hash(element, self.roots[d - 1], self.roots[d - 2]);
            self.roots[d - 2] = treeRoot;

            tree = d - 2;
            rank = _rank(r, d - 1) + 1;
            d -= 1;
            r = _setRank(r, d, 0);
        } else {
            if (d == MAX_TREES) revert TooDeep();

            treeRoot = element;
            self.roots[d] = treeRoot;

            tree = d;
            rank = 0;
            d += 1;
        }

        top = _link(tree >= 1 ? self.chains[tree - 1] : IV, treeRoot);
        self.chains[tree] = top;

        self.packedRanks = _setRank(r, tree, rank);
        // forge-lint: disable-next-line(unsafe-typecast)
        self.depth = uint8(d);
        self.count += 1;
    }

    /// @notice The commitment to the frontier this MMR holds now, as `LibSkewMmrVerifier.append`
    ///         returns and `LibSkewMmrVerifier.frontierCommitment` recomputes.
    /// @dev The last tree's chain folds every root.
    function root(State storage self) internal view returns (bytes32) {
        uint256 depth = self.depth;
        bytes32 top = depth == 0 ? IV : self.chains[depth - 1];
        return _commit(top, self.packedRanks, depth, self.count);
    }

    function ranks(State storage self, uint256 tree) internal view returns (uint8) {
        return uint8(_rank(self.packedRanks, tree));
    }

    function _link(bytes32 prev, bytes32 treeRoot) internal pure returns (bytes32 chain) {
        assembly ("memory-safe") {
            mstore(0x00, prev)
            mstore(0x20, treeRoot)
            chain := keccak256(0x00, 0x40)
        }
    }

    function _rank(uint256 r, uint256 tree) internal pure returns (uint256) {
        return (r >> (RANK_BITS * tree)) & RANK_MASK;
    }

    function _setRank(uint256 r, uint256 tree, uint256 rank) internal pure returns (uint256) {
        uint256 offset = RANK_BITS * tree;
        return (r & ~(RANK_MASK << offset)) | (rank << offset);
    }

    function _commit(bytes32 top, uint256 packedRanks, uint256 depth, uint256 count)
        internal
        pure
        returns (bytes32 commitment)
    {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, top)
            mstore(add(ptr, 0x20), packedRanks)
            mstore(add(ptr, 0x40), depth)
            mstore(add(ptr, 0x60), count)
            commitment := keccak256(ptr, 0x80)
        }
    }
}
