// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./AssetRegistry.sol";
import "./IVerifierPrecompile.sol";
import "./IXcmOracle.sol";

/// @title XcmAssetVerifier
/// @notice End-to-end trustless asset verifier using XCM queries + Rust precompile
/// @dev Phase 3: Automatically fetches data from parachains via XCM oracle,
///      verifies via precompile, and stores results in registry.
contract XcmAssetVerifier {
    // ─── Custom Errors ───────────────────────────────────────────────
    error Unauthorized();
    error InvalidAssetId();
    error InvalidOriginChain();
    error InvalidAmount();
    error ContractPaused();
    error EmptyBatch();
    error ZeroAddress();
    error ParachainNotSupported(string chainName);
    error AssetNotFoundOnChain(string assetId, string originChain);

    // ─── Constants ───────────────────────────────────────────────────
    uint256 public constant ANOMALY_THRESHOLD_PCT = 200;

    // ─── State Variables ─────────────────────────────────────────────
    AssetRegistry public immutable registry;
    IVerifierPrecompile public precompile;
    IXcmOracle public xcmOracle;
    address public immutable owner;
    bool public paused;

    // ─── Previous Snapshot (for anomaly detection) ───────────────────
    struct PreviousSnapshot {
        uint256 supply;
        bytes32 stateHash;
        uint256 timestamp;
        uint32 verificationCount;
    }

    /// @notice assetId => paraId => previous snapshot
    mapping(string => mapping(uint32 => PreviousSnapshot)) public previousSnapshots;

    /// @notice minterAddress => isWhitelisted
    mapping(address => bool) public whitelistedMinters;

    // ─── Structs ─────────────────────────────────────────────────────
    struct VerificationRequest {
        string assetId;
        string originChain;
        uint256 amount;
    }

    struct VerificationResponse {
        bool isVerified;
        uint8 score;
        string message;
    }

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
    event ContractPausedEvent(address indexed by);
    event ContractUnpausedEvent(address indexed by);
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);
    event PrecompileUpdated(address indexed oldPrecompile, address indexed newPrecompile);
    event MinterWhitelisted(address indexed minter, bool status);

    // ─── Modifiers ───────────────────────────────────────────────────
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────
    /// @param _registry Address of AssetRegistry
    /// @param _precompile Address of VerifierPrecompile (mock or real)
    /// @param _xcmOracle Address of XCM Oracle (mock or real)
    constructor(address _registry, address _precompile, address _xcmOracle) {
        registry = AssetRegistry(_registry);
        precompile = IVerifierPrecompile(_precompile);
        xcmOracle = IXcmOracle(_xcmOracle);
        owner = msg.sender;
    }

    // ─── Admin Functions ─────────────────────────────────────────────

    function pause() external onlyOwner {
        paused = true;
        emit ContractPausedEvent(msg.sender);
    }

    function unpause() external onlyOwner {
        paused = false;
        emit ContractUnpausedEvent(msg.sender);
    }

    function setOracle(address _newOracle) external onlyOwner {
        if (_newOracle == address(0)) revert ZeroAddress();
        address old = address(xcmOracle);
        xcmOracle = IXcmOracle(_newOracle);
        emit OracleUpdated(old, _newOracle);
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
    /// @dev Flow: resolve chain → XCM query → compare with previous → score → registry
    /// @param assetId The asset identifier (e.g., "aDOT")
    /// @param originChain The origin parachain (e.g., "acala")
    /// @param amount The amount being verified
    function verifyAsset(
        string memory assetId,
        string memory originChain,
        uint256 amount
    ) public whenNotPaused returns (bool isVerified, uint8 score, string memory message) {
        // ── Input Validation ──
        if (bytes(assetId).length == 0) revert InvalidAssetId();
        if (bytes(originChain).length == 0) revert InvalidOriginChain();
        if (amount == 0) revert InvalidAmount();

        // ── Step 1: Resolve chain name → paraId ──
        uint32 paraId = xcmOracle.getParachainId(originChain);
        if (paraId == 0) revert ParachainNotSupported(originChain);

        // ── Step 2: XCM Query — fetch current asset state ──
        IXcmOracle.AssetState memory currentState = xcmOracle.queryAssetState(paraId, assetId);
        if (!currentState.exists) revert AssetNotFoundOnChain(assetId, originChain);

        emit XcmQueryCompleted(assetId, paraId, currentState.totalSupply, currentState.stateHash);

        // ── Step 3: Load previous snapshot ──
        PreviousSnapshot storage prev = previousSnapshots[assetId][paraId];

        // ── Step 4: Verification via precompile ──
        uint8 anomalyType;
        (isVerified, score, message, anomalyType) = _verifyWithPrecompile(currentState, prev);

        // ── Step 5: Store result in registry ──
        bytes32 proof = keccak256(abi.encodePacked(
            assetId, originChain, amount, currentState.stateHash, block.timestamp
        ));
        registry.setVerificationResult(assetId, originChain, score, anomalyType, proof);

        // ── Step 6: Update previous snapshot ──
        prev.supply = currentState.totalSupply;
        prev.stateHash = currentState.stateHash;
        prev.timestamp = block.timestamp;
        if (isVerified) {
            prev.verificationCount++;
        }

        // ── Step 7: Emit ──
        emit AssetVerified(assetId, originChain, amount, score, isVerified);

        return (isVerified, score, message);
    }

    /// @notice Verify multiple assets in a single transaction
    function verifyBatchAssets(
        VerificationRequest[] memory requests
    ) external whenNotPaused returns (VerificationResponse[] memory responses) {
        if (requests.length == 0) revert EmptyBatch();

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
            hashOk = true; // No previous hash to compare
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
        if (anomalyType == 1) { // SupplySpike
            if (score > 20) score = 20;
        } else if (anomalyType == 2) { // SupplyDrop
            if (score > 35) score = 35;
        }

        // 6. Determine verification result
        isVerified = score >= 70;

        if (score >= 90) {
            message = "Asset verified, high confidence";
        } else if (score >= 70) {
            message = "Asset likely safe, acceptable confidence";
        } else if (score >= 50) {
            message = "Asset uncertain, manual review recommended";
        } else {
            message = "ALERT: Suspicious asset detected. Do not accept.";
        }
    }
}
