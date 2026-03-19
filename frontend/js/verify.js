/* ===================================================================
   VeritasXCM -- Verification Logic
   =================================================================== */

// --- Input Validation ---
function validateInputLength(value, fieldName) {
  if (value.length > MAX_INPUT_LENGTH) {
    showError(fieldName + " must be " + MAX_INPUT_LENGTH + " characters or less.");
    return false;
  }
  return true;
}

// --- Handle Read State (No Tx) ---
async function handleReadState() {
  var assetId = document.getElementById("assetId").value.trim();
  var originChain = document.getElementById("originChain").value.trim();

  if (!assetId || !originChain) {
    showError("Please enter Asset ID and Origin Chain");
    return;
  }

  if (!validateInputLength(assetId, "Asset ID")) return;
  if (!validateInputLength(originChain, "Origin Chain")) return;

  var btn = document.getElementById("readStateBtn");
  var originalText = btn.textContent;
  btn.textContent = "Reading from Paseo...";
  btn.disabled = true;

  try {
    var registry = new ethers.Contract(
      REGISTRY_ADDRESS,
      REGISTRY_ABI,
      readOnlyProvider,
    );
    var result = await registry.getVerificationResult(assetId, originChain);

    var score = Number(result.score);
    var anomalyType = Number(result.anomalyType);
    var verifiedAt = Number(result.verifiedAt);

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
var _lastVerifyTime = 0;

async function handleVerify(e) {
  e.preventDefault();

  if (!signer) {
    showError("Please connect your wallet first to submit a transaction.");
    return;
  }

  var assetId = document.getElementById("assetId").value.trim();
  var originChain = document.getElementById("originChain").value.trim();
  var amountRaw = document.getElementById("amount").value.trim();

  if (!assetId || !originChain || !amountRaw) {
    showError("Please enter all fields.");
    return;
  }

  if (!validateInputLength(assetId, "Asset ID")) return;
  if (!validateInputLength(originChain, "Origin Chain")) return;

  // Use BigInt for uint256 precision
  var amount;
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

  // Rate limiting: prevent rapid re-submission
  var now = Date.now();
  if (now - _lastVerifyTime < VERIFY_COOLDOWN_MS) {
    var remaining = Math.ceil((VERIFY_COOLDOWN_MS - (now - _lastVerifyTime)) / 1000);
    showError("Please wait " + remaining + " seconds before verifying again.");
    return;
  }

  var btn = document.getElementById("verifyBtn");
  btn.querySelector(".btn-verify__text").classList.add("hidden");
  btn.querySelector(".btn-verify__loading").classList.remove("hidden");
  btn.disabled = true;

  try {
    var verifier = new ethers.Contract(
      VERIFIER_ADDRESS,
      VERIFIER_ABI,
      signer,
    );

    var tx = await verifier.verifyAsset(assetId, originChain, amount);

    // Wait for confirmation
    await tx.wait(1);

    _lastVerifyTime = Date.now();
    startVerifyCooldown(btn);

    // Read immediately after using read-only provider
    var registry = new ethers.Contract(
      REGISTRY_ADDRESS,
      REGISTRY_ABI,
      readOnlyProvider,
    );
    var result = await registry.getVerificationResult(assetId, originChain);
    var score = Number(result.score);
    var anomalyType = Number(result.anomalyType);
    var verifiedAt = Number(result.verifiedAt);

    displayResult(score, assetId, originChain, verifiedAt, anomalyType, tx.hash);
    addToHistory(assetId, originChain, score, tx.hash);
  } catch (error) {
    // Parse revert reason for user-friendly messages
    var errorData = String(error.data || (error.error && error.error.data) || "");
    var reason = error.reason || error.shortMessage || "";
    var msg = "Verification failed. ";

    // Match custom error selector (first 10 hex chars = 4 bytes)
    var selector = errorData.length >= 10 ? errorData.substring(0, 10).toLowerCase() : "";
    var selectorMsg = ERROR_SELECTORS[selector];

    if (error.code === "ACTION_REJECTED" || error.code === 4001) {
      msg = "Transaction was rejected by the wallet.";
    } else if (selectorMsg) {
      msg += selectorMsg;
    } else if (reason.includes("insufficient funds") || reason.includes("INSUFFICIENT")) {
      msg += "Insufficient PAS balance for gas fees.";
    } else {
      msg += reason || "Unknown error. Check browser console.";
      console.error("Verification error details:", error);
    }

    showError(msg);
  } finally {
    btn.querySelector(".btn-verify__text").classList.remove("hidden");
    btn.querySelector(".btn-verify__loading").classList.add("hidden");
    if (Date.now() - _lastVerifyTime >= VERIFY_COOLDOWN_MS) {
      btn.disabled = false;
    }
  }
}

// --- Verify Button Cooldown ---
var _cooldownTimer = null;

function startVerifyCooldown(btn) {
  var textEl = btn.querySelector(".btn-verify__text");
  var end = _lastVerifyTime + VERIFY_COOLDOWN_MS;

  if (_cooldownTimer) clearInterval(_cooldownTimer);

  function tick() {
    var remaining = Math.ceil((end - Date.now()) / 1000);
    if (remaining <= 0) {
      clearInterval(_cooldownTimer);
      _cooldownTimer = null;
      textEl.textContent = "Verify on Paseo (Submit Tx)";
      btn.disabled = false;
      return;
    }
    textEl.textContent = "Wait " + remaining + "s...";
    btn.disabled = true;
  }
  tick();
  _cooldownTimer = setInterval(tick, 1000);
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
  document.getElementById("resultEmpty").classList.add("hidden");
  var content = document.getElementById("resultContent");
  content.classList.remove("hidden");
  content.style.animation = "none";
  void content.offsetHeight;
  content.style.animation = "fadeIn 0.5s ease-out";

  animateScore(score);

  var badge = document.getElementById("resultBadge");
  var badgeIcon = document.getElementById("badgeIcon");
  var badgeText = document.getElementById("badgeText");
  var msgEl = document.getElementById("resultMessage");

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
  var anomalyMap = {
    0: "None (Healthy)",
    1: "Supply Spike (Mint)",
    2: "Supply Drop (Burn/Exploit)",
    3: "Unwhitelisted Minter",
  };

  var safeRef = escapeHtml(
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

  document.getElementById("detailVerifiedAt").textContent = formattedTime;
  document.getElementById("detailAnomaly").textContent =
    anomalyMap[anomalyType] || "Unknown";
}

// --- Score Animation ---
function animateScore(targetScore) {
  var ring = document.getElementById("scoreRingFill");
  var valueEl = document.getElementById("scoreValue");
  var circumference = SCORE_RING_CIRCUMFERENCE;

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

// --- XCM Send (Real Precompile Call) ---
async function sendXcmQuery() {
  if (!signer) {
    showError("Please connect your wallet first to send an XCM message.");
    return;
  }

  var btn = document.getElementById("xcmSendBtn");
  if (!btn) return;
  var originalText = btn.textContent;
  btn.textContent = "Sending XCM...";
  btn.disabled = true;

  try {
    var xcmContract = new ethers.Contract(XCM_PRECOMPILE, XCM_ABI, signer);

    var tx = await xcmContract.send(XCM_DESTINATION, XCM_MESSAGE);
    await tx.wait(1);

    btn.textContent = "XCM Sent!";
    btn.style.borderColor = "var(--safe)";

    // Add to history
    addToHistory("XCM-Query", "relay-chain", 100, tx.hash);
  } catch (error) {
    btn.textContent = "XCM Failed";
    btn.style.borderColor = "var(--danger)";
    showError("XCM send failed: " + (error.reason || error.message || "Unknown error"));
  } finally {
    setTimeout(function () {
      btn.textContent = originalText;
      btn.disabled = false;
      btn.style.borderColor = "";
    }, 3000);
  }
}
