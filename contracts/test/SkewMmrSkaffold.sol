// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {SkewMmrWithHistory} from "../src/SkewMmrWithHistory.sol";

contract SkewMmrSkaffold is SkewMmrWithHistory {
    constructor(uint256 maxDepth, uint256 historySize) SkewMmrWithHistory(maxDepth, historySize) {}

    function append(bytes32 element) public {
        super._append(element);
    }
}
