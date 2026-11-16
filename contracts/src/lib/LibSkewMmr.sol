// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

library LibSkewMmr {
    /// The most trees a frontier can hold, which a `uint64` count never exceeds.
    uint256 internal constant MAX_TREES = 64;

    /// @dev Initial value for the tree folding chain. Non-zero, so that the chain of an empty
    ///      frontier never equals an unwritten storage slot.
    bytes32 internal constant IV = bytes32(uint256(1));

    struct State {
        /// @dev The frontier: tree roots, smallest-ranked last. Entries above `depth` are undefined.
        bytes32[MAX_TREES] roots;

        /// @dev `chains[i]` folds `roots[0..i]`. Entries above `depth` are undefined.
        bytes32[MAX_TREES] chains;

        uint64 count;
        uint8 depth;

        /// @dev Bit `k` is set when the frontier holds a tree of rank `k`.
        uint64 ranks;

        /// @dev Whether the two smallest trees have the same rank.
        bool doubled;
    }

    error TooDeep();

    /// @notice Append an element to the MMR.
    /// @return top The chain folding every root of the resulting frontier.
    ///
    /// @param element The new elelment to append to the MMR.
    /// @param hash Merges a new element with the two roots it subsumes into a new tree root.
    ///
    /// @dev Exactly 1 hash per append. Follows skew-binary carry rules:
    ///      1. If the two smallest trees have the same rank, merge them into a tree of rank+1.
    ///      2. Otherwise, append the new element as a tree of rank 0, `hash(element, 0, 0)`.
    ///
    ///      Every node, leaf or not, is `hash(element, left, right)`, so no node can pass as an
    ///      element in an inclusion proof.
    ///
    ///      Either branch writes `roots[tree]`, and `chains[tree - 1]` is stable across it.
    function append(
        State storage self,
        bytes32 element,
        function(bytes32, bytes32, bytes32) internal view returns (bytes32) hash
    ) internal returns (bytes32 top) {
        uint256 d = self.depth;
        uint256 r = self.ranks;
        uint256 tree;
        // The bit of `ranks` for the new tree.
        uint256 rank;
        bytes32 treeRoot;

        if (self.doubled) {
            treeRoot = hash(element, self.roots[d - 1], self.roots[d - 2]);

            uint256 smallest = r & (~r + 1);
            r ^= smallest;

            tree = d - 2;
            rank = smallest << 1;
            d -= 1;
        } else {
            if (d == MAX_TREES) revert TooDeep();

            treeRoot = hash(element, bytes32(0), bytes32(0));

            tree = d;
            rank = 1;
            d += 1;
        }

        self.roots[tree] = treeRoot;
        top = _link(tree >= 1 ? self.chains[tree - 1] : IV, treeRoot);
        self.chains[tree] = top;

        self.doubled = r & rank != 0;
        // forge-lint: disable-next-line(unsafe-typecast)
        self.ranks = uint64(r | rank);
        // forge-lint: disable-next-line(unsafe-typecast)
        self.depth = uint8(d);
        self.count += 1;
    }

    /// @notice The commitment to the frontier this MMR holds now, as `append` returns and
    ///         `fold` recomputes.
    /// @dev The last tree's chain folds every root.
    function root(State storage self) internal view returns (bytes32) {
        uint256 depth = self.depth;
        return depth == 0 ? IV : self.chains[depth - 1];
    }

    /// @notice The commitment to `frontier`, which equals `root` when `frontier` holds the
    ///         MMR's roots in order.
    function fold(bytes32[] calldata frontier) internal pure returns (bytes32 chain) {
        chain = IV;
        for (uint256 i = 0; i < frontier.length; ++i) {
            chain = _link(chain, frontier[i]);
        }
    }

    function _link(bytes32 prev, bytes32 treeRoot) internal pure returns (bytes32 chain) {
        assembly ("memory-safe") {
            mstore(0x00, prev)
            mstore(0x20, treeRoot)
            chain := keccak256(0x00, 0x40)
        }
    }
}
