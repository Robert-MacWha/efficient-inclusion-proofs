// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test, Vm} from "forge-std/Test.sol";

import {IInsert, SkewMmrPoseidon, LeanImtPoseidon} from "../src/Targets.sol";

/// @dev Records the gas of each insert into an empty tree, as `members,gas` in
///      `results/gas/<name>.csv`. Every call runs as its own transaction (`isolate`), so `gas` is
///      whole-transaction gas.
///
/// forge-config: default.isolate = true
contract InsertGasBench is Test {
    uint256 constant MEMBERS = 1_024;

    /// Matches `contracts/test/SkewMmrWithHistory.gas.t.sol`.
    uint256 constant MAX_DEPTH = 26;
    uint256 constant HISTORY_SIZE = 64;

    function test_skewMmr() public {
        run("skew-mmr", new SkewMmrPoseidon(MAX_DEPTH, HISTORY_SIZE));
    }

    function test_leanImt() public {
        run("leanimt", new LeanImtPoseidon());
    }

    function run(string memory name, IInsert target) internal {
        string memory path = string.concat("results/gas/", name, ".csv");
        vm.writeFile(path, "members,gas\n");

        for (uint256 n = 1; n <= MEMBERS; ++n) {
            target.insert(n);
            Vm.Gas memory gas = vm.lastCallGas();
            vm.writeLine(path, string.concat(vm.toString(n), ",", vm.toString(gas.gasTotalUsed)));
        }
    }
}
