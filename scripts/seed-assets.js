/**
 * Seed Script — Verify all 4 assets on live Paseo testnet.
 *
 * Calls verifyAsset() for each asset so the registry has on-chain records.
 * Run this once before E2E tests or whenever you redeploy contracts.
 *
 * Usage:
 *   node scripts/seed-assets.js
 *
 * Expected results (first verification, no history):
 *   aDOT/acala    → score 85 (minter whitelisted)
 *   iBTC/interlay → score 85 (minter whitelisted)
 *   vDOT/bifrost  → score 85 (minter whitelisted)
 *   xcDOT/moonbeam→ score 60 (minter NOT whitelisted)
 */

const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

// ─── Load config from .env.test ────────────────────────────────
const envPath = path.join(__dirname, "../.env.test");
if (fs.existsSync(envPath)) {
  const envContent = fs.readFileSync(envPath, "utf-8");
  for (const line of envContent.split("\n")) {
    const [key, ...val] = line.split("=");
    if (key && val.length) process.env[key.trim()] = val.join("=").trim();
  }
}

const RPC_URL = process.env.RPC_URL || "https://eth-asset-hub-paseo.dotters.network";
const PRIVATE_KEY = process.env.TEST_PRIVATE_KEY;
const VERIFIER_ADDRESS = process.env.VERIFIER_ADDRESS || "0x6a141914Db10C0D3ccc00D5F9b970450f38F5863";
const REGISTRY_ADDRESS = process.env.REGISTRY_ADDRESS || "0x107e8156A1301e03F8Cf05DE20dD4E89e451F910";

if (!PRIVATE_KEY) {
  console.error("ERROR: TEST_PRIVATE_KEY not set. Check .env.test");
  process.exit(1);
}

const VERIFIER_ABI = [
  "function verifyAsset(string calldata assetId, string calldata originChain, uint256 amount) external returns (bool isVerified, uint8 score, string memory message)",
];

const REGISTRY_ABI = [
  "function getVerificationResult(string calldata assetId, string calldata originChain) external view returns (tuple(uint8 score, uint8 anomalyType, uint256 verifiedAt, bytes32 proof))",
];

// ─── Assets to seed ────────────────────────────────────────────
const ASSETS = [
  { assetId: "aDOT", originChain: "acala", amount: 1000 },
  { assetId: "iBTC", originChain: "interlay", amount: 100 },
  { assetId: "vDOT", originChain: "bifrost", amount: 500 },
  { assetId: "xcDOT", originChain: "moonbeam", amount: 1000 },
];

async function main() {
  console.log("═══════════════════════════════════════════════════════");
  console.log("  VeritasXCM — Seed Assets on Paseo Testnet");
  console.log("═══════════════════════════════════════════════════════\n");

  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
  const address = await wallet.getAddress();

  console.log(`Wallet:   ${address}`);
  console.log(`RPC:      ${RPC_URL}`);
  console.log(`Verifier: ${VERIFIER_ADDRESS}`);
  console.log(`Registry: ${REGISTRY_ADDRESS}\n`);

  // Check balance
  const balance = await provider.getBalance(address);
  console.log(`Balance:  ${ethers.formatEther(balance)} PAS\n`);

  if (balance === 0n) {
    console.error("ERROR: No balance. Fund the wallet with testnet PAS first.");
    process.exit(1);
  }

  const verifier = new ethers.Contract(VERIFIER_ADDRESS, VERIFIER_ABI, wallet);
  const registry = new ethers.Contract(REGISTRY_ADDRESS, REGISTRY_ABI, provider);

  const results = [];

  for (const asset of ASSETS) {
    console.log(`─── Verifying ${asset.assetId} / ${asset.originChain} ───`);

    try {
      // Check if already verified
      const existing = await registry.getVerificationResult(asset.assetId, asset.originChain);
      if (Number(existing.score) > 0 && Number(existing.verifiedAt) > 0) {
        console.log(`  Already verified: score=${existing.score}, skipping tx`);
        results.push({
          ...asset,
          score: Number(existing.score),
          anomalyType: Number(existing.anomalyType),
          status: "EXISTING",
        });
        continue;
      }
    } catch (e) {
      // No existing record, proceed with verification
    }

    try {
      console.log(`  Sending verifyAsset tx...`);
      const tx = await verifier.verifyAsset(asset.assetId, asset.originChain, asset.amount);
      console.log(`  Tx hash: ${tx.hash}`);
      console.log(`  Waiting for confirmation...`);

      const receipt = await tx.wait(1);
      console.log(`  Confirmed in block ${receipt.blockNumber}`);

      // Read result from registry
      const result = await registry.getVerificationResult(asset.assetId, asset.originChain);
      const score = Number(result.score);
      const anomalyType = Number(result.anomalyType);

      console.log(`  Score: ${score} | Anomaly: ${anomalyType} | Verified: ${score >= 70 ? "YES" : "NO"}`);

      results.push({
        ...asset,
        score,
        anomalyType,
        txHash: tx.hash,
        status: "NEW",
      });
    } catch (error) {
      console.error(`  FAILED: ${error.message}`);
      results.push({
        ...asset,
        score: 0,
        status: "FAILED",
        error: error.message,
      });
    }

    console.log("");
  }

  // ─── Summary ─────────────────────────────────────────────────
  console.log("═══════════════════════════════════════════════════════");
  console.log("  SEED RESULTS SUMMARY");
  console.log("═══════════════════════════════════════════════════════");
  console.log("");

  for (const r of results) {
    const statusIcon = r.score >= 70 ? "V" : r.score >= 50 ? "?" : r.score > 0 ? "X" : "!";
    const verified = r.score >= 70 ? "VERIFIED" : r.score >= 50 ? "UNCERTAIN" : r.score > 0 ? "SUSPICIOUS" : "FAILED";
    console.log(
      `  [${statusIcon}] ${r.assetId.padEnd(6)} / ${r.originChain.padEnd(10)} → score: ${String(r.score).padStart(3)} | ${verified} (${r.status})`,
    );
  }

  console.log("");

  const passed = results.filter((r) => r.score > 0).length;
  const failed = results.filter((r) => r.score === 0).length;
  console.log(`  Total: ${results.length} | Seeded: ${passed} | Failed: ${failed}`);
  console.log("═══════════════════════════════════════════════════════\n");

  // Exit with error code if any failed
  if (failed > 0) process.exit(1);
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
