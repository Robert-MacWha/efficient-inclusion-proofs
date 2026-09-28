// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {SkewMmr} from "../src/SkewMmr.sol";

contract SkewMmrTest is Test {
    SkewMmr private mmr;

    function setUp() public {
        mmr = new SkewMmr();
    }

    function test_ranksAboveDepthAreZero() public {
        for (uint256 i = 0; i < 500; ++i) {
            mmr.append(bytes32(i + 1));

            for (uint256 j = mmr.depth(); j < mmr.MAX_DEPTH(); ++j) {
                assertEq(mmr.ranks(j), 0, "stale rank above depth");
            }
        }
    }
}
