// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./AssetRegistry.sol";
import "./IVerifierPrecompile.sol";
import "./VerifierBase.sol";

/// @title AssetVerifier
/// @notice Core verifier contract for VeritasXCM — trustless cross-chain asset verification
/// @dev Phase 2: Uses precompile for hash verification, anomaly detection, and score calculation.
contract AssetVerifier is VerifierBase {
    // ─── State Variables ─────────────────────────────────────────────
    AssetRegistry public immutable registry;
    IVerifierPrecompile public precompile;

    // ─── Asset Snapshot Storage ──────────────────────────────────────
    /// @notice Recorded state snapshot for an asset on its origin chain
    struct AssetSnapshot {
        uint256 supply;           // Total supply at last check
        uint256 previousSupply;   // Previous supply for anomaly detection
        address minterAddress;    // Authorized minter address
        bytes32 stateHash;        // State hash at last check
        uint256 lastChecked;      // Timestamp of last check
        uint256 verificationCount; // Number of successful verifications
    }

    /// @notice assetId => originChain => AssetSnapshot
    mapping(string => mapping(string => AssetSnapshot)) public assetSnapshots;

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
    event SnapshotUpdated(
        string indexed assetId,
        string indexed originChain,
        uint256 supply,
        bytes32 stateHash
    );

    // ─── Constructor ─────────────────────────────────────────────────
    /// @param _registryAddress Address of the deployed AssetRegistry contract
    /// @param _precompileAddress Address of the VerifierPrecompile (mock or real)
    constructor(address _registryAddress, address _precompileAddress) VerifierBase() {
        registry = AssetRegistry(_registryAddress);
        precompile = IVerifierPrecompile(_precompileAddress);
    }

    // ─── Admin Functions ─────────────────────────────────────────────

    /// @notice Update the precompile address
    /// @param _newPrecompile New precompile contract address
    function setPrecompile(address _newPrecompile) external onlyOwner {
        if (_newPrecompile == address(0)) revert ZeroAddress();
        address old = address(precompile);
        precompile = IVerifierPrecompile(_newPrecompile);
        emit PrecompileUpdated(old, _newPrecompile);
    }

    /// @notice Whitelist or remove a minter address
    /// @param minter The minter address
    /// @param status True to whitelist, false to remove
    function setMinterWhitelist(address minter, bool status) external onlyOwner {
        whitelistedMinters[minter] = status;
        emit MinterWhitelisted(minter, status);
    }

    /// @notice Set asset snapshot data (simulates parachain data for Phase 2)
    /// @param assetId The asset identifier
    /// @param originChain The origin parachain
    /// @param supply Current total supply
    /// @param minter Authorized minter address
    /// @param stateHash Current state hash
    function setAssetSnapshot(
        string memory assetId,
        string memory originChain,
        uint256 supply,
        address minter,
        bytes32 stateHash
    ) external onlyOwner {
        uint256 assetLen = bytes(assetId).length;
        uint256 chainLen = bytes(originChain).length;
        if (assetLen == 0) revert InvalidAssetId();
        if (assetLen > MAX_STRING_LEN) revert StringTooLong();
        if (chainLen == 0) revert InvalidOriginChain();
        if (chainLen > MAX_STRING_LEN) revert StringTooLong();
        if (minter == address(0)) revert ZeroAddress();
        if (stateHash == bytes32(0)) revert InvalidAssetId(); // reuse error for invalid hash

        AssetSnapshot storage snapshot = assetSnapshots[assetId][originChain];
        snapshot.previousSupply = snapshot.supply;
        snapshot.supply = supply;
        snapshot.minterAddress = minter;
        snapshot.stateHash = stateHash;
        snapshot.lastChecked = block.timestamp;

        emit SnapshotUpdated(assetId, originChain, supply, stateHash);
    }

    // ─── Core Verification ───────────────────────────────────────────

    /// @notice Verify the legitimacy of a cross-chain asset using precompile
    /// @param assetId The asset identifier
    /// @param originChain The origin parachain name
    /// @param amount The amount to verify
    /// @return isVerified Whether the asset passed verification
    /// @return score Composite verification score (0-100)
    /// @return message Human-readable result message
    function verifyAsset(
        string memory assetId,
        string memory originChain,
        uint256 amount
    ) public whenNotPaused returns (bool isVerified, uint8 score, string memory message) {
        _validateInputs(assetId, originChain, amount);

        AssetSnapshot storage snapshot = assetSnapshots[assetId][originChain];

        // Enforce cooldown to prevent spam
        if (snapshot.lastChecked > 0) {
            if (block.timestamp < snapshot.lastChecked + VERIFICATION_COOLDOWN_PERIOD) {
                revert VerificationCooldown();
            }
        }

        // Require snapshot — no mock fallback in production
        uint8 anomalyType = 0;
        (isVerified, score, message, anomalyType) = _verifyViaPrecompile(assetId, originChain, snapshot);

        // Store result in registry
        bytes32 proof = keccak256(abi.encodePacked(assetId, originChain, amount, block.number, block.timestamp));
        registry.setVerificationResult(assetId, originChain, score, anomalyType, proof);

        // Update snapshot state
        snapshot.lastChecked = block.timestamp;
        if (isVerified) {
            snapshot.verificationCount++;
        }

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
            responses[i] = VerificationResponse({
                isVerified: isVerified,
                score: score,
                message: message
            });
        }

        return responses;
    }

    // ─── Internal: Precompile-based Verification ─────────────────────

    /// @dev Verify using the precompile — hash comparison, anomaly detection, scoring
    function _verifyViaPrecompile(
        string memory assetId,
        string memory originChain,
        AssetSnapshot storage snapshot
    ) internal view returns (bool isVerified, uint8 score, string memory message, uint8 anomalyType) {
        bool isFirstCheck = (snapshot.lastChecked == 0);

        // 1. Hash verification
        bytes32 currentHash = keccak256(abi.encodePacked(assetId, originChain, snapshot.supply));
        bool hashOk;
        if (isFirstCheck) {
            hashOk = true;
        } else {
            hashOk = precompile.verifyHash(currentHash, snapshot.stateHash);
        }

        // 2. Anomaly detection — use previousSupply instead of self-comparison
        bool supplyOk = true;
        if (!isFirstCheck && snapshot.previousSupply > 0) {
            bool isAnomaly;
            uint8 _anomalyType;
            (isAnomaly, _anomalyType,) = precompile.detectAnomaly(
                snapshot.supply,
                snapshot.previousSupply,
                ANOMALY_THRESHOLD_PCT
            );
            supplyOk = !isAnomaly;
            if (isAnomaly) anomalyType = _anomalyType;
        }

        // 3. Minter check
        bool minterOk = whitelistedMinters[snapshot.minterAddress];

        // 4. Calculate score
        score = precompile.calculateScore(
            supplyOk,
            minterOk,
            hashOk,
            snapshot.verificationCount
        );

        // 5. Apply anomaly cap
        score = _applyAnomalyCap(score, anomalyType);

        // 6. Determine result
        isVerified = score >= SCORE_VERIFIED;
        message = _scoreToMessage(score);

        return (isVerified, score, message, anomalyType);
    }
}
