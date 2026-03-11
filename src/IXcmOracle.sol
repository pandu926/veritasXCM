// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IXcmOracle
/// @notice Interface for cross-chain XCM data queries
/// @dev In production, this calls real XCM precompiles to query parachain state.
///      For testing, MockXcmOracle simulates parachain responses.
interface IXcmOracle {
    /// @notice State data returned from a parachain query
    struct AssetState {
        uint256 totalSupply;    // Total supply of the asset on origin chain
        address minterAddress;  // Authorized minter/issuer address
        bytes32 stateHash;      // Merkle root or state hash of the asset
        uint256 timestamp;      // When this data was fetched
        bool exists;            // Whether the asset exists on the parachain
    }

    /// @notice Query the current state of an asset on its origin parachain
    /// @param paraId The parachain ID (e.g., 2000 for Acala)
    /// @param assetId The asset identifier on that parachain
    /// @return state The current asset state from the parachain
    function queryAssetState(
        uint32 paraId,
        string memory assetId
    ) external view returns (AssetState memory state);

    /// @notice Check if a parachain is supported for queries
    /// @param paraId The parachain ID
    /// @return True if the parachain is registered and queryable
    function isParachainSupported(uint32 paraId) external view returns (bool);

    /// @notice Resolve a chain name to its parachain ID
    /// @param chainName Human-readable chain name (e.g., "acala", "interlay")
    /// @return paraId The parachain ID (0 if not found)
    function getParachainId(string memory chainName) external view returns (uint32 paraId);
}
