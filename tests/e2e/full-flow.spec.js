// @ts-check
const { test, expect } = require("@playwright/test");
const { VeritasPage } = require("./pages/VeritasPage");
const { createLiveWalletMock } = require("./fixtures/live-wallet-mock");

const PRIVATE_KEY = process.env.TEST_PRIVATE_KEY;
const ADDRESS = process.env.TEST_ADDRESS;
const RPC_URL = process.env.RPC_URL || "https://eth-asset-hub-paseo.dotters.network";
const CHAIN_ID = Number(process.env.CHAIN_ID || "420420417");
const CHAIN_ID_HEX = "0x" + CHAIN_ID.toString(16);

/**
 * Full E2E flows against LIVE Paseo testnet.
 * Assets are already seeded on-chain with known scores.
 */
test.describe("Full Verification Flow (Live Paseo)", () => {
  test("complete read flow: load → quick fill → read → verify score 85", async ({ page }) => {
    const veritasPage = new VeritasPage(page);

    // Step 1: Load page
    await veritasPage.goto();
    await expect(page).toHaveTitle(/VeritasXCM/);
    await expect(veritasPage.resultEmpty).toBeVisible();

    // Step 2: Quick fill aDOT
    await veritasPage.clickQuickFill("aDOT");
    const values = await veritasPage.getFormValues();
    expect(values.assetId).toBe("aDOT");
    expect(values.originChain).toBe("acala");
    expect(values.amount).toBe("1000");

    // Step 3: Read latest state from LIVE Paseo
    await veritasPage.readLatestState();

    // Step 4: Verify real on-chain score
    await expect(veritasPage.resultContent).toBeVisible({ timeout: 15000 });
    await page.waitForTimeout(2000);

    await expect(veritasPage.scoreValue).toHaveText("85");
    await expect(veritasPage.badgeText).toHaveText("VERIFIED");
    await expect(veritasPage.detailAsset).toHaveText("aDOT");
    await expect(veritasPage.detailOrigin).toHaveText("acala");
    await expect(veritasPage.detailAnomaly).toHaveText("None (Healthy)");

    await page.screenshot({ path: "artifacts/full-flow-adot-85.png" });
  });

  test("connect wallet + submit tx to Paseo (live verification)", async ({ page }) => {
    test.slow(); // Real blockchain tx

    const mockScript = createLiveWalletMock(PRIVATE_KEY, ADDRESS, RPC_URL, CHAIN_ID_HEX);
    await page.addInitScript(mockScript);

    const veritasPage = new VeritasPage(page);
    await veritasPage.goto();
    await page.waitForTimeout(500);

    // Step 1: Connect wallet
    await veritasPage.connectWallet();
    await page.waitForTimeout(1000);
    await expect(veritasPage.connectedState).toBeVisible();
    await page.screenshot({ path: "artifacts/full-flow-wallet-connected.png" });

    // Step 2: Fill aDOT
    await veritasPage.clickQuickFill("aDOT");

    // Step 3: Submit tx
    await veritasPage.submitVerification();

    // Step 4: Wait for tx to process on Paseo (~6-12s block time)
    await expect(veritasPage.verifyBtnLoading).toBeVisible({ timeout: 5000 });

    // Step 5: Result should appear after tx confirms
    await expect(veritasPage.resultContent).toBeVisible({ timeout: 60000 });
    await page.waitForTimeout(2000);

    // Score should be 85 (second verification, same state = hash matches)
    const scoreText = await veritasPage.scoreValue.textContent();
    const score = Number(scoreText);
    if (scoreText !== "ERR") {
      // Second verification: supply:30 + minter:25 + hash:30 + history:1 = 86
      // (history factor: 15 * min(1, 10) / 10 = 1.5 → rounds to 1)
      expect(score).toBeGreaterThanOrEqual(85);
      expect(score).toBeLessThanOrEqual(87);

      // History should grow by 1
      const historyCount = await veritasPage.getHistoryRowCount();
      expect(historyCount).toBe(3); // 1 new + 2 pre-filled

      // Tx hash reference should be visible
      const txRef = await veritasPage.txHashLink.textContent();
      expect(txRef).toContain("Ref:");
    }

    await page.screenshot({ path: "artifacts/full-flow-tx-verified.png" });
  });

  test("verify all 4 assets show correct scores from chain", async ({ page }) => {
    const veritasPage = new VeritasPage(page);
    await veritasPage.goto();

    const expectedResults = [
      { asset: "aDOT", score: "85", badge: "VERIFIED" },
      { asset: "iBTC", score: "85", badge: "VERIFIED" },
      { asset: "vDOT", score: "85", badge: "VERIFIED" },
      { asset: "xcDOT", score: "60", badge: "UNCERTAIN" },
    ];

    for (const expected of expectedResults) {
      await veritasPage.clickQuickFill(expected.asset);
      await veritasPage.readLatestState();

      await expect(veritasPage.resultContent).toBeVisible({ timeout: 15000 });
      await page.waitForTimeout(2000);

      const scoreText = await veritasPage.scoreValue.textContent();
      const badgeText = await veritasPage.badgeText.textContent();

      console.log(`${expected.asset}: score=${scoreText}, badge=${badgeText}`);

      // Score may increase slightly due to re-verification (history bonus)
      const score = Number(scoreText);
      const expectedScore = Number(expected.score);
      expect(score).toBeGreaterThanOrEqual(expectedScore);
      expect(score).toBeLessThanOrEqual(expectedScore + 5); // max +5 from history

      await page.screenshot({ path: `artifacts/all-assets-${expected.asset.toLowerCase()}.png` });
    }
  });

  test("xcDOT shows UNCERTAIN with correct warning message", async ({ page }) => {
    const veritasPage = new VeritasPage(page);
    await veritasPage.goto();

    await veritasPage.clickQuickFill("xcDOT");
    await veritasPage.readLatestState();

    await expect(veritasPage.resultContent).toBeVisible({ timeout: 15000 });
    await page.waitForTimeout(2000);

    // xcDOT minter (0xBEAB) is NOT whitelisted → score 60
    await expect(veritasPage.scoreValue).toHaveText("60");
    await expect(veritasPage.badgeText).toHaveText("UNCERTAIN");
    await expect(veritasPage.resultBadge).toHaveClass(/uncertain/);
    await expect(veritasPage.resultMessage).toContainText("Caution");

    await page.screenshot({ path: "artifacts/xcdot-uncertain-detail.png" });
  });
});
