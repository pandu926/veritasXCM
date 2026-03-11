//! # VeritasXCM Verification Precompile
//!
//! Rust implementation of the verification logic for the VeritasXCM oracle.
//! This crate provides hash verification, anomaly detection, and composite
//! score calculation — designed to run as a PolkaVM precompile.

/// Types of anomalies that can be detected
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum AnomalyType {
    /// No anomaly detected
    None = 0,
    /// Supply increased beyond threshold
    SupplySpike = 1,
    /// Supply decreased beyond threshold
    SupplyDrop = 2,
    /// Unauthorized minter detected
    UnauthorizedMinter = 3,
    /// State hash mismatch
    HashMismatch = 4,
}

/// Result of anomaly detection
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AnomalyResult {
    pub is_anomaly: bool,
    pub anomaly_type: AnomalyType,
    pub severity: u8, // 0-100
}

/// Weights for composite score calculation
pub struct ScoreWeights {
    pub supply_weight: u8,  // out of 100
    pub minter_weight: u8,  // out of 100
    pub hash_weight: u8,    // out of 100
    pub history_weight: u8, // out of 100
}

impl Default for ScoreWeights {
    fn default() -> Self {
        Self {
            supply_weight: 30,
            minter_weight: 25,
            hash_weight: 30,
            history_weight: 15,
        }
    }
}

// ─── Hash Verification ───────────────────────────────────────────────

/// Compare two state hashes to verify integrity.
///
/// Returns `true` if the hashes match (state is consistent).
///
/// # Arguments
/// * `current_hash` - The current state hash (32 bytes)
/// * `previous_hash` - The previously recorded state hash (32 bytes)
pub fn verify_hash(current_hash: &[u8; 32], previous_hash: &[u8; 32]) -> bool {
    current_hash == previous_hash
}

// ─── Anomaly Detection ──────────────────────────────────────────────

/// Detect supply anomalies by comparing current vs previous supply.
///
/// A supply spike is flagged if `current_supply > previous_supply * (100 + threshold_pct) / 100`.
/// A supply drop is flagged if `current_supply < previous_supply * (100 - threshold_pct) / 100`.
///
/// # Arguments
/// * `current_supply` - Current total supply
/// * `previous_supply` - Previously recorded total supply
/// * `threshold_pct` - Percentage threshold for anomaly (e.g., 200 = 200% increase)
pub fn detect_anomaly(
    current_supply: u128,
    previous_supply: u128,
    threshold_pct: u128,
) -> AnomalyResult {
    // First check: if previous supply was 0
    if previous_supply == 0 {
        if current_supply > 0 {
            // New asset appearing — not necessarily an anomaly, but flag as low severity
            return AnomalyResult {
                is_anomaly: false,
                anomaly_type: AnomalyType::None,
                severity: 0,
            };
        }
        return AnomalyResult {
            is_anomaly: false,
            anomaly_type: AnomalyType::None,
            severity: 0,
        };
    }

    // Calculate percentage change (using u128 to avoid overflow)
    let change_pct = if current_supply >= previous_supply {
        // Increase
        ((current_supply - previous_supply) as u128)
            .checked_mul(100)
            .map(|v| v / previous_supply as u128)
            .unwrap_or(u128::MAX)
    } else {
        // Decrease
        ((previous_supply - current_supply) as u128)
            .checked_mul(100)
            .map(|v| v / previous_supply as u128)
            .unwrap_or(u128::MAX)
    };

    if current_supply > previous_supply && change_pct >= threshold_pct {
        // Supply spike
        let severity = std::cmp::min(100, (change_pct / 2) as u8);
        AnomalyResult {
            is_anomaly: true,
            anomaly_type: AnomalyType::SupplySpike,
            severity,
        }
    } else if current_supply < previous_supply && change_pct >= threshold_pct {
        // Supply drop
        let severity = std::cmp::min(100, (change_pct / 2) as u8);
        AnomalyResult {
            is_anomaly: true,
            anomaly_type: AnomalyType::SupplyDrop,
            severity,
        }
    } else {
        AnomalyResult {
            is_anomaly: false,
            anomaly_type: AnomalyType::None,
            severity: 0,
        }
    }
}

/// Check if a minter address is in the authorized whitelist.
///
/// # Arguments
/// * `minter` - The minter address (20 bytes)
/// * `whitelist` - List of authorized minter addresses
pub fn check_minter(minter: &[u8; 20], whitelist: &[[u8; 20]]) -> bool {
    whitelist.iter().any(|authorized| authorized == minter)
}

