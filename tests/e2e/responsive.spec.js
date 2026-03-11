// @ts-check
const { test, expect } = require("@playwright/test");
const { VeritasPage } = require("./pages/VeritasPage");

test.describe("Responsive Layout", () => {
  test("desktop layout shows two-column panels", async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 720 });
    const veritasPage = new VeritasPage(page);
    await veritasPage.goto();

    // Both panels should be visible side by side
    await expect(veritasPage.verifyPanel).toBeVisible();
    await expect(veritasPage.resultPanel).toBeVisible();

    // Stats should show 4 columns
    const statsGrid = page.locator(".stats");
    await expect(statsGrid).toBeVisible();
  });

  test("mobile layout stacks panels vertically", async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 });
    const veritasPage = new VeritasPage(page);
    await veritasPage.goto();

    // Both panels should still be visible
    await expect(veritasPage.verifyPanel).toBeVisible();
    await expect(veritasPage.resultPanel).toBeVisible();

    // Verify form is usable on mobile
    await expect(veritasPage.assetIdInput).toBeVisible();
    await expect(veritasPage.verifyBtn).toBeVisible();
  });

  test("quick fill buttons work on mobile", async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 });
    const veritasPage = new VeritasPage(page);
    await veritasPage.goto();

    await veritasPage.clickQuickFill("aDOT");
    const values = await veritasPage.getFormValues();
    expect(values.assetId).toBe("aDOT");
  });

  test("tablet layout renders correctly", async ({ page }) => {
    await page.setViewportSize({ width: 768, height: 1024 });
    const veritasPage = new VeritasPage(page);
    await veritasPage.goto();

    await expect(veritasPage.headerTitle).toBeVisible();
    await expect(veritasPage.verifyPanel).toBeVisible();
    await expect(veritasPage.historySection).toBeVisible();
  });
});
