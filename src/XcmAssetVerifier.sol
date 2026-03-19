// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./AssetRegistry.sol";
import "./IVerifierPrecompile.sol";
import "./IXcmOracle.sol";
import "./VerifierBase.sol";

/// @title XcmAssetVerifier
/// @notice End-to-end trustless asset verifier using XCM queries + Rust precompile
/// @dev Phase 3: Automatically fetches data from parachains via XCM oracle,
///      verifies via precompile, and stores results in registry.
contract XcmAssetVerifier is VerifierBase {
    // ─── Additional Errors ────────────────────────────────────────────
    error ParachainNotSupported(string chainName);
    error AssetNotFoundOnChain(string assetId, string originChain);
    error StaleOracleData();
    error InvalidMaxDataAge();

    // ─── State Variables ─────────────────────────────────────────────
    uint256 public maxDataAge;

    AssetRegistry public immutable registry;
    IVerifierPrecompile public precompile;
    IXcmOracle public xcmOracle;

    // ─── Previous Snapshot (for anomaly detection) ───────────────────
    struct PreviousSnapshot {
        uint256 supply;
        bytes32 stateHash;
        uint256 timestamp;
        uint256 verificationCount;
    }

    /// @notice assetId => paraId => previous snapshot
    mapping(string => mapping(uint32 => PreviousSnapshot)) public previousSnapshots;

    /// @notice minterAddress => isWhitelisted
    mapping(address => bool) public whitelistedMinters;

    // ─── Events ──────────────────────────────────────────────────────
    event AssetVerified(
        string indexed assetId,
        string indexed originChain,
        uint256 amount,
        uint8 score,
        bool isVerified
    );
    event XcmQueryCompleted(
        string indexed assetId,
        uint32 indexed paraId,
        uint256 supply,
        bytes32 stateHash
    );
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);

    // ─── Constructor ─────────────────────────────────────────────────
    /// @param _registry Address of AssetRegistry
    /// @param _precompile Address of VerifierPrecompile (mock or real)
    /// @param _xcmOracle Address of XCM Oracle (mock or real)
    constructor(address _registry, address _precompile, address _xcmOracle) VerifierBase() {
        registry = AssetRegistry(_registry);
        precompile = IVerifierPrecompile(_precompile);
        xcmOracle = IXcmOracle(_xcmOracle);
        maxDataAge = 30 days;
    }

    // ─── Admin Functions ─────────────────────────────────────────────

    function setOracle(address _newOracle) external onlyOwner {
        if (_newOracle == address(0)) revert ZeroAddress();
        address old = address(xcmOracle);
        xcmOracle = IXcmOracle(_newOracle);
        emit OracleUpdated(old, _newOracle);
    }

    function setMaxDataAge(uint256 _maxDataAge) external onlyOwner {
        if (_maxDataAge < 1 hours) revert InvalidMaxDataAge();
        maxDataAge = _maxDataAge;
    }

    function setPrecompile(address _newPrecompile) external onlyOwner {
        if (_newPrecompile == address(0)) revert ZeroAddress();
        address old = address(precompile);
        precompile = IVerifierPrecompile(_newPrecompile);
        emit PrecompileUpdated(old, _newPrecompile);
    }

    function setMinterWhitelist(address minter, bool status) external onlyOwner {
        whitelistedMinters[minter] = status;
        emit MinterWhitelisted(minter, status);
    }

    // ─── Core Verification (End-to-End) ──────────────────────────────

    /// @notice Verify a cross-chain asset end-to-end via XCM + precompile
    /// @dev Flow: resolve chain -> XCM query -> compare with previous -> score -> registry
    function verifyAsset(
        string memory assetId,
        string memory originChain,
        uint256 amount
    ) public whenNotPaused returns (bool isVerified, uint8 score, string memory message) {
        _validateInputs(assetId, originChain, amount);

        // Step 1: Resolve chain name -> paraId
        uint32 paraId = xcmOracle.getParachainId(originChain);
        if (paraId == 0) revert ParachainNotSupported(originChain);

        // Step 2: XCM Query — fetch current asset state
        IXcmOracle.AssetState memory currentState = xcmOracle.queryAssetState(paraId, assetId);
        if (!currentState.exists) revert AssetNotFoundOnChain(assetId, originChain);

        // Step 3: Enforce oracle data freshness
        if (currentState.timestamp > 0 && block.timestamp > currentState.timestamp + maxDataAge) {
            revert StaleOracleData();
        }

        emit XcmQueryCompleted(assetId, paraId, currentState.totalSupply, currentState.stateHash);

        // Step 4: Load previous snapshot
        PreviousSnapshot storage prev = previousSnapshots[assetId][paraId];

        // Step 5: Enforce cooldown
        if (prev.timestamp > 0) {
            if (block.timestamp < prev.timestamp + VERIFICATION_COOLDOWN_PERIOD) {
                revert VerificationCooldown();
            }
        }

        // Step 6: Verification via precompile
        uint8 anomalyType;
        (isVerified, score, message, anomalyType) = _verifyWithPrecompile(currentState, prev);

        // Step 7: Store result in registry
        bytes32 proof = keccak256(abi.encodePacked(
            assetId, originChain, amount, currentState.stateHash, block.number, block.timestamp
        ));
        registry.setVerificationResult(assetId, originChain, score, anomalyType, proof);

        // Step 8: Update previous snapshot
        prev.supply = currentState.totalSupply;
        prev.stateHash = currentState.stateHash;
        prev.timestamp = block.timestamp;
        if (isVerified) {
            prev.verificationCount++;
        }

        // Step 9: Emit
        emit AssetVerified(assetId, originChain, amount, score, isVerified);

        return (isVerified, score, message);
    }

    /// @notice Verify multiple assets in a single transaction
    function verifyBatchAssets(
        VerificationRequest[] memory requests
    ) external whenNotPaused returns (VerificationResponse[] memory responses) {
        if (requests.length == 0) revert EmptyBatch();
        if (requests.length > MAX_BATCH_SIZE) revert BatchTooLarge();

        responses = new VerificationResponse[](requests.length);
        for (uint256 i = 0; i < requests.length; i++) {
            (bool isVerified, uint8 score, string memory message) = verifyAsset(
                requests[i].assetId,
                requests[i].originChain,
                requests[i].amount
            );
            responses[i] = VerificationResponse(isVerified, score, message);
        }
        return responses;
    }

    // ─── Internal: Precompile Verification ───────────────────────────

    function _verifyWithPrecompile(
        IXcmOracle.AssetState memory current,
        PreviousSnapshot storage prev
    ) internal view returns (bool isVerified, uint8 score, string memory message, uint8 anomalyType) {
        bool isFirstCheck = (prev.timestamp == 0);

        // 1. Hash verification (skip on first check)
        bool hashOk;
        if (isFirstCheck) {
            hashOk = true;
        } else {
            hashOk = precompile.verifyHash(current.stateHash, prev.stateHash);
        }

        // 2. Supply anomaly detection
        bool supplyOk = true;
        if (!isFirstCheck) {
            bool isAnomaly;
            uint8 _anomalyType;
            (isAnomaly, _anomalyType,) = precompile.detectAnomaly(
                current.totalSupply,
                prev.supply,
                ANOMALY_THRESHOLD_PCT
            );
            supplyOk = !isAnomaly;
            if (isAnomaly) anomalyType = _anomalyType;
        }

        // 3. Minter authorization check
        bool minterOk = whitelistedMinters[current.minterAddress];

        // 4. Calculate composite score
        uint256 historyCount = isFirstCheck ? 0 : prev.verificationCount;
        score = precompile.calculateScore(supplyOk, minterOk, hashOk, historyCount);

        // 5. Apply anomaly cap
        score = _applyAnomalyCap(score, anomalyType);

        // 6. Determine verification result
        isVerified = score >= SCORE_VERIFIED;
        message = _scoreToMessage(score);
    }
}
