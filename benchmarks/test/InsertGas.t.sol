// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test, Vm} from "forge-std/Test.sol";

import {IInsert, SkewMmrKeccak, SkewMmrPoseidon, LeanImtKeccak, LeanImtPoseidon} from "../src/Targets.sol";

/// @dev Records the gas of every single insert into an initially empty structure, writing
///      `results/gas/<name>.csv` as `members,gas`, where `members` is the size after the insert.
///
///      `gas` is the execution gas of the `insert` call (`vm.lastCallGas().gasTotalUsed`), with the
///      target's storage cooled before each call so every insert pays cold-access costs as its own
///      transaction would. It excludes the 21,000 base cost, calldata, and the cold access to the
///      target account, which are identical across structures.
///
/// forge-config: default.isolate = false
contract InsertGasBench is Test {
    uint256 constant MEMBERS = 10_000;

    /// Matches `contracts/test/SkewMmrWithHistory.gas.t.sol`.
    uint256 constant MAX_DEPTH = 26;
    uint256 constant HISTORY_SIZE = 64;

    function test_skewMmrKeccak() public {
        run("skew-mmr-keccak", new SkewMmrKeccak(MAX_DEPTH, HISTORY_SIZE));
    }

    function test_skewMmrPoseidon() public {
        run("skew-mmr-poseidon", new SkewMmrPoseidon(MAX_DEPTH, HISTORY_SIZE));
    }

    function test_leanImtKeccak() public {
        run("leanimt-keccak", new LeanImtKeccak());
    }

    function test_leanImtPoseidon() public {
        run("leanimt-poseidon", new LeanImtPoseidon());
    }

    function run(string memory name, IInsert target) internal {
        string memory path = string.concat("results/gas/", name, ".csv");
        vm.writeFile(path, "members,gas\n");

        for (uint256 n = 1; n <= MEMBERS; ++n) {
            vm.cool(address(target));
            target.insert(n);
            Vm.Gas memory gas = vm.lastCallGas();
            vm.writeLine(path, string.concat(vm.toString(n), ",", vm.toString(gas.gasTotalUsed)));
        }
    }
}
