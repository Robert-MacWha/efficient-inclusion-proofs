// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {HashChainVerifier} from "../src/HashChainVerifier.sol";

/// @dev Gas benchmarks.
/// forge-config: default.isolate = false
contract HashChainVerifierGasTest is Test {
    HashChainVerifier private chain;

    function setUp() public {
        chain = new HashChainVerifier();
    }

    function test_append_gas() public {
        for (uint256 i = 0; i < 10000; ++i) {
            vm.cool(address(chain));
            chain.append(bytes32(i + 1));
        }
    }

    function test_verifyAccumulators_gas() public {
        for (uint256 i = 0; i < 4096; ++i) {
            vm.cool(address(chain));
            chain.append(bytes32(i + 1));
            bytes32[5] memory stored = chain.accumulators();
            bytes32[] memory open = new bytes32[](stored.length);
            for (uint256 l = 0; l < stored.length; ++l) {
                open[l] = stored[l];
            }

            vm.cool(address(chain));
            chain.verifyAccumulators(chain.count(), open);
        }
    }
}
