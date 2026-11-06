// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {InternalLeanIMT, LeanIMTData} from "lean-imt/InternalLeanIMT.sol";
import {PoseidonT4} from "poseidon-solidity/PoseidonT4.sol";

import {SkewMmrWithHistory} from "../src/SkewMmrWithHistory.sol";

interface IInsert {
    function insert(uint256 element) external;
}

contract SkewMmrPoseidon is SkewMmrWithHistory, IInsert {
    constructor() SkewMmrWithHistory(26, 64) {}

    function insert(uint256 element) external {
        _append(bytes32(element));
    }

    function _hash(bytes32 a, bytes32 b, bytes32 c) internal pure override returns (bytes32) {
        return bytes32(PoseidonT4.hash([uint256(a), uint256(b), uint256(c)]));
    }
}

contract LeanImtPoseidon is IInsert {
    using InternalLeanIMT for LeanIMTData;

    LeanIMTData internal tree;

    function insert(uint256 leaf) external {
        tree._insert(leaf);
    }
}

/// @dev Writes the gas of each insert into an empty tree to `bench/results/gas-<name>.csv`.
contract LeanImtComparisonGasTest is Test {
    uint256 constant MEMBERS = 1_024;

    function test_skewMmr_gas() public {
        run("skew-mmr", new SkewMmrPoseidon());
    }

    function test_leanImt_gas() public {
        run("leanimt", new LeanImtPoseidon());
    }

    function run(string memory name, IInsert target) internal {
        string memory path = string.concat("../bench/results/gas-", name, ".csv");
        vm.writeFile(path, "members,gas\n");

        for (uint256 n = 1; n <= MEMBERS; ++n) {
            target.insert(n);
            vm.writeLine(path, string.concat(vm.toString(n), ",", vm.toString(vm.lastCallGas().gasTotalUsed)));
        }
    }
}
