/* ===================================================================
   VeritasXCM -- Frontend Application
   Web3 Integration for Paseo Testnet
   =================================================================== */

// Use local proxy on localhost to avoid CORS, direct RPC otherwise
const DIRECT_RPC = "https://eth-asset-hub-paseo.dotters.network";
const RPC_URL =
  window.location.hostname === "localhost" || window.location.hostname === "127.0.0.1"
    ? window.location.origin + "/rpc"
    : DIRECT_RPC;
const REGISTRY_ADDRESS = "0x9A340E7eeDA37623556A566473648365dfe390E1";
const VERIFIER_ADDRESS = "0xBb1Df6990CCCd16c32939c8E30fb38A9D2cFC820";
const PASEO_CHAIN_ID = 420420417;

const REGISTRY_ABI = [
  "function getVerificationResult(string calldata assetId, string calldata originChain) external view returns (tuple(uint8 score, uint8 anomalyType, uint256 verifiedAt, bytes32 proof))",
];

const VERIFIER_ABI = [
  "function verifyAsset(string calldata assetId, string calldata originChain, uint256 amount) external",
];

// --- Variables ---
const readOnlyProvider = new ethers.JsonRpcProvider(RPC_URL);
let provider;
let signer;
let userAddress;

// Pre-fill history with actual on-chain test data
const verificationHistory = [
  {
    assetId: "xcDOT",
    chain: "moonbeam",
    score: 60,
    isVerified: false,
    tx: "0x3c5aa9...7758",
    url: "https://paseo.subscan.io",
  },
  {
    assetId: "aDOT",
    chain: "acala",
    score: 85,
    isVerified: true,
    tx: "0x296e97...9a80",
    url: "https://paseo.subscan.io",
  },
];

// --- Utility: Escape HTML to prevent XSS ---
function escapeHtml(str) {
  const div = document.createElement("div");
  div.appendChild(document.createTextNode(str));
  return div.innerHTML;
}

// --- Wallet Connection ---
async function connectWallet() {
  if (typeof window.ethereum !== "undefined") {
    try {
      provider = new ethers.BrowserProvider(window.ethereum);

      // Switch to Paseo Network
      try {
        await window.ethereum.request({
          method: "wallet_switchEthereumChain",
          params: [{ chainId: "0x" + PASEO_CHAIN_ID.toString(16) }],
        });
      } catch (switchError) {
        if (switchError.code === 4902) {
          await window.ethereum.request({
            method: "wallet_addEthereumChain",
            params: [
              {
                chainId: "0x" + PASEO_CHAIN_ID.toString(16),
                chainName: "Paseo Asset Hub (pallet-revive)",
                rpcUrls: [DIRECT_RPC],
                nativeCurrency: { name: "PAS", symbol: "PAS", decimals: 18 },
              },
            ],
          });
        } else {
          throw switchError;
        }
      }

      signer = await provider.getSigner();
      userAddress = await signer.getAddress();

      document.getElementById("connectWalletBtn").style.display = "none";
      document.getElementById("connectedState").style.display = "flex";
      document.getElementById("statusText").innerText =
        userAddress.substring(0, 6) + "..." + userAddress.substring(38);
    } catch (_error) {
      showError("Connection failed. Please check MetaMask console.");
    }
  } else {
    showError(
      "Please install MetaMask or another Web3 wallet to submit transactions.",
    );
  }
}

// --- Show Error in UI ---
function showError(msg) {
  document.getElementById("resultEmpty").style.display = "none";
  const content = document.getElementById("resultContent");
  content.style.display = "block";

  document.getElementById("scoreRingFill").style.strokeDashoffset =
    2 * Math.PI * 70;
  document.getElementById("scoreValue").textContent = "ERR";
  document.getElementById("scoreValue").style.color = "var(--danger)";

  const badge = document.getElementById("resultBadge");
  badge.className = "result-badge suspicious";
  document.getElementById("badgeIcon").textContent = "X";
  document.getElementById("badgeText").textContent = "ERROR";

  document.getElementById("resultMessage").textContent = msg;
  document.getElementById("txHashLink").textContent = "";
}

// --- Quick Fill (receives event explicitly) ---
function quickFill(assetId, chain, amount, evt) {
  document.getElementById("assetId").value = assetId;
  document.getElementById("originChain").value = chain;
  document.getElementById("amount").value = amount;

  document.querySelectorAll(".quick-btn").forEach(function (btn) {
    btn.style.borderColor = "";
  });
  if (evt && evt.currentTarget) {
    evt.currentTarget.style.borderColor = "var(--pink)";
  }
}

