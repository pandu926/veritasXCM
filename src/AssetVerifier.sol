// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./AssetRegistry.sol";
import "./IVerifierPrecompile.sol";

/// @title AssetVerifier
/// @notice Core verifier contract for VeritasXCM — trustless cross-chain asset verification
/// @dev Phase 2: Uses precompile for hash verification, anomaly detection, and score calculation.
contract AssetVerifier {
    // ─── Custom Errors ───────────────────────────────────────────────
    error Unauthorized();
    error InvalidAssetId();
    error InvalidOriginChain();
    error InvalidAmount();
    error ContractPaused();
    error EmptyBatch();
    error ZeroAddress();

    // ─── Constants ───────────────────────────────────────────────────
    uint256 public constant ANOMALY_THRESHOLD_PCT = 200; // 200% supply change = anomaly

    // ─── State Variables ─────────────────────────────────────────────
    AssetRegistry public immutable registry;
    IVerifierPrecompile public precompile;
    address public immutable owner;
    bool public paused;

    // ─── Asset Snapshot Storage ──────────────────────────────────────
    /// @notice Recorded state snapshot for an asset on its origin chain
    struct AssetSnapshot {
        uint256 supply;           // Total supply at last check
        address minterAddress;    // Authorized minter address
        bytes32 stateHash;        // State hash at last check
        uint256 lastChecked;      // Timestamp of last check
        uint32 verificationCount; // Number of successful verifications
    }

    /// @notice assetId => originChain => AssetSnapshot
    mapping(string => mapping(string => AssetSnapshot)) public assetSnapshots;

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
    event SnapshotUpdated(
        string indexed assetId,
        string indexed originChain,
        uint256 supply,
        bytes32 stateHash
    );
    event PrecompileUpdated(address indexed oldPrecompile, address indexed newPrecompile);
    event MinterWhitelisted(address indexed minter, bool status);
    event ContractPausedEvent(address indexed by);
    event ContractUnpausedEvent(address indexed by);

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
    /// @param _registryAddress Address of the deployed AssetRegistry contract
    /// @param _precompileAddress Address of the VerifierPrecompile (mock or real)
    constructor(address _registryAddress, address _precompileAddress) {
        registry = AssetRegistry(_registryAddress);
        precompile = IVerifierPrecompile(_precompileAddress);
        owner = msg.sender;
    }

    // ─── Admin Functions ─────────────────────────────────────────────

    /// @notice Pause the contract (emergency circuit breaker)
    function pause() external onlyOwner {
        paused = true;
        emit ContractPausedEvent(msg.sender);
    }

    /// @notice Unpause the contract
    function unpause() external onlyOwner {
        paused = false;
        emit ContractUnpausedEvent(msg.sender);
    }

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
    /// @dev In Phase 3, this will be replaced by XCM query responses
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
        if (bytes(assetId).length == 0) revert InvalidAssetId();
        if (bytes(originChain).length == 0) revert InvalidOriginChain();

        AssetSnapshot storage snapshot = assetSnapshots[assetId][originChain];
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
        // ── Input Validation ──
        if (bytes(assetId).length == 0) revert InvalidAssetId();
        if (bytes(originChain).length == 0) revert InvalidOriginChain();
        if (amount == 0) revert InvalidAmount();

        AssetSnapshot storage snapshot = assetSnapshots[assetId][originChain];

        // ── Route: Precompile (has snapshot) vs Mock (no snapshot) ──
        uint8 anomalyType = 0;
        if (snapshot.lastChecked > 0) {
            (isVerified, score, message, anomalyType) = _verifyViaPrecompile(assetId, originChain, snapshot);
        } else {
            (isVerified, score, message) = _mockVerify(assetId, originChain);
        }

        // ── Store Result in Registry ──
        bytes32 proof = keccak256(abi.encodePacked(assetId, originChain, amount, block.timestamp));
        registry.setVerificationResult(assetId, originChain, score, anomalyType, proof);

        // ── Update verification count ──
        if (isVerified && snapshot.lastChecked > 0) {
            snapshot.verificationCount++;
        }

        // ── Emit Event ──
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
        // 1. Hash verification
        bytes32 currentHash = keccak256(abi.encodePacked(assetId, originChain, snapshot.supply));
        bool hashOk = precompile.verifyHash(currentHash, snapshot.stateHash);

        // 2. Anomaly detection
        bool isAnomaly;
        uint8 _anomalyType;
        (isAnomaly, _anomalyType,) = precompile.detectAnomaly(
            snapshot.supply,
            snapshot.supply, // In Phase 3, previous supply comes from XCM
            ANOMALY_THRESHOLD_PCT
        );
        bool supplyOk = !isAnomaly;

        // 3. Minter check
        bool minterOk = whitelistedMinters[snapshot.minterAddress];

        // 4. Calculate score
        score = precompile.calculateScore(
            supplyOk,
            minterOk,
            hashOk,
            snapshot.verificationCount
        );

        // 5. Apply anomaly cap if needed
        if (isAnomaly) {
            anomalyType = _anomalyType;
            if (_anomalyType == 1) { // SupplySpike
                score = score < 20 ? score : 20;
            } else if (_anomalyType == 2) { // SupplyDrop
                score = score < 35 ? score : 35;
            }
        }

        // 6. Determine result
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

        return (isVerified, score, message, anomalyType);
    }

    // ─── Internal: Mock Fallback ─────────────────────────────────────

    /// @dev Mock verification for assets without snapshots (Phase 1 compatibility)
    function _mockVerify(
        string memory assetId,
        string memory originChain
    ) internal pure returns (bool isVerified, uint8 score, string memory message) {
        bytes32 assetHash = keccak256(abi.encodePacked(assetId));
        bytes32 chainHash = keccak256(abi.encodePacked(originChain));

        if (assetHash == keccak256("aDOT") && chainHash == keccak256("acala")) {
            return (true, 94, "Asset legitimate, high confidence");
        }
        if (assetHash == keccak256("iBTC") && chainHash == keccak256("interlay")) {
            return (true, 88, "Asset likely safe, multiple positive indicators");
        }
        if (assetHash == keccak256("vDOT") && chainHash == keccak256("bifrost")) {
            return (true, 75, "Liquid staking derivative, acceptable confidence");
        }
        if (assetHash == keccak256("xcDOT")) {
            return (false, 12, "ALERT: Abnormal supply detected. Do not accept.");
        }
        return (false, 50, "Asset unknown or uncertain, manual review needed.");
    }
}
