// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {HashChain} from "../src/HashChain.sol";

contract HashChainTest is Test {
    HashChain private chain;

    function setUp() public {
        chain = new HashChain();
    }

    function test_closingABatchReopensTheLevel() public {
        for (uint256 i = 0; i < chain.BATCH(); ++i) {
            chain.append(bytes32(i + 1));
        }

        bytes32[5] memory open = chain.accumulators();
        assertEq(open[0], bytes32(0), "level 0 still open");
        assertTrue(open[1] != bytes32(0), "level 1 never carried");
    }
}
