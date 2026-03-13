// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title AssetRegistry
/// @notice On-chain registry storing cross-chain asset verification results
/// @dev Queryable by any DeFi protocol in the Polkadot ecosystem
contract AssetRegistry {
    // ─── Custom Errors ───────────────────────────────────────────────
    error NotOwner();
    error NotVerifier();
    error ZeroAddress();
    error InvalidAssetId();
    error InvalidOriginChain();
    error StringTooLong();

    // ─── Constants ──────────────────────────────────────────────────
    uint256 public constant MAX_STRING_LEN = 64;

    // ─── Structs ─────────────────────────────────────────────────────
    /// @notice Verification result for a cross-chain asset
    struct VerificationResult {
        uint8 score;          // Composite score 0-100
        uint8 anomalyType;    // 0=None, 1=SupplySpike, 2=SupplyDrop, 3=UnauthorizedMinter, 4=HashMismatch
        uint256 verifiedAt;   // Block timestamp of verification
        bytes32 proof;        // Cryptographic proof hash
    }

    // ─── State Variables ─────────────────────────────────────────────
    address public immutable owner;
    address public authorizedVerifier;

    /// @notice assetId => originChain => VerificationResult
    mapping(string => mapping(string => VerificationResult)) internal _assetVerifications;

    // ─── Events ──────────────────────────────────────────────────────
    event VerificationUpdated(string indexed assetId, string indexed originChain, uint8 score, bytes32 proof);
    event AssetFlagged(string indexed assetId, string indexed originChain, uint8 score, string reason);
    event AnomalyDetected(string indexed assetId, string indexed originChain, uint8 anomalyType, uint8 severity);
    event VerifierUpdated(address indexed oldVerifier, address indexed newVerifier);

    // ─── Modifiers ───────────────────────────────────────────────────
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyVerifier() {
        if (msg.sender != authorizedVerifier) revert NotVerifier();
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────
    constructor() {
        owner = msg.sender;
    }

    // ─── Admin Functions ─────────────────────────────────────────────

    /// @notice Set the authorized verifier contract address
    /// @param _verifier Address of the AssetVerifier contract
    function setVerifier(address _verifier) external onlyOwner {
        if (_verifier == address(0)) revert ZeroAddress();
        address oldVerifier = authorizedVerifier;
        authorizedVerifier = _verifier;
        emit VerifierUpdated(oldVerifier, _verifier);
    }

    // ─── Verifier Functions ──────────────────────────────────────────

    /// @notice Store a verification result (only callable by authorized verifier)
    /// @param assetId The asset identifier
    /// @param originChain The origin parachain
    /// @param score Composite verification score (0-100)
    /// @param anomalyType Type of anomaly detected (0=None)
    /// @param proof Cryptographic proof hash
    function setVerificationResult(
        string memory assetId,
        string memory originChain,
        uint8 score,
        uint8 anomalyType,
        bytes32 proof
    ) external onlyVerifier {
        uint256 assetLen = bytes(assetId).length;
        uint256 chainLen = bytes(originChain).length;
        if (assetLen == 0) revert InvalidAssetId();
        if (assetLen > MAX_STRING_LEN) revert StringTooLong();
        if (chainLen == 0) revert InvalidOriginChain();
        if (chainLen > MAX_STRING_LEN) revert StringTooLong();

        _assetVerifications[assetId][originChain] = VerificationResult({
            score: score,
            anomalyType: anomalyType,
            verifiedAt: block.timestamp,
            proof: proof
        });

        emit VerificationUpdated(assetId, originChain, score, proof);

        // Flag suspicious assets (score < 50)
        if (score < 50) {
            emit AssetFlagged(assetId, originChain, score, "Suspicious asset detected");
        }

        // Emit anomaly event
        if (anomalyType > 0) {
            emit AnomalyDetected(assetId, originChain, anomalyType, 100 - score);
        }
    }

    // ─── View Functions ──────────────────────────────────────────────

    /// @notice Get the full verification result for an asset
    function getVerificationResult(
        string memory assetId,
        string memory originChain
    ) external view returns (VerificationResult memory result) {
        return _assetVerifications[assetId][originChain];
    }

    /// @notice Get only the verification score for an asset
    function getAssetScore(
        string memory assetId,
        string memory originChain
    ) external view returns (uint8 score) {
        return _assetVerifications[assetId][originChain].score;
    }

    /// @notice Check if an asset has been verified
    function isAssetVerified(
        string memory assetId,
        string memory originChain
    ) external view returns (bool) {
        return _assetVerifications[assetId][originChain].verifiedAt > 0;
    }
}
