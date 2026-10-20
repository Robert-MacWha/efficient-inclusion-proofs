// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {SkewMmrWithHistory} from "../src/SkewMmrWithHistory.sol";
import {LibSkewMmr} from "../src/lib/LibSkewMmr.sol";

contract SkewMmrSkaffold is SkewMmrWithHistory {
    constructor(uint256 maxDepth, uint256 historySize) SkewMmrWithHistory(maxDepth, historySize) {}

    function append(bytes32 element) public {
        super._append(element);
    }

    function appendBatch(bytes32[] calldata elements) public {
        for (uint256 i = 0; i < elements.length; ++i) {
            super._appendWithoutHistory(elements[i]);
        }
        super._recordHistory();
    }

    /// @dev Appends `n` elements in one call, so a benchmark can reach steady state
    ///      without its warmup showing up under `append`.
    function fill(uint256 n) public {
        uint256 seed = mmr.count;
        for (uint256 i = 0; i < n; ++i) {
            super._append(bytes32(seed + i + 1));
        }
    }

    function root() public view returns (bytes32) {
        return LibSkewMmr.root(mmr);
    }

    function frontier() public view returns (uint256 ranks, uint256 depth_, uint256 count_, bytes32[] memory roots_) {
        depth_ = mmr.depth;
        roots_ = new bytes32[](depth_);
        for (uint256 i = 0; i < depth_; ++i) {
            roots_[i] = mmr.roots[i];
        }
        return (mmr.packedRanks, depth_, mmr.count, roots_);
    }
}
