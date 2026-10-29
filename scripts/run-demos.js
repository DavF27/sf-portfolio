#!/usr/bin/env node
"use strict";
/**
 * Runs every active demo in BEFORE then AFTER mode against an org, waits for the Demo_Run__c
 * records written by the Demo_Step__e trigger and exports the measured metrics.
 *
 * Usage: node scripts/run-demos.js --target-org <alias> [--demo Limits_Probe] [--volume 150]
 *                                  [--out scripts/out] [--timeout 90]
 * Writes <out>/metrics.json and <out>/metrics.md; appends the table to $GITHUB_STEP_SUMMARY when set.
 */
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { runAnonymousApex, query } = require("./lib/sf");
const {
  buildRunApex,
  parseApexRun,
  toMarkdown,
  parseArgs
} = require("./lib/report");
const { recordUncaughtFailure, waitForRuns } = require("./lib/runs");

function loadDemos(targetOrg, onlyDemo) {
  const settings = query(
    "SELECT DeveloperName, Default_Volume__c, Max_Volume__c, Sort_Order__c FROM Demo_Setting__mdt WHERE Is_Active__c = true ORDER BY Sort_Order__c, DeveloperName",
    targetOrg
  );
  return settings.filter(
    (setting) => !onlyDemo || setting.DeveloperName === onlyDemo
  );
}

function executeRun(run, targetOrg) {
  const outcome = parseApexRun(runAnonymousApex(buildRunApex(run), targetOrg));
  if (!outcome.success) {
    // Uncatchable failure (e.g. System.LimitException): the transaction is gone, record it explicitly.
    recordUncaughtFailure(run, outcome.message, targetOrg);
  }
  return outcome;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const targetOrg = args["target-org"];
  if (!targetOrg) {
    throw new Error("--target-org is required");
  }
  const outDir = path.resolve(args.out || "scripts/out");
  const demos = loadDemos(targetOrg, args.demo);
  if (demos.length === 0) {
    throw new Error("No active demo found");
  }

  const planned = [];
  for (const demo of demos) {
    const volume = Number(
      args.volume || demo.Max_Volume__c || demo.Default_Volume__c
    );
    for (const mode of ["BEFORE", "AFTER"]) {
      const run = {
        demo: demo.DeveloperName,
        mode,
        volume,
        runKey: crypto.randomUUID(),
        chaos: false
      };
      const outcome = executeRun(run, targetOrg);
      console.log(
        `${run.demo} ${mode} volume=${volume}: ${outcome.success ? "completed" : `failed (${outcome.message})`}`
      );
      planned.push(run);
    }
  }

  const ordered = await waitForRuns(
    planned.map((run) => run.runKey),
    targetOrg,
    Number(args.timeout || 90)
  );
  const markdown = toMarkdown(ordered, {
    title: "Demo metrics (measured in the org)",
    commit: process.env.GITHUB_SHA,
    date: new Date().toISOString()
  });

  fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(
    path.join(outDir, "metrics.json"),
    JSON.stringify(ordered, null, 2)
  );
  fs.writeFileSync(path.join(outDir, "metrics.md"), markdown);
  if (process.env.GITHUB_STEP_SUMMARY) {
    fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, markdown);
  }
  console.log(markdown);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
