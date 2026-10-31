"use strict";
/**
 * Showcase data: the demo catalogue and the headline numbers, always computed from the files measured by the CI
 * (metrics.json, bulk.json, drift.json). Nothing here is typed by hand.
 */

const CATALOG = [
  {
    slug: "bulk-all-or-nothing",
    demo: "Bulk_All_Or_Nothing",
    title: "Bulk API all-or-nothing batch",
    problem:
      "One bad design in a trigger makes a whole Bulk API batch fail, valid rows included.",
    mechanism:
      "Per-record SOQL/DML in a trigger cascades through two flows and breaks a governor limit for the whole transaction; the fix bulkifies and isolates the invalid row with partial success.",
    doc: "docs/demos/bulk-all-or-nothing.md"
  },
  {
    slug: "order-of-execution",
    demo: "Order_Of_Execution",
    title: "Trigger vs flow order of execution",
    problem:
      "Saves succeed, yet archived snapshots silently miss the values a flow computes.",
    mechanism:
      "An after-save flow runs after the after trigger that takes the snapshot; moving the calculation to a before-save flow fixes the order and saves a DML.",
    doc: "docs/demos/order-of-execution.md"
  },
  {
    slug: "async-chain-break",
    demo: "Async_Chain_Break",
    title: "Silent asynchronous chain",
    problem:
      "A chain of queueables stops on one bad line and nobody is told: the rest stays pending forever.",
    mechanism:
      "One chained job per line dies silently; the fix processes bounded bundles, isolates failures and logs them from a Transaction Finalizer.",
    doc: "docs/demos/async-chain-break.md"
  },
  {
    slug: "batch-filter",
    demo: "Batch_Filter",
    title: "Batch Apex: filter in Apex vs in SOQL",
    problem:
      "A nightly batch gets slower as data grows while the work it does stays the same.",
    mechanism:
      "The batch scans the whole stock with scope 1 and filters in Apex; filtering in the start() query on a formula field leaves one execution. Both race side by side.",
    doc: "docs/demos/batch-filter.md"
  },
  {
    slug: "drift-guard",
    demo: null,
    title: "Org drift and deployment guard",
    problem:
      "A hotfix made directly in the org is silently overwritten by the next deployment.",
    mechanism:
      "Tooling API hashes compared with the working copy and the last deployment tag; an UNKNOWN drift blocks the deployment.",
    doc: "docs/demos/drift-guard.md"
  },
  {
    slug: "limits-probe",
    demo: "Limits_Probe",
    title: "Limits probe (calibration)",
    problem: "Calibration of the measurement chain.",
    mechanism:
      "One SOQL query per unit of volume breaks the 100-query limit; a single aggregate query does not. Proves that a LimitException is still measured.",
    doc: null
  }
];

function runsOf(metrics, demo, { chaos = false } = {}) {
  const pick = (mode) =>
    (metrics || []).find(
      (run) =>
        run.Demo__c === demo &&
        run.Mode__c === mode &&
        Boolean(run.Chaos__c) === chaos
    ) || null;
  return { before: pick("BEFORE"), after: pick("AFTER") };
}

function seconds(ms) {
  if (ms === null || ms === undefined) {
    return "?";
  }
  return `${(ms / 1000).toFixed(ms < 10000 ? 1 : 0)} s`;
}

function outcome(run) {
  if (!run) {
    return { ok: null, text: "not measured" };
  }
  return { ok: run.Status__c === "Succeeded", text: run.Status__c };
}

/**
 * Headline of a demo: { label, before: { value, detail, ok }, after: {...} } or null when nothing was measured.
 * ok is the visual verdict (red/green), not a copy of the run status: a BEFORE run that "succeeds" with corrupted
 * data is still the bad side.
 */
