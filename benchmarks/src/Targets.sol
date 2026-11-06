// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {SkewMmrWithHistory} from "skew-mmr/SkewMmrWithHistory.sol";
import {InternalLeanIMT, LeanIMTData} from "lean-imt/InternalLeanIMT.sol";
import {PoseidonT4} from "poseidon-solidity/PoseidonT4.sol";

interface IInsert {
    function insert(uint256 element) external;
}

/// @notice `SkewMmrWithHistory` with a 3-input Poseidon node hash.
contract SkewMmrPoseidon is SkewMmrWithHistory, IInsert {
    constructor(uint256 maxDepth, uint256 historySize) SkewMmrWithHistory(maxDepth, historySize) {}

    function insert(uint256 element) external {
        _append(bytes32(element));
    }

    function _hash(bytes32 a, bytes32 b, bytes32 c) internal pure override returns (bytes32) {
        return bytes32(PoseidonT4.hash([uint256(a), uint256(b), uint256(c)]));
    }
}

/// @notice zk-kit's `InternalLeanIMT`, unmodified (2-input Poseidon).
contract LeanImtPoseidon is IInsert {
    using InternalLeanIMT for LeanIMTData;

    LeanIMTData internal tree;

    function insert(uint256 leaf) external {
        tree._insert(leaf);
    }
}
