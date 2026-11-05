// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test, Vm} from "forge-std/Test.sol";

import {
    IInsert,
    SkewMmrKeccak,
    SkewMmrPoseidon,
    LeanImtKeccak,
    LeanImtPoseidon,
    BinaryImtPoseidon,
    QuinaryImtPoseidon
} from "../src/Targets.sol";

/// @dev Records the gas of every single insert into an initially empty structure, writing
///      `results/gas/<name>.csv` as `members,gas`, where `members` is the size after the insert.
///
///      With `isolate = true` every call from the test runs as its own transaction, so `gas`
///      (`vm.lastCallGas().gasTotalUsed`) is the whole transaction's gas: the 21,000 base cost,
///      calldata, and cold access to every account and slot touched, including the Poseidon
///      libraries. This is what `hardhat-gas-reporter` reports for zk-kit's own tests.
///
/// forge-config: default.isolate = true
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

    function test_binaryImt16() public {
        run("binary-imt-16-poseidon", new BinaryImtPoseidon(16));
    }

    function test_binaryImt32() public {
        run("binary-imt-32-poseidon", new BinaryImtPoseidon(32));
    }

    function test_quinaryImt7() public {
        run("quinary-imt-7-poseidon", new QuinaryImtPoseidon(7));
    }

    function test_quinaryImt14() public {
        run("quinary-imt-14-poseidon", new QuinaryImtPoseidon(14));
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
