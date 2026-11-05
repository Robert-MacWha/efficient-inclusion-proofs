// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test, Vm} from "forge-std/Test.sol";

import {
    IInsert,
    SkewMmrKeccak,
    SkewMmrPoseidon,
    LeanImtKeccak,
    LeanImtPoseidon
} from "../src/Targets.sol";

/// @dev Records the gas of single inserts into an initially empty structure, writing
///      `results/gas/<name>.csv` as `members,gas`, where `members` is the size after the insert.
///
///      Every insert up to `DENSE` members is measured. Beyond that, the structure is filled in bulk
///      (`fill`, many inserts per call) to `WINDOW` short of each checkpoint, and the `WINDOW`
///      inserts ending at the checkpoint are measured one by one.
///
///      With `isolate = true` every call from the test runs as its own transaction, so `gas`
///      (`vm.lastCallGas().gasTotalUsed`) is the whole transaction's gas: the 21,000 base cost,
///      calldata, and cold access to every account and slot touched, including the Poseidon
///      libraries. This is what `hardhat-gas-reporter` reports for zk-kit's own tests.
///
/// forge-config: default.isolate = true
contract InsertGasBench is Test {
    uint256 constant DENSE = 10_000;
    uint256 constant WINDOW = 1_000;
    /// Inserts per `fill` call. Few, large calls keep the fill fast; see `evm_version` in foundry.toml.
    uint256 constant FILL_CHUNK = 2_000;

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

        measure(path, target, 1, DENSE);

        uint256[4] memory checkpoints = [uint256(50_000), 100_000, 500_000, 1_000_000];
        uint256 size = DENSE;
        for (uint256 c = 0; c < checkpoints.length; ++c) {
            uint256 start = checkpoints[c] - WINDOW;
            while (size < start) {
                uint256 count = start - size < FILL_CHUNK ? start - size : FILL_CHUNK;
                target.fill(size + 1, count);
                size += count;
            }
            measure(path, target, start + 1, checkpoints[c]);
            size = checkpoints[c];
        }
    }

    /// Inserts `from..=to` one call each, logging each call's gas.
    function measure(string memory path, IInsert target, uint256 from, uint256 to) internal {
        for (uint256 n = from; n <= to; ++n) {
            target.insert(n);
            Vm.Gas memory gas = vm.lastCallGas();
            vm.writeLine(path, string.concat(vm.toString(n), ",", vm.toString(gas.gasTotalUsed)));
        }
    }
}