// ─── Composite Score Calculation ─────────────────────────────────────

/// Calculate a composite verification score from multiple factors.
///
/// Score = w1 * supply_consistency + w2 * minter_authorized + w3 * hash_integrity + w4 * history_factor
///
/// # Arguments
/// * `supply_ok` - Whether supply is consistent (no anomaly)
/// * `minter_ok` - Whether minter is authorized
/// * `hash_ok` - Whether state hash is consistent
/// * `history_count` - Number of previous successful verifications (max impact at 10+)
/// * `weights` - Weight configuration for each factor
///
/// # Returns
/// Composite score from 0 to 100
pub fn calculate_score(
    supply_ok: bool,
    minter_ok: bool,
    hash_ok: bool,
    history_count: u32,
    weights: &ScoreWeights,
) -> u8 {
    let supply_score: u32 = if supply_ok {
        weights.supply_weight as u32
    } else {
        0
    };

    let minter_score: u32 = if minter_ok {
        weights.minter_weight as u32
    } else {
        0
    };

    let hash_score: u32 = if hash_ok {
        weights.hash_weight as u32
    } else {
        0
    };

    // History factor: scales from 0 to full weight over 10 verifications
    let history_factor = std::cmp::min(history_count, 10);
    let history_score: u32 = (weights.history_weight as u32 * history_factor) / 10;

    let total = supply_score + minter_score + hash_score + history_score;

    std::cmp::min(total, 100) as u8
}

/// Calculate score with anomaly penalty applied.
///
/// If an anomaly is detected, the score is capped at a maximum based on anomaly type.
pub fn calculate_score_with_anomaly(
    supply_ok: bool,
    minter_ok: bool,
    hash_ok: bool,
    history_count: u32,
    anomaly: &AnomalyResult,
    weights: &ScoreWeights,
) -> u8 {
    let base_score = calculate_score(supply_ok, minter_ok, hash_ok, history_count, weights);

    if !anomaly.is_anomaly {
        return base_score;
    }

    // Apply caps based on anomaly type
    let max_score = match anomaly.anomaly_type {
        AnomalyType::SupplySpike => 20,
        AnomalyType::SupplyDrop => 35,
        AnomalyType::UnauthorizedMinter => 40,
        AnomalyType::HashMismatch => 15,
        AnomalyType::None => 100,
    };

    std::cmp::min(base_score, max_score)
}

