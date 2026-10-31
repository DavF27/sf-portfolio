#!/usr/bin/env node
"use strict";
/**
 * Freshness: proves that the local version of each component is the one in the org before any analysis.
 *   node tools/freshness.js --target-org <alias> [--out <dir>]
 * Exit code: 0 when every component is fresh, 1 otherwise.
 */
const { parseArgs } = require("node:util");
const { FRESHNESS } = require("./lib/drift");
const { inspect, writeReport } = require("./lib/inspect");

function main() {
  const { values } = parseArgs({
    options: {
      "target-org": { type: "string" },
      out: { type: "string" }
    }
  });
  if (!values["target-org"]) {
    console.error(
      "Usage: node tools/freshness.js --target-org <alias> [--out <dir>]"
    );
    return 1;
  }

  const report = inspect(values["target-org"]);
  writeReport(report, values.out, "freshness");
  const notFresh = report.rows.filter(
    (row) => row.freshness !== FRESHNESS.FRESH
  );
  for (const row of notFresh) {
    const where = row.missingIn ? ` (missing in ${row.missingIn})` : "";
    console.log(`${row.freshness.padEnd(7)} ${row.component}${where}`);
  }
  console.log(
    `${report.summary.fresh}/${report.summary.components} components fresh in ${report.targetOrg}`
  );
  return notFresh.length === 0 ? 0 : 1;
}

process.exitCode = main();
