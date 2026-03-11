// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IXcmOracle.sol";

/// @title MockXcmOracle
/// @notice Simulates XCM cross-chain queries for testing and hackathon demo
/// @dev Owner can register parachains, seed asset data, and inject anomalies.
///      In production, replaced by a contract that uses real XCM precompiles.
contract MockXcmOracle is IXcmOracle {
    // ─── Custom Errors ───────────────────────────────────────────────
    error Unauthorized();
    error ParachainNotRegistered(uint32 paraId);
    error AssetNotFound(uint32 paraId, string assetId);

    // ─── State ───────────────────────────────────────────────────────
    address public immutable owner;

    /// @notice chainName => paraId mapping
    mapping(string => uint32) internal _chainNameToId;

    /// @notice paraId => registered flag
    mapping(uint32 => bool) internal _registeredParachains;

    /// @notice paraId => name
    mapping(uint32 => string) internal _parachainNames;

    /// @notice paraId => assetId => AssetState
    mapping(uint32 => mapping(string => AssetState)) internal _assetStates;

    // ─── Events ──────────────────────────────────────────────────────
    event ParachainRegistered(uint32 indexed paraId, string name);
    event AssetStateUpdated(uint32 indexed paraId, string assetId, uint256 supply);
    event AnomalyInjected(uint32 indexed paraId, string assetId, uint256 newSupply);

    // ─── Modifier ────────────────────────────────────────────────────
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────
    constructor() {
        owner = msg.sender;
        _seedDefaultParachains();
    }

    // ─── Admin Functions ─────────────────────────────────────────────

    /// @notice Register a parachain for XCM queries
    /// @param name Human-readable name (e.g., "acala")
    /// @param paraId The parachain ID (e.g., 2000)
    function registerParachain(string memory name, uint32 paraId) external onlyOwner {
        _chainNameToId[name] = paraId;
        _registeredParachains[paraId] = true;
        _parachainNames[paraId] = name;
        emit ParachainRegistered(paraId, name);
    }

    /// @notice Set asset state for a parachain (simulates XCM response data)
    /// @param paraId The parachain ID
    /// @param assetId The asset identifier
    /// @param totalSupply Total supply of the asset
    /// @param minter Authorized minter address
    /// @param stateHash State hash / merkle root
    function setAssetState(
        uint32 paraId,
        string memory assetId,
        uint256 totalSupply,
        address minter,
        bytes32 stateHash
    ) external onlyOwner {
        if (!_registeredParachains[paraId]) revert ParachainNotRegistered(paraId);

        _assetStates[paraId][assetId] = AssetState({
            totalSupply: totalSupply,
            minterAddress: minter,
            stateHash: stateHash,
            timestamp: block.timestamp,
            exists: true
        });

        emit AssetStateUpdated(paraId, assetId, totalSupply);
    }

    /// @notice Inject a supply anomaly for demo purposes
    /// @param paraId The parachain ID
    /// @param assetId The asset to inject anomaly into
    /// @param newSupply The new (anomalous) supply value
    function injectAnomaly(
        uint32 paraId,
        string memory assetId,
        uint256 newSupply
    ) external onlyOwner {
        if (!_registeredParachains[paraId]) revert ParachainNotRegistered(paraId);

        AssetState storage state = _assetStates[paraId][assetId];
        state.totalSupply = newSupply;
        state.timestamp = block.timestamp;
        // Intentionally do NOT update stateHash — this creates a hash mismatch

        emit AnomalyInjected(paraId, assetId, newSupply);
    }

    // ─── IXcmOracle Implementation ──────────────────────────────────

    /// @inheritdoc IXcmOracle
    function queryAssetState(
        uint32 paraId,
        string memory assetId
    ) external view override returns (AssetState memory state) {
        if (!_registeredParachains[paraId]) revert ParachainNotRegistered(paraId);

        state = _assetStates[paraId][assetId];
        return state;
    }

    /// @inheritdoc IXcmOracle
    function isParachainSupported(uint32 paraId) external view override returns (bool) {
        return _registeredParachains[paraId];
    }

    /// @inheritdoc IXcmOracle
    function getParachainId(string memory chainName) external view override returns (uint32 paraId) {
        return _chainNameToId[chainName];
    }

    // ─── Internal: Default Parachain Setup ───────────────────────────

    /// @dev Pre-register common Polkadot parachains with mock data
    function _seedDefaultParachains() internal {
        // Acala (paraId: 2000)
        _registerInternal("acala", 2000);
        _setAssetInternal(2000, "aDOT", 50_000 ether, address(0xACA1), _computeHash("aDOT", 50_000 ether));

        // Interlay (paraId: 2032)
        _registerInternal("interlay", 2032);
        _setAssetInternal(2032, "iBTC", 21_000 ether, address(0x1B7C), _computeHash("iBTC", 21_000 ether));

        // Bifrost (paraId: 2030)
        _registerInternal("bifrost", 2030);
        _setAssetInternal(2030, "vDOT", 100_000 ether, address(0xBF05), _computeHash("vDOT", 100_000 ether));

        // Moonbeam (paraId: 2004)
        _registerInternal("moonbeam", 2004);
        _setAssetInternal(2004, "xcDOT", 30_000 ether, address(0xBEAB), _computeHash("xcDOT", 30_000 ether));
    }

    function _registerInternal(string memory name, uint32 paraId) internal {
        _chainNameToId[name] = paraId;
        _registeredParachains[paraId] = true;
        _parachainNames[paraId] = name;
    }

    function _setAssetInternal(
        uint32 paraId,
        string memory assetId,
        uint256 supply,
        address minter,
        bytes32 stateHash
    ) internal {
        _assetStates[paraId][assetId] = AssetState({
            totalSupply: supply,
            minterAddress: minter,
            stateHash: stateHash,
            timestamp: block.timestamp,
            exists: true
        });
    }

    function _computeHash(string memory assetId, uint256 supply) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(assetId, supply));
    }
}
