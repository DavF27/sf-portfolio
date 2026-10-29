#!/usr/bin/env node
"use strict";
/**
 * Sends real Bulk API 2.0 jobs that activate N demo contracts in BEFORE then AFTER mode, reads the
 * job results and joins them with the Demo_Run__c measured by the trigger.
 *
 * Usage: node scripts/bulk-demo.js --target-org <alias> [--volume 50] [--with-chaos]
 *                                  [--out scripts/out] [--timeout 120]
 * Writes <out>/bulk.json and <out>/bulk.md; appends the table to $GITHUB_STEP_SUMMARY when set.
 * Writes demo data in the target org: never point it at an org without the demo-bulk package.
 */
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { sf, runAnonymousApex } = require("./lib/sf");
const { parseApexRun, parseArgs } = require("./lib/report");
const { recordUncaughtFailure, waitForRuns } = require("./lib/runs");
const bulk = require("./lib/bulk");

function prepare(volume, chaos, targetOrg) {
  const outcome = parseApexRun(
    runAnonymousApex(bulk.buildPrepareApex(volume, chaos), targetOrg)
  );
  if (!outcome.success) {
    throw new Error(`Data preparation failed: ${outcome.message}`);
  }
}

function runJob(run, targetOrg, workDir) {
  const csvFile = path.join(workDir, `${run.mode}-${run.runKey}.csv`);
  fs.writeFileSync(csvFile, bulk.buildCsv(run.volume, run.mode, run.runKey));
  const upsert = sf([
    "data",
    "upsert",
    "bulk",
    "--sobject",
    bulk.SOBJECT,
    "--external-id",
    bulk.EXTERNAL_ID,
    "--file",
    csvFile,
    "--line-ending",
    "LF",
    "--wait",
    "10",
    "--target-org",
    targetOrg
  ]);
  const jobId = bulk.parseJobId(upsert);

  // Writes <jobId>-success-records.csv and <jobId>-failed-records.csv in workDir.
  const results = sf(
    ["data", "bulk", "results", "--job-id", jobId, "--target-org", targetOrg],
    { cwd: workDir }
  );
  if (results.status !== 0) {
    throw new Error(`Cannot read Bulk API job ${jobId}: ${results.message}`);
  }
  const failedFile = results.result.failedFilePath
    ? path.resolve(workDir, results.result.failedFilePath)
    : null;
  const failures = bulk.summarizeFailures(
    failedFile && fs.existsSync(failedFile)
      ? fs.readFileSync(failedFile, "utf8")
      : ""
  );
  return { jobId, results: results.result, failures };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const targetOrg = args["target-org"];
  if (!targetOrg) {
    throw new Error("--target-org is required");
  }
  const volume = Number(args.volume || 50);
  const outDir = path.resolve(args.out || "scripts/out");
  const workDir = path.join(outDir, "bulk-jobs");
  fs.mkdirSync(workDir, { recursive: true });

  const plan = [
    { mode: "BEFORE", chaos: false },
    { mode: "AFTER", chaos: false }
  ];
  if (args["with-chaos"]) {
    plan.push({ mode: "AFTER", chaos: true });
  }

  const rows = [];
  for (const step of plan) {
    const run = {
      demo: bulk.DEMO,
      mode: step.mode,
      volume,
      chaos: step.chaos,
      runKey: crypto.randomUUID()
    };
    prepare(volume, step.chaos, targetOrg);
    const job = runJob(run, targetOrg, workDir);
    if (bulk.isWholeBatchFailure(job.results)) {
      // The trigger died with the whole chunk (LimitException or unhandled error): record it.
      recordUncaughtFailure(
        run,
        job.failures.firstError || "Every row of the batch failed",
        targetOrg
      );
    }
    const [measured] = await waitForRuns(
      [run.runKey],
      targetOrg,
      Number(args.timeout || 120)
    );
    rows.push({
      mode: run.mode,
      chaos: run.chaos,
      rows: Number(job.results.processedRecords),
      succeeded: Number(job.results.successfulRecords ?? 0),
      failed: Number(job.results.failedRecords ?? 0),
      failedRows: job.failures.failedRows,
      firstError: job.failures.firstError,
      jobId: job.jobId,
      run: measured
    });
    console.log(
      `${run.mode}${run.chaos ? " + chaos" : ""}: job ${job.jobId}, ${job.results.failedRecords ?? 0}/${job.results.processedRecords} rows failed`
    );
  }

  const markdown = bulk.toBulkMarkdown(rows, {
    commit: process.env.GITHUB_SHA,
    date: new Date().toISOString()
  });
  fs.writeFileSync(
    path.join(outDir, "bulk.json"),
    JSON.stringify(rows, null, 2)
  );
  fs.writeFileSync(path.join(outDir, "bulk.md"), markdown);
  if (process.env.GITHUB_STEP_SUMMARY) {
    fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, markdown);
  }
  console.log(markdown);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
