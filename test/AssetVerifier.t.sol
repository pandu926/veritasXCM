// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AssetVerifier.sol";
import "../src/AssetRegistry.sol";
import "../src/MockVerifierPrecompile.sol";
import "../src/VerifierBase.sol";

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

    // ===================================================================
    // HELPER
    // ===================================================================

    function _setupSnapshot(
        string memory assetId,
        string memory originChain,
        uint256 supply,
        address minter,
        bytes32 stateHash
    ) internal {
        verifier.setAssetSnapshot(assetId, originChain, supply, minter, stateHash);
    }

    function _skipCooldown() internal {
        skip(verifier.VERIFICATION_COOLDOWN_PERIOD() + 1);
    }

    // ===================================================================
    // INPUT VALIDATION TESTS
    // ===================================================================

    function test_verifyAsset_emptyAssetId_reverts() public {
        vm.expectRevert(VerifierBase.InvalidAssetId.selector);
        verifier.verifyAsset("", "acala", 1000);
    }

    function test_verifyAsset_emptyOriginChain_reverts() public {
        vm.expectRevert(VerifierBase.InvalidOriginChain.selector);
        verifier.verifyAsset("aDOT", "", 1000);
    }

    function test_verifyAsset_zeroAmount_reverts() public {
        vm.expectRevert(VerifierBase.InvalidAmount.selector);
        verifier.verifyAsset("aDOT", "acala", 0);
    }

    function test_verifyAsset_stringTooLong_reverts() public {
        string memory longStr = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"; // 67 chars
        bytes32 stateHash = keccak256(abi.encodePacked(longStr, "acala", uint256(50000)));
        vm.expectRevert(VerifierBase.StringTooLong.selector);
        verifier.verifyAsset(longStr, "acala", 1000);
    }

    // ===================================================================
    // PAUSE MECHANISM TESTS
    // ===================================================================

    function test_pause_byOwner() public {
        verifier.pause();
        assertTrue(verifier.paused());
    }

    function test_pause_byNonOwner_reverts() public {
        vm.prank(randomUser);
        vm.expectRevert(VerifierBase.Unauthorized.selector);
        verifier.pause();
    }

    function test_verifyAsset_whenPaused_reverts() public {
        bytes32 stateHash = keccak256(abi.encodePacked("aDOT", "acala", uint256(50000)));
        _setupSnapshot("aDOT", "acala", 50000, minterAlice, stateHash);
        _skipCooldown();

        verifier.pause();
        vm.expectRevert(VerifierBase.ContractPaused.selector);
        verifier.verifyAsset("aDOT", "acala", 1000);
    }

    function test_verifyAsset_afterUnpause_works() public {
        bytes32 stateHash = keccak256(abi.encodePacked("aDOT", "acala", uint256(50000)));
        _setupSnapshot("aDOT", "acala", 50000, minterAlice, stateHash);
        _skipCooldown();

        verifier.pause();
        verifier.unpause();
        (bool isVerified,,) = verifier.verifyAsset("aDOT", "acala", 1000);
        assertTrue(isVerified);
    }

    // ===================================================================
    // PRECOMPILE-BASED VERIFICATION TESTS
    // ===================================================================

    function test_precompile_verifyWithSnapshot_allGood() public {
        // Setup: matching hash, whitelisted minter, stable supply
        bytes32 stateHash = keccak256(abi.encodePacked("testDOT", "testChain", uint256(50000)));
        _setupSnapshot("testDOT", "testChain", 50000, minterAlice, stateHash);
        _skipCooldown();

        (bool isVerified, uint8 score,) = verifier.verifyAsset("testDOT", "testChain", 1000);

        // With matching hash, whitelisted minter, no anomaly, 0 history:
        // supply(30) + minter(25) + hash(30) + history(0) = 85
        assertTrue(isVerified);
        assertEq(score, 85);
    }

    function test_precompile_verifyWithSnapshot_unmatchedHash() public {
        // Hash mismatch: stateHash != computed hash
        _setupSnapshot("testDOT", "testChain", 50000, minterAlice, bytes32(uint256(999)));
        _skipCooldown();

        (, uint8 score,) = verifier.verifyAsset("testDOT", "testChain", 1000);

        // supply(30) + minter(25) + hash(0) + history(0) = 55
        assertEq(score, 55);
    }

    function test_precompile_verifyWithSnapshot_unauthorizedMinter() public {
        address unknownMinter = makeAddr("unknownMinter");
        bytes32 stateHash = keccak256(abi.encodePacked("testDOT", "testChain", uint256(50000)));
        _setupSnapshot("testDOT", "testChain", 50000, unknownMinter, stateHash);
        _skipCooldown();

        (, uint8 score,) = verifier.verifyAsset("testDOT", "testChain", 1000);

        // supply(30) + minter(0) + hash(30) + history(0) = 60
        assertEq(score, 60);
    }

    function test_precompile_verifyWithSnapshot_allBad() public {
        address unknownMinter = makeAddr("unknownMinter");
        _setupSnapshot("testDOT", "testChain", 50000, unknownMinter, bytes32(uint256(999)));
        _skipCooldown();

        (, uint8 score, string memory message) = verifier.verifyAsset("testDOT", "testChain", 1000);

        // supply(30) + minter(0) + hash(0) + history(0) = 30
        assertEq(score, 30);
        assertEq(message, "ALERT: Suspicious asset detected. Do not accept.");
    }

    function test_precompile_verificationCount_increments() public {
        bytes32 stateHash = keccak256(abi.encodePacked("testDOT", "testChain", uint256(50000)));
        _setupSnapshot("testDOT", "testChain", 50000, minterAlice, stateHash);
        _skipCooldown();

        // First verification
        verifier.verifyAsset("testDOT", "testChain", 1000);
        (, , , , , uint256 count1) = verifier.assetSnapshots("testDOT", "testChain");
        assertEq(count1, 1);

        // Second verification (skip cooldown)
        _skipCooldown();
        verifier.verifyAsset("testDOT", "testChain", 2000);
        (, , , , , uint256 count2) = verifier.assetSnapshots("testDOT", "testChain");
        assertEq(count2, 2);
    }

    function test_precompile_historyImprovesScore() public {
        bytes32 stateHash = keccak256(abi.encodePacked("testDOT", "testChain", uint256(50000)));
        _setupSnapshot("testDOT", "testChain", 50000, minterAlice, stateHash);
        _skipCooldown();

        // First verification: history=0 -> score = 85
        (, uint8 score1,) = verifier.verifyAsset("testDOT", "testChain", 1000);

        // After several more verifications, history builds up
        for (uint256 i = 0; i < 9; i++) {
            _skipCooldown();
            verifier.verifyAsset("testDOT", "testChain", 1000);
        }

        // 11th verification: history=10 -> score includes full history weight
        _skipCooldown();
        (, uint8 score10,) = verifier.verifyAsset("testDOT", "testChain", 1000);

        assertGt(score10, score1);
    }

    // ===================================================================
    // COOLDOWN TESTS
    // ===================================================================

    function test_verifyAsset_cooldown_reverts() public {
        bytes32 stateHash = keccak256(abi.encodePacked("testDOT", "testChain", uint256(50000)));
        _setupSnapshot("testDOT", "testChain", 50000, minterAlice, stateHash);
        _skipCooldown();

        verifier.verifyAsset("testDOT", "testChain", 1000);

        // Attempt immediately — should revert
        vm.expectRevert(VerifierBase.VerificationCooldown.selector);
        verifier.verifyAsset("testDOT", "testChain", 1000);
    }

    function test_verifyAsset_afterCooldown_works() public {
        bytes32 stateHash = keccak256(abi.encodePacked("testDOT", "testChain", uint256(50000)));
        _setupSnapshot("testDOT", "testChain", 50000, minterAlice, stateHash);
        _skipCooldown();

        verifier.verifyAsset("testDOT", "testChain", 1000);
        _skipCooldown();
        (bool isVerified,,) = verifier.verifyAsset("testDOT", "testChain", 1000);
        assertTrue(isVerified);
    }

    // ===================================================================
    // SNAPSHOT MANAGEMENT TESTS
    // ===================================================================

    function test_setAssetSnapshot_byOwner() public {
        bytes32 hash = bytes32(uint256(1));
        verifier.setAssetSnapshot("aDOT", "acala", 50000, minterAlice, hash);

        (uint256 supply, uint256 prevSupply, address minter, bytes32 stateHash, uint256 lastChecked, uint256 count) =
            verifier.assetSnapshots("aDOT", "acala");

        assertEq(supply, 50000);
        assertEq(minter, minterAlice);
        assertEq(stateHash, hash);
        assertGt(lastChecked, 0);
        assertEq(count, 0);
    }

    function test_setAssetSnapshot_byNonOwner_reverts() public {
        vm.prank(randomUser);
        vm.expectRevert(VerifierBase.Unauthorized.selector);
        verifier.setAssetSnapshot("aDOT", "acala", 50000, minterAlice, bytes32(uint256(1)));
    }

    function test_setAssetSnapshot_emptyAssetId_reverts() public {
        vm.expectRevert(VerifierBase.InvalidAssetId.selector);
        verifier.setAssetSnapshot("", "acala", 50000, minterAlice, bytes32(uint256(1)));
    }

    function test_setAssetSnapshot_emptyOriginChain_reverts() public {
        vm.expectRevert(VerifierBase.InvalidOriginChain.selector);
        verifier.setAssetSnapshot("aDOT", "", 50000, minterAlice, bytes32(uint256(1)));
    }

    function test_setAssetSnapshot_zeroMinter_reverts() public {
        vm.expectRevert(VerifierBase.ZeroAddress.selector);
        verifier.setAssetSnapshot("aDOT", "acala", 50000, address(0), bytes32(uint256(1)));
    }

    function test_setAssetSnapshot_zeroHash_reverts() public {
        vm.expectRevert(VerifierBase.InvalidAssetId.selector);
        verifier.setAssetSnapshot("aDOT", "acala", 50000, minterAlice, bytes32(0));
    }

    function test_setAssetSnapshot_emitsEvent() public {
        bytes32 hash = bytes32(uint256(42));
        vm.expectEmit(true, true, false, true);
        emit SnapshotUpdated("aDOT", "acala", 50000, hash);
        verifier.setAssetSnapshot("aDOT", "acala", 50000, minterAlice, hash);
    }

    function test_setAssetSnapshot_updatesPreviousSupply() public {
        bytes32 hash1 = bytes32(uint256(1));
        bytes32 hash2 = bytes32(uint256(2));
        verifier.setAssetSnapshot("aDOT", "acala", 50000, minterAlice, hash1);
        verifier.setAssetSnapshot("aDOT", "acala", 60000, minterAlice, hash2);

        (uint256 supply, uint256 prevSupply, , , ,) = verifier.assetSnapshots("aDOT", "acala");
        assertEq(supply, 60000);
        assertEq(prevSupply, 50000);
    }

    // ===================================================================
    // MINTER WHITELIST TESTS
    // ===================================================================

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
        vm.expectRevert(VerifierBase.Unauthorized.selector);
        verifier.setMinterWhitelist(makeAddr("minter"), true);
    }

    // ===================================================================
    // PRECOMPILE UPDATE TESTS
    // ===================================================================

    function test_setPrecompile_byOwner() public {
        MockVerifierPrecompile newPrecompile = new MockVerifierPrecompile();
        verifier.setPrecompile(address(newPrecompile));
        assertEq(address(verifier.precompile()), address(newPrecompile));
    }

    function test_setPrecompile_zeroAddress_reverts() public {
        vm.expectRevert(VerifierBase.ZeroAddress.selector);
        verifier.setPrecompile(address(0));
    }

    // ===================================================================
    // BATCH VERIFICATION TESTS
    // ===================================================================

    function test_verifyBatchAssets_works() public {
        bytes32 stateHash1 = keccak256(abi.encodePacked("testDOT", "testChain", uint256(50000)));
        bytes32 stateHash2 = keccak256(abi.encodePacked("testBTC", "testChain2", uint256(21000)));
        _setupSnapshot("testDOT", "testChain", 50000, minterAlice, stateHash1);
        _setupSnapshot("testBTC", "testChain2", 21000, minterAlice, stateHash2);
        _skipCooldown();

        VerifierBase.VerificationRequest[] memory requests = new VerifierBase.VerificationRequest[](2);
        requests[0] = VerifierBase.VerificationRequest("testDOT", "testChain", 1000);
        requests[1] = VerifierBase.VerificationRequest("testBTC", "testChain2", 500);

        VerifierBase.VerificationResponse[] memory responses = verifier.verifyBatchAssets(requests);

        assertEq(responses.length, 2);
        assertTrue(responses[0].isVerified);
        assertEq(responses[0].score, 85);
        assertTrue(responses[1].isVerified);
        assertEq(responses[1].score, 85);
    }

    function test_verifyBatchAssets_emptyBatch_reverts() public {
        VerifierBase.VerificationRequest[] memory requests = new VerifierBase.VerificationRequest[](0);
        vm.expectRevert(VerifierBase.EmptyBatch.selector);
        verifier.verifyBatchAssets(requests);
    }

    function test_verifyBatchAssets_tooLarge_reverts() public {
        VerifierBase.VerificationRequest[] memory requests = new VerifierBase.VerificationRequest[](21);
        for (uint256 i = 0; i < 21; i++) {
            requests[i] = VerifierBase.VerificationRequest("test", "chain", 100);
        }
        vm.expectRevert(VerifierBase.BatchTooLarge.selector);
        verifier.verifyBatchAssets(requests);
    }

    // ===================================================================
    // INTEGRATION: REGISTRY STORAGE
    // ===================================================================

    function test_registryUpdated_afterPrecompileVerification() public {
        bytes32 stateHash = keccak256(abi.encodePacked("testDOT", "testChain", uint256(50000)));
        _setupSnapshot("testDOT", "testChain", 50000, minterAlice, stateHash);
        _skipCooldown();

        verifier.verifyAsset("testDOT", "testChain", 1000);

        AssetRegistry.VerificationResult memory result = registry.getVerificationResult("testDOT", "testChain");
        assertEq(result.score, 85);
        assertTrue(registry.isAssetVerified("testDOT", "testChain"));
    }

    // ===================================================================
    // EVENT TESTS
    // ===================================================================

    function test_event_AssetVerified_emitted() public {
        bytes32 stateHash = keccak256(abi.encodePacked("testDOT", "testChain", uint256(50000)));
        _setupSnapshot("testDOT", "testChain", 50000, minterAlice, stateHash);
        _skipCooldown();

        vm.expectEmit(true, true, false, true);
        emit AssetVerified("testDOT", "testChain", 1000, 85, true);
        verifier.verifyAsset("testDOT", "testChain", 1000);
    }
}
