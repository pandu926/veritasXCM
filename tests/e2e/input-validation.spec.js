// @ts-check
const { test, expect } = require("@playwright/test");
const { VeritasPage } = require("./pages/VeritasPage");

test.describe("Input Validation", () => {
  let veritasPage;

  test.beforeEach(async ({ page }) => {
    veritasPage = new VeritasPage(page);
    await veritasPage.goto();
  });

  test("asset ID input has maxlength=64", async () => {
    await expect(veritasPage.assetIdInput).toHaveAttribute("maxlength", "64");
  });

  test("origin chain input has maxlength=64", async () => {
    await expect(veritasPage.originChainInput).toHaveAttribute(
      "maxlength",
      "64",
    );
  });

  test("amount input has min=1", async () => {
    await expect(veritasPage.amountInput).toHaveAttribute("min", "1");
  });

  test("browser enforces maxlength on asset ID", async ({ page }) => {
    var longInput = "A".repeat(100);
    await veritasPage.assetIdInput.fill(longInput);
    var value = await veritasPage.assetIdInput.inputValue();
    expect(value.length).toBeLessThanOrEqual(64);
  });

  test("browser enforces maxlength on origin chain", async ({ page }) => {
    var longInput = "B".repeat(100);
    await veritasPage.originChainInput.fill(longInput);
    var value = await veritasPage.originChainInput.inputValue();
    expect(value.length).toBeLessThanOrEqual(64);
  });

  test("special characters in input do not cause XSS", async ({ page }) => {
    var xssPayload = '<script>alert("xss")</script>';
    await veritasPage.fillAssetForm(xssPayload, "acala", 1000);
    await veritasPage.readStateBtn.click();

    // Wait for the error/result to display
    await expect(veritasPage.resultContent).toBeVisible({ timeout: 30000 });

    // Page should not have alert dialog or script execution
    var bodyHtml = await page.locator("body").innerHTML();
    expect(bodyHtml).not.toContain("<script>alert");
  });

  test("form inputs are required", async () => {
    await expect(veritasPage.assetIdInput).toHaveAttribute("required", "");
    await expect(veritasPage.originChainInput).toHaveAttribute("required", "");
    await expect(veritasPage.amountInput).toHaveAttribute("required", "");
  });
});
