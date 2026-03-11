// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/XcmAssetVerifier.sol";
import "../src/AssetRegistry.sol";
import "../src/MockVerifierPrecompile.sol";
import "../src/MockXcmOracle.sol";

contract XcmAssetVerifierTest is Test {
    XcmAssetVerifier public verifier;
    AssetRegistry public registry;
    MockVerifierPrecompile public precompile;
    MockXcmOracle public oracle;
    address public owner;
    address public randomUser;

    event AssetVerified(
        string indexed assetId, string indexed originChain,
        uint256 amount, uint8 score, bool isVerified
    );
    event XcmQueryCompleted(
        string indexed assetId, uint32 indexed paraId,
        uint256 supply, bytes32 stateHash
    );

    function setUp() public {
        owner = address(this);
        randomUser = makeAddr("randomUser");

        // Deploy all contracts
        registry = new AssetRegistry();
        precompile = new MockVerifierPrecompile();
        oracle = new MockXcmOracle();
        verifier = new XcmAssetVerifier(
            address(registry), address(precompile), address(oracle)
        );

        // Authorize verifier in registry
        registry.setVerifier(address(verifier));

        // Whitelist default minters from MockXcmOracle seed data
        verifier.setMinterWhitelist(address(0xACA1), true);  // Acala aDOT minter
        verifier.setMinterWhitelist(address(0x1B7C), true);  // Interlay iBTC minter
        verifier.setMinterWhitelist(address(0xBF05), true);  // Bifrost vDOT minter
    }

    // ═══════════════════════════════════════════════════════════════════
    // END-TO-END HAPPY PATH
    // ═══════════════════════════════════════════════════════════════════

    function test_e2e_verifyAsset_aDOT_firstCheck() public {
        // First verification: no previous snapshot
        // hash=true (first), supply=true (first), minter=true (whitelisted), history=0
        // Score: 30 + 25 + 30 + 0 = 85
        (bool isVerified, uint8 score, string memory message) =
            verifier.verifyAsset("aDOT", "acala", 1000);

        assertTrue(isVerified);
        assertEq(score, 85);
        assertEq(message, "Asset likely safe, acceptable confidence");
    }

    function test_e2e_verifyAsset_iBTC() public {
        (bool isVerified, uint8 score,) =
            verifier.verifyAsset("iBTC", "interlay", 100);

        assertTrue(isVerified);
        assertEq(score, 85);
    }

    function test_e2e_verifyAsset_vDOT() public {
        (bool isVerified, uint8 score,) =
            verifier.verifyAsset("vDOT", "bifrost", 500);

        assertTrue(isVerified);
        assertEq(score, 85);
    }

    function test_e2e_verifyAsset_xcDOT_unmintedMinter() public {
        // xcDOT minter (0xBEAB) is NOT whitelisted
        // Score: 30 + 0 + 30 + 0 = 60
        (bool isVerified, uint8 score,) =
            verifier.verifyAsset("xcDOT", "moonbeam", 1000);

        assertFalse(isVerified);
        assertEq(score, 60);
    }

    // ═══════════════════════════════════════════════════════════════════
    // SUBSEQUENT VERIFICATION (with history)
    // ═══════════════════════════════════════════════════════════════════

    function test_e2e_secondVerification_sameData() public {
        // First verification
        verifier.verifyAsset("aDOT", "acala", 1000);

        // Second verification — supply unchanged, hash same
        // hash=true, supply=true, minter=true, history=1
        // Score: 30 + 25 + 30 + 15*1/10 = 86
        (, uint8 score2,) = verifier.verifyAsset("aDOT", "acala", 2000);
        assertEq(score2, 86);
    }

    function test_e2e_scoreImprovesWithHistory() public {
        // Build up verification history
        (, uint8 score1,) = verifier.verifyAsset("aDOT", "acala", 100);

        // Verify 9 more times
        for (uint i = 0; i < 9; i++) {
            verifier.verifyAsset("aDOT", "acala", 100);
        }

        // 11th verification: history=10 (capped)
        // Score: 30 + 25 + 30 + 15 = 100
        (, uint8 score11,) = verifier.verifyAsset("aDOT", "acala", 100);

        assertGt(score11, score1);
        assertEq(score11, 100);
    }

    // ═══════════════════════════════════════════════════════════════════
    // ANOMALY DETECTION
    // ═══════════════════════════════════════════════════════════════════

    function test_e2e_anomalyDetection_supplySpike() public {
        // First verification (establishes baseline)
        verifier.verifyAsset("aDOT", "acala", 1000);

        // Inject 10x supply spike via oracle
        oracle.injectAnomaly(2000, "aDOT", 500_000 ether);

        // Second verification — should detect anomaly
        (bool isVerified, uint8 score, string memory message) =
            verifier.verifyAsset("aDOT", "acala", 1000);

        assertFalse(isVerified);
        assertLe(score, 20); // Capped by supply spike
        assertEq(message, "ALERT: Suspicious asset detected. Do not accept.");
    }

    function test_e2e_anomalyDetection_registryStoresAnomaly() public {
        verifier.verifyAsset("aDOT", "acala", 1000);
        oracle.injectAnomaly(2000, "aDOT", 500_000 ether);
        verifier.verifyAsset("aDOT", "acala", 1000);

        AssetRegistry.VerificationResult memory result =
            registry.getVerificationResult("aDOT", "acala");
        assertGt(result.anomalyType, 0); // Should have anomaly type set
        assertLe(result.score, 20);
    }

    // ═══════════════════════════════════════════════════════════════════
    // INPUT VALIDATION
    // ═══════════════════════════════════════════════════════════════════

    function test_verifyAsset_emptyAssetId_reverts() public {
        vm.expectRevert(XcmAssetVerifier.InvalidAssetId.selector);
        verifier.verifyAsset("", "acala", 1000);
    }

    function test_verifyAsset_emptyOriginChain_reverts() public {
        vm.expectRevert(XcmAssetVerifier.InvalidOriginChain.selector);
        verifier.verifyAsset("aDOT", "", 1000);
    }

    function test_verifyAsset_zeroAmount_reverts() public {
        vm.expectRevert(XcmAssetVerifier.InvalidAmount.selector);
        verifier.verifyAsset("aDOT", "acala", 0);
    }

    function test_verifyAsset_unknownChain_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(
            XcmAssetVerifier.ParachainNotSupported.selector, "nonexistent"
        ));
        verifier.verifyAsset("aDOT", "nonexistent", 1000);
    }

    function test_verifyAsset_nonexistentAsset_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(
            XcmAssetVerifier.AssetNotFoundOnChain.selector, "FAKE", "acala"
        ));
        verifier.verifyAsset("FAKE", "acala", 1000);
    }

    // ═══════════════════════════════════════════════════════════════════
    // PAUSE MECHANISM
    // ═══════════════════════════════════════════════════════════════════

    function test_pause_works() public {
        verifier.pause();
        vm.expectRevert(XcmAssetVerifier.ContractPaused.selector);
        verifier.verifyAsset("aDOT", "acala", 1000);
    }

    function test_unpause_works() public {
        verifier.pause();
        verifier.unpause();
        (bool isVerified,,) = verifier.verifyAsset("aDOT", "acala", 1000);
        assertTrue(isVerified);
    }

    // ═══════════════════════════════════════════════════════════════════
    // BATCH VERIFICATION
    // ═══════════════════════════════════════════════════════════════════

    function test_batchVerify_multipleChains() public {
        XcmAssetVerifier.VerificationRequest[] memory requests =
            new XcmAssetVerifier.VerificationRequest[](3);
        requests[0] = XcmAssetVerifier.VerificationRequest("aDOT", "acala", 1000);
        requests[1] = XcmAssetVerifier.VerificationRequest("iBTC", "interlay", 100);
        requests[2] = XcmAssetVerifier.VerificationRequest("xcDOT", "moonbeam", 500);

        XcmAssetVerifier.VerificationResponse[] memory responses =
            verifier.verifyBatchAssets(requests);

        assertEq(responses.length, 3);
        assertTrue(responses[0].isVerified);   // aDOT: whitelisted minter
        assertTrue(responses[1].isVerified);   // iBTC: whitelisted minter
        assertFalse(responses[2].isVerified);  // xcDOT: minter NOT whitelisted
    }

    function test_batchVerify_emptyBatch_reverts() public {
        XcmAssetVerifier.VerificationRequest[] memory requests =
            new XcmAssetVerifier.VerificationRequest[](0);
        vm.expectRevert(XcmAssetVerifier.EmptyBatch.selector);
        verifier.verifyBatchAssets(requests);
    }

    // ═══════════════════════════════════════════════════════════════════
    // REGISTRY INTEGRATION
    // ═══════════════════════════════════════════════════════════════════

    function test_registry_storedAfterVerification() public {
        verifier.verifyAsset("aDOT", "acala", 1000);

        AssetRegistry.VerificationResult memory result =
            registry.getVerificationResult("aDOT", "acala");
        assertEq(result.score, 85);
        assertGt(result.verifiedAt, 0);
        assertTrue(result.proof != bytes32(0));
        assertTrue(registry.isAssetVerified("aDOT", "acala"));
    }

    // ═══════════════════════════════════════════════════════════════════
    // EVENT TESTS
    // ═══════════════════════════════════════════════════════════════════

    function test_event_AssetVerified() public {
        vm.expectEmit(true, true, false, true);
        emit AssetVerified("aDOT", "acala", 1000, 85, true);
        verifier.verifyAsset("aDOT", "acala", 1000);
    }

    function test_event_XcmQueryCompleted() public {
        vm.expectEmit(true, true, false, false);
        emit XcmQueryCompleted("aDOT", 2000, 50_000 ether, bytes32(0));
        verifier.verifyAsset("aDOT", "acala", 1000);
    }

    // ═══════════════════════════════════════════════════════════════════
    // ADMIN TESTS
    // ═══════════════════════════════════════════════════════════════════

    function test_setOracle_byOwner() public {
        MockXcmOracle newOracle = new MockXcmOracle();
        verifier.setOracle(address(newOracle));
        assertEq(address(verifier.xcmOracle()), address(newOracle));
    }

    function test_setOracle_zeroAddress_reverts() public {
        vm.expectRevert(XcmAssetVerifier.ZeroAddress.selector);
        verifier.setOracle(address(0));
    }

    function test_setOracle_byNonOwner_reverts() public {
        vm.prank(randomUser);
        vm.expectRevert(XcmAssetVerifier.Unauthorized.selector);
        verifier.setOracle(address(1));
    }
}
