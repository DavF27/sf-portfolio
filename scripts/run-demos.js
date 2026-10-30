#!/usr/bin/env node
"use strict";
/**
 * Runs every active demo in BEFORE then AFTER mode against an org, waits for the Demo_Run__c
 * records written by the Demo_Step__e trigger and exports the measured metrics.
 *
 * Usage: node scripts/run-demos.js --target-org <alias> [--demo Limits_Probe] [--volume 150]
 *                                  [--chaos-demo Async_Chain_Break[,Other]] [--out scripts/out] [--timeout 90]
 * --chaos-demo also runs the listed demos in BEFORE and AFTER mode with Chaos on. Runs that no job closes
 * (silent asynchronous failures) are handed to the demo monitor once the queueable jobs are done.
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
const {
  recordUncaughtFailure,
  pollRuns,
  waitForRuns,
  waitForAsyncJobs,
  monitorRun
} = require("./lib/runs");

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

  const chaosDemos = String(args["chaos-demo"] || "")
    .split(",")
    .map((name) => name.trim())
    .filter(Boolean);
  const planned = [];
  for (const demo of demos) {
    const volume = Number(
      args.volume || demo.Max_Volume__c || demo.Default_Volume__c
    );
    const variants = [false];
    if (chaosDemos.includes(demo.DeveloperName)) {
      variants.push(true);
    }
    for (const [chaos, mode] of variants.flatMap((c) =>
      ["BEFORE", "AFTER"].map((m) => [c, m])
    )) {
      const run = {
        demo: demo.DeveloperName,
        mode,
        volume,
        runKey: crypto.randomUUID(),
        chaos
      };
      const outcome = executeRun(run, targetOrg);
      if (outcome.response?.status === "Running") {
        // Asynchronous demo: the next run resets the same records, let these jobs finish first.
        await waitForAsyncJobs(targetOrg, 600);
      }
      console.log(
        `${run.demo} ${mode}${chaos ? " + chaos" : ""} volume=${volume}: ${outcome.success ? "completed" : `failed (${outcome.message})`}`
      );
      planned.push(run);
    }
  }

  const runKeys = planned.map((run) => run.runKey);
  await waitForAsyncJobs(targetOrg, 600);
  const { missing } = await pollRuns(
    runKeys,
    targetOrg,
    Number(args.timeout || 90)
  );
  for (const run of planned.filter((item) => missing.includes(item.runKey))) {
    // Nobody closed this run: ask the demo monitor (a silent asynchronous failure is closed as FAILED).
    const response = monitorRun(run, targetOrg);
    console.log(
      `${run.demo} ${run.mode}${run.chaos ? " + chaos" : ""}: monitoring says ${response?.status}`
    );
  }
  const ordered = await waitForRuns(runKeys, targetOrg, 60);
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
