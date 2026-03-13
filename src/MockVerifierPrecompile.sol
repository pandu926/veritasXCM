// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IVerifierPrecompile.sol";

/// @title MockVerifierPrecompile
/// @notice Solidity mock of the Rust verification precompile for testing
/// @dev Replicates the Rust logic exactly. In production, replaced by Rust precompile at fixed address.
contract MockVerifierPrecompile is IVerifierPrecompile {
    // ─── Score Weights (matching Rust defaults) ──────────────────────
    uint8 public constant SUPPLY_WEIGHT = 30;
    uint8 public constant MINTER_WEIGHT = 25;
    uint8 public constant HASH_WEIGHT = 30;
    uint8 public constant HISTORY_WEIGHT = 15;
    uint8 public constant MAX_HISTORY = 10;

    // ─── Anomaly Type Constants ──────────────────────────────────────
    uint8 public constant ANOMALY_NONE = 0;
    uint8 public constant ANOMALY_SUPPLY_SPIKE = 1;
    uint8 public constant ANOMALY_SUPPLY_DROP = 2;

    // ─── Anomaly Score Caps ──────────────────────────────────────────
    uint8 public constant CAP_SUPPLY_SPIKE = 20;
    uint8 public constant CAP_SUPPLY_DROP = 35;
    uint8 public constant CAP_UNAUTHORIZED_MINTER = 40;
    uint8 public constant CAP_HASH_MISMATCH = 15;

    /// @inheritdoc IVerifierPrecompile
    function verifyHash(
        bytes32 currentHash,
        bytes32 previousHash
    ) external pure override returns (bool) {
        return currentHash == previousHash;
    }

    /// @inheritdoc IVerifierPrecompile
    function detectAnomaly(
        uint256 currentSupply,
        uint256 previousSupply,
        uint256 thresholdPct
    ) external pure override returns (bool isAnomaly, uint8 anomalyType, uint8 severity) {
        if (previousSupply == 0) {
            return (false, ANOMALY_NONE, 0);
        }

        uint256 changePct;
        bool isIncrease;

        if (currentSupply >= previousSupply) {
            isIncrease = true;
            changePct = ((currentSupply - previousSupply) * 100) / previousSupply;
        } else {
            isIncrease = false;
            changePct = ((previousSupply - currentSupply) * 100) / previousSupply;
        }

        if (isIncrease && changePct >= thresholdPct) {
            uint8 sev = uint8(_min(changePct / 2, 100));
            return (true, ANOMALY_SUPPLY_SPIKE, sev);
        }

        if (!isIncrease && changePct >= thresholdPct) {
            uint8 sev = uint8(_min(changePct / 2, 100));
            return (true, ANOMALY_SUPPLY_DROP, sev);
        }

        return (false, ANOMALY_NONE, 0);
    }

    /// @inheritdoc IVerifierPrecompile
    function calculateScore(
        bool supplyOk,
        bool minterOk,
        bool hashOk,
        uint256 historyCount
    ) external pure override returns (uint8 score) {
        return _calculateScoreInternal(supplyOk, minterOk, hashOk, historyCount);
    }

    /// @notice Calculate score with anomaly cap applied
    function calculateScoreWithAnomaly(
        bool supplyOk,
        bool minterOk,
        bool hashOk,
        uint256 historyCount,
        bool hasAnomaly,
        uint8 anomalyType
    ) external pure returns (uint8 score) {
        uint8 baseScore = _calculateScoreInternal(supplyOk, minterOk, hashOk, historyCount);

        if (!hasAnomaly) return baseScore;

        uint8 maxScore;
        if (anomalyType == ANOMALY_SUPPLY_SPIKE) {
            maxScore = CAP_SUPPLY_SPIKE;
        } else if (anomalyType == ANOMALY_SUPPLY_DROP) {
            maxScore = CAP_SUPPLY_DROP;
        } else {
            maxScore = 100;
        }

        return baseScore < maxScore ? baseScore : maxScore;
    }

    // ─── Internal Helpers ────────────────────────────────────────────

    function _calculateScoreInternal(
        bool supplyOk,
        bool minterOk,
        bool hashOk,
        uint256 historyCount
    ) internal pure returns (uint8) {
        uint256 total = 0;

        if (supplyOk) total += SUPPLY_WEIGHT;
        if (minterOk) total += MINTER_WEIGHT;
        if (hashOk) total += HASH_WEIGHT;

        uint256 histCapped = _min(historyCount, MAX_HISTORY);
        total += (uint256(HISTORY_WEIGHT) * histCapped) / MAX_HISTORY;

        return uint8(_min(total, 100));
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
