/* ===================================================================
   VeritasXCM -- Entry Point
   Binds all event listeners (no inline onclick handlers)
   =================================================================== */

document.addEventListener("DOMContentLoaded", function () {
  // --- Wallet ---
  document.getElementById("connectWalletBtn")
    .addEventListener("click", connectWallet);

  // --- Verify Form ---
  document.getElementById("verifyForm")
    .addEventListener("submit", handleVerify);

  // --- Read State ---
  document.getElementById("readStateBtn")
    .addEventListener("click", handleReadState);

  // --- XCM Send ---
  document.getElementById("xcmSendBtn")
    .addEventListener("click", sendXcmQuery);

  // --- Quick Fill Buttons ---
  var quickFillData = [
    { asset: "aDOT", chain: "acala", amount: 1000 },
    { asset: "iBTC", chain: "interlay", amount: 100 },
    { asset: "vDOT", chain: "bifrost", amount: 500 },
    { asset: "xcDOT", chain: "moonbeam", amount: 1000 },
  ];

  document.querySelectorAll(".quick-btn").forEach(function (btn, index) {
    var data = quickFillData[index];
    if (data) {
      btn.addEventListener("click", function (evt) {
        quickFill(data.asset, data.chain, data.amount, evt);
      });
    }
  });

  // --- Dashboard Cards ---
  document.querySelectorAll(".dash-card").forEach(function (card) {
    var asset = card.getAttribute("data-asset");
    var chain = card.getAttribute("data-chain");
    if (asset && chain) {
      card.addEventListener("click", function (evt) {
        var amounts = { aDOT: 1000, iBTC: 100, vDOT: 500, xcDOT: 1000 };
        quickFill(asset, chain, amounts[asset] || 1000, evt);
      });
    }
  });

  // --- Init ---
  animateStats();
  renderHistory();
  loadDashboard();
});
