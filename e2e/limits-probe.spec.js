// Captures the Limits Probe demo in BEFORE then AFTER mode from the deployed panel.
// Requires SF_FRONTDOOR_URL (from `sf org open --url-only --path /lightning/n/Demo_Panel`).
const { test, expect } = require("@playwright/test");
const path = require("node:path");

const DEMO = "Limits_Probe";
const VOLUME = "150";
const SCREENSHOT_DIR =
  process.env.SCREENSHOT_DIR ||
  path.join("docs", "screenshots", "limits-probe");

test.skip(!process.env.SF_FRONTDOOR_URL, "SF_FRONTDOOR_URL is not set");

async function runMode(page, mode, expectedStatus) {
  const card = page.locator(`[data-id="demo-card"][data-demo="${DEMO}"]`);
  await card.locator(`lightning-button[data-mode="${mode}"] button`).click();
  const status = page.locator('[data-id="run-status"]');
  await expect(status).toHaveText(expectedStatus);
  // Let the live steps and the recent runs table catch up before the capture.
  await expect(page.locator('[data-id="runs-table"]')).toContainText(mode);
  await page.waitForTimeout(3000);
}

test("Limits Probe: BEFORE breaks the SOQL limit, AFTER passes", async ({
  page
}) => {
  await page.goto(process.env.SF_FRONTDOOR_URL);
  const card = page.locator(`[data-id="demo-card"][data-demo="${DEMO}"]`);
  await expect(card).toBeVisible();
  await page.screenshot({ path: path.join(SCREENSHOT_DIR, "panel.png") });

  await card.locator('[data-id="volume-input"] input').fill(VOLUME);

  await runMode(page, "BEFORE", "Failed");
  await expect(page.locator('[data-id="run-error"]')).toContainText(
    "Too many SOQL queries: 101"
  );
  await page.screenshot({
    path: path.join(SCREENSHOT_DIR, "before.png"),
    fullPage: true
  });

  await runMode(page, "AFTER", "Succeeded");
  await page.screenshot({
    path: path.join(SCREENSHOT_DIR, "after.png"),
    fullPage: true
  });
});
