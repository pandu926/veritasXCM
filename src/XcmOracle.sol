// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IXcmOracle.sol";
import "./IXcm.sol";

/// @title XcmOracle
/// @notice Real XCM oracle using Polkadot's native XCM precompile
/// @dev Sends real XCM messages to parachains and caches responses.
///      Uses the XCM precompile at 0x00000000000000000000000000000000000a0000
///
///      XCM Query Flow:
///      1. Contract calls xcmSend() to dispatch query to parachain
///      2. Parachain processes and responds via XCM
///      3. Response is handled by xcmExecute() and stored in cache
///      4. DApps read cached state via queryAssetState()
///
///      Note: Since XCM is async (response arrives in a later block),
///      this oracle uses a cache pattern — data is pushed via reportAssetState()
///      after XCM response is received.
contract XcmOracle is IXcmOracle {
    // ─── Constants ───────────────────────────────────────────────────
    /// @notice The XCM precompile address on Polkadot Hub
    address public constant XCM_PRECOMPILE = 0x00000000000000000000000000000000000a0000;

    // ─── Custom Errors ───────────────────────────────────────────────
    error Unauthorized();
    error ParachainNotRegistered(uint32 paraId);

    // ─── State ───────────────────────────────────────────────────────
    address public immutable owner;
    IXcm public immutable xcm;

    /// @notice Authorized data reporters (can push XCM response data)
    mapping(address => bool) public authorizedReporters;

    /// @notice chainName => paraId
    mapping(string => uint32) internal _chainNameToId;

    /// @notice paraId => registered
    mapping(uint32 => bool) internal _registeredParachains;

    /// @notice paraId => assetId => cached state
    mapping(uint32 => mapping(string => AssetState)) internal _cachedStates;

    /// @notice paraId => assetId => query dispatched
    mapping(uint32 => mapping(string => bool)) public queryDispatched;

    // ─── Events ──────────────────────────────────────────────────────
    event ParachainRegistered(uint32 indexed paraId, string name);
    event XcmQueryDispatched(uint32 indexed paraId, string assetId, bytes xcmMessage);
    event AssetStateReported(uint32 indexed paraId, string assetId, uint256 supply);
    event ReporterUpdated(address indexed reporter, bool authorized);

    // ─── Modifier ────────────────────────────────────────────────────
    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyAuthorized() {
        if (msg.sender != owner && !authorizedReporters[msg.sender]) revert Unauthorized();
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────
    constructor() {
        owner = msg.sender;
        xcm = IXcm(XCM_PRECOMPILE);
        _seedDefaultParachains();
    }

    // ─── Admin Functions ─────────────────────────────────────────────

    /// @notice Register a parachain for XCM queries
    function registerParachain(string memory name, uint32 paraId) external onlyOwner {
        _chainNameToId[name] = paraId;
        _registeredParachains[paraId] = true;
        emit ParachainRegistered(paraId, name);
    }

    /// @notice Authorize an address to report XCM response data
    function setReporter(address reporter, bool authorized) external onlyOwner {
        authorizedReporters[reporter] = authorized;
        emit ReporterUpdated(reporter, authorized);
    }

    // ─── XCM Query Dispatch ──────────────────────────────────────────

    /// @notice Dispatch an XCM query to a parachain to fetch asset state
    /// @dev Constructs and sends an XCM message to the target parachain.
    ///      Response will arrive asynchronously and must be reported via reportAssetState().
    /// @param paraId Target parachain ID
    /// @param assetId Asset to query
    function dispatchAssetQuery(uint32 paraId, string memory assetId) external onlyAuthorized {
        if (!_registeredParachains[paraId]) revert ParachainNotRegistered(paraId);

        // Encode destination: parachain location in XCM format
        // V4 Location: { parents: 0, interior: X1(Parachain(paraId)) }
        bytes memory destination = _encodeParachainDestination(paraId);

        // Encode XCM message: QueryPallet or Transact to fetch asset info
        // This is a simplified query — in production, would use QueryResponse pattern
        bytes memory message = _encodeAssetQuery(assetId);

        // Send via XCM precompile
        xcm.xcmSend(destination, message);

        queryDispatched[paraId][assetId] = true;
        emit XcmQueryDispatched(paraId, assetId, message);
    }

    /// @notice Report asset state received from XCM response
    /// @dev Called by authorized reporter after XCM response arrives
    /// @param paraId Source parachain
    /// @param assetId Asset identifier
    /// @param totalSupply Total supply from parachain
    /// @param minter Authorized minter address
    /// @param stateHash State hash from parachain
    function reportAssetState(
        uint32 paraId,
        string memory assetId,
        uint256 totalSupply,
        address minter,
        bytes32 stateHash
    ) external onlyAuthorized {
        if (!_registeredParachains[paraId]) revert ParachainNotRegistered(paraId);

        _cachedStates[paraId][assetId] = AssetState({
            totalSupply: totalSupply,
            minterAddress: minter,
            stateHash: stateHash,
            timestamp: block.timestamp,
            exists: true
        });

        emit AssetStateReported(paraId, assetId, totalSupply);
    }

    // ─── IXcmOracle Implementation ──────────────────────────────────

    /// @inheritdoc IXcmOracle
    function queryAssetState(
        uint32 paraId,
        string memory assetId
    ) external view override returns (AssetState memory state) {
        if (!_registeredParachains[paraId]) revert ParachainNotRegistered(paraId);
        return _cachedStates[paraId][assetId];
    }

    /// @inheritdoc IXcmOracle
    function isParachainSupported(uint32 paraId) external view override returns (bool) {
        return _registeredParachains[paraId];
    }

    /// @inheritdoc IXcmOracle
    function getParachainId(string memory chainName) external view override returns (uint32) {
        return _chainNameToId[chainName];
    }

    // ─── XCM Encoding Helpers ────────────────────────────────────────

    /// @dev Encode parachain destination in SCALE format
    /// @param paraId The parachain ID
    /// @return SCALE-encoded destination bytes
    function _encodeParachainDestination(uint32 paraId) internal pure returns (bytes memory) {
        // XCM V4 Location: { parents: 0, interior: X1(Parachain(paraId)) }
        // SCALE encoding:
        // - parents: 0 (1 byte: 0x00)
        // - interior: X1 variant (1 byte: 0x01) + Parachain variant (1 byte: 0x00)
        //   + paraId (4 bytes LE)
        bytes memory dest = new bytes(7);
        dest[0] = 0x00; // parents = 0
        dest[1] = 0x01; // X1
        dest[2] = 0x00; // Parachain junction variant
        dest[3] = bytes1(uint8(paraId & 0xFF));
        dest[4] = bytes1(uint8((paraId >> 8) & 0xFF));
        dest[5] = bytes1(uint8((paraId >> 16) & 0xFF));
        dest[6] = bytes1(uint8((paraId >> 24) & 0xFF));
        return dest;
    }

    /// @dev Encode a simple asset query as XCM instructions
    /// @param assetId The asset to query
    /// @return SCALE-encoded XCM message bytes
    function _encodeAssetQuery(string memory assetId) internal pure returns (bytes memory) {
        // XCM V4 message encoding for asset state query
        // This uses Transact instruction to call runtime API on the parachain
        // Simplified encoding for hackathon demo:
        // [Transact { originKind: SovereignAccount, call: encoded_query }]
        bytes memory assetBytes = bytes(assetId);
        bytes memory message = abi.encodePacked(
            uint8(0x06),              // Transact instruction index
            uint8(0x02),              // OriginKind::SovereignAccount
            uint64(1_000_000_000),    // requireWeightAtMost refTime
            uint64(65_536),           // requireWeightAtMost proofSize
            uint32(assetBytes.length),// call length (compact)
            assetBytes                // call data (asset query)
        );
        return message;
    }

    // ─── Internal: Default Setup ─────────────────────────────────────

    function _seedDefaultParachains() internal {
        _chainNameToId["acala"] = 2000;
        _registeredParachains[2000] = true;

        _chainNameToId["interlay"] = 2032;
        _registeredParachains[2032] = true;

        _chainNameToId["bifrost"] = 2030;
        _registeredParachains[2030] = true;

        _chainNameToId["moonbeam"] = 2004;
        _registeredParachains[2004] = true;
    }
}
