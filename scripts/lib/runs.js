"use strict";
// Demo_Run__c helpers shared by run-demos.js and bulk-demo.js.
const { runAnonymousApex, query } = require("./sf");
const {
  buildUncaughtFailureApex,
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

/** Waits until every run key has a terminal Demo_Run__c (written asynchronously by the event trigger). */
async function waitForRuns(runKeys, targetOrg, timeoutSeconds = 90) {
  runKeys.forEach((key) => {
    if (!RUN_KEY_PATTERN.test(key)) {
      throw new Error(`Invalid run key: ${key}`);
    }
  });
  const deadline = Date.now() + timeoutSeconds * 1000;
  const keys = runKeys.map((key) => `'${key}'`).join(",");
  let runs = [];
  while (Date.now() < deadline) {
    runs = query(
      `SELECT ${RUN_FIELDS} FROM Demo_Run__c WHERE Run_Key__c IN (${keys})`,
      targetOrg
    );
    if (runs.length === runKeys.length && runs.every(isTerminal)) {
      return runKeys.map((key) => runs.find((run) => run.Run_Key__c === key));
    }
    await sleep(3000);
  }
  const missing = runKeys.filter(
    (key) => !runs.some((run) => run.Run_Key__c === key && isTerminal(run))
  );
  throw new Error(`Timed out waiting for Demo_Run__c: ${missing.join(", ")}`);
}

module.exports = { recordUncaughtFailure, waitForRuns };
