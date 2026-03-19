// @ts-check
const { test, expect } = require("@playwright/test");
const { VeritasPage } = require("./pages/VeritasPage");

test.describe("Error Scenarios", () => {
  let veritasPage;

  test.beforeEach(async ({ page }) => {
    veritasPage = new VeritasPage(page);
    await veritasPage.goto();
  });

  test("empty form shows validation error on read state", async () => {
    await veritasPage.readStateBtn.click();
    await expect(veritasPage.resultMessage).toContainText(
      "Please enter Asset ID and Origin Chain",
    );
  });

  test("non-existent asset returns no verification record", async () => {
    await veritasPage.fillAssetForm("FAKE_ASSET_999", "nonexistent_chain", 100);
    await veritasPage.readStateBtn.click();

    await expect(veritasPage.resultMessage).toContainText(
      "No verification record found",
      { timeout: 30000 },
    );
  });

  test("verify button requires wallet connection", async () => {
    await veritasPage.fillAssetForm("aDOT", "acala", 1000);
    await veritasPage.submitVerification();

    await expect(veritasPage.resultMessage).toContainText(
      "connect your wallet",
    );
  });

  test("missing origin chain shows error on read state", async ({ page }) => {
    await veritasPage.assetIdInput.fill("aDOT");
    await veritasPage.readStateBtn.click();

    await expect(veritasPage.resultMessage).toContainText(
      "Please enter Asset ID and Origin Chain",
    );
  });

  test("missing asset ID shows error on read state", async ({ page }) => {
    await veritasPage.originChainInput.fill("acala");
    await veritasPage.readStateBtn.click();

    await expect(veritasPage.resultMessage).toContainText(
      "Please enter Asset ID and Origin Chain",
    );
  });
});
