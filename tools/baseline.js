#!/usr/bin/env node
"use strict";
/**
 * Baseline: tags the current commit as deployed in an org, only when the org holds exactly this commit.
 * Used once to adopt an org that was deployed before the deployment guard existed.
 *   node tools/baseline.js --target-org <alias>
 * Exit code: 0 when tagged, 2 when the org differs from the commit, 1 on usage errors.
 */
const { parseArgs } = require("node:util");
const { FRESHNESS } = require("./lib/drift");
const { inspect } = require("./lib/inspect");
const sources = require("./lib/sources");

function main() {
  const { values } = parseArgs({
    options: { "target-org": { type: "string" } }
  });
  const targetOrg = values["target-org"];
  if (!targetOrg) {
    console.error("Usage: node tools/baseline.js --target-org <alias>");
    return 1;
  }

  const root = sources.repoRoot();
  const dirty = sources.uncommittedChanges(
    root,
    sources.packageDirectories(root)
  );
  if (dirty.length > 0) {
    console.error(
      `Commit the package directories first: the tag must describe the org.\n${dirty.join("\n")}`
    );
    return 1;
  }

  const report = inspect(targetOrg, { root });
  const notFresh = report.rows.filter(
    (row) => row.freshness !== FRESHNESS.FRESH
  );
  if (notFresh.length > 0) {
    console.error(
      `${targetOrg} does not hold commit ${report.commit}; no baseline tag:\n` +
        notFresh.map((row) => `  ${row.freshness} ${row.component}`).join("\n")
    );
    return 2;
  }

  const tag = sources.createDeployTag(
    root,
    targetOrg,
    `Baseline of ${targetOrg}: ${report.summary.components} components fresh at ${report.commit}`
  );
  console.log(`Tagged ${tag} (${report.summary.components} components fresh)`);
  console.log(`Publish it with: git push origin ${tag}`);
  return 0;
}

process.exitCode = main();
