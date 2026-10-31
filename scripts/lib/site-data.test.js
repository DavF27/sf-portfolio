"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  CATALOG,
  headline,
  cardSvg,
  appendHistory,
  durationsOf
} = require("./site-data");

const item = (slug) => CATALOG.find((entry) => entry.slug === slug);

function run(demo, mode, fields = {}) {
  return {
    Demo__c: demo,
    Mode__c: mode,
    Chaos__c: false,
    Status__c: "Succeeded",
    ...fields
  };
}

test("every demo of the catalogue points to an existing write-up", () => {
  const fs = require("node:fs");
  const path = require("node:path");
  for (const entry of CATALOG.filter((candidate) => candidate.doc)) {
    assert.ok(
      fs.existsSync(path.join(__dirname, "..", "..", entry.doc)),
      entry.doc
    );
  }
});

test("headlines are computed from the measured runs, chaos runs apart", () => {
  const metrics = [
    run("Batch_Filter", "BEFORE", {
      Volume__c: 1000,
      Async_Executions__c: 1000,
      Duration_Ms__c: 32000
    }),
    run("Batch_Filter", "AFTER", {
      Volume__c: 1000,
      Async_Executions__c: 1,
      Duration_Ms__c: 1000
    }),
    run("Async_Chain_Break", "BEFORE", { Records_Failed__c: 0 }),
    run("Async_Chain_Break", "BEFORE", {
      Chaos__c: true,
      Status__c: "Failed",
      Records_Failed__c: 3
    }),
    run("Async_Chain_Break", "AFTER", {
      Chaos__c: true,
      Records_Failed__c: 5
    })
  ];
  const batch = headline(item("batch-filter"), { metrics });
  assert.equal(batch.label, "Batch executions for 1000 contracts");
  assert.equal(batch.before.value, "1000 executions");
  assert.equal(batch.before.detail, "32 s");
  assert.equal(batch.after.value, "1 execution");
  assert.equal(batch.after.detail, "1.0 s");

  const chain = headline(item("async-chain-break"), { metrics });
  assert.equal(chain.before.value, "3 lines stuck");
  assert.equal(chain.after.value, "5 lines failed, logged");
});

test("the Bulk headline comes from the real Bulk API jobs", () => {
  const bulk = [
    { mode: "BEFORE", chaos: false, rows: 100, succeeded: 0, failed: 100 },
    { mode: "AFTER", chaos: false, rows: 100, succeeded: 100, failed: 0 },
    { mode: "AFTER", chaos: true, rows: 100, succeeded: 99, failed: 1 }
  ];
  const data = headline(item("bulk-all-or-nothing"), { bulk });
  assert.equal(data.before.value, "100 / 100 failed");
  assert.equal(data.after.value, "100 / 100 succeeded");
});

test("no headline without measurements", () => {
  for (const entry of CATALOG) {
    assert.equal(
      headline(entry, { metrics: [], bulk: [], drift: null }),
      null,
      entry.slug
    );
  }
});

test("the SVG card escapes text and describes itself", () => {
  const svg = cardSvg(
    "A <b> & c",
    {
      label: "label",
      before: { value: "1 < 2", detail: "d", ok: false },
      after: { value: "ok", detail: "d", ok: true }
    },
    "stamp"
  );
  assert.match(svg, /A &lt;b&gt; &amp; c/);
  assert.match(
    svg,
    /aria-label="A &lt;b&gt; &amp; c: before 1 &lt; 2, after ok"/
  );
  assert.doesNotMatch(svg, /<b>/);
});

test("history keeps the newest run first, once, and is capped", () => {
  let history = [];
  for (let index = 1; index <= 4; index++) {
    history = appendHistory(history, { run: String(index) }, 3);
  }
  assert.deepEqual(
    history.map((entry) => entry.run),
    ["4", "3", "2"]
  );
  history = appendHistory(history, { run: "3", rerun: true }, 3);
  assert.deepEqual(
    history.map((entry) => entry.run),
    ["3", "4", "2"]
  );
});

test("durations ignore chaos runs", () => {
  assert.deepEqual(
    durationsOf([
      run("D", "BEFORE", { Duration_Ms__c: 10 }),
      run("D", "AFTER", { Duration_Ms__c: 2 }),
      run("D", "AFTER", { Duration_Ms__c: 99, Chaos__c: true })
    ]),
    { "D:BEFORE": 10, "D:AFTER": 2 }
  );
});
