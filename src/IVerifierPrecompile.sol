// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IVerifierPrecompile
/// @notice Interface for the VeritasXCM verification precompile
/// @dev In production, this is a Rust precompile at a fixed PolkaVM address.
///      For testing, MockVerifierPrecompile implements this interface.
interface IVerifierPrecompile {
    /// @notice Compare two state hashes for integrity verification
    /// @param currentHash Current state hash
    /// @param previousHash Previously recorded state hash
    /// @return True if hashes match (state is consistent)
    function verifyHash(bytes32 currentHash, bytes32 previousHash) external pure returns (bool);

    /// @notice Detect supply anomalies between current and previous supply
    /// @param currentSupply Current total supply
    /// @param previousSupply Previously recorded total supply
    /// @param thresholdPct Percentage threshold for anomaly (e.g., 200 = 200%)
    /// @return isAnomaly Whether an anomaly was detected
    /// @return anomalyType Type of anomaly (0=None, 1=SupplySpike, 2=SupplyDrop)
    /// @return severity Severity score (0-100)
    function detectAnomaly(
        uint256 currentSupply,
        uint256 previousSupply,
        uint256 thresholdPct
    ) external pure returns (bool isAnomaly, uint8 anomalyType, uint8 severity);

    /// @notice Calculate composite verification score from multiple factors
    /// @param supplyOk Whether supply is consistent
    /// @param minterOk Whether minter is authorized
    /// @param hashOk Whether state hash matches
    /// @param historyCount Number of previous successful verifications
    /// @return score Composite score (0-100)
    function calculateScore(
        bool supplyOk,
        bool minterOk,
        bool hashOk,
        uint256 historyCount
    ) external pure returns (uint8 score);
}
