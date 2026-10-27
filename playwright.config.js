// Playwright drives the deployed demo panel in a scratch org (see .github/workflows/ci.yml).
const { defineConfig, devices } = require("@playwright/test");

module.exports = defineConfig({
  testDir: "./e2e",
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
    viewport: { width: 1440, height: 900 },
    video: { mode: "on", size: { width: 1440, height: 900 } },
    screenshot: "only-on-failure",
    actionTimeout: 60 * 1000,
    navigationTimeout: 2 * 60 * 1000
  }
});
