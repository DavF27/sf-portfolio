"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const report = require("./report");

const RUN = {
  demo: "Limits_Probe",
  mode: "BEFORE",
  volume: 150,
  runKey: "0b6c1f5e-4c1d-4a7a-9d0e-3f2a1b0c9d8e"
};

test("buildRunApex embeds validated inputs", () => {
  const apex = report.buildRunApex(RUN);
  assert.match(
    apex,
    /new DemoRunService\.Request\('Limits_Probe', 'BEFORE', 150\)/
  );
  assert.match(
    apex,
    /request\.runKey = '0b6c1f5e-4c1d-4a7a-9d0e-3f2a1b0c9d8e'/
  );
  assert.match(apex, /request\.chaos = false/);
});

test("buildRunApex rejects injection attempts and invalid values", () => {
  assert.throws(
    () =>
      report.buildRunApex({
        ...RUN,
        demo: "X'); delete [SELECT Id FROM Account]; //"
      }),
    /Invalid demo name/
  );
  assert.throws(
    () => report.buildRunApex({ ...RUN, mode: "SIDEWAYS" }),
    /Invalid mode/
  );
  assert.throws(
    () => report.buildRunApex({ ...RUN, volume: 0 }),
    /Invalid volume/
  );
  assert.throws(
    () => report.buildRunApex({ ...RUN, runKey: "a'b" }),
    /Invalid run key/
  );
});

test("buildUncaughtFailureApex escapes the platform message", () => {
  const apex = report.buildUncaughtFailureApex(
    RUN,
    "Too many SOQL queries: 101\nat 'Class.X'"
  );
  assert.match(
    apex,
    /recordUncaughtFailure\(request, 'Too many SOQL queries: 101 at \\'Class\.X\\''\);/
  );
});

test("buildUncaughtFailureApex keeps the closing quote on long messages", () => {
  const apex = report.buildUncaughtFailureApex(RUN, "x".repeat(40000));
  assert.match(apex, /'\);$/);
});

test("buildMonitorApex asks the demo monitor about one run", () => {
  const apex = report.buildMonitorApex({ ...RUN, chaos: true });
  assert.match(apex, /DemoRunService\.monitor\(request\)/);
  assert.match(apex, /request\.chaos = true/);
  assert.match(apex, /DEMO_RESPONSE/);
  assert.throws(
    () => report.buildMonitorApex({ ...RUN, mode: "X" }),
    /Invalid mode/
  );
});

test("buildSeedApex validates inputs", () => {
  assert.match(
    report.buildSeedApex("Bulk_Demo", 500),
    /DemoDataService\.seed\('Bulk_Demo', 500\)/
  );
  assert.throws(() => report.buildSeedApex("Bulk_Demo", -1), /Invalid volume/);
  assert.throws(() => report.buildSeedApex("1bad", 1), /Invalid demo name/);
});

test("parseApexRun reports success with the serialized response", () => {
  const outcome = report.parseApexRun({
    status: 0,
    result: {
      compiled: true,
      success: true,
      logs: 'USER_DEBUG|[6]|ERROR|DEMO_RESPONSE {"status":"Succeeded","runKey":"k"}\nmore'
    }
  });
  assert.deepEqual(outcome, {
    success: true,
    response: { status: "Succeeded", runKey: "k" }
  });
});

test("parseApexRun reports exceptions and compile errors", () => {
  assert.deepEqual(
    report.parseApexRun({
      status: 1,
      result: {
        compiled: true,
        success: false,
        exceptionMessage: "System.LimitException: Too many SOQL queries: 101"
      }
    }),
    {
      success: false,
      message: "System.LimitException: Too many SOQL queries: 101"
    }
  );
  assert.equal(
    report.parseApexRun({
      status: 1,
      result: { compiled: false, line: 3, compileProblem: "Unexpected token" }
    }).message,
    "Compile error line 3: Unexpected token"
  );
  assert.equal(
    report.parseApexRun({ status: 1, message: "No org" }).message,
    "No org"
  );
  assert.equal(
    report.parseApexRun({ status: 0, result: { success: true, logs: "" } })
      .response,
    null
  );
});

test("isTerminal recognises final statuses only", () => {
  assert.equal(report.isTerminal({ Status__c: "Succeeded" }), true);
  assert.equal(report.isTerminal({ Status__c: "Failed" }), true);
  assert.equal(report.isTerminal({ Status__c: "Running" }), false);
  assert.equal(report.isTerminal(undefined), false);
});

test("toMarkdown renders one row per run and escapes errors", () => {
  const markdown = report.toMarkdown(
    [
      {
        Demo__c: "Limits_Probe",
        Mode__c: "BEFORE",
        Volume__c: 150,
        Status__c: "Failed",
        SOQL_Queries__c: 101,
        Error_Message__c: "Too many | queries\nline"
      },
      {
        Demo__c: "Limits_Probe",
        Mode__c: "AFTER",
        Volume__c: 150,
        Status__c: "Succeeded",
        Chaos__c: true,
        SOQL_Queries__c: 1,
        Records_Processed__c: 150
      }
    ],
    { title: "Metrics", commit: "abc123", date: "2026-10-27" }
  );
  assert.match(markdown, /^## Metrics/);
  assert.match(markdown, /Commit `abc123` · 2026-10-27/);
  assert.match(
    markdown,
    /\| Limits_Probe \| BEFORE \| no \| 150 \| ❌ Failed \| 101 \|/
  );
  assert.match(markdown, /Too many \\\| queries line/);
  assert.match(
    markdown,
    /\| Limits_Probe \| AFTER \| yes \| 150 \| ✅ Succeeded \| 1 \|/
  );
});

test("withLimit shows consumption next to the limit when known", () => {
  assert.equal(report.withLimit(101, 100), "101 / 100");
  assert.equal(report.withLimit(3, null), "3");
  assert.equal(report.withLimit(null, 100), "");
});

test("parseArgs reads flags and values", () => {
  assert.deepEqual(
    report.parseArgs([
      "--target-org",
      "ci",
      "--dry",
      "--volume",
      "10",
      "stray"
    ]),
    { "target-org": "ci", dry: true, volume: "10" }
  );
});
