// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {
    LeanIMTData,
    LeafGreaterThanSnarkScalarField,
    LeafCannotBeZero,
    LeafAlreadyExists
} from "lean-imt/InternalLeanIMT.sol";
import {SNARK_SCALAR_FIELD} from "lean-imt/Constants.sol";

/// @notice Copy of `InternalLeanIMT._insert` from `@zk-kit/lean-imt.sol@2.0.1`, with
///         `PoseidonT3.hash([a, b])` replaced by `keccak256(abi.encode(a, b))`. Nothing else differs.
library LeanImtKeccakLib {
    function _insert(LeanIMTData storage self, uint256 leaf) internal returns (uint256) {
        if (leaf >= SNARK_SCALAR_FIELD) {
            revert LeafGreaterThanSnarkScalarField();
        } else if (leaf == 0) {
            revert LeafCannotBeZero();
        } else if (self.leaves[leaf] != 0) {
            revert LeafAlreadyExists();
        }

        uint256 index = self.size;
        uint256 treeDepth = self.depth;

        if (2 ** treeDepth < index + 1) {
            ++treeDepth;
        }

        self.depth = treeDepth;

        uint256 node = leaf;

        for (uint256 level = 0; level < treeDepth;) {
            if ((index >> level) & 1 == 1) {
                node = uint256(keccak256(abi.encode(self.sideNodes[level], node)));
            } else {
                self.sideNodes[level] = node;
            }

            unchecked {
                ++level;
            }
        }

        self.size = ++index;

        self.sideNodes[treeDepth] = node;
        self.leaves[leaf] = index;

        return node;
    }
}
