// Logs in once through the single-use frontdoor URL and stores the session for every test.
const { chromium } = require("@playwright/test");
const fs = require("node:fs");
const path = require("node:path");

const STATE_FILE = path.join("test-results", "e2e-session.json");

module.exports = async () => {
  if (!process.env.SF_FRONTDOOR_URL) {
    return;
  }
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.goto(process.env.SF_FRONTDOOR_URL);
  await page.waitForURL(/\/lightning\//, { timeout: 120000 });
  fs.mkdirSync(path.dirname(STATE_FILE), { recursive: true });
  await page.context().storageState({ path: STATE_FILE });
  // Read by the tests (workers inherit the environment of the global setup).
  process.env.SF_PANEL_URL = page.url();
  await browser.close();
};

module.exports.STATE_FILE = STATE_FILE;
