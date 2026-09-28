// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test, console} from "forge-std/Test.sol";
import {SkewMmrVerifier} from "../src/SkewMmrVerifier.sol";

contract SkewMmrVerifierTest is Test {
    uint256 private constant PUSH = 0;
    uint256 private constant COMBINE = 1;
    uint256 private constant GROW = 2;

    SkewMmrVerifier private mmr;

    function setUp() public {
        mmr = new SkewMmrVerifier();
    }

    function test_verifiesCommittedFrontier() public {
        for (uint256 i = 0; i < 200; ++i) {
            mmr.append(bytes32(i + 1));
            mmr.verifyFrontier(mmr.state(), _frontier());
        }
    }

    function test_rejectsTruncatedFrontier() public {
        _fill(40);

        bytes32[] memory frontier = _frontier();
        bytes32[] memory truncated = new bytes32[](frontier.length - 1);
        for (uint256 i = 0; i < truncated.length; ++i) {
            truncated[i] = frontier[i];
        }

        uint256 anchorState = mmr.state();

        vm.expectRevert(SkewMmrVerifier.BadFrontier.selector);
        mmr.verifyFrontier(anchorState, truncated);
    }

    function test_rejectsForgedRoot() public {
        _fill(40);
        uint256 anchorState = mmr.state();
        uint256 d = mmr.depth();

        for (uint256 j = 0; j < d; ++j) {
            bytes32[] memory frontier = _frontier();
            frontier[j] = bytes32(uint256(frontier[j]) ^ 1);

            vm.expectRevert(SkewMmrVerifier.UnknownFrontier.selector);
            mmr.verifyFrontier(anchorState, frontier);
        }
    }

    function test_rejectsForgedState() public {
        _fill(40);
        uint256 forgedState = mmr.state() ^ 1;
        bytes32[] memory frontier = _frontier();

        vm.expectRevert(SkewMmrVerifier.UnknownFrontier.selector);
        mmr.verifyFrontier(forgedState, frontier);
    }

    function test_acceptsHistoricFrontierInsideTheWindow() public {
        _fill(40);
        uint256 anchorState = mmr.state();
        bytes32[] memory anchor = _frontier();

        _fill(mmr.HISTORY_SIZE() - 1);

        mmr.verifyFrontier(anchorState, anchor);
    }

    function test_rejectsHistoricFrontierPastTheWindow() public {
        _fill(40);
        uint256 anchorState = mmr.state();
        bytes32[] memory anchor = _frontier();

        _fill(mmr.HISTORY_SIZE());

        vm.expectRevert(SkewMmrVerifier.UnknownFrontier.selector);
        mmr.verifyFrontier(anchorState, anchor);
    }

    function test_gasProfile() public {
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
                kind = COMBINE;
            } else if (d + 1 > maxDepth) {
                kind = GROW;
            }
            if (kind != COMBINE && d + 1 > maxDepth) maxDepth = d + 1;

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
        _report("combine            ", kindTotal[COMBINE], kindCount[COMBINE]);
        _report("push (new max depth)", kindTotal[GROW], kindCount[GROW]);
    }

    function test_verifyGasProfile() public {
        uint256 shallow = _measureVerify(57);
        uint256 deep = _measureVerify(4083);
        uint256 perRoot = (deep - shallow) / 6;

        console.log("depth  5           %s", shallow);
        console.log("depth 11           %s", deep);
        console.log("per root           %s", perRoot);
        console.log("depth 26 projected %s", deep + perRoot * 15);
        console.log("depth 26 sloads    %s", uint256(2100 * 26));
    }

    function _measureVerify(uint256 n) internal returns (uint256) {
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
        return before - gasleft();
    }

    function _fill(uint256 n) internal {
        uint256 seed = mmr.count();
        for (uint256 i = 0; i < n; ++i) {
            mmr.append(bytes32(seed + i + 1));
        }
    }

    function _frontier() internal view returns (bytes32[] memory frontier) {
        uint256 d = mmr.depth();
        frontier = new bytes32[](d);
        for (uint256 i = 0; i < d; ++i) {
            frontier[i] = mmr.roots(i);
        }
    }

    function _report(string memory label, uint256 total, uint256 count) internal pure {
        if (count == 0) return;
        console.log("%s  n=%s  mean=%s", label, count, total / count);
    }
}
