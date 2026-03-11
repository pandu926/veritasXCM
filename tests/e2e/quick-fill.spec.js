// @ts-check
const { test, expect } = require("@playwright/test");
const { VeritasPage } = require("./pages/VeritasPage");

test.describe("Quick Fill Buttons", () => {
  let veritasPage;

  test.beforeEach(async ({ page }) => {
    veritasPage = new VeritasPage(page);
    await veritasPage.goto();
  });

  test("aDOT / Acala fills form correctly", async () => {
    await veritasPage.clickQuickFill("aDOT");

    const values = await veritasPage.getFormValues();
    expect(values.assetId).toBe("aDOT");
    expect(values.originChain).toBe("acala");
    expect(values.amount).toBe("1000");
  });

  test("iBTC / Interlay fills form correctly", async () => {
    await veritasPage.clickQuickFill("iBTC");

    const values = await veritasPage.getFormValues();
    expect(values.assetId).toBe("iBTC");
    expect(values.originChain).toBe("interlay");
    expect(values.amount).toBe("100");
  });

  test("vDOT / Bifrost fills form correctly", async () => {
    await veritasPage.clickQuickFill("vDOT");

    const values = await veritasPage.getFormValues();
    expect(values.assetId).toBe("vDOT");
    expect(values.originChain).toBe("bifrost");
    expect(values.amount).toBe("500");
  });

  test("xcDOT / Moonbeam fills form correctly", async () => {
    await veritasPage.clickQuickFill("xcDOT");

    const values = await veritasPage.getFormValues();
    expect(values.assetId).toBe("xcDOT");
    expect(values.originChain).toBe("moonbeam");
    expect(values.amount).toBe("1000");
  });

  test("clicking different quick fill buttons updates form", async () => {
    await veritasPage.clickQuickFill("aDOT");
    let values = await veritasPage.getFormValues();
    expect(values.assetId).toBe("aDOT");

    await veritasPage.clickQuickFill("xcDOT");
    values = await veritasPage.getFormValues();
    expect(values.assetId).toBe("xcDOT");
    expect(values.originChain).toBe("moonbeam");
    expect(values.amount).toBe("1000");
  });

  test("quick fill does not submit the form", async () => {
    await veritasPage.clickQuickFill("aDOT");

    // Result panel should still show empty state
    await expect(veritasPage.resultEmpty).toBeVisible();
    await expect(veritasPage.resultContent).not.toBeVisible();
  });

  test("manual input overrides quick fill values", async () => {
    await veritasPage.clickQuickFill("aDOT");
    await veritasPage.assetIdInput.fill("customToken");

    const values = await veritasPage.getFormValues();
    expect(values.assetId).toBe("customToken");
    expect(values.originChain).toBe("acala");
  });
});
