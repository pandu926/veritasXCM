// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AssetVerifier.sol";
import "../src/AssetRegistry.sol";
import "../src/MockVerifierPrecompile.sol";

contract AssetVerifierTest is Test {
    AssetVerifier public verifier;
    AssetRegistry public registry;
    MockVerifierPrecompile public precompile;
    address public owner;
    address public randomUser;
    address public minterAlice;

    event AssetVerified(
        string indexed assetId,
        string indexed originChain,
        uint256 amount,
        uint8 score,
        bool isVerified
    );
    event SnapshotUpdated(
        string indexed assetId,
        string indexed originChain,
        uint256 supply,
        bytes32 stateHash
    );
    event ContractPausedEvent(address indexed by);
    event ContractUnpausedEvent(address indexed by);

    function setUp() public {
        owner = address(this);
        randomUser = makeAddr("randomUser");
        minterAlice = makeAddr("minterAlice");

        // Deploy all contracts
        registry = new AssetRegistry();
        precompile = new MockVerifierPrecompile();
        verifier = new AssetVerifier(address(registry), address(precompile));

        // Authorize verifier
        registry.setVerifier(address(verifier));

        // Whitelist a minter
        verifier.setMinterWhitelist(minterAlice, true);
    }

    // ═══════════════════════════════════════════════════════════════════
    // MOCK FALLBACK TESTS (no snapshot — Phase 1 compatibility)
    // ═══════════════════════════════════════════════════════════════════

    function test_mockFallback_aDOT_returnsHighScore() public {
        (bool isVerified, uint8 score, string memory message) = verifier.verifyAsset("aDOT", "acala", 1000);
        assertTrue(isVerified);
        assertEq(score, 94);
        assertEq(message, "Asset legitimate, high confidence");
    }

    function test_mockFallback_iBTC_returnsLikelySafe() public {
        (bool isVerified, uint8 score,) = verifier.verifyAsset("iBTC", "interlay", 500);
        assertTrue(isVerified);
        assertEq(score, 88);
    }

    function test_mockFallback_vDOT_returnsAcceptable() public {
        (bool isVerified, uint8 score,) = verifier.verifyAsset("vDOT", "bifrost", 2000);
        assertTrue(isVerified);
        assertEq(score, 75);
    }

    function test_mockFallback_xcDOT_returnsSuspicious() public {
        (bool isVerified, uint8 score,) = verifier.verifyAsset("xcDOT", "unknown", 10000);
        assertFalse(isVerified);
        assertEq(score, 12);
    }

    function test_mockFallback_unknown_returnsUncertain() public {
        (bool isVerified, uint8 score,) = verifier.verifyAsset("RANDOM", "chain", 100);
        assertFalse(isVerified);
        assertEq(score, 50);
    }

    // ═══════════════════════════════════════════════════════════════════
    // INPUT VALIDATION TESTS
    // ═══════════════════════════════════════════════════════════════════

    function test_verifyAsset_emptyAssetId_reverts() public {
        vm.expectRevert(AssetVerifier.InvalidAssetId.selector);
        verifier.verifyAsset("", "acala", 1000);
    }

    function test_verifyAsset_emptyOriginChain_reverts() public {
        vm.expectRevert(AssetVerifier.InvalidOriginChain.selector);
        verifier.verifyAsset("aDOT", "", 1000);
    }

    function test_verifyAsset_zeroAmount_reverts() public {
        vm.expectRevert(AssetVerifier.InvalidAmount.selector);
        verifier.verifyAsset("aDOT", "acala", 0);
    }

    // ═══════════════════════════════════════════════════════════════════
    // PAUSE MECHANISM TESTS
    // ═══════════════════════════════════════════════════════════════════

    function test_pause_byOwner() public {
        verifier.pause();
        assertTrue(verifier.paused());
    }

    function test_pause_byNonOwner_reverts() public {
        vm.prank(randomUser);
        vm.expectRevert(AssetVerifier.Unauthorized.selector);
        verifier.pause();
    }

    function test_verifyAsset_whenPaused_reverts() public {
        verifier.pause();
        vm.expectRevert(AssetVerifier.ContractPaused.selector);
        verifier.verifyAsset("aDOT", "acala", 1000);
    }

    function test_verifyAsset_afterUnpause_works() public {
        verifier.pause();
        verifier.unpause();
        (bool isVerified,,) = verifier.verifyAsset("aDOT", "acala", 1000);
        assertTrue(isVerified);
    }

    // ═══════════════════════════════════════════════════════════════════
    // PRECOMPILE-BASED VERIFICATION TESTS
    // ═══════════════════════════════════════════════════════════════════

    function _setupSnapshot(
        string memory assetId,
        string memory originChain,
        uint256 supply,
        address minter,
        bytes32 stateHash
    ) internal {
        verifier.setAssetSnapshot(assetId, originChain, supply, minter, stateHash);
    }

    function test_precompile_verifyWithSnapshot_allGood() public {
        // Setup: matching hash, whitelisted minter, stable supply
        bytes32 stateHash = keccak256(abi.encodePacked("testDOT", "testChain", uint256(50000)));
        _setupSnapshot("testDOT", "testChain", 50000, minterAlice, stateHash);

        (bool isVerified, uint8 score,) = verifier.verifyAsset("testDOT", "testChain", 1000);

        // With matching hash, whitelisted minter, no anomaly, 0 history:
        // supply(30) + minter(25) + hash(30) + history(0) = 85
        assertTrue(isVerified);
        assertEq(score, 85);
    }

    function test_precompile_verifyWithSnapshot_unmatchedHash() public {
        // Hash mismatch: stateHash != computed hash
        _setupSnapshot("testDOT", "testChain", 50000, minterAlice, bytes32(uint256(999)));

        (, uint8 score,) = verifier.verifyAsset("testDOT", "testChain", 1000);

        // supply(30) + minter(25) + hash(0) + history(0) = 55
        assertEq(score, 55);
    }

    function test_precompile_verifyWithSnapshot_unauthorizedMinter() public {
        address unknownMinter = makeAddr("unknownMinter");
        bytes32 stateHash = keccak256(abi.encodePacked("testDOT", "testChain", uint256(50000)));
        _setupSnapshot("testDOT", "testChain", 50000, unknownMinter, stateHash);

        (, uint8 score,) = verifier.verifyAsset("testDOT", "testChain", 1000);

        // supply(30) + minter(0) + hash(30) + history(0) = 60
        assertEq(score, 60);
    }

    function test_precompile_verifyWithSnapshot_allBad() public {
        address unknownMinter = makeAddr("unknownMinter");
        _setupSnapshot("testDOT", "testChain", 50000, unknownMinter, bytes32(uint256(999)));

        (, uint8 score, string memory message) = verifier.verifyAsset("testDOT", "testChain", 1000);

        // supply(30) + minter(0) + hash(0) + history(0) = 30
        assertEq(score, 30);
        assertEq(message, "ALERT: Suspicious asset detected. Do not accept.");
    }

    function test_precompile_verificationCount_increments() public {
        bytes32 stateHash = keccak256(abi.encodePacked("testDOT", "testChain", uint256(50000)));
        _setupSnapshot("testDOT", "testChain", 50000, minterAlice, stateHash);

        // First verification
        verifier.verifyAsset("testDOT", "testChain", 1000);
        (, , , , uint32 count1) = verifier.assetSnapshots("testDOT", "testChain");
        assertEq(count1, 1);

        // Second verification
        verifier.verifyAsset("testDOT", "testChain", 2000);
        (, , , , uint32 count2) = verifier.assetSnapshots("testDOT", "testChain");
        assertEq(count2, 2);
    }

    function test_precompile_historyImprovesScore() public {
        bytes32 stateHash = keccak256(abi.encodePacked("testDOT", "testChain", uint256(50000)));
        _setupSnapshot("testDOT", "testChain", 50000, minterAlice, stateHash);

        // First verification: history=0 → score = 85
        (, uint8 score1,) = verifier.verifyAsset("testDOT", "testChain", 1000);

        // After several more verifications, history builds up
        for (uint256 i = 0; i < 9; i++) {
            verifier.verifyAsset("testDOT", "testChain", 1000);
        }

        // 10th verification: history=10 → score includes full history weight
        (, uint8 score10,) = verifier.verifyAsset("testDOT", "testChain", 1000);

        assertGt(score10, score1);
    }

    // ═══════════════════════════════════════════════════════════════════
    // SNAPSHOT MANAGEMENT TESTS
    // ═══════════════════════════════════════════════════════════════════

    function test_setAssetSnapshot_byOwner() public {
        verifier.setAssetSnapshot("aDOT", "acala", 50000, minterAlice, bytes32(uint256(1)));

        (uint256 supply, address minter, bytes32 hash, uint256 lastChecked, uint32 count) =
            verifier.assetSnapshots("aDOT", "acala");

        assertEq(supply, 50000);
        assertEq(minter, minterAlice);
        assertEq(hash, bytes32(uint256(1)));
        assertGt(lastChecked, 0);
        assertEq(count, 0);
    }

    function test_setAssetSnapshot_byNonOwner_reverts() public {
        vm.prank(randomUser);
        vm.expectRevert(AssetVerifier.Unauthorized.selector);
        verifier.setAssetSnapshot("aDOT", "acala", 50000, minterAlice, bytes32(0));
    }

    function test_setAssetSnapshot_emptyAssetId_reverts() public {
        vm.expectRevert(AssetVerifier.InvalidAssetId.selector);
        verifier.setAssetSnapshot("", "acala", 50000, minterAlice, bytes32(0));
    }

    function test_setAssetSnapshot_emitsEvent() public {
        bytes32 hash = bytes32(uint256(42));
        vm.expectEmit(true, true, false, true);
        emit SnapshotUpdated("aDOT", "acala", 50000, hash);
        verifier.setAssetSnapshot("aDOT", "acala", 50000, minterAlice, hash);
    }

    // ═══════════════════════════════════════════════════════════════════
    // MINTER WHITELIST TESTS
    // ═══════════════════════════════════════════════════════════════════

    function test_setMinterWhitelist_byOwner() public {
        address newMinter = makeAddr("newMinter");
        verifier.setMinterWhitelist(newMinter, true);
        assertTrue(verifier.whitelistedMinters(newMinter));
    }

    function test_setMinterWhitelist_remove() public {
        verifier.setMinterWhitelist(minterAlice, false);
        assertFalse(verifier.whitelistedMinters(minterAlice));
    }

    function test_setMinterWhitelist_byNonOwner_reverts() public {
        vm.prank(randomUser);
        vm.expectRevert(AssetVerifier.Unauthorized.selector);
        verifier.setMinterWhitelist(makeAddr("minter"), true);
    }

    // ═══════════════════════════════════════════════════════════════════
    // PRECOMPILE UPDATE TESTS
    // ═══════════════════════════════════════════════════════════════════

    function test_setPrecompile_byOwner() public {
        MockVerifierPrecompile newPrecompile = new MockVerifierPrecompile();
        verifier.setPrecompile(address(newPrecompile));
        assertEq(address(verifier.precompile()), address(newPrecompile));
    }

    function test_setPrecompile_zeroAddress_reverts() public {
        vm.expectRevert(AssetVerifier.ZeroAddress.selector);
        verifier.setPrecompile(address(0));
    }

    // ═══════════════════════════════════════════════════════════════════
    // BATCH VERIFICATION TESTS
    // ═══════════════════════════════════════════════════════════════════

    function test_verifyBatchAssets_mixMockAndPrecompile() public {
        // Setup one asset with snapshot, one without
        bytes32 stateHash = keccak256(abi.encodePacked("testDOT", "testChain", uint256(50000)));
        _setupSnapshot("testDOT", "testChain", 50000, minterAlice, stateHash);

        AssetVerifier.VerificationRequest[] memory requests = new AssetVerifier.VerificationRequest[](2);
        requests[0] = AssetVerifier.VerificationRequest("testDOT", "testChain", 1000); // precompile
        requests[1] = AssetVerifier.VerificationRequest("aDOT", "acala", 1000);        // mock fallback

        AssetVerifier.VerificationResponse[] memory responses = verifier.verifyBatchAssets(requests);

        assertEq(responses.length, 2);
        assertTrue(responses[0].isVerified);  // precompile: score 85
        assertEq(responses[0].score, 85);
        assertTrue(responses[1].isVerified);  // mock: score 94
        assertEq(responses[1].score, 94);
    }

    function test_verifyBatchAssets_emptyBatch_reverts() public {
        AssetVerifier.VerificationRequest[] memory requests = new AssetVerifier.VerificationRequest[](0);
        vm.expectRevert(AssetVerifier.EmptyBatch.selector);
        verifier.verifyBatchAssets(requests);
    }

    // ═══════════════════════════════════════════════════════════════════
    // INTEGRATION: REGISTRY STORAGE
    // ═══════════════════════════════════════════════════════════════════

    function test_registryUpdated_afterMockVerification() public {
        verifier.verifyAsset("aDOT", "acala", 1000);

        AssetRegistry.VerificationResult memory result = registry.getVerificationResult("aDOT", "acala");
        assertEq(result.score, 94);
        assertEq(result.anomalyType, 0);
        assertGt(result.verifiedAt, 0);
    }

    function test_registryUpdated_afterPrecompileVerification() public {
        bytes32 stateHash = keccak256(abi.encodePacked("testDOT", "testChain", uint256(50000)));
        _setupSnapshot("testDOT", "testChain", 50000, minterAlice, stateHash);

        verifier.verifyAsset("testDOT", "testChain", 1000);

        AssetRegistry.VerificationResult memory result = registry.getVerificationResult("testDOT", "testChain");
        assertEq(result.score, 85);
        assertTrue(registry.isAssetVerified("testDOT", "testChain"));
    }

    // ═══════════════════════════════════════════════════════════════════
    // EVENT TESTS
    // ═══════════════════════════════════════════════════════════════════

    function test_event_AssetVerified_emitted() public {
        vm.expectEmit(true, true, false, true);
        emit AssetVerified("aDOT", "acala", 1000, 94, true);
        verifier.verifyAsset("aDOT", "acala", 1000);
    }
}
