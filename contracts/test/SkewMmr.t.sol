// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test, console} from "forge-std/Test.sol";
import {SkewMmr} from "../src/SkewMmr.sol";

contract SkewMmrTest is Test {
    SkewMmr private mmr;

    function setUp() public {
        mmr = new SkewMmr();
    }

    function element(uint256 i) internal pure returns (bytes32) {
        return bytes32(1_000_000 + i);
    }

    /// The contract packs all metadata into one slot and writes roots to raw slots it never
    /// zeroes. This rebuilds the whole stack from scratch the obvious way after every append
    /// and checks the two agree.
    function test_matchesReference() public {
        bytes32[] memory refRoots = new bytes32[](33);
        uint256[] memory refRanks = new uint256[](33);
        uint256 refDepth;

        for (uint256 i = 0; i < 300; ++i) {
            mmr.append(element(i));

            if (refDepth >= 2 && refRanks[refDepth - 1] == refRanks[refDepth - 2]) {
                bytes32 root = keccak256(abi.encode(element(i), refRoots[refDepth - 1], refRoots[refDepth - 2]));
                refDepth -= 1;
                refRoots[refDepth - 1] = root;
                refRanks[refDepth - 1] += 1;
            } else {
                refRoots[refDepth] = element(i);
                refRanks[refDepth] = 0;
                refDepth += 1;
            }

            assertEq(mmr.depth(), refDepth, "depth");
            assertEq(mmr.count(), i + 1, "count");
            for (uint256 j = 0; j < refDepth; ++j) {
                assertEq(mmr.roots(j), refRoots[j], "root");
                assertEq(mmr.ranks(j), refRanks[j], "rank");
            }
        }
    }

    /// Ranks strictly decrease except that the top two may tie, and the tree sizes account for
    /// every element.
    function test_rankInvariant() public {
        for (uint256 i = 0; i < 500; ++i) {
            mmr.append(element(i));

            uint256 d = mmr.depth();
            uint256 covered;
            for (uint256 j = 0; j < d; ++j) {
                uint256 rank = mmr.ranks(j);
                covered += (1 << (rank + 1)) - 1;
                if (j + 2 < d) {
                    assertGt(rank, mmr.ranks(j + 1), "ranks must strictly decrease");
                } else if (j + 1 < d) {
                    assertGe(rank, mmr.ranks(j + 1), "top two may tie");
                }
            }
            assertEq(covered, i + 1, "sizes must cover every element");
        }
    }

    /// Matches what the Rust reference measured: max depth is exactly floor(log2(n)).
    function test_depthGrowth() public {
        uint256 maxDepth;
        for (uint256 i = 1; i <= 4096; ++i) {
            mmr.append(element(i));
            if (mmr.depth() > maxDepth) maxDepth = mmr.depth();

            // From n=4 on. At n=2 the stack is two singletons, so depth 2 > floor(log2 2).
            if (i & (i - 1) == 0 && i >= 4) {
                assertEq(maxDepth, log2(i), "max depth should be floor(log2 n)");
                assertEq(mmr.depth(), 2, "a power of two is one full tree plus a singleton");
            }
        }
    }

    /// Gas per append, with genuinely cold storage.
    ///
    /// EIP-2929 warms a slot after its first access in a transaction, so a naive loop would
    /// pay cold prices once and warm prices forever after -- understating a real
    /// one-append-per-tx cost by ~2000 gas each. vm.cool resets that before every append.
    function test_gasProfile() public {
        mmr.count(); // warm the account and the meta slot
        uint256 warmRead = _timeCount();
        vm.cool(address(mmr));
        uint256 coldRead = _timeCount();
        console.log("calibration: warm count() %s gas, cold %s gas, delta %s", warmRead, coldRead, coldRead - warmRead);

        uint256 n = 4096;
        uint256 total;
        uint256 lo = type(uint256).max;
        uint256 hi;
        uint256[3] memory kindTotal;
        uint256[3] memory kindCount;
        uint256 maxDepth;

        for (uint256 i = 0; i < n; ++i) {
            // Classify before cooling, so these reads do not warm the slots the append pays for.
            uint256 d = mmr.depth();
            uint256 kind = 0; // push
            if (d >= 2 && mmr.ranks(d - 1) == mmr.ranks(d - 2)) {
                kind = 1; // combine
            } else if (d + 1 > maxDepth) {
                kind = 2; // push into a slot that has never been written
            }
            if (kind != 1 && d + 1 > maxDepth) maxDepth = d + 1;

            vm.cool(address(mmr));
            uint256 before = gasleft();
            mmr.append(element(i));
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
        _report("push (reused slot) ", kindTotal[0], kindCount[0]);
        _report("combine            ", kindTotal[1], kindCount[1]);
        _report("push (new max depth)", kindTotal[2], kindCount[2]);
    }

    function _report(string memory label, uint256 total, uint256 count) internal pure {
        if (count == 0) return;
        console.log("%s  n=%s  mean=%s", label, count, total / count);
    }

    function _timeCount() internal view returns (uint256) {
        uint256 before = gasleft();
        mmr.count();
        return before - gasleft();
    }

    function log2(uint256 x) internal pure returns (uint256 r) {
        while (x > 1) {
            x >>= 1;
            ++r;
        }
    }
}
