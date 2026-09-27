// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

/// @title Skew-binary MMR
/// @notice Append-only set commitment based on a Merkle Mountain Range (MMR)
///         with skew-binary carry rules for O(1) appends.
contract SkewMmr {
    uint256 public constant MAX_DEPTH = 32;

    /// @dev Stack of tree roots. Sorted by rank, smallest-ranked tree last.
    /// Entries above `depth` are undefined.
    bytes32[MAX_DEPTH] public roots;

    /// @notice Consider merging `ranks`, `depth`, and `count` into a single
    ///         uint256. If we reduce MAX_DEPTH to ~24 we can pack them and save
    ///         on storage reads/writes.
    /// @dev Stack of tree ranks. Entries above `depth` are undefined.
    uint8[MAX_DEPTH] public ranks;

    /// @dev Number of trees on the stack.
    uint256 public depth;

    /// @dev Number of elements appended.
    uint256 public count;

    error TooDeep();

    /// @notice Append an element to the MMR.
    ///
    /// @dev Maximum of 1 hash per append. Follows skew-binary carry rules:
    ///      1. If the two smallest trees have the same rank, merge them into a tree of rank+1.
    ///      2. Otherwise, append the new element as a tree of rank 0.
    function append(bytes32 element) external {
        uint256 d = depth;

        if (d >= 2 && ranks[d - 1] == ranks[d - 2]) {
            //? poseidon2_3(a, b, c) = ~20k gas
            bytes32 root = keccak256(abi.encode(element, roots[d - 1], roots[d - 2]));
            uint8 rank = ranks[d - 1];

            depth = d - 1;
            roots[d - 2] = root;
            ranks[d - 2] = rank + 1;
        } else {
            if (d == MAX_DEPTH) revert TooDeep();

            depth = d + 1;
            roots[d] = element;
            ranks[d] = 0;
        }

        count += 1;
    }
}