// ─── Tests ──────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    // ── Hash Verification Tests ──

    #[test]
    fn test_verify_hash_matching() {
        let hash = [0xABu8; 32];
        assert!(verify_hash(&hash, &hash));
    }

    #[test]
    fn test_verify_hash_different() {
        let hash_a = [0xABu8; 32];
        let hash_b = [0xCDu8; 32];
        assert!(!verify_hash(&hash_a, &hash_b));
    }

    #[test]
    fn test_verify_hash_zero() {
        let hash = [0u8; 32];
        assert!(verify_hash(&hash, &hash));
    }

    #[test]
    fn test_verify_hash_one_bit_diff() {
        let mut hash_a = [0xABu8; 32];
        let hash_b = [0xABu8; 32];
        hash_a[31] = 0xAC; // one bit different
        assert!(!verify_hash(&hash_a, &hash_b));
    }

    // ── Anomaly Detection Tests ──

    #[test]
    fn test_detect_anomaly_no_change() {
        let result = detect_anomaly(1000, 1000, 200);
        assert!(!result.is_anomaly);
        assert_eq!(result.anomaly_type, AnomalyType::None);
    }

    #[test]
    fn test_detect_anomaly_small_increase() {
        // 10% increase, threshold 200% — no anomaly
        let result = detect_anomaly(1100, 1000, 200);
        assert!(!result.is_anomaly);
    }

    #[test]
    fn test_detect_anomaly_supply_spike() {
        // 500% increase, threshold 200%
        let result = detect_anomaly(6000, 1000, 200);
        assert!(result.is_anomaly);
        assert_eq!(result.anomaly_type, AnomalyType::SupplySpike);
        assert!(result.severity > 0);
    }

    #[test]
    fn test_detect_anomaly_exact_threshold() {
        // Exactly 200% increase, threshold 200%
        let result = detect_anomaly(3000, 1000, 200);
        assert!(result.is_anomaly);
        assert_eq!(result.anomaly_type, AnomalyType::SupplySpike);
    }

    #[test]
    fn test_detect_anomaly_supply_drop() {
        // 80% decrease, threshold 50%
        let result = detect_anomaly(200, 1000, 50);
        assert!(result.is_anomaly);
        assert_eq!(result.anomaly_type, AnomalyType::SupplyDrop);
    }

    #[test]
    fn test_detect_anomaly_zero_previous() {
        let result = detect_anomaly(1000, 0, 200);
        assert!(!result.is_anomaly);
    }

    #[test]
    fn test_detect_anomaly_both_zero() {
        let result = detect_anomaly(0, 0, 200);
        assert!(!result.is_anomaly);
    }

    // ── Minter Check Tests ──

    #[test]
    fn test_check_minter_authorized() {
        let minter = [0x01u8; 20];
        let whitelist = [[0x01u8; 20], [0x02u8; 20]];
        assert!(check_minter(&minter, &whitelist));
    }

    #[test]
    fn test_check_minter_unauthorized() {
        let minter = [0x03u8; 20];
        let whitelist = [[0x01u8; 20], [0x02u8; 20]];
        assert!(!check_minter(&minter, &whitelist));
    }

    #[test]
    fn test_check_minter_empty_whitelist() {
        let minter = [0x01u8; 20];
        let whitelist: [[u8; 20]; 0] = [];
        assert!(!check_minter(&minter, &whitelist));
    }

    // ── Score Calculation Tests ──

    #[test]
    fn test_calculate_score_all_good_with_history() {
        let weights = ScoreWeights::default();
        // supply(30) + minter(25) + hash(30) + history(15 * 10/10) = 100
        let score = calculate_score(true, true, true, 10, &weights);
        assert_eq!(score, 100);
    }

    #[test]
    fn test_calculate_score_all_good_no_history() {
        let weights = ScoreWeights::default();
        // supply(30) + minter(25) + hash(30) + history(0) = 85
        let score = calculate_score(true, true, true, 0, &weights);
        assert_eq!(score, 85);
    }

    #[test]
    fn test_calculate_score_supply_fail() {
        let weights = ScoreWeights::default();
        // supply(0) + minter(25) + hash(30) + history(15) = 70
        let score = calculate_score(false, true, true, 10, &weights);
        assert_eq!(score, 70);
    }

    #[test]
    fn test_calculate_score_all_fail_no_history() {
        let weights = ScoreWeights::default();
        let score = calculate_score(false, false, false, 0, &weights);
        assert_eq!(score, 0);
    }

    #[test]
    fn test_calculate_score_partial_history() {
        let weights = ScoreWeights::default();
        // supply(30) + minter(25) + hash(30) + history(15 * 5/10 = 7) = 92
        let score = calculate_score(true, true, true, 5, &weights);
        assert_eq!(score, 92);
    }

    #[test]
    fn test_calculate_score_history_cap_at_10() {
        let weights = ScoreWeights::default();
        let score_10 = calculate_score(true, true, true, 10, &weights);
        let score_100 = calculate_score(true, true, true, 100, &weights);
        assert_eq!(score_10, score_100);
    }

    // ── Score with Anomaly Tests ──

    #[test]
    fn test_score_with_no_anomaly() {
        let weights = ScoreWeights::default();
        let anomaly = AnomalyResult {
            is_anomaly: false,
            anomaly_type: AnomalyType::None,
            severity: 0,
        };
        let score = calculate_score_with_anomaly(true, true, true, 10, &anomaly, &weights);
        assert_eq!(score, 100);
    }

    #[test]
    fn test_score_capped_by_supply_spike() {
        let weights = ScoreWeights::default();
        let anomaly = AnomalyResult {
            is_anomaly: true,
            anomaly_type: AnomalyType::SupplySpike,
            severity: 80,
        };
        let score = calculate_score_with_anomaly(true, true, true, 10, &anomaly, &weights);
        assert_eq!(score, 20); // capped at 20
    }

    #[test]
    fn test_score_capped_by_hash_mismatch() {
        let weights = ScoreWeights::default();
        let anomaly = AnomalyResult {
            is_anomaly: true,
            anomaly_type: AnomalyType::HashMismatch,
            severity: 100,
        };
        let score = calculate_score_with_anomaly(true, true, true, 10, &anomaly, &weights);
        assert_eq!(score, 15); // capped at 15
    }

    #[test]
    fn test_score_capped_by_unauthorized_minter() {
        let weights = ScoreWeights::default();
        let anomaly = AnomalyResult {
            is_anomaly: true,
            anomaly_type: AnomalyType::UnauthorizedMinter,
            severity: 50,
        };
        let score = calculate_score_with_anomaly(true, true, true, 10, &anomaly, &weights);
        assert_eq!(score, 40); // capped at 40
    }
}
