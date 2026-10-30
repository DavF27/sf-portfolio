"use strict";
// Demo_Run__c helpers shared by run-demos.js and bulk-demo.js.
const { runAnonymousApex, query } = require("./sf");
const {
  buildUncaughtFailureApex,
  buildMonitorApex,
  parseApexRun,
  isTerminal,
  RUN_KEY_PATTERN
} = require("./report");

const RUN_FIELDS = [
  "Run_Key__c",
  "Demo__c",
  "Mode__c",
  "Status__c",
  "Source__c",
  "Volume__c",
  "Chaos__c",
  "SOQL_Queries__c",
  "SOQL_Limit__c",
  "DML_Limit__c",
  "DML_Statements__c",
  "DML_Rows__c",
  "CPU_Time_Ms__c",
  "Duration_Ms__c",
  "Records_Processed__c",
  "Records_Failed__c",
  "Step_Count__c",
  "Error_Message__c"
].join(", ");

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** Records a failure the platform did not let the run catch (System.LimitException, unhandled trigger error). */
function recordUncaughtFailure(run, message, targetOrg) {
  const recorded = parseApexRun(
    runAnonymousApex(buildUncaughtFailureApex(run, message), targetOrg)
  );
  if (!recorded.success) {
    throw new Error(
      `Could not record failure of ${run.demo} ${run.mode}: ${recorded.message}`
    );
  }
}

/**
 * Polls Demo_Run__c until every run key is terminal or the timeout expires.
 * Returns the runs in key order (undefined when absent) and the keys still not terminal.
 */
async function pollRuns(runKeys, targetOrg, timeoutSeconds = 90) {
  runKeys.forEach((key) => {
    if (!RUN_KEY_PATTERN.test(key)) {
      throw new Error(`Invalid run key: ${key}`);
    }
  });
  const deadline = Date.now() + timeoutSeconds * 1000;
  const keys = runKeys.map((key) => `'${key}'`).join(",");
  let runs = [];
  for (;;) {
    runs = query(
      `SELECT ${RUN_FIELDS} FROM Demo_Run__c WHERE Run_Key__c IN (${keys})`,
      targetOrg
    );
    const ordered = runKeys.map((key) =>
      runs.find((run) => run.Run_Key__c === key)
    );
    const missing = runKeys.filter((key, index) => !isTerminal(ordered[index]));
    if (missing.length === 0 || Date.now() >= deadline) {
      return { runs: ordered, missing };
    }
    await sleep(3000);
  }
}

/** Waits until every run key has a terminal Demo_Run__c (written asynchronously by the event trigger). */
async function waitForRuns(runKeys, targetOrg, timeoutSeconds = 90) {
  const { runs, missing } = await pollRuns(runKeys, targetOrg, timeoutSeconds);
  if (missing.length > 0) {
    throw new Error(`Timed out waiting for Demo_Run__c: ${missing.join(", ")}`);
  }
  return runs;
}

/** Waits until no queueable job is queued or running in the org (the demo org runs nothing else). */
async function waitForAsyncJobs(targetOrg, timeoutSeconds = 300) {
  const deadline = Date.now() + timeoutSeconds * 1000;
  for (;;) {
    const active = query(
      "SELECT Id FROM AsyncApexJob WHERE JobType = 'Queueable' AND Status IN ('Holding', 'Queued', 'Preparing', 'Processing') LIMIT 200",
      targetOrg
    );
    if (active.length === 0) {
      return;
    }
    if (Date.now() >= deadline) {
      throw new Error(
        `${active.length} queueable job(s) still active after ${timeoutSeconds} s`
      );
    }
    await sleep(5000);
  }
}

/** Asks the demo monitor about a run nobody closed; a stuck run is closed as FAILED. */
function monitorRun(run, targetOrg) {
  const outcome = parseApexRun(
    runAnonymousApex(buildMonitorApex(run), targetOrg)
  );
  if (!outcome.success) {
    throw new Error(
      `Could not monitor ${run.demo} ${run.mode}: ${outcome.message}`
    );
  }
  return outcome.response;
}

module.exports = {
  recordUncaughtFailure,
  pollRuns,
  waitForRuns,
  waitForAsyncJobs,
  monitorRun
};