// --- Handle Read State (No Tx) ---
async function handleReadState() {
  const assetId = document.getElementById("assetId").value.trim();
  const originChain = document.getElementById("originChain").value.trim();

  if (!assetId || !originChain) {
    showError("Please enter Asset ID and Origin Chain");
    return;
  }

  const btn = document.querySelector(
    '.btn-connect[onclick="handleReadState()"]',
  );
  const originalText = btn.textContent;
  btn.textContent = "Reading from Paseo...";
  btn.disabled = true;

  try {
    const registry = new ethers.Contract(
      REGISTRY_ADDRESS,
      REGISTRY_ABI,
      readOnlyProvider,
    );
    const result = await registry.getVerificationResult(assetId, originChain);

    const score = Number(result.score);
    const anomalyType = Number(result.anomalyType);
    const verifiedAt = Number(result.verifiedAt);

    if (score === 0 && verifiedAt === 0) {
      showError(
        "No verification record found for this asset on Paseo Testnet.",
      );
      btn.textContent = originalText;
      btn.disabled = false;
      return;
    }

    displayResult(
      score,
      assetId,
      originChain,
      verifiedAt,
      anomalyType,
      "Read from Paseo RPC via readOnlyProvider",
    );
  } catch (error) {
    if (error.message && error.message.includes("CORS")) {
      showError(
        "CORS Error: The Paseo RPC node blocked the connection. See console.",
      );
    } else {
      showError(
        "Failed to read data. This might be due to no record existing or an RPC timeout.",
      );
    }
  } finally {
    btn.textContent = originalText;
    btn.disabled = false;
  }
}

// --- Handle Verification (Tx Submit) ---
async function handleVerify(e) {
  e.preventDefault();

  if (!signer) {
    showError("Please connect your wallet first to submit a transaction.");
    return;
  }

  const assetId = document.getElementById("assetId").value.trim();
  const originChain = document.getElementById("originChain").value.trim();
  const amountRaw = document.getElementById("amount").value.trim();

  if (!assetId || !originChain || !amountRaw) {
    showError("Please enter all fields.");
    return;
  }

  // Use BigInt for uint256 precision
  let amount;
  try {
    amount = BigInt(amountRaw);
  } catch (_e) {
    showError("Invalid amount. Please enter a valid number.");
    return;
  }

  if (amount <= 0n) {
    showError("Amount must be greater than zero.");
    return;
  }

  const btn = document.getElementById("verifyBtn");
  btn.querySelector(".btn-verify__text").style.display = "none";
  btn.querySelector(".btn-verify__loading").style.display = "inline";
  btn.disabled = true;

  try {
    const verifier = new ethers.Contract(
      VERIFIER_ADDRESS,
      VERIFIER_ABI,
      signer,
    );

    const tx = await verifier.verifyAsset(assetId, originChain, amount);

    // Wait for confirmation
    await tx.wait(1);

    // Read immediately after using read-only provider
    const registry = new ethers.Contract(
      REGISTRY_ADDRESS,
      REGISTRY_ABI,
      readOnlyProvider,
    );
    const result = await registry.getVerificationResult(assetId, originChain);
    const score = Number(result.score);
    const anomalyType = Number(result.anomalyType);
    const verifiedAt = Number(result.verifiedAt);

    displayResult(score, assetId, originChain, verifiedAt, anomalyType, tx.hash);
    addToHistory(assetId, originChain, score, tx.hash);
  } catch (_error) {
    showError("Verification failed. Please try again.");
  } finally {
    btn.querySelector(".btn-verify__text").style.display = "inline";
    btn.querySelector(".btn-verify__loading").style.display = "none";
    btn.disabled = false;
  }
}

// --- Display Result ---
function displayResult(
  score,
  assetId,
  chain,
  verifiedAt,
  anomalyType,
  txHashOrMsg,
) {
  document.getElementById("resultEmpty").style.display = "none";
  const content = document.getElementById("resultContent");
  content.style.display = "block";
  content.style.animation = "none";
  void content.offsetHeight;
  content.style.animation = "fadeIn 0.5s ease-out";

  animateScore(score);

  const badge = document.getElementById("resultBadge");
  const badgeIcon = document.getElementById("badgeIcon");
  const badgeText = document.getElementById("badgeText");
  const msgEl = document.getElementById("resultMessage");

  badge.className = "result-badge";

  if (score >= 90) {
    badge.classList.add("verified");
    badgeIcon.textContent = "V";
    badgeText.textContent = "HIGH CONFIDENCE";
    msgEl.textContent =
      "Asset perfectly matches supply. Fully verified via XCM.";
  } else if (score >= 70) {
    badge.classList.add("verified");
    badgeIcon.textContent = "V";
    badgeText.textContent = "VERIFIED";
    msgEl.textContent =
      "Asset acceptable, minor anomalies detected but within normal variance.";
  } else if (score >= 50) {
    badge.classList.add("uncertain");
    badgeIcon.textContent = "!";
    badgeText.textContent = "UNCERTAIN";
    msgEl.textContent =
      "Major discrepancies in supply or scoring. Caution advised.";
  } else {
    badge.classList.add("suspicious");
    badgeIcon.textContent = "X";
    badgeText.textContent = "SUSPICIOUS";
    msgEl.textContent =
      "ALERT: Suspicious asset detected. High risk of counterfeit.";
  }

  // Mapping anomalyType
  const anomalyMap = {
    0: "None (Healthy)",
    1: "Supply Spike (Mint)",
    2: "Supply Drop (Burn/Exploit)",
    3: "Unwhitelisted Minter",
  };

  const safeRef = escapeHtml(
    typeof txHashOrMsg === "string" ? txHashOrMsg.substring(0, 25) + "..." : "",
  );
  document.getElementById("txHashLink").textContent = "Ref: " + safeRef;
  document.getElementById("detailAsset").textContent = escapeHtml(assetId);
  document.getElementById("detailOrigin").textContent = escapeHtml(chain);

  // Format verifiedAt timestamp
  var formattedTime = "Unknown";
  try {
    if (verifiedAt > 0) {
      var date = new Date(verifiedAt * 1000);
      formattedTime = date.toLocaleString();
    }
  } catch (_e) {
    formattedTime = String(verifiedAt);
  }

  document.getElementById("detailSupply").textContent = formattedTime;
  document.getElementById("detailAnomaly").textContent =
    anomalyMap[anomalyType] || "Unknown";
}

