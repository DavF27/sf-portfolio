#!/usr/bin/env node
"use strict";
/**
 * Drift: classifies the differences between the org and Git since the last deployment tag.
 *   node tools/drift.js --target-org <alias> [--out <dir>]
 * Exit code: 2 when an UNKNOWN drift exists (a deployment would overwrite it), 0 otherwise.
 */
const { parseArgs } = require("node:util");
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
      "Usage: node tools/drift.js --target-org <alias> [--out <dir>]"
    );
    return 1;
  }

  const report = inspect(values["target-org"]);
  console.log(writeReport(report, values.out, "drift"));
  return report.summary.unknown > 0 ? 2 : 0;
}

process.exitCode = main();
