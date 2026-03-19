/**
 * Refresh Oracle — Update timestamps on MockXcmOracle so data isn't stale.
 *
 * The XcmAssetVerifier has MAX_DATA_AGE = 1 hour. If the oracle data
 * timestamps are older than 1 hour, verifyAsset() reverts with StaleOracleData().
 *
 * Run this before verifying assets if the oracle was deployed more than 1 hour ago.
 *
 * Usage:
 *   node scripts/refresh-oracle.js
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
const ORACLE_ADDRESS = process.env.ORACLE_ADDRESS;

if (!PRIVATE_KEY) {
  console.error("ERROR: TEST_PRIVATE_KEY not set. Check .env.test");
  process.exit(1);
}

if (!ORACLE_ADDRESS) {
  console.error("ERROR: ORACLE_ADDRESS not set. Check .env.test");
  process.exit(1);
}

const ORACLE_ABI = [
  "function setAssetState(uint32 paraId, string memory assetId, uint256 totalSupply, address minter, bytes32 stateHash) external",
];

// Same assets and params as the constructor's _seedDefaultParachains()
const ASSETS = [
  {
    paraId: 2000,
    assetId: "aDOT",
    supply: ethers.parseEther("50000"),
    minter: "0x000000000000000000000000000000000000ACA1",
  },
  {
    paraId: 2032,
    assetId: "iBTC",
    supply: ethers.parseEther("21000"),
    minter: "0x0000000000000000000000000000000000001B7C",
  },
  {
    paraId: 2030,
    assetId: "vDOT",
    supply: ethers.parseEther("100000"),
    minter: "0x000000000000000000000000000000000000BF05",
  },
  {
    paraId: 2004,
    assetId: "xcDOT",
    supply: ethers.parseEther("30000"),
    minter: "0x000000000000000000000000000000000000BEAB",
  },
];

function computeHash(assetId, supply) {
  return ethers.keccak256(ethers.solidityPacked(["string", "uint256"], [assetId, supply]));
}

async function main() {
  console.log("═══════════════════════════════════════════════════════");
  console.log("  VeritasXCM — Refresh Oracle Data (fix StaleOracleData)");
  console.log("═══════════════════════════════════════════════════════\n");

  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
  const address = await wallet.getAddress();

  console.log(`Wallet:  ${address}`);
  console.log(`Oracle:  ${ORACLE_ADDRESS}\n`);

  const oracle = new ethers.Contract(ORACLE_ADDRESS, ORACLE_ABI, wallet);

  for (const asset of ASSETS) {
    const stateHash = computeHash(asset.assetId, asset.supply);
    console.log(`Refreshing ${asset.assetId} (paraId: ${asset.paraId})...`);

    try {
      const tx = await oracle.setAssetState(
        asset.paraId,
        asset.assetId,
        asset.supply,
        asset.minter,
        stateHash,
        { gasLimit: 500000 },
      );
      console.log(`  Tx: ${tx.hash}`);
      await tx.wait(1);
      console.log(`  Done.`);
    } catch (error) {
      console.error(`  FAILED: ${error.reason || error.message}`);
    }
  }

  console.log("\nOracle data refreshed. Timestamps are now current.");
  console.log("You can now run: node scripts/seed-assets.js\n");
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
