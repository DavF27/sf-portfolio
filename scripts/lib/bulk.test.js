"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const bulk = require("./bulk");

const RUN_KEY = "0b6c1f5e-4c1d-4a7a-9d0e-3f2a1b0c9d8e";

test("contractKey matches the Apex external Ids", () => {
  assert.equal(bulk.contractKey(1), "CTR-00001");
  assert.equal(bulk.contractKey(200), "CTR-00200");
});

test("buildPrepareApex validates inputs", () => {
  assert.equal(
    bulk.buildPrepareApex(50, true),
    "BulkActivationDemo.prepare(50, true, new SyntheticDataGenerator(DemoDataService.DEFAULT_SEED));"
  );
  assert.match(bulk.buildPrepareApex(5, "yes"), /prepare\(5, false,/);
  assert.throws(() => bulk.buildPrepareApex(0, false), /Invalid volume/);
  assert.throws(
    () => bulk.buildPrepareApex("5); delete x;", false),
    /Invalid volume/
  );
});

test("buildCsv activates every contract with the mode and run key", () => {
  const csv = bulk.buildCsv(3, "BEFORE", RUN_KEY);
  assert.equal(
    csv,
    `External_Id__c,Status__c,Processing_Mode__c,Run_Key__c\nCTR-00001,Active,BEFORE,${RUN_KEY}\nCTR-00002,Active,BEFORE,${RUN_KEY}\nCTR-00003,Active,BEFORE,${RUN_KEY}\n`
  );
  assert.throws(() => bulk.buildCsv(3, "SIDEWAYS", RUN_KEY), /Invalid mode/);
  assert.throws(() => bulk.buildCsv(3, "AFTER", "a,b"), /Invalid run key/);
});

test("parseJobId reads the job from success and failure outputs", () => {
  assert.equal(
    bulk.parseJobId({
      status: 0,
      result: {
        jobInfo: {
          id: "750cf00000LTKGzAAP",
          state: "JobComplete",
          numberRecordsFailed: 0
        },
        records: {}
      }
    }),
    "750cf00000LTKGzAAP"
  );
  assert.equal(
    bulk.parseJobId({ status: 0, result: { jobId: "750A" } }),
    "750A"
  );
  assert.equal(
    bulk.parseJobId({
      status: 1,
      message: "1 record failed",
      data: { jobId: "750B", state: "JobComplete" }
    }),
    "750B"
  );
  assert.equal(
    bulk.parseJobId({
      status: 1,
      message:
        "Job 750cf00000LTKH0AAP has 100 failed records. Run sf data bulk results --job-id 750cf00000LTKH0AAP"
    }),
    "750cf00000LTKH0AAP"
  );
  assert.throws(
    () => bulk.parseJobId({ status: 1, message: "No org" }),
    /did not start: No org/
  );
});

test("parseCsv handles quotes, commas and newlines", () => {
  const csv =
    '"sf__Id","sf__Error",External_Id__c\r\n"","CANNOT_INSERT: ContractDemoTrigger: execution, caused by ""System.LimitException""\nline 2",CTR-00002\n';
  assert.deepEqual(bulk.parseCsv(csv), [
    {
      sf__Id: "",
      sf__Error:
        'CANNOT_INSERT: ContractDemoTrigger: execution, caused by "System.LimitException"\nline 2',
      External_Id__c: "CTR-00002"
    }
  ]);
  assert.deepEqual(bulk.parseCsv(""), []);
});

test("summarizeFailures returns sorted rows and the first error", () => {
  const csv =
    '"sf__Id","sf__Error","External_Id__c"\n"","Too many SOQL queries: 101","CTR-00010"\n"","Too many SOQL queries: 101","CTR-00002"\n';
  assert.deepEqual(bulk.summarizeFailures(csv), {
    failedRows: [2, 10],
    firstError: "Too many SOQL queries: 101"
  });
  assert.deepEqual(bulk.summarizeFailures(undefined), {
    failedRows: [],
    firstError: null
  });
});

test("inlineJobOutcome reads counters and failures returned inline", () => {
  const outcome = bulk.inlineJobOutcome({
    status: 0,
    result: {
      jobInfo: {
        id: "750A",
        numberRecordsProcessed: 100,
        numberRecordsFailed: 1
      },
      records: {
        successfulResults: [],
        failedResults: [
          {
            sf__Id: "",
            sf__Error:
              "FIELD_CUSTOM_VALIDATION_EXCEPTION:Deal CTR-00050-2: Amount must be greater than zero",
            External_Id__c: "CTR-00050"
          }
        ],
        unprocessedRecords: []
      }
    }
  });
  assert.deepEqual(outcome, {
    results: { processedRecords: 100, successfulRecords: 99, failedRecords: 1 },
    failures: {
      failedRows: [50],
      firstError:
        "FIELD_CUSTOM_VALIDATION_EXCEPTION:Deal CTR-00050-2: Amount must be greater than zero"
    }
  });
  assert.equal(
    bulk.inlineJobOutcome({ status: 0, result: { jobId: "750B" } }),
    null
  );
});

test("isWholeBatchFailure distinguishes all-or-nothing from isolated failures", () => {
  assert.equal(
    bulk.isWholeBatchFailure({ processedRecords: 50, failedRecords: 50 }),
    true
  );
  assert.equal(
    bulk.isWholeBatchFailure({ processedRecords: 50, failedRecords: 1 }),
    false
  );
  assert.equal(
    bulk.isWholeBatchFailure({ processedRecords: 0, failedRecords: 0 }),
    false
  );
});

test("toBulkMarkdown renders one verdict per job", () => {
  const markdown = bulk.toBulkMarkdown(
    [
      {
        mode: "BEFORE",
        chaos: false,
        rows: 50,
        succeeded: 0,
        failed: 50,
        firstError: "Too many | SOQL",
        run: { SOQL_Queries__c: 201, SOQL_Limit__c: 200, Status__c: "Failed" }
      },
      {
        mode: "AFTER",
        chaos: false,
        rows: 50,
        succeeded: 50,
        failed: 0,
        run: { SOQL_Queries__c: 3, Status__c: "Succeeded" }
      },
      {
        mode: "AFTER",
        chaos: true,
        rows: 50,
        succeeded: 49,
        failed: 1,
        firstError: "Deal CTR-00025-2: Amount",
        run: null
      }
    ],
    { commit: "abc", date: "2026-10-29" }
  );
  assert.match(markdown, /Commit `abc` · 2026-10-29/);
  assert.match(
    markdown,
    /\| BEFORE \| no \| 50 \| 0 \| ❌ 50 \| 201 \/ 200 \|/
  );
  assert.match(markdown, /Too many \\\| SOQL/);
  assert.match(markdown, /\| AFTER \| no \| 50 \| 50 \| ✅ 0 \| 3 \|/);
  assert.match(markdown, /\| AFTER \| yes \| 50 \| 49 \| ⚠️ 1 \|/);
});
