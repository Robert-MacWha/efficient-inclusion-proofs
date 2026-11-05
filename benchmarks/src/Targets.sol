// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {SkewMmrWithHistory} from "skew-mmr/SkewMmrWithHistory.sol";
import {InternalLeanIMT, LeanIMTData} from "lean-imt/InternalLeanIMT.sol";
import {InternalBinaryIMT, BinaryIMTData} from "imt/internal/InternalBinaryIMT.sol";
import {InternalQuinaryIMT, QuinaryIMTData} from "imt/internal/InternalQuinaryIMT.sol";
import {PoseidonT4} from "poseidon-solidity/PoseidonT4.sol";

import {LeanImtKeccakLib} from "./LeanImtKeccakLib.sol";

/// @dev Common entry point so the benchmark can drive every structure the same way.
interface IInsert {
    function insert(uint256 element) external;
}

/// @notice `SkewMmrWithHistory` as shipped: keccak node hash, frontier committed to a history ring.
contract SkewMmrKeccak is SkewMmrWithHistory, IInsert {
    constructor(uint256 maxDepth, uint256 historySize) SkewMmrWithHistory(maxDepth, historySize) {}

    function insert(uint256 element) external {
        _append(bytes32(element));
    }
}

/// @notice `SkewMmrWithHistory` with a 3-input Poseidon node hash (the hash the circuit uses).
/// @dev The frontier chain and history commitment stay keccak, as in `LibSkewMmr`.
contract SkewMmrPoseidon is SkewMmrKeccak {
    constructor(uint256 maxDepth, uint256 historySize) SkewMmrKeccak(maxDepth, historySize) {}

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

    function root() external view returns (uint256) {
        return tree._root();
    }
}

/// @notice zk-kit's `InternalLeanIMT._insert` with keccak in place of Poseidon.
contract LeanImtKeccak is IInsert {
    using LeanImtKeccakLib for LeanIMTData;

    LeanIMTData internal tree;

    function insert(uint256 leaf) external {
        tree._insert(leaf);
    }
}

/// @notice zk-kit's `InternalBinaryIMT` (`@zk-kit/imt.sol@2.0.0-beta.12`), unmodified: a fixed-depth
///         binary tree padded with zeroes, 2-input Poseidon. Initialised as zk-kit's tests do.
contract BinaryImtPoseidon is IInsert {
    using InternalBinaryIMT for BinaryIMTData;

    BinaryIMTData internal tree;

    constructor(uint256 depth) {
        tree._init(depth, 0);
    }

    function insert(uint256 leaf) external {
        tree._insert(leaf);
    }
}

/// @notice zk-kit's `InternalQuinaryIMT`, unmodified: a fixed-depth 5-ary tree padded with zeroes,
///         5-input Poseidon.
contract QuinaryImtPoseidon is IInsert {
    using InternalQuinaryIMT for QuinaryIMTData;

    QuinaryIMTData internal tree;

    constructor(uint256 depth) {
        tree._init(depth, 0);
    }

    function insert(uint256 leaf) external {
        tree._insert(leaf);
    }
}