// --- Score Animation ---
function animateScore(targetScore) {
  const ring = document.getElementById("scoreRingFill");
  const valueEl = document.getElementById("scoreValue");
  const circumference = 2 * Math.PI * 70;

  var color;
  if (targetScore >= 90) color = "var(--safe)";
  else if (targetScore >= 70) color = "var(--warn)";
  else if (targetScore >= 50) color = "var(--uncertain)";
  else color = "var(--danger)";

  ring.style.stroke = color;
  valueEl.style.color = color;

  var offset = circumference - (targetScore / 100) * circumference;
  ring.style.strokeDashoffset = circumference;
  requestAnimationFrame(function () {
    ring.style.strokeDashoffset = offset;
  });

  var duration = 1200;
  var start = performance.now();

  function tick(now) {
    var elapsed = now - start;
    var progress = Math.min(elapsed / duration, 1);
    var eased = 1 - Math.pow(1 - progress, 3);
    valueEl.textContent = Math.round(eased * targetScore);
    if (progress < 1) requestAnimationFrame(tick);
  }
  requestAnimationFrame(tick);
}

// --- History ---
function addToHistory(assetId, chain, score, txHash) {
  var isVerified = score >= 70;
  var entry = {
    assetId: assetId,
    chain: chain,
    score: score,
    isVerified: isVerified,
    tx: txHash.substring(0, 10) + "..." + txHash.substring(60),
  };

  verificationHistory.unshift(entry);
  if (verificationHistory.length > 10) verificationHistory.pop();
  renderHistory();
}

function renderHistory() {
  var tbody = document.getElementById("historyBody");
  // Clear existing content safely
  tbody.textContent = "";

  verificationHistory.forEach(function (entry) {
    var scoreClass =
      entry.score >= 90
        ? "high"
        : entry.score >= 70
          ? "medium"
          : entry.score >= 50
            ? "low"
            : "critical";
    var statusClass = entry.isVerified ? "verified" : "rejected";
    var statusText = entry.isVerified ? "Verified" : "Rejected";

    var tr = document.createElement("tr");

    var tdAsset = document.createElement("td");
    var strong = document.createElement("strong");
    strong.textContent = entry.assetId;
    tdAsset.appendChild(strong);

    var tdChain = document.createElement("td");
    tdChain.textContent = entry.chain;

    var tdScore = document.createElement("td");
    var scoreBadge = document.createElement("span");
    scoreBadge.className = "score-badge " + scoreClass;
    scoreBadge.textContent = entry.score;
    tdScore.appendChild(scoreBadge);

    var tdStatus = document.createElement("td");
    var statusTag = document.createElement("span");
    statusTag.className = "status-tag " + statusClass;
    statusTag.textContent = statusText;
    tdStatus.appendChild(statusTag);

    var tdTx = document.createElement("td");
    tdTx.style.cssText = "color: var(--text-muted); font-family: 'JetBrains Mono', monospace; font-size: 0.78rem;";
    tdTx.textContent = entry.tx || "Read Only";

    tr.appendChild(tdAsset);
    tr.appendChild(tdChain);
    tr.appendChild(tdScore);
    tr.appendChild(tdStatus);
    tr.appendChild(tdTx);

    tbody.appendChild(tr);
  });
}

// --- Initialize ---
document.addEventListener("DOMContentLoaded", function () {
  animateStats();
  renderHistory();
});

function animateStats() {
  document.querySelectorAll(".stat-card__value").forEach(function (el) {
    if (el.textContent === "LIVE") return;
    var target = parseInt(el.textContent);
    if (isNaN(target)) return;
    el.textContent = "0";
    var duration = 1500;
    var start = performance.now();

    function tick(now) {
      var progress = Math.min((now - start) / duration, 1);
      var eased = 1 - Math.pow(1 - progress, 3);
      el.textContent = Math.round(eased * target);
      if (progress < 1) requestAnimationFrame(tick);
    }
    requestAnimationFrame(tick);
  });
}
