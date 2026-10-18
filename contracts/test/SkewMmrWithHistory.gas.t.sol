// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {SkewMmrSkaffold} from "./SkewMmrSkaffold.sol";

/// @dev Gas benchmarks.
/// forge-config: default.isolate = false
contract SkewMmrWithHistoryGasTest is Test {
    SkewMmrSkaffold mmr;

    function setUp() public {
        mmr = new SkewMmrSkaffold(26, 64);
        // Wrap the history ring once, so every measured append overwrites a slot.
        mmr.fill(mmr.HISTORY_SIZE());
    }

    function test_append_gas() public {
        for (uint256 i = 0; i < 10000; ++i) {
            vm.cool(address(mmr));
            mmr.append(bytes32(i + 1));
        }
    }

    function test_appendBatch_gas() public {
        bytes32[] memory batch = new bytes32[](3);
        for (uint256 i = 0; i < 10000; i += 3) {
            for (uint256 j = 0; j < 3; ++j) {
                batch[j] = bytes32(i + j + 1);
            }
            vm.cool(address(mmr));
            mmr.appendBatch(batch);
        }
    }

    /// @dev Verify cost grows with the frontier depth; min/max span the depths reached.
    function test_verifyFrontier_gas() public {
        for (uint256 i = 0; i < 10000; ++i) {
            vm.cool(address(mmr));
            mmr.append(bytes32(i + 1));
            (uint256 ranks, uint256 depth, uint256 count, bytes32[] memory roots) = mmr.frontier();

            vm.cool(address(mmr));
            mmr.verifyFrontier(ranks, depth, count, roots);
        }
    }
}
