/**
 * Playwright Global Setup — ensures assets are seeded on Paseo before tests run.
 * Checks if assets are already verified; if not, runs seed script.
 */
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

// Load .env.test
const envPath = path.join(__dirname, "../../.env.test");
if (fs.existsSync(envPath)) {
  const envContent = fs.readFileSync(envPath, "utf-8");
  for (const line of envContent.split("\n")) {
    const [key, ...val] = line.split("=");
    if (key && val.length) process.env[key.trim()] = val.join("=").trim();
  }
}

const RPC_URL = process.env.RPC_URL || "https://eth-asset-hub-paseo.dotters.network";
const PRIVATE_KEY = process.env.TEST_PRIVATE_KEY;
const VERIFIER_ADDRESS = process.env.VERIFIER_ADDRESS || "0xBb1Df6990CCCd16c32939c8E30fb38A9D2cFC820";
const REGISTRY_ADDRESS = process.env.REGISTRY_ADDRESS || "0x9A340E7eeDA37623556A566473648365dfe390E1";

const REGISTRY_ABI = [
  "function getVerificationResult(string calldata assetId, string calldata originChain) external view returns (tuple(uint8 score, uint8 anomalyType, uint256 verifiedAt, bytes32 proof))",
];

const VERIFIER_ABI = [
  "function verifyAsset(string calldata assetId, string calldata originChain, uint256 amount) external returns (bool, uint8, string memory)",
];

const ASSETS = [
  { assetId: "aDOT", originChain: "acala", amount: 1000 },
  { assetId: "iBTC", originChain: "interlay", amount: 100 },
  { assetId: "vDOT", originChain: "bifrost", amount: 500 },
  { assetId: "xcDOT", originChain: "moonbeam", amount: 1000 },
];

async function globalSetup() {
  console.log("\n[Global Setup] Checking asset verification state on Paseo...");

  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const registry = new ethers.Contract(REGISTRY_ADDRESS, REGISTRY_ABI, provider);

  const needsSeeding = [];

  for (const asset of ASSETS) {
    try {
      const result = await registry.getVerificationResult(asset.assetId, asset.originChain);
      const score = Number(result.score);
      const verifiedAt = Number(result.verifiedAt);

      if (score > 0 && verifiedAt > 0) {
        console.log(`  [OK] ${asset.assetId}/${asset.originChain} → score: ${score}`);
      } else {
        console.log(`  [NEED] ${asset.assetId}/${asset.originChain} → not verified yet`);
        needsSeeding.push(asset);
      }
    } catch (e) {
      console.log(`  [NEED] ${asset.assetId}/${asset.originChain} → read error, will seed`);
      needsSeeding.push(asset);
    }
  }

  if (needsSeeding.length === 0) {
    console.log("[Global Setup] All assets verified. Ready to test.\n");
    return;
  }

  console.log(`\n[Global Setup] Seeding ${needsSeeding.length} assets on Paseo...`);

  if (!PRIVATE_KEY) {
    throw new Error("TEST_PRIVATE_KEY not set in .env.test — cannot seed assets");
  }

  const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
  const verifier = new ethers.Contract(VERIFIER_ADDRESS, VERIFIER_ABI, wallet);

  for (const asset of needsSeeding) {
    try {
      console.log(`  Verifying ${asset.assetId}/${asset.originChain}...`);
      const tx = await verifier.verifyAsset(asset.assetId, asset.originChain, asset.amount);
      await tx.wait(1);

      const result = await registry.getVerificationResult(asset.assetId, asset.originChain);
      console.log(`  Seeded: score=${result.score}`);
    } catch (e) {
      console.error(`  FAILED to seed ${asset.assetId}: ${e.message}`);
      throw e;
    }
  }

  console.log("[Global Setup] All assets seeded. Ready to test.\n");
}

module.exports = globalSetup;
