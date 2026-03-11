// @ts-check
const { test, expect } = require("@playwright/test");
const { VeritasPage } = require("./pages/VeritasPage");

test.describe("Page Load & Initial State", () => {
  let veritasPage;

  test.beforeEach(async ({ page }) => {
    veritasPage = new VeritasPage(page);
    await veritasPage.goto();
  });

  test("page loads with correct title", async ({ page }) => {
    await expect(page).toHaveTitle(/VeritasXCM/);
  });

  test("header displays brand name and subtitle", async () => {
    await expect(veritasPage.headerTitle).toHaveText("VeritasXCM");
    await expect(veritasPage.headerSubtitle).toContainText(
      "Trustless Cross-Chain Verification",
    );
  });

  test("connect wallet button is visible initially", async () => {
    await expect(veritasPage.connectWalletBtn).toBeVisible();
    await expect(veritasPage.connectWalletBtn).toHaveText("Connect Wallet");
  });

  test("connected state is hidden initially", async () => {
    await expect(veritasPage.connectedState).not.toBeVisible();
  });

  test("four stat cards are displayed", async () => {
    await expect(veritasPage.statCards).toHaveCount(4);
  });

  test("stat values animate to target numbers", async ({ page }) => {
    await page.waitForTimeout(2000);

    const testsVal = await veritasPage.statTests.textContent();
    expect(Number(testsVal)).toBe(152);

    const parachainsVal = await veritasPage.statParachains.textContent();
    expect(Number(parachainsVal)).toBe(4);

    const contractsVal = await veritasPage.statContracts.textContent();
    expect(Number(contractsVal)).toBe(9);
  });

  test("LIVE status is displayed for Paseo Testnet", async ({ page }) => {
    const liveCard = page.locator('.stat-card__value:has-text("LIVE")');
    await expect(liveCard).toBeVisible();
  });

  test("verify panel is visible with form inputs", async () => {
    await expect(veritasPage.verifyPanel).toBeVisible();
    await expect(veritasPage.assetIdInput).toBeVisible();
    await expect(veritasPage.originChainInput).toBeVisible();
    await expect(veritasPage.amountInput).toBeVisible();
  });

  test("result panel shows empty state initially", async () => {
    await expect(veritasPage.resultEmpty).toBeVisible();
    await expect(veritasPage.resultContent).not.toBeVisible();
  });

  test("empty state shows correct message", async () => {
    await expect(veritasPage.resultEmpty).toContainText(
      "Select an asset to verify its legitimacy",
    );
  });

  test("four quick fill buttons are displayed", async () => {
    await expect(veritasPage.quickButtons).toHaveCount(4);
  });

  test("verify button has correct label", async () => {
    await expect(veritasPage.verifyBtnText).toContainText(
      "Verify on Paseo (Submit Tx)",
    );
  });

  test("read state button is visible", async () => {
    await expect(veritasPage.readStateBtn).toBeVisible();
    await expect(veritasPage.readStateBtn).toContainText(
      "Read Latest State (No Tx)",
    );
  });

  test("history table is present with pre-filled data", async () => {
    await expect(veritasPage.historySection).toBeVisible();
    const rowCount = await veritasPage.getHistoryRowCount();
    expect(rowCount).toBe(2);
  });

  test("history table has correct headers", async ({ page }) => {
    const headers = page.locator(".history-table th");
    await expect(headers).toHaveCount(5);
    await expect(headers.nth(0)).toHaveText("Asset");
    await expect(headers.nth(1)).toHaveText("Chain");
    await expect(headers.nth(2)).toHaveText("Score");
    await expect(headers.nth(3)).toHaveText("Status");
    await expect(headers.nth(4)).toHaveText("Tx / Time");
  });

  test("footer is visible with hackathon info", async () => {
    await expect(veritasPage.footer).toBeVisible();
    await expect(veritasPage.footer).toContainText(
      "Polkadot Solidity Hackathon 2026",
    );
  });
});
