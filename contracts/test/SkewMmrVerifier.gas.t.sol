// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test, console} from "forge-std/Test.sol";
import {SkewMmrVerifier} from "../src/SkewMmrVerifier.sol";

/// @dev Gas benchmarks. These report rather than assert; run with `-vv` to read them.
contract SkewMmrVerifierGasTest is Test {
    uint256 private constant PUSH = 0;
    uint256 private constant MERGE = 1;
    uint256 private constant GROW = 2;

    SkewMmrVerifier private mmr;

    function setUp() public {
        mmr = new SkewMmrVerifier();
    }

    function test_appendGasProfile() public {
        uint256 n = 4096;
        uint256 total;
        uint256 lo = type(uint256).max;
        uint256 hi;
        uint256[3] memory kindTotal;
        uint256[3] memory kindCount;
        uint256 maxDepth;

        for (uint256 i = 0; i < n; ++i) {
            // Classify the append
            uint256 d = mmr.depth();
            uint256 kind = PUSH;
            if (d >= 2 && mmr.ranks(d - 1) == mmr.ranks(d - 2)) {
                kind = MERGE;
            } else if (d + 1 > maxDepth) {
                kind = GROW;
            }
            if (kind != MERGE && d + 1 > maxDepth) maxDepth = d + 1;

            // Measure append gas cost
            vm.cool(address(mmr));
            uint256 before = gasleft();
            mmr.append(bytes32(i + 1));
            uint256 used = before - gasleft();

            // Update stats
            total += used;
            kindTotal[kind] += used;
            kindCount[kind] += 1;
            if (used < lo) lo = used;
            if (used > hi) hi = used;
        }

        console.log("appends            %s", n);
        console.log("mean gas           %s", total / n);
        console.log("min / max          %s / %s", lo, hi);
        _report("push (reused slot) ", kindTotal[PUSH], kindCount[PUSH]);
        _report("merge              ", kindTotal[MERGE], kindCount[MERGE]);
        _report("push (new max depth)", kindTotal[GROW], kindCount[GROW]);
    }

    function test_verifyGasProfile() public {
        (uint256 shallowGas, uint256 shallowDepth) = _measureVerify(57);
        (uint256 deepGas, uint256 deepDepth) = _measureVerify(4083);
        uint256 perRoot = (deepGas - shallowGas) / (deepDepth - shallowDepth);
        uint256 maxDepth = mmr.MAX_DEPTH();
        uint256 projected = deepGas + perRoot * (maxDepth - deepDepth);

        console.log("depth %s            %s", shallowDepth, shallowGas);
        console.log("depth %s            %s", deepDepth, deepGas);
        console.log("per root            %s", perRoot);
        console.log("depth %s projected  %s", maxDepth, projected);
        console.log("+ calldata          %s", projected + maxDepth * 32 * 16);
    }

    /// @dev Returns the execution gas of one `verifyFrontier` call and the depth it ran at.
    /// Excludes the calldata the caller pays to deliver the frontier.
    function _measureVerify(uint256 n) internal returns (uint256, uint256) {
        // Fill a new MMR with `n` elements
        SkewMmrVerifier target = new SkewMmrVerifier();
        for (uint256 i = 0; i < n; ++i) {
            target.append(bytes32(i + 1));
        }

        // Extract the frontier and state
        uint256 d = target.depth();
        bytes32[] memory frontier = new bytes32[](d);
        for (uint256 i = 0; i < d; ++i) {
            frontier[i] = target.roots(i);
        }
        uint256 anchorState = target.state();

        // Measure verification gas cost
        vm.cool(address(target));
        uint256 before = gasleft();
        target.verifyFrontier(anchorState, frontier);
        return (before - gasleft(), d);
    }

    function _report(string memory label, uint256 total, uint256 count) internal pure {
        if (count == 0) return;
        console.log("%s  n=%s  mean=%s", label, count, total / count);
    }
}
