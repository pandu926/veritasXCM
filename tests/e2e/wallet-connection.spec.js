// @ts-check
const { test, expect } = require("@playwright/test");
const { VeritasPage } = require("./pages/VeritasPage");
const { createLiveWalletMock } = require("./fixtures/live-wallet-mock");

const PRIVATE_KEY = process.env.TEST_PRIVATE_KEY;
const ADDRESS = process.env.TEST_ADDRESS;
const RPC_URL = process.env.RPC_URL || "https://eth-asset-hub-paseo.dotters.network";
const CHAIN_ID = Number(process.env.CHAIN_ID || "420420417");
const CHAIN_ID_HEX = "0x" + CHAIN_ID.toString(16);

test.describe("Wallet Connection (Live Paseo)", () => {
  test("shows error when no wallet is installed", async ({ page }) => {
    const veritasPage = new VeritasPage(page);
    await veritasPage.goto();

    await veritasPage.connectWallet();

    await expect(veritasPage.resultContent).toBeVisible();
    await expect(veritasPage.resultMessage).toContainText("install MetaMask");
  });

  test("connects wallet successfully to Paseo testnet", async ({ page }) => {
    const mockScript = createLiveWalletMock(PRIVATE_KEY, ADDRESS, RPC_URL, CHAIN_ID_HEX);
    await page.addInitScript(mockScript);

    const veritasPage = new VeritasPage(page);
    await veritasPage.goto();
    await page.waitForTimeout(500); // Wait for ethers to load + mock to init

    await veritasPage.connectWallet();
    await page.waitForTimeout(1000);

    // Connect button should be hidden
    await expect(veritasPage.connectWalletBtn).not.toBeVisible();
    // Connected state should show
    await expect(veritasPage.connectedState).toBeVisible();

    // Should show truncated address
    const statusText = await veritasPage.statusText.textContent();
    expect(statusText).toContain("0x165C");
  });

  test("shows green status dot when connected", async ({ page }) => {
    const mockScript = createLiveWalletMock(PRIVATE_KEY, ADDRESS, RPC_URL, CHAIN_ID_HEX);
    await page.addInitScript(mockScript);

    const veritasPage = new VeritasPage(page);
    await veritasPage.goto();
    await page.waitForTimeout(500);

    await veritasPage.connectWallet();
    await page.waitForTimeout(1000);

    await expect(veritasPage.statusDot).toBeVisible();
  });

  test("verify button requires wallet connection", async ({ page }) => {
    const veritasPage = new VeritasPage(page);
    await veritasPage.goto();

    await veritasPage.fillAssetForm("aDOT", "acala", 1000);
    await veritasPage.submitVerification();

    await expect(veritasPage.resultContent).toBeVisible();
    await expect(veritasPage.resultMessage).toContainText("connect your wallet");
  });
});
