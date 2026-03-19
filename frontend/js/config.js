/* ===================================================================
   VeritasXCM -- Configuration & Constants
   =================================================================== */

// Use local proxy on localhost to avoid CORS, direct RPC otherwise
var DIRECT_RPC = "https://eth-asset-hub-paseo.dotters.network";
var RPC_URL =
  window.location.hostname === "localhost" || window.location.hostname === "127.0.0.1"
    ? window.location.origin + "/rpc"
    : DIRECT_RPC;
var REGISTRY_ADDRESS = "0x37bA0f0B66474E96C96332935e95F98aE72b2d29";
var VERIFIER_ADDRESS = "0x1627524AEf2D11Ca01561d839BC5b45Ae12195A0";
var XCM_PRECOMPILE = "0x00000000000000000000000000000000000a0000";
var PASEO_CHAIN_ID = 420420417;

var MAX_INPUT_LENGTH = 64;
var VERIFY_COOLDOWN_MS = 30000;
var SCORE_RING_CIRCUMFERENCE = 2 * Math.PI * 70;

// XCM V5 encoded payloads for relay chain query
var XCM_DESTINATION = "0x050100"; // VersionedLocation V5: relay chain (parents=1, Here)
var XCM_MESSAGE = "0x05040a";    // VersionedXcm V5: [ClearOrigin]

var REGISTRY_ABI = [
  "function getVerificationResult(string calldata assetId, string calldata originChain) external view returns (tuple(uint8 score, uint8 anomalyType, uint256 verifiedAt, bytes32 proof))",
];

var VERIFIER_ABI = [
  "function verifyAsset(string calldata assetId, string calldata originChain, uint256 amount) external",
];

var XCM_ABI = [
  "function send(bytes calldata destination, bytes calldata message) external",
];

// Custom error selectors (keccak256 first 4 bytes) for revert decoding
var ERROR_SELECTORS = {
  "0xa5273631": "Oracle data is stale (>1 hour old). Run refresh-oracle script before verifying.",
  "0x647489b8": "Cooldown active — please wait 5 minutes between verifications for the same asset.",
  "0xab35696f": "The verifier contract is currently paused.",
  "0xfafca5a0": "Invalid Asset ID.",
  "0x9d9108aa": "This parachain/origin chain is not registered in the oracle.",
  "0x2c5211c6": "Invalid amount.",
  "0xb11b2ad8": "Input string exceeds maximum length (64 characters).",
  "0x82b42900": "Unauthorized — only contract owner can perform this action.",
};

var DASHBOARD_ASSETS = [
  { assetId: "aDOT", chain: "acala" },
  { assetId: "iBTC", chain: "interlay" },
  { assetId: "vDOT", chain: "bifrost" },
  { assetId: "xcDOT", chain: "moonbeam" },
];
