// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {SkewMmr} from "../src/SkewMmr.sol";

contract SkewMmrTest is Test {
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

    function test_ranksAboveDepthAreZero() public {
        for (uint256 i = 0; i < 500; ++i) {
            mmr.append(bytes32(i + 1));

            for (uint256 j = mmr.depth(); j < mmr.MAX_DEPTH(); ++j) {
                assertEq(mmr.ranks(j), 0, "stale rank above depth");
            }
        }
    }

    function test_mergesAtDepthTwo() public {
        mmr.append(bytes32(uint256(1)));
        mmr.append(bytes32(uint256(2)));
        assertEq(mmr.depth(), 2);

        mmr.append(bytes32(uint256(3)));
        assertEq(mmr.depth(), 1);
    }
}
