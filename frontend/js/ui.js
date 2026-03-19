/* ===================================================================
   VeritasXCM -- UI Helpers
   =================================================================== */

// --- Utility: Escape HTML to prevent XSS ---
function escapeHtml(str) {
  var div = document.createElement("div");
  div.appendChild(document.createTextNode(str));
  return div.innerHTML;
}

// --- Show Error in UI ---
function showError(msg) {
  document.getElementById("resultEmpty").classList.add("hidden");
  var content = document.getElementById("resultContent");
  content.classList.remove("hidden");

  document.getElementById("scoreRingFill").style.strokeDashoffset =
    SCORE_RING_CIRCUMFERENCE;
  document.getElementById("scoreValue").textContent = "ERR";
  document.getElementById("scoreValue").style.color = "var(--danger)";

  var badge = document.getElementById("resultBadge");
  badge.className = "result-badge suspicious";
  document.getElementById("badgeIcon").textContent = "X";
  document.getElementById("badgeText").textContent = "ERROR";

  document.getElementById("resultMessage").textContent = msg;
  document.getElementById("txHashLink").textContent = "";
}

// --- Quick Fill ---
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

// --- History (Immutable) ---
// Seed entries from actual on-chain test verifications
var verificationHistory = [
  { assetId: "xcDOT", chain: "moonbeam", score: 60, isVerified: false, tx: "0x3c5aa9...7758" },
  { assetId: "aDOT", chain: "acala", score: 85, isVerified: true, tx: "0x296e97...9a80" },
];

function addToHistory(assetId, chain, score, txHash) {
  var isVerified = score >= 70;
  var entry = {
    assetId: assetId,
    chain: chain,
    score: score,
    isVerified: isVerified,
    tx: txHash.substring(0, 10) + "..." + txHash.substring(60),
  };

  // Immutable update: create new array instead of mutating
  verificationHistory = [entry].concat(verificationHistory).slice(0, 10);
  renderHistory();
}

function renderHistory() {
  var tbody = document.getElementById("historyBody");
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
    tdTx.className = "td-tx-hash";
    tdTx.textContent = entry.tx || "Read Only";

    tr.appendChild(tdAsset);
    tr.appendChild(tdChain);
    tr.appendChild(tdScore);
    tr.appendChild(tdStatus);
    tr.appendChild(tdTx);

    tbody.appendChild(tr);
  });
}

// --- Ecosystem Health Dashboard ---
async function loadDashboard() {
  var registry = new ethers.Contract(REGISTRY_ADDRESS, REGISTRY_ABI, readOnlyProvider);
  var cards = document.querySelectorAll(".dash-card");

  var tasks = DASHBOARD_ASSETS.map(function (asset, i) {
    var card = cards[i];
    if (!card) return Promise.resolve();

    var scoreEl = card.querySelector(".dash-card__score");
    var statusEl = card.querySelector(".dash-card__status");

    return registry.getVerificationResult(asset.assetId, asset.chain)
      .then(function (result) {
        var score = Number(result.score);
        var verifiedAt = Number(result.verifiedAt);

        if (score === 0 && verifiedAt === 0) {
          scoreEl.textContent = "--";
          statusEl.textContent = "NO DATA";
          return;
        }

        scoreEl.textContent = String(score);

        if (score >= 90) {
          scoreEl.style.color = "var(--safe)";
          statusEl.textContent = "HIGH CONFIDENCE";
          statusEl.className = "dash-card__status verified";
        } else if (score >= 70) {
          scoreEl.style.color = "var(--warn)";
          statusEl.textContent = "VERIFIED";
          statusEl.className = "dash-card__status verified";
        } else if (score >= 50) {
          scoreEl.style.color = "var(--uncertain)";
          statusEl.textContent = "UNCERTAIN";
          statusEl.className = "dash-card__status uncertain";
        } else {
          scoreEl.style.color = "var(--danger)";
          statusEl.textContent = "SUSPICIOUS";
          statusEl.className = "dash-card__status suspicious";
        }
      })
      .catch(function () {
        scoreEl.textContent = "--";
        statusEl.textContent = "ERROR";
      });
  });

  await Promise.allSettled(tasks);
}

// --- Animate Stats ---
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
