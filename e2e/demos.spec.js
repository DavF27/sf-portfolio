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
  },
  {
    name: "Order_Of_Execution",
    slug: "order-of-execution",
    volume: "50",
    // Silent failure: the save succeeds, every snapshot misses the service terms.
    before: { status: "Succeeded", summary: "0 succeeded, 50 failed" },
    after: { status: "Succeeded", summary: "50 succeeded, 0 failed" }
  },
  {
    name: "Async_Chain_Break",
    slug: "async-chain-break",
    volume: "50",
    // Chaos traps one line in both modes. BEFORE: its chain stops silently, the panel monitor detects
    // the stuck lines after 20 s without news. AFTER: the bundle fails as a whole and is logged.
    chaosFirst: true,
    before: {
      status: "Failed",
      summary: "47 succeeded, 3 failed",
      error: "Detected by monitoring",
      timeout: 4 * 60 * 1000
    },
    after: {
      status: "Succeeded",
      summary: "45 succeeded, 5 failed",
      timeout: 4 * 60 * 1000
    }
  },
  {
    name: "Batch_Filter",
    slug: "batch-filter",
    volume: "200",
    // BEFORE and AFTER race side by side, each on its own lane of renewals.
    race: true
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

function laneStatus(page, mode) {
  return page.locator(
    `[data-id="lane"][data-mode="${mode}"] [data-id="lane-status"]`
  );
}

/** Race: capture when AFTER has finished while BEFORE is still going, then when both are done. */
async function runRace(page, card, dir) {
  await card.locator('[data-id="race-button"] button').click();
  await expect(laneStatus(page, "AFTER")).toHaveText("Succeeded", {
    timeout: 5 * 60 * 1000
  });
  await page.waitForTimeout(2000);
  await fullPageCapture(page, dir, "race.png");
  await expect(laneStatus(page, "BEFORE")).toHaveText("Succeeded", {
    timeout: 20 * 60 * 1000
  });
  await page.waitForTimeout(2000);
  await fullPageCapture(page, dir, "race-finished.png");
}

async function runMode(page, card, mode, expected) {
  const timeout = expected.timeout;
  await card.locator(`lightning-button[data-mode="${mode}"] button`).click();
  await expect(page.locator('[data-id="run-status"]')).toHaveText(
    expected.status,
    { timeout }
  );
  // The row grid reaches its final state once the server answered and the steps arrived.
  const summary = page.locator('[data-id="row-grid"] [data-id="summary"]');
  await expect(summary).toContainText(expected.summary || /succeeded|failed/, {
    timeout
  });
  if (expected.error) {
    await expect(page.locator('[data-id="run-error"]')).toContainText(
      expected.error
    );
  }
  await page.waitForTimeout(3000);
}

for (const demo of DEMOS) {
  test(`${demo.name}: BEFORE fails, AFTER passes`, async ({ page }) => {
    if (demo.chaosFirst) {
      // Asynchronous demo: jobs, then 20 s of silence before the panel monitor, in both modes.
      test.setTimeout(12 * 60 * 1000);
    }
    if (demo.race) {
      // The BEFORE batch runs one execution per record.
      test.setTimeout(25 * 60 * 1000);
    }
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
    if (demo.race) {
      await runRace(page, card, dir);
    } else {
      if (demo.chaosFirst) {
        await card
          .locator('[data-id="chaos-toggle"] input[type="checkbox"]')
          .check({ force: true });
      }

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
    }
    const video = page.video();
    await page.close();
    if (video) {
      await video.saveAs(path.join(dir, `${demo.slug}.webm`));
    }
  });
}
