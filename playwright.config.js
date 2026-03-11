// @ts-check
const { defineConfig, devices } = require("@playwright/test");
const path = require("path");
const fs = require("fs");

// Load .env.test
const envPath = path.join(__dirname, ".env.test");
if (fs.existsSync(envPath)) {
  const envContent = fs.readFileSync(envPath, "utf-8");
  for (const line of envContent.split("\n")) {
    const [key, ...val] = line.split("=");
    if (key && val.length) process.env[key.trim()] = val.join("=").trim();
  }
}

module.exports = defineConfig({
  globalSetup: "./tests/e2e/global-setup.js",
  testDir: "./tests/e2e",
  fullyParallel: false, // Sequential for live testnet (avoid nonce conflicts)
  forbidOnly: !!process.env.CI,
  retries: 1,
  workers: 1, // Single worker for live testnet
  reporter: [["html", { outputFolder: "playwright-report" }], ["list"]],
  outputDir: "artifacts/test-results",
  timeout: 60000, // 60s timeout for live blockchain interactions

  use: {
    baseURL: "http://localhost:3333",
    trace: "on-first-retry",
    screenshot: "only-on-failure",
    video: "on-first-retry",
  },

  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],

  webServer: {
    command: "node tests/e2e/fixtures/serve.js",
    port: 3333,
    reuseExistingServer: !process.env.CI,
    timeout: 10000,
  },
});
