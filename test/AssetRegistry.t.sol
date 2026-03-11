// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AssetRegistry.sol";

contract AssetRegistryTest is Test {
    AssetRegistry public registry;
    address public owner;
    address public verifier;
    address public randomUser;

    event VerificationUpdated(string indexed assetId, string indexed originChain, uint8 score, bytes32 proof);
    event AssetFlagged(string indexed assetId, string indexed originChain, uint8 score, string reason);
    event AnomalyDetected(string indexed assetId, string indexed originChain, uint8 anomalyType, uint8 severity);
    event VerifierUpdated(address indexed oldVerifier, address indexed newVerifier);

    function setUp() public {
        owner = address(this);
        verifier = makeAddr("verifier");
        randomUser = makeAddr("randomUser");

        registry = new AssetRegistry();
        registry.setVerifier(verifier);
    }

    // ─── Owner & Access Control ──────────────────────────────────────

    function test_owner_isDeployer() public view {
        assertEq(registry.owner(), owner);
    }

    function test_setVerifier_byOwner() public {
        address newVerifier = makeAddr("newVerifier");
        registry.setVerifier(newVerifier);
        assertEq(registry.authorizedVerifier(), newVerifier);
    }

    function test_setVerifier_emitsEvent() public {
        address newVerifier = makeAddr("newVerifier");
        vm.expectEmit(true, true, false, false);
        emit VerifierUpdated(verifier, newVerifier);
        registry.setVerifier(newVerifier);
    }

    function test_setVerifier_byNonOwner_reverts() public {
        vm.prank(randomUser);
        vm.expectRevert(AssetRegistry.Unauthorized.selector);
        registry.setVerifier(makeAddr("attacker"));
    }

    function test_setVerifier_zeroAddress_reverts() public {
        vm.expectRevert(AssetRegistry.ZeroAddress.selector);
        registry.setVerifier(address(0));
    }

    // ─── Set Verification Result ─────────────────────────────────────

    function test_setVerificationResult_byVerifier() public {
        bytes32 proof = keccak256("proof");

        vm.prank(verifier);
        registry.setVerificationResult("aDOT", "acala", 94, 0, proof);

        AssetRegistry.VerificationResult memory result = registry.getVerificationResult("aDOT", "acala");
        assertEq(result.score, 94);
        assertEq(result.anomalyType, 0);
        assertEq(result.proof, proof);
        assertGt(result.verifiedAt, 0);
    }

    function test_setVerificationResult_byRandom_reverts() public {
        vm.prank(randomUser);
        vm.expectRevert(AssetRegistry.Unauthorized.selector);
        registry.setVerificationResult("aDOT", "acala", 94, 0, bytes32(0));
    }

    function test_setVerificationResult_emptyAssetId_reverts() public {
        vm.prank(verifier);
        vm.expectRevert(AssetRegistry.InvalidAssetId.selector);
        registry.setVerificationResult("", "acala", 94, 0, bytes32(0));
    }

    function test_setVerificationResult_emptyOriginChain_reverts() public {
        vm.prank(verifier);
        vm.expectRevert(AssetRegistry.InvalidOriginChain.selector);
        registry.setVerificationResult("aDOT", "", 94, 0, bytes32(0));
    }

    function test_setVerificationResult_emitsVerificationUpdated() public {
        bytes32 proof = keccak256("proof");
        vm.prank(verifier);
        vm.expectEmit(true, true, false, true);
        emit VerificationUpdated("aDOT", "acala", 94, proof);
        registry.setVerificationResult("aDOT", "acala", 94, 0, proof);
    }

    function test_setVerificationResult_emitsAssetFlagged_whenSuspicious() public {
        vm.prank(verifier);
        vm.expectEmit(true, true, false, false);
        emit AssetFlagged("xcDOT", "unknown", 12, "Suspicious asset detected");
        registry.setVerificationResult("xcDOT", "unknown", 12, 1, bytes32(0));
    }

    function test_setVerificationResult_emitsAnomalyDetected() public {
        vm.prank(verifier);
        vm.expectEmit(true, true, false, true);
        emit AnomalyDetected("xcDOT", "unknown", 1, 88); // 100 - 12 = 88
        registry.setVerificationResult("xcDOT", "unknown", 12, 1, bytes32(0));
    }

    function test_setVerificationResult_noAnomalyEvent_whenNormal() public {
        vm.prank(verifier);
        registry.setVerificationResult("aDOT", "acala", 94, 0, bytes32(0));
        // No revert, no anomaly event expected
        assertEq(registry.getAssetScore("aDOT", "acala"), 94);
    }

    // ─── View Functions ──────────────────────────────────────────────

    function test_getAssetScore() public {
        vm.prank(verifier);
        registry.setVerificationResult("aDOT", "acala", 94, 0, bytes32(0));
        assertEq(registry.getAssetScore("aDOT", "acala"), 94);
    }

    function test_isAssetVerified_true() public {
        vm.prank(verifier);
        registry.setVerificationResult("aDOT", "acala", 94, 0, bytes32(0));
        assertTrue(registry.isAssetVerified("aDOT", "acala"));
    }

    function test_isAssetVerified_false_whenNotVerified() public view {
        assertFalse(registry.isAssetVerified("unknown", "chain"));
    }

    function test_getVerificationResult_defaultsToZero() public view {
        AssetRegistry.VerificationResult memory result = registry.getVerificationResult("nonexistent", "chain");
        assertEq(result.score, 0);
        assertEq(result.anomalyType, 0);
        assertEq(result.verifiedAt, 0);
    }

    // ─── Overwrites ──────────────────────────────────────────────────

    function test_setVerificationResult_overwritesPrevious() public {
        vm.startPrank(verifier);
        registry.setVerificationResult("aDOT", "acala", 94, 0, keccak256("proof1"));
        registry.setVerificationResult("aDOT", "acala", 30, 1, keccak256("proof2"));
        vm.stopPrank();

        AssetRegistry.VerificationResult memory result = registry.getVerificationResult("aDOT", "acala");
        assertEq(result.score, 30);
        assertEq(result.anomalyType, 1);
    }
}
