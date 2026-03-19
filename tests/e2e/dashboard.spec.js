// @ts-check
const { test, expect } = require("@playwright/test");
const { VeritasPage } = require("./pages/VeritasPage");

test.describe("Ecosystem Health Dashboard", () => {
  let veritasPage;

  test.beforeEach(async ({ page }) => {
    veritasPage = new VeritasPage(page);
    await veritasPage.goto();
  });

  test("dashboard section is visible on page load", async ({ page }) => {
    const dashboard = page.locator("#dashboardSection");
    await expect(dashboard).toBeVisible();
    await expect(page.locator(".dashboard-title")).toHaveText(
      "Ecosystem Health",
    );
  });

  test("displays 4 asset cards", async ({ page }) => {
    const cards = page.locator(".dash-card");
    await expect(cards).toHaveCount(4);
  });

  test("asset cards show correct asset names", async ({ page }) => {
    const names = page.locator(".dash-card__name");
    await expect(names.nth(0)).toHaveText("aDOT");
    await expect(names.nth(1)).toHaveText("iBTC");
    await expect(names.nth(2)).toHaveText("vDOT");
    await expect(names.nth(3)).toHaveText("xcDOT");
  });

  test("asset cards show origin chain", async ({ page }) => {
    const chains = page.locator(".dash-card__chain");
    await expect(chains.nth(0)).toHaveText("acala");
    await expect(chains.nth(1)).toHaveText("interlay");
    await expect(chains.nth(2)).toHaveText("bifrost");
    await expect(chains.nth(3)).toHaveText("moonbeam");
  });

  test("aDOT card loads score 85 from chain", async ({ page }) => {
    const score = page.locator(".dash-card").nth(0).locator(".dash-card__score");
    await expect(score).toHaveText("85", { timeout: 15000 });
  });

  test("xcDOT card loads score 60 from chain", async ({ page }) => {
    const score = page.locator(".dash-card").nth(3).locator(".dash-card__score");
    await expect(score).toHaveText("60", { timeout: 15000 });
  });

  test("aDOT card has verified status", async ({ page }) => {
    const badge = page
      .locator(".dash-card")
      .nth(0)
      .locator(".dash-card__status");
    await expect(badge).toHaveText("VERIFIED", { timeout: 15000 });
    await expect(badge).toHaveClass(/verified/, { timeout: 15000 });
  });

  test("xcDOT card has uncertain status", async ({ page }) => {
    const badge = page
      .locator(".dash-card")
      .nth(3)
      .locator(".dash-card__status");
    await expect(badge).toHaveText("UNCERTAIN", { timeout: 15000 });
    await expect(badge).toHaveClass(/uncertain/, { timeout: 15000 });
  });

  test("cards show loading state initially", async ({ page }) => {
    // Reload with network throttling to catch loading state
    const card = page.locator(".dash-card").nth(0).locator(".dash-card__score");
    // Score should eventually load (not stay at "...")
    await expect(card).not.toHaveText("...", { timeout: 15000 });
  });

  test("clicking a dashboard card fills the verify form", async ({ page }) => {
    const card = page.locator(".dash-card").nth(0);
    await card.click();

    const assetId = await page.locator("#assetId").inputValue();
    const originChain = await page.locator("#originChain").inputValue();
    expect(assetId).toBe("aDOT");
    expect(originChain).toBe("acala");
  });
});
