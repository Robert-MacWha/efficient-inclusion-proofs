// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test, console} from "forge-std/Test.sol";
import {HashChainVerifier} from "../src/HashChainVerifier.sol";

contract HashChainVerifierGasTest is Test {
    HashChainVerifier private chain;
    uint256 private batch;
    uint256 private depth;

    function setUp() public {
        chain = new HashChainVerifier();
        batch = chain.BATCH();
        depth = chain.DEPTH();
    }

    function test_appendGasProfile() public {
        uint256 n = 35000;
        uint256 total;
        uint256[] memory levelTotal = new uint256[](depth + 1);
        uint256[] memory levelCount = new uint256[](depth + 1);
        uint256[] memory levelLow = new uint256[](depth + 1);
        uint256[] memory levelHigh = new uint256[](depth + 1);

        for (uint256 i = 0; i < n; ++i) {
            uint256 levels = _levels(i);

            vm.cool(address(chain));
            uint256 before = gasleft();
            chain.append(bytes32(i + 1));
            uint256 used = before - gasleft();

            total += used;
            levelTotal[levels] += used;
            levelCount[levels] += 1;
            if (levelLow[levels] == 0 || used < levelLow[levels]) levelLow[levels] = used;
            if (used > levelHigh[levels]) levelHigh[levels] = used;
        }

        console.log("appends            %s", n);
        console.log("mean gas           %s", total / n);
        for (uint256 l = 1; l <= depth; ++l) {
            _report(l, levelTotal[l], levelCount[l], levelLow[l], levelHigh[l]);
        }
    }

    /// @dev Verification cost does not vary with size.
    function test_verifyGasProfile() public {
        for (uint256 i = 0; i < 4083; ++i) {
            chain.append(bytes32(i + 1));
        }

        bytes32[5] memory stored = chain.accumulators();
        bytes32[] memory open = new bytes32[](stored.length);
        for (uint256 l = 0; l < stored.length; ++l) {
            open[l] = stored[l];
        }
        uint256 at = chain.count();

        vm.cool(address(chain));
        uint256 before = gasleft();
        chain.verifyAccumulators(at, open);
        uint256 used = before - gasleft();

        console.log("execution           %s", used);
        console.log("+ calldata          %s", used + stored.length * 32 * 16);
    }

    function _levels(uint256 i) internal view returns (uint256 levels) {
        levels = 1;
        while (i % batch == batch - 1 && levels < depth) {
            levels += 1;
            i /= batch;
        }
    }

    function _report(uint256 levels, uint256 total, uint256 count, uint256 low, uint256 high) internal pure {
        if (count == 0) return;
        console.log("%s level(s)  n=%s  mean=%s", levels, count, total / count);
        console.log("            min=%s  max=%s", low, high);
    }
}
