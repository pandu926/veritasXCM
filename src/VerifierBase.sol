// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title VerifierBase
/// @notice Shared constants, errors, structs, and utilities for all verifier contracts
abstract contract VerifierBase {
    // ─── Custom Errors ───────────────────────────────────────────────
    error Unauthorized();
    error InvalidAssetId();
    error InvalidOriginChain();
    error InvalidAmount();
    error ContractPaused();
    error EmptyBatch();
    error BatchTooLarge();
    error ZeroAddress();
    error StringTooLong();
    error VerificationCooldown();

    // ─── Constants ───────────────────────────────────────────────────
    uint256 public constant ANOMALY_THRESHOLD_PCT = 200;
    uint8 public constant SCORE_HIGH = 90;
    uint8 public constant SCORE_VERIFIED = 70;
    uint8 public constant SCORE_UNCERTAIN = 50;
    uint256 public constant MAX_BATCH_SIZE = 20;
    uint256 public constant MAX_STRING_LEN = 64;
    uint256 public constant VERIFICATION_COOLDOWN_PERIOD = 5 minutes;

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

    // ─── State Variables ─────────────────────────────────────────────
    address public immutable owner;
    bool public paused;

    // ─── Events ──────────────────────────────────────────────────────
    event ContractPausedEvent(address indexed by);
    event ContractUnpausedEvent(address indexed by);
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
    constructor() {
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

    // ─── Internal Helpers ────────────────────────────────────────────

    function _validateInputs(
        string memory assetId,
        string memory originChain,
        uint256 amount
    ) internal pure {
        uint256 assetLen = bytes(assetId).length;
        uint256 chainLen = bytes(originChain).length;
        if (assetLen == 0) revert InvalidAssetId();
        if (assetLen > MAX_STRING_LEN) revert StringTooLong();
        if (chainLen == 0) revert InvalidOriginChain();
        if (chainLen > MAX_STRING_LEN) revert StringTooLong();
        if (amount == 0) revert InvalidAmount();
    }

    function _scoreToMessage(uint8 score) internal pure returns (string memory) {
        if (score >= SCORE_HIGH) {
            return "Asset verified, high confidence";
        } else if (score >= SCORE_VERIFIED) {
            return "Asset likely safe, acceptable confidence";
        } else if (score >= SCORE_UNCERTAIN) {
            return "Asset uncertain, manual review recommended";
        } else {
            return "ALERT: Suspicious asset detected. Do not accept.";
        }
    }

    function _applyAnomalyCap(uint8 score, uint8 anomalyType) internal pure returns (uint8) {
        if (anomalyType == 1) { // SupplySpike
            return score > 20 ? 20 : score;
        } else if (anomalyType == 2) { // SupplyDrop
            return score > 35 ? 35 : score;
        }
        return score;
    }
}
