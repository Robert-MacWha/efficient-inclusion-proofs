// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {HashChainVerifier} from "../src/HashChainVerifier.sol";

contract HashChainVerifierTest is Test {
    HashChainVerifier private chain;

    function setUp() public {
        chain = new HashChainVerifier();
    }

    function test_verifiesCommittedAccumulators() public {
        for (uint256 i = 0; i < 200; ++i) {
            chain.append(bytes32(i + 1));
            chain.verifyAccumulators(chain.count(), _accumulators());
        }
    }

    function test_rejectsWrongLength() public {
        _fill(40);

        bytes32[] memory truncated = new bytes32[](chain.DEPTH() - 1);
        uint256 at = chain.count();

        vm.expectRevert(HashChainVerifier.BadAccumulators.selector);
        chain.verifyAccumulators(at, truncated);
    }

    function test_rejectsForgedAccumulator() public {
        _fill(40);
        uint256 at = chain.count();

        for (uint256 l = 0; l < chain.DEPTH(); ++l) {
            bytes32[] memory open = _accumulators();
            open[l] = bytes32(uint256(open[l]) ^ 1);

            vm.expectRevert(HashChainVerifier.UnknownAccumulators.selector);
            chain.verifyAccumulators(at, open);
        }
    }

    function test_rejectsForgedCount() public {
        _fill(40);
        uint256 forgedCount = chain.count() ^ 1;
        bytes32[] memory open = _accumulators();

        vm.expectRevert(HashChainVerifier.UnknownAccumulators.selector);
        chain.verifyAccumulators(forgedCount, open);
    }

    function test_acceptsHistoricAccumulatorsInsideTheWindow() public {
        _fill(40);
        uint256 at = chain.count();
        bytes32[] memory anchor = _accumulators();

        _fill(chain.HISTORY_SIZE() - 1);

        chain.verifyAccumulators(at, anchor);
    }

    function test_rejectsHistoricAccumulatorsPastTheWindow() public {
        _fill(40);
        uint256 at = chain.count();
        bytes32[] memory anchor = _accumulators();

        _fill(chain.HISTORY_SIZE());

        vm.expectRevert(HashChainVerifier.UnknownAccumulators.selector);
        chain.verifyAccumulators(at, anchor);
    }

    function _fill(uint256 n) internal {
        uint256 seed = chain.count();
        for (uint256 i = 0; i < n; ++i) {
            chain.append(bytes32(seed + i + 1));
        }
    }

    function _accumulators() internal view returns (bytes32[] memory open) {
        bytes32[5] memory stored = chain.accumulators();
        open = new bytes32[](stored.length);
        for (uint256 l = 0; l < stored.length; ++l) {
            open[l] = stored[l];
        }
    }
}
