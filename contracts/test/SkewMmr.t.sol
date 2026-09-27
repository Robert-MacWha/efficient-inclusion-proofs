// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test, console} from "forge-std/Test.sol";
import {SkewMmr} from "../src/SkewMmr.sol";

contract SkewMmrTest is Test {
    uint256 private constant PUSH = 0;
    uint256 private constant COMBINE = 1;
    uint256 private constant GROW = 2;

    SkewMmr private mmr;

    function setUp() public {
        mmr = new SkewMmr();
    }

    function test_ranksDecreaseExceptTheTopPair() public {
        for (uint256 i = 0; i < 500; ++i) {
            mmr.append(bytes32(i));

            uint256 d = mmr.depth();
            for (uint256 j = 0; j + 1 < d; ++j) {
                if (j + 2 < d) {
                    assertGt(mmr.ranks(j), mmr.ranks(j + 1), "ranks must strictly decrease");
                } else {
                    assertGe(mmr.ranks(j), mmr.ranks(j + 1), "top two may tie");
                }
            }
        }
    }

    function test_treeSizesCoverEveryElement() public {
        for (uint256 i = 0; i < 500; ++i) {
            mmr.append(bytes32(i));

            uint256 covered;
            for (uint256 j = 0; j < mmr.depth(); ++j) {
                covered += (1 << (mmr.ranks(j) + 1)) - 1;
            }
            assertEq(covered, i + 1);
        }
    }

    function test_depthPeaksAtLog2OfCount() public {
        uint256 peak;
        for (uint256 i = 1; i <= 4096; ++i) {
            mmr.append(bytes32(i));
            if (mmr.depth() > peak) peak = mmr.depth();

            // n=2 is two singletons, so depth only tracks log2 from n=4 on.
            if (i & (i - 1) == 0 && i >= 4) assertEq(peak, log2(i));
        }
    }

    function test_powerOfTwoHoldsOneFullTreeAndASingleton() public {
        for (uint256 i = 1; i <= 4096; ++i) {
            mmr.append(bytes32(i));
            if (i & (i - 1) == 0 && i >= 2) assertEq(mmr.depth(), 2);
        }
    }

    /// Gas per append against cold storage. Without `vm.cool` a loop would measure warm slots.
    function test_gasProfile() public {
        uint256 n = 4096;
        uint256 total;
        uint256 lo = type(uint256).max;
        uint256 hi;
        uint256[3] memory kindTotal;
        uint256[3] memory kindCount;
        uint256 maxDepth;

        // Elements are never zero: a zero root leaves its slot zero and skews the SSTORE cost.
        for (uint256 i = 0; i < n; ++i) {
            // Classify first: these reads would warm the slots the append is measured on.
            uint256 d = mmr.depth();
            uint256 kind = PUSH;
            if (d >= 2 && mmr.ranks(d - 1) == mmr.ranks(d - 2)) {
                kind = COMBINE;
            } else if (d + 1 > maxDepth) {
                kind = GROW;
            }
            if (kind != COMBINE && d + 1 > maxDepth) maxDepth = d + 1;

            vm.cool(address(mmr));
            uint256 before = gasleft();
            mmr.append(bytes32(i + 1));
            uint256 used = before - gasleft();

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
        _report("combine            ", kindTotal[COMBINE], kindCount[COMBINE]);
        _report("push (new max depth)", kindTotal[GROW], kindCount[GROW]);
    }

    function _report(string memory label, uint256 total, uint256 count) internal pure {
        if (count == 0) return;
        console.log("%s  n=%s  mean=%s", label, count, total / count);
    }

    function log2(uint256 x) internal pure returns (uint256 r) {
        while (x > 1) {
            x >>= 1;
            ++r;
        }
    }
}
