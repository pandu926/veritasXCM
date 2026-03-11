// @ts-check
const { test, expect } = require("@playwright/test");
const { VeritasPage } = require("./pages/VeritasPage");

/**
 * Read State tests — hit LIVE Paseo testnet RPC.
 * Assets have been seeded on-chain via scripts/seed-assets.js.
 *
 * Expected scores (first verification):
 *   aDOT/acala    → 85 (supply:30 + minter:25 + hash:30 + history:0)
 *   iBTC/interlay → 85
 *   vDOT/bifrost  → 85
 *   xcDOT/moonbeam→ 60 (supply:30 + minter:0 + hash:30 + history:0)
 */
test.describe("Read Latest State (Live Paseo)", () => {
  let veritasPage;

  test.beforeEach(async ({ page }) => {
    veritasPage = new VeritasPage(page);
    await veritasPage.goto();
  });

  test("shows error when fields are empty", async () => {
    await veritasPage.readLatestState();

    await expect(veritasPage.resultContent).toBeVisible();
    await expect(veritasPage.resultMessage).toContainText(
      "Please enter Asset ID and Origin Chain",
    );
  });

  test("shows error when only asset ID is filled", async () => {
    await veritasPage.assetIdInput.fill("aDOT");
    await veritasPage.readLatestState();

    await expect(veritasPage.resultMessage).toContainText(
      "Please enter Asset ID and Origin Chain",
    );
  });

  test("shows error when only origin chain is filled", async () => {
    await veritasPage.originChainInput.fill("acala");
    await veritasPage.readLatestState();

    await expect(veritasPage.resultMessage).toContainText(
      "Please enter Asset ID and Origin Chain",
    );
  });

  test("reads aDOT/acala → score 85, VERIFIED", async ({ page }) => {
    await veritasPage.clickQuickFill("aDOT");
    await veritasPage.readLatestState();

    await expect(veritasPage.resultContent).toBeVisible({ timeout: 15000 });
    await page.waitForTimeout(2000);

    await expect(veritasPage.scoreValue).toHaveText("85");
    await expect(veritasPage.badgeText).toHaveText("VERIFIED");
    await expect(veritasPage.resultBadge).toHaveClass(/verified/);
    await expect(veritasPage.detailAsset).toHaveText("aDOT");
    await expect(veritasPage.detailOrigin).toHaveText("acala");
    await expect(veritasPage.detailAnomaly).toHaveText("None (Healthy)");

    // Verified At should show a real timestamp
    const verifiedAt = await veritasPage.detailVerifiedAt.textContent();
    expect(verifiedAt).not.toBe("—");
    expect(verifiedAt).not.toBe("Unknown");

    await page.screenshot({ path: "artifacts/live-read-adot-verified.png" });
  });

  test("reads iBTC/interlay → score 85, VERIFIED", async ({ page }) => {
    await veritasPage.clickQuickFill("iBTC");
    await veritasPage.readLatestState();

    await expect(veritasPage.resultContent).toBeVisible({ timeout: 15000 });
    await page.waitForTimeout(2000);

    await expect(veritasPage.scoreValue).toHaveText("85");
    await expect(veritasPage.badgeText).toHaveText("VERIFIED");
    await expect(veritasPage.detailAsset).toHaveText("iBTC");
    await expect(veritasPage.detailOrigin).toHaveText("interlay");
    await expect(veritasPage.detailAnomaly).toHaveText("None (Healthy)");

    await page.screenshot({ path: "artifacts/live-read-ibtc-verified.png" });
  });

  test("reads vDOT/bifrost → score 85, VERIFIED", async ({ page }) => {
    await veritasPage.clickQuickFill("vDOT");
    await veritasPage.readLatestState();

    await expect(veritasPage.resultContent).toBeVisible({ timeout: 15000 });
    await page.waitForTimeout(2000);

    await expect(veritasPage.scoreValue).toHaveText("85");
    await expect(veritasPage.badgeText).toHaveText("VERIFIED");
    await expect(veritasPage.detailAsset).toHaveText("vDOT");
    await expect(veritasPage.detailOrigin).toHaveText("bifrost");
    await expect(veritasPage.detailAnomaly).toHaveText("None (Healthy)");

    await page.screenshot({ path: "artifacts/live-read-vdot-verified.png" });
  });

  test("reads xcDOT/moonbeam → score 60, UNCERTAIN (minter not whitelisted)", async ({ page }) => {
    await veritasPage.clickQuickFill("xcDOT");
    await veritasPage.readLatestState();

    await expect(veritasPage.resultContent).toBeVisible({ timeout: 15000 });
    await page.waitForTimeout(2000);

    await expect(veritasPage.scoreValue).toHaveText("60");
    await expect(veritasPage.badgeText).toHaveText("UNCERTAIN");
    await expect(veritasPage.resultBadge).toHaveClass(/uncertain/);
    await expect(veritasPage.detailAsset).toHaveText("xcDOT");
    await expect(veritasPage.detailOrigin).toHaveText("moonbeam");
    await expect(veritasPage.detailAnomaly).toHaveText("None (Healthy)");
    await expect(veritasPage.resultMessage).toContainText("Caution");

    await page.screenshot({ path: "artifacts/live-read-xcdot-uncertain.png" });
  });

  test("non-existent asset returns no verification record", async ({ page }) => {
    await veritasPage.fillAssetForm("FAKECOIN", "nowhere", 999);
    await veritasPage.readLatestState();

    await expect(veritasPage.resultContent).toBeVisible({ timeout: 15000 });

    // Should show error — either "No verification record" or RPC error
    const scoreText = await veritasPage.scoreValue.textContent();
    expect(scoreText).toBe("ERR");

    await page.screenshot({ path: "artifacts/live-read-fake.png" });
  });

  test("button re-enables after read completes", async ({ page }) => {
    await veritasPage.clickQuickFill("aDOT");
    await veritasPage.readLatestState();

    await expect(veritasPage.resultContent).toBeVisible({ timeout: 15000 });
    await expect(veritasPage.readStateBtn).toBeEnabled();
    await expect(veritasPage.readStateBtn).toContainText("Read Latest State (No Tx)");
  });
});