function headline(item, { metrics, bulk, drift }) {
  switch (item.slug) {
    case "limits-probe": {
      const { before, after } = runsOf(metrics, item.demo);
      if (!before || !after) {
        return null;
      }
      return {
        label: "SOQL queries for 150 units",
        before: {
          value: `${before.SOQL_Queries__c} / ${before.SOQL_Limit__c}`,
          detail: outcome(before).text,
          ok: false
        },
        after: {
          value: `${after.SOQL_Queries__c} / ${after.SOQL_Limit__c}`,
          detail: outcome(after).text,
          ok: true
        }
      };
    }
    case "bulk-all-or-nothing": {
      const before = (bulk || []).find(
        (job) => job.mode === "BEFORE" && !job.chaos
      );
      const after = (bulk || []).find(
        (job) => job.mode === "AFTER" && !job.chaos
      );
      if (!before || !after) {
        return null;
      }
      return {
        label: `Real Bulk API 2.0 job, ${before.rows} rows`,
        before: {
          value: `${before.failed} / ${before.rows} failed`,
          detail: "governor limit, whole batch rolled back",
          ok: false
        },
        after: {
          value: `${after.succeeded} / ${after.rows} succeeded`,
          detail: "bulkified, partial success",
          ok: true
        }
      };
    }
    case "order-of-execution": {
      const { before, after } = runsOf(metrics, item.demo);
      if (!before || !after) {
        return null;
      }
      return {
        label: `Snapshots with empty service terms, ${before.Records_Processed__c} assets`,
        before: {
          value: `${before.Records_Failed__c} / ${before.Records_Processed__c}`,
          detail: "the save still succeeds",
          ok: false
        },
        after: {
          value: `${after.Records_Failed__c} / ${after.Records_Processed__c}`,
          detail: "before-save flow",
          ok: true
        }
      };
    }
    case "async-chain-break": {
      const { before, after } = runsOf(metrics, item.demo, { chaos: true });
      if (!before || !after) {
        return null;
      }
      return {
        label: "With one failing line injected (Chaos)",
        before: {
          value: `${before.Records_Failed__c} lines stuck`,
          detail: "no error logged, found by monitoring",
          ok: false
        },
        after: {
          value: `${after.Records_Failed__c} lines failed, logged`,
          detail: "other bundles completed",
          ok: true
        }
      };
    }
    case "batch-filter": {
      const { before, after } = runsOf(metrics, item.demo);
      if (!before || !after) {
        return null;
      }
      return {
        label: `Batch executions for ${before.Volume__c} contracts`,
        before: {
          value: `${before.Async_Executions__c} executions`,
          detail: seconds(before.Duration_Ms__c),
          ok: false
        },
        after: {
          value: `${after.Async_Executions__c} execution${after.Async_Executions__c === 1 ? "" : "s"}`,
          detail: seconds(after.Duration_Ms__c),
          ok: true
        }
      };
    }
    case "drift-guard": {
      if (!drift || !drift.summary) {
        return null;
      }
      return {
        label: `Hotfix outside Git, ${drift.summary.components} components checked`,
        before: {
          value: `${drift.summary.unknown} UNKNOWN drift`,
          detail: "detected with author and date",
          ok: false
        },
        after: {
          value: drift.summary.unknown > 0 ? "deployment blocked" : "allowed",
          detail: "guard exit code 2",
          ok: true
        }
      };
    }
    default:
      return null;
  }
}

function escapeXml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/** A small SVG card (README and site): label, then a red BEFORE box and a green AFTER box. */
function cardSvg(title, data, provenance) {
  const width = 640;
  const height = 150;
  const box = (x, heading, side) => {
    const fill = side.ok ? "#e3f6e9" : "#fde8e8";
    const stroke = side.ok ? "#2e844a" : "#ba0517";
    return [
      `<rect x="${x}" y="52" width="296" height="74" rx="8" fill="${fill}" stroke="${stroke}"/>`,
      `<text x="${x + 14}" y="72" font-size="12" font-weight="700" fill="${stroke}">${heading}</text>`,
      `<text x="${x + 14}" y="97" font-size="20" font-weight="700" fill="#181818">${escapeXml(side.value)}</text>`,
      `<text x="${x + 14}" y="116" font-size="12" fill="#444">${escapeXml(side.detail)}</text>`
    ].join("");
  };
  return (
    `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" ` +
    `role="img" aria-label="${escapeXml(`${title}: before ${data.before.value}, after ${data.after.value}`)}" ` +
    `font-family="Segoe UI, Helvetica, Arial, sans-serif">` +
    `<rect width="${width}" height="${height}" rx="10" fill="#ffffff" stroke="#d8dde6"/>` +
    `<text x="16" y="26" font-size="15" font-weight="700" fill="#032d60">${escapeXml(title)}</text>` +
    `<text x="16" y="44" font-size="12" fill="#444">${escapeXml(data.label)}</text>` +
    box(16, "BEFORE", data.before) +
    box(328, "AFTER", data.after) +
    `<text x="16" y="142" font-size="10" fill="#706e6b">${escapeXml(provenance)}</text>` +
    `</svg>\n`
  );
}

/** Appends this run to the history (newest first), replacing an entry of the same run, capped. */
function appendHistory(history, entry, max = 100) {
  const others = (history || []).filter((item) => item.run !== entry.run);
  return [entry, ...others].slice(0, max);
}

/** Durations per demo and mode, kept in the history for the trend charts. */
function durationsOf(metrics) {
  const durations = {};
  for (const run of metrics || []) {
    if (run.Chaos__c) {
      continue;
    }
    durations[`${run.Demo__c}:${run.Mode__c}`] = run.Duration_Ms__c;
  }
  return durations;
}

module.exports = {
  CATALOG,
  headline,
  cardSvg,
  appendHistory,
  durationsOf,
  escapeXml,
  seconds
};
