// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {LibSkewMmr} from "./LibSkewMmr.sol";

library LibSkewMmrVerifier {
    using LibSkewMmr for LibSkewMmr.State;

    error BadFrontier();

    /// @notice Append an element to the MMR.
    /// @dev See `LibSkewMmr.append` for more details.
    ///
    /// @return commitment The history value the caller should record for this append.
    function append(
        LibSkewMmr.State storage self,
        bytes32 element,
        function(bytes32, bytes32, bytes32) internal view returns (bytes32) hash
    ) internal returns (bytes32 commitment) {
        bytes32 top = self.append(element, hash);
        return _commit(top, self.packedRanks, self.depth, self.count);
    }

    /// @notice The history value a caller must hold for `frontier` to have been the frontier
    ///         this MMR held at `count`.
    function frontierCommitment(uint256 packedRanks, uint256 depth, uint256 count, bytes32[] calldata frontier)
        internal
        pure
        returns (bytes32)
    {
        if (frontier.length != depth) revert BadFrontier();

        bytes32 chain = LibSkewMmr.IV;
        for (uint256 i = 0; i < frontier.length; ++i) {
            chain = LibSkewMmr._link(chain, frontier[i]);
        }

        return _commit(chain, packedRanks, depth, count);
    }

    /// @notice The history value for the frontier this MMR holds now.
    /// @dev The last tree's chain folds every root, so it is the top `append` returns.
    function currentCommitment(LibSkewMmr.State storage self) internal view returns (bytes32) {
        uint256 depth = self.depth;
        bytes32 top = depth == 0 ? LibSkewMmr.IV : self.chains[depth - 1];
        return _commit(top, self.packedRanks, depth, self.count);
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
