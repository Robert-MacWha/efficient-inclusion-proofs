// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {SkewMmrVerifier} from "../src/SkewMmrVerifier.sol";
import {LibSkewMmr} from "../src/lib/LibSkewMmr.sol";
import {LibSkewMmrVerifier} from "../src/lib/LibSkewMmrVerifier.sol";

contract SkewMmrVerifierTest is Test {
    uint256 private constant MAX_DEPTH = LibSkewMmr.MAX_TREES;

    uint256 private constant SHALLOW_DEPTH = 4;
    uint256 private constant SHALLOW_CAPACITY = 26;

    SkewMmrVerifier private mmr;

    function setUp() public {
        mmr = new SkewMmrVerifier(MAX_DEPTH);
    }

    function test_verifiesCommittedFrontier() public {
        for (uint256 i = 0; i < 200; ++i) {
            mmr.append(bytes32(i + 1));
            assert(mmr.verifyFrontier(mmr.packedRanks(), mmr.depth(), mmr.count(), _frontier()));
        }
    }

    function test_rejectsTruncatedFrontier() public {
        _fill(40);

        bytes32[] memory frontier = _frontier();
        bytes32[] memory truncated = new bytes32[](frontier.length - 1);
        for (uint256 i = 0; i < truncated.length; ++i) {
            truncated[i] = frontier[i];
        }

        uint256 anchorRanks = mmr.packedRanks();
        uint256 anchorDepth = mmr.depth();
        uint256 anchorCount = mmr.count();

        vm.expectRevert(LibSkewMmrVerifier.BadFrontier.selector);
        mmr.verifyFrontier(anchorRanks, anchorDepth, anchorCount, truncated);
    }

    function test_rejectsForgedRoot() public {
        _fill(40);
        uint256 anchorRanks = mmr.packedRanks();
        uint256 d = mmr.depth();
        uint256 anchorCount = mmr.count();

        for (uint256 j = 0; j < d; ++j) {
            bytes32[] memory frontier = _frontier();
            frontier[j] = bytes32(uint256(frontier[j]) ^ 1);

            assert(!mmr.verifyFrontier(anchorRanks, d, anchorCount, frontier));
        }
    }

    function test_rejectsForgedRanks() public {
        _fill(40);
        uint256 forgedRanks = mmr.packedRanks() ^ 1;
        bytes32[] memory frontier = _frontier();

        assert(!mmr.verifyFrontier(forgedRanks, mmr.depth(), mmr.count(), frontier));
    }

    function test_rejectsForgedCount() public {
        _fill(40);
        uint256 forgedCount = mmr.count() + mmr.HISTORY_SIZE();
        bytes32[] memory frontier = _frontier();

        assert(!mmr.verifyFrontier(mmr.packedRanks(), mmr.depth(), forgedCount, frontier));
    }

    function test_acceptsHistoricFrontierInsideTheWindow() public {
        _fill(40);
        uint256 anchorRanks = mmr.packedRanks();
        uint256 anchorDepth = mmr.depth();
        uint256 anchorCount = mmr.count();
        bytes32[] memory anchor = _frontier();

        _fill(mmr.HISTORY_SIZE() - 1);

        assert(mmr.verifyFrontier(anchorRanks, anchorDepth, anchorCount, anchor));
    }

    function test_rejectsHistoricFrontierPastTheWindow() public {
        _fill(40);
        uint256 anchorRanks = mmr.packedRanks();
        uint256 anchorDepth = mmr.depth();
        uint256 anchorCount = mmr.count();
        bytes32[] memory anchor = _frontier();

        _fill(mmr.HISTORY_SIZE());

        assert(!mmr.verifyFrontier(anchorRanks, anchorDepth, anchorCount, anchor));
    }

    function test_rejectsAppendsPastMaxDepth() public {
        SkewMmrVerifier shallow = new SkewMmrVerifier(SHALLOW_DEPTH);

        for (uint256 i = 0; i < SHALLOW_CAPACITY; ++i) {
            shallow.append(bytes32(i + 1));
        }

        vm.expectRevert(LibSkewMmr.TooDeep.selector);
        shallow.append(bytes32(SHALLOW_CAPACITY + 1));
    }

    function test_rejectsAMaxDepthAboveTheRankWord() public {
        vm.expectRevert(LibSkewMmr.TooDeep.selector);
        new SkewMmrVerifier(MAX_DEPTH + 1);
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
}
