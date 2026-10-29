// Captures every demo from the deployed panel: BEFORE, AFTER and, when relevant, AFTER with Chaos.
// Requires SF_FRONTDOOR_URL (from `sf org open --url-only --path /lightning/n/Demo_Panel`), consumed once
// by e2e/global-setup.js which stores the session and the panel URL (SF_PANEL_URL).
const { test, expect } = require("@playwright/test");
const fs = require("node:fs");
const path = require("node:path");

const SCREENSHOT_ROOT =
  process.env.SCREENSHOT_ROOT || path.join("docs", "screenshots");

const DEMOS = [
  {
    name: "Limits_Probe",
    slug: "limits-probe",
    volume: "150",
    before: { status: "Failed", error: "Too many SOQL queries: 101" },
    after: { status: "Succeeded" }
  },
  {
    name: "Bulk_All_Or_Nothing",
    slug: "bulk-all-or-nothing",
    volume: "50",
    // Synchronous transaction: the limit breaks inside a deal flow, reported as LIMIT_EXCEEDED.
    before: { status: "Failed", error: /Limit Exceeded|Too many/ },
    after: { status: "Succeeded", summary: "50 succeeded, 0 failed" },
    chaos: { status: "Succeeded", summary: "49 succeeded, 1 failed" }
  }
];

test.skip(!process.env.SF_FRONTDOOR_URL, "SF_FRONTDOOR_URL is not set");

// Fixed bars docked at the bottom (e.g. the app utility bar) are painted mid-image in full-page captures.
// Hidden by geometry rather than by Salesforce-internal class names, which are not a stable API.
async function hideBottomDockedBars(page) {
  const hidden = await page.evaluate(() => {
    let count = 0;
    for (const element of document.querySelectorAll("body *")) {
      if (getComputedStyle(element).position !== "fixed") {
        continue;
      }
      const rect = element.getBoundingClientRect();
      const dockedAtBottom = rect.top > window.innerHeight / 2;
      const isBar = rect.height > 0 && rect.height < window.innerHeight / 3;
      if (dockedAtBottom && isBar) {
        element.style.visibility = "hidden";
        count++;
      }
    }
    return count;
  });
  test.info().annotations.push({
    type: "hidden-bottom-bars",
    description: String(hidden)
  });
}

async function fullPageCapture(page, dir, file) {
  // A full-page capture of a scrolled page paints the fixed global header mid-image.
  await page.evaluate(() => window.scrollTo(0, 0));
  await hideBottomDockedBars(page);
  await page.screenshot({ path: path.join(dir, file), fullPage: true });
}

async function runMode(page, card, mode, expected) {
  await card.locator(`lightning-button[data-mode="${mode}"] button`).click();
  await expect(page.locator('[data-id="run-status"]')).toHaveText(
    expected.status
  );
  // The row grid reaches its final state once the server answered and the steps arrived.
  const summary = page.locator('[data-id="row-grid"] [data-id="summary"]');
  await expect(summary).toContainText(expected.summary || /succeeded|failed/);
  if (expected.error) {
    await expect(page.locator('[data-id="run-error"]')).toContainText(
      expected.error
    );
  }
  await page.waitForTimeout(3000);
}

for (const demo of DEMOS) {
  test(`${demo.name}: BEFORE fails, AFTER passes`, async ({ page }) => {
    const dir = path.join(SCREENSHOT_ROOT, demo.slug);
    fs.mkdirSync(dir, { recursive: true });

    await page.goto(process.env.SF_PANEL_URL);
    const card = page.locator(
      `[data-id="demo-card"][data-demo="${demo.name}"]`
    );
    await expect(card).toBeVisible();
    await card.scrollIntoViewIfNeeded();
    await page.screenshot({ path: path.join(dir, "panel.png") });
    await card.locator('[data-id="volume-input"] input').fill(demo.volume);

    await runMode(page, card, "BEFORE", demo.before);
    await fullPageCapture(page, dir, "before.png");

    await runMode(page, card, "AFTER", demo.after);
    await fullPageCapture(page, dir, "after.png");

    if (demo.chaos) {
      await card
        .locator('[data-id="chaos-toggle"] input[type="checkbox"]')
        .check({ force: true });
      await runMode(page, card, "AFTER", demo.chaos);
      await fullPageCapture(page, dir, "chaos.png");
    }

    const video = page.video();
    await page.close();
    if (video) {
      await video.saveAs(path.join(dir, `${demo.slug}.webm`));
    }
  });
}
