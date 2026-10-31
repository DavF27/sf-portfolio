#!/usr/bin/env node
"use strict";
/**
 * Deployment guard: refuses to overwrite a component changed in the org since the last deployment tag,
 * then deploys the committed package directories and tags the deployment.
 *   node tools/deploy.js --target-org <alias> [--dry-run] [--test-level RunLocalTests]
 *                        [--force --reason "<why the org change can be overwritten>"] [--out <dir>]
 * Exit code: 0 deployed (or dry run allowed), 2 blocked by an UNKNOWN drift, 1 on any other failure.
 */
const { parseArgs } = require("node:util");
const { sf } = require("../scripts/lib/sf");
const { DRIFT } = require("./lib/drift");
const { inspect, writeReport } = require("./lib/inspect");
const sources = require("./lib/sources");

function main() {
  const { values } = parseArgs({
    options: {
      "target-org": { type: "string" },
      "dry-run": { type: "boolean", default: false },
      force: { type: "boolean", default: false },
      reason: { type: "string" },
      "test-level": { type: "string", default: "RunLocalTests" },
      out: { type: "string" }
    }
  });
  const targetOrg = values["target-org"];
  if (!targetOrg) {
    console.error(
      'Usage: node tools/deploy.js --target-org <alias> [--dry-run] [--force --reason "..."]'
    );
    return 1;
  }
  if (values.force && !values.reason) {
    console.error(
      "--force needs a --reason: it is recorded in the deployment tag."
    );
    return 1;
  }

  const root = sources.repoRoot();
  const directories = sources.packageDirectories(root);
  const dirty = sources.uncommittedChanges(root, directories);
  if (dirty.length > 0 && !values["dry-run"]) {
    console.error(
      `Commit the package directories first: the deployment tag must describe what is deployed.\n${dirty.join("\n")}`
    );
    return 1;
  }

  const report = inspect(targetOrg, { root });
  writeReport(report, values.out, "deploy-guard");
  const unknown = report.rows.filter((row) => row.drift === DRIFT.UNKNOWN);
  const baseline = report.baselineTag || "no baseline tag";
  console.log(
    `Guard for ${targetOrg} (${baseline}): ${report.summary.pendingDeploy} pending, ` +
      `${report.summary.known} KNOWN, ${report.summary.intentional} INTENTIONAL, ${unknown.length} UNKNOWN`
  );

  if (unknown.length > 0 && !values.force) {
    console.error(
      "Deployment blocked: these components were changed in the org outside Git and would be overwritten.\n" +
        unknown
          .map(
            (row) =>
              `  ${row.component} — ${row.lastModifiedBy || "?"} on ${row.lastModifiedDate || "?"}`
          )
          .join("\n") +
        "\nRetrieve and commit them, list them in tools/drift-exceptions.json, or rerun with --force --reason."
    );
    return 2;
  }
  if (values["dry-run"]) {
    console.log("Dry run: the deployment would be allowed.");
    return 0;
  }

  const args = ["project", "deploy", "start", "--target-org", targetOrg];
  directories.forEach((directory) => args.push("--source-dir", directory));
  args.push("--test-level", values["test-level"], "--wait", "60");
  console.log(
    `Deploying ${directories.length} package directories to ${targetOrg}...`
  );
  const result = sf(args, { cwd: root });
  if (result.status !== 0 || result.result?.success === false) {
    console.error(
      `Deployment failed: ${result.message || result.result?.status}`
    );
    return 1;
  }

  const lines = [
    `Deployed ${report.commit} to ${targetOrg}`,
    `Deploy id: ${result.result.id}`,
    `Components: ${result.result.numberComponentsDeployed}, tests: ${result.result.numberTestsCompleted}`
  ];
  if (values.force && unknown.length > 0) {
    lines.push(
      `Forced over UNKNOWN drift: ${unknown.map((row) => row.component).join(", ")}`,
      `Reason: ${values.reason}`
    );
  }
  const tag = sources.createDeployTag(root, targetOrg, lines.join("\n"));
  console.log(
    `${lines.join("\n")}\nTagged ${tag}. Publish it with: git push origin ${tag}`
  );
  return 0;
}

process.exitCode = main();
