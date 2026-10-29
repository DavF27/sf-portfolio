// Playwright drives the deployed demo panel in a scratch org (see .github/workflows/ci.yml).
const { defineConfig, devices } = require("@playwright/test");
const { STATE_FILE } = require("./e2e/global-setup");

module.exports = defineConfig({
  testDir: "./e2e",
  globalSetup: require.resolve("./e2e/global-setup"),
  timeout: 5 * 60 * 1000,
  expect: { timeout: 90 * 1000 },
  retries: 0,
  workers: 1,
  reporter: [
    ["list"],
    ["html", { open: "never", outputFolder: "playwright-report" }]
  ],
  outputDir: "test-results/e2e",
  use: {
    ...devices["Desktop Chrome"],
    // The frontdoor URL is single-use: tests reuse the session stored by the global setup.
    storageState: process.env.SF_FRONTDOOR_URL ? STATE_FILE : undefined,
    viewport: { width: 1440, height: 900 },
    video: { mode: "on", size: { width: 1440, height: 900 } },
    screenshot: "only-on-failure",
    actionTimeout: 60 * 1000,
    navigationTimeout: 2 * 60 * 1000
  }
});
