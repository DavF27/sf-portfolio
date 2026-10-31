"use strict";

const FRESHNESS = Object.freeze({
  FRESH: "fresh",
  STALE: "stale",
  MISSING: "missing"
});

const DRIFT = Object.freeze({
  KNOWN: "KNOWN",
  INTENTIONAL: "INTENTIONAL",
  UNKNOWN: "UNKNOWN"
});

/** fresh: the org holds the local version; stale: both exist and differ; missing: one side only. */
function freshnessOf(localHash, orgHash) {
  if (localHash === orgHash) {
    return { status: FRESHNESS.FRESH, missingIn: null };
  }
  if (!orgHash) {
    return { status: FRESHNESS.MISSING, missingIn: "org" };
  }
  if (!localHash) {
    return { status: FRESHNESS.MISSING, missingIn: "local" };
  }
  return { status: FRESHNESS.STALE, missingIn: null };
}

/**
 * Classifies a component from three hashes (null when absent):
 * L = local working copy, O = org, B = last deployment tag (baseline).
 *
 * - O = B: the org was not touched since the baseline; L != O is a local change waiting for deployment.
 * - O != B: the org changed outside Git. KNOWN when Git already holds the same content (O = L),
 *   INTENTIONAL when listed in the exceptions file, UNKNOWN otherwise: deploying would overwrite it.
 * Without any baseline, every difference is UNKNOWN: nothing proves which side is the newest.
 */
function classify({
  localHash,
  orgHash,
  baselineHash,
  hasBaseline,
  exception
}) {
  const freshness = freshnessOf(localHash, orgHash);
  const orgChanged = hasBaseline
    ? orgHash !== baselineHash
    : orgHash !== localHash;
  let drift = null;
  if (orgChanged) {
    if (orgHash === localHash) {
      drift = DRIFT.KNOWN;
    } else if (exception) {
      drift = DRIFT.INTENTIONAL;
    } else {
      drift = DRIFT.UNKNOWN;
    }
  }
  return {
    freshness: freshness.status,
    missingIn: freshness.missingIn,
    drift,
    pendingDeploy: !orgChanged && localHash !== orgHash
  };
}

function indexExceptions(exceptions) {
  const index = new Map();
  for (const item of exceptions || []) {
    if (!item || !item.component || !item.reason) {
      throw new Error(
        "Every drift exception needs a component and a reason: " +
          JSON.stringify(item)
      );
    }
    index.set(item.component, item.reason);
  }
  return index;
}

/**
 * Compares the three sides. local/org/baseline are Maps key -> { hash, ... }; org entries also carry
 * lastModifiedBy and lastModifiedDate. baseline is null when no deployment tag exists.
 */
function analyze({ local, org, baseline, exceptions }) {
  const exceptionIndex = indexExceptions(exceptions);
  const keys = new Set([
    ...local.keys(),
    ...org.keys(),
    ...(baseline ? baseline.keys() : [])
  ]);
  const rows = [];
  for (const key of [...keys].sort()) {
    const localItem = local.get(key);
    const orgItem = org.get(key);
    if (!localItem && !orgItem) {
      // Deleted on both sides since the baseline: nothing left to compare.
      continue;
    }
    const item = localItem || orgItem;
    const result = classify({
      localHash: localItem?.hash || null,
      orgHash: orgItem?.hash || null,
      baselineHash: baseline?.get(key)?.hash || null,
      hasBaseline: Boolean(baseline),
      exception: exceptionIndex.get(key)
    });
    rows.push({
      component: key,
      type: item.type,
      name: item.name,
      ...result,
      lastModifiedBy: orgItem?.lastModifiedBy || null,
      lastModifiedDate: orgItem?.lastModifiedDate || null,
      reason:
        result.drift === DRIFT.INTENTIONAL ? exceptionIndex.get(key) : null
    });
  }
  return rows;
}

function summarize(rows) {
  const count = (predicate) => rows.filter(predicate).length;
  return {
    components: rows.length,
    fresh: count((row) => row.freshness === FRESHNESS.FRESH),
    stale: count((row) => row.freshness === FRESHNESS.STALE),
    missing: count((row) => row.freshness === FRESHNESS.MISSING),
    pendingDeploy: count((row) => row.pendingDeploy),
    known: count((row) => row.drift === DRIFT.KNOWN),
    intentional: count((row) => row.drift === DRIFT.INTENTIONAL),
    unknown: count((row) => row.drift === DRIFT.UNKNOWN)
  };
}

function cell(value) {
  if (value === null || value === undefined) {
    return "";
  }
  return String(value).replace(/\|/g, "\\|");
}

function noteOf(row) {
  if (row.pendingDeploy) {
    return "local change waiting for deployment";
  }
  if (row.missingIn) {
    return `missing in ${row.missingIn}`;
  }
  return row.reason || "";
}

function toMarkdown({ targetOrg, baselineTag, commit, rows }) {
  const summary = summarize(rows);
  const baseline = baselineTag
    ? `\`${baselineTag}\``
    : "none (every difference is UNKNOWN)";
  const lines = [
    `## Org drift: \`${targetOrg}\``,
    "",
    `Baseline: ${baseline} · local commit \`${commit}\``,
    "",
    "| Components | Fresh | Stale | Missing | Pending deploy | KNOWN | INTENTIONAL | UNKNOWN |",
    "|---:|---:|---:|---:|---:|---:|---:|---:|",
    `| ${summary.components} | ${summary.fresh} | ${summary.stale} | ${summary.missing} | ` +
      `${summary.pendingDeploy} | ${summary.known} | ${summary.intentional} | ${summary.unknown} |`,
    ""
  ];
  const notable = rows.filter(
    (row) => row.freshness !== FRESHNESS.FRESH || row.drift
  );
  if (notable.length === 0) {
    lines.push("Every component in the org matches the local version.");
    return lines.join("\n") + "\n";
  }
  lines.push(
    "| Component | Freshness | Drift | Last modified in the org | By | Note |",
    "|---|---|---|---|---|---|"
  );
  for (const row of notable) {
    const drift = row.drift ? `**${row.drift}**` : "";
    lines.push(
      `| ${cell(row.component)} | ${row.freshness} | ${drift} | ` +
        `${cell(row.lastModifiedDate)} | ${cell(row.lastModifiedBy)} | ${cell(noteOf(row))} |`
    );
  }
  return lines.join("\n") + "\n";
}

module.exports = {
  FRESHNESS,
  DRIFT,
  freshnessOf,
  classify,
  analyze,
  summarize,
  toMarkdown
};
