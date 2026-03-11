// @ts-check
const { test, expect } = require("@playwright/test");
const { VeritasPage } = require("./pages/VeritasPage");

test.describe("Verification History", () => {
  let veritasPage;

  test.beforeEach(async ({ page }) => {
    veritasPage = new VeritasPage(page);
    await veritasPage.goto();
  });

  test("pre-filled history shows xcDOT and aDOT entries", async ({
    page,
  }) => {
    const rows = veritasPage.historyRows;
    await expect(rows).toHaveCount(2);

    // First row: xcDOT (most recent, unshift)
    const firstRow = rows.nth(0);
    await expect(firstRow.locator("td").nth(0)).toContainText("xcDOT");
    await expect(firstRow.locator("td").nth(1)).toContainText("moonbeam");

    // Second row: aDOT
    const secondRow = rows.nth(1);
    await expect(secondRow.locator("td").nth(0)).toContainText("aDOT");
    await expect(secondRow.locator("td").nth(1)).toContainText("acala");
  });

  test("history displays score badges with correct classes", async ({
    page,
  }) => {
    // xcDOT score = 60 → "low" class
    const firstBadge = page
      .locator("#historyBody tr")
      .nth(0)
      .locator(".score-badge");
    await expect(firstBadge).toHaveText("60");
    await expect(firstBadge).toHaveClass(/low/);

    // aDOT score = 85 → "medium" class (70-89)
    const secondBadge = page
      .locator("#historyBody tr")
      .nth(1)
      .locator(".score-badge");
    await expect(secondBadge).toHaveText("85");
    await expect(secondBadge).toHaveClass(/medium/);
  });

  test("history displays correct status tags", async ({ page }) => {
    // xcDOT score=60, isVerified=false → "Rejected"
    const firstStatus = page
      .locator("#historyBody tr")
      .nth(0)
      .locator(".status-tag");
    await expect(firstStatus).toContainText("Rejected");
    await expect(firstStatus).toHaveClass(/rejected/);

    // aDOT score=85, isVerified=true → "Verified"
    const secondStatus = page
      .locator("#historyBody tr")
      .nth(1)
      .locator(".status-tag");
    await expect(secondStatus).toContainText("Verified");
    await expect(secondStatus).toHaveClass(/verified/);
  });

  test("history section title is correct", async ({ page }) => {
    const title = page.locator(".history-section .section-title");
    await expect(title).toHaveText("On-Chain Verifications");
  });
});
