"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { classify, analyze, summarize, toMarkdown } = require("./drift");

const base = { hasBaseline: true, exception: undefined };

test("an untouched org with a local change is a pending deployment, not a drift", () => {
  assert.deepEqual(
    classify({ ...base, localHash: "L", orgHash: "B", baselineHash: "B" }),
    { freshness: "stale", missingIn: null, drift: null, pendingDeploy: true }
  );
});

test("an org that holds the local version is fresh", () => {
  assert.deepEqual(
    classify({ ...base, localHash: "B", orgHash: "B", baselineHash: "B" }),
    { freshness: "fresh", missingIn: null, drift: null, pendingDeploy: false }
  );
});

test("an org change already committed to Git is KNOWN", () => {
  const result = classify({
    ...base,
    localHash: "O",
    orgHash: "O",
    baselineHash: "B"
  });
  assert.equal(result.drift, "KNOWN");
  assert.equal(result.freshness, "fresh");
});

test("an org change missing from Git is UNKNOWN, or INTENTIONAL when listed", () => {
  const input = { ...base, localHash: "B", orgHash: "O", baselineHash: "B" };
  assert.equal(classify(input).drift, "UNKNOWN");
  assert.equal(
    classify({ ...input, exception: "org-only setting" }).drift,
    "INTENTIONAL"
  );
});

test("components created or deleted directly in the org are drifts", () => {
  const created = classify({
    ...base,
    localHash: null,
    orgHash: "O",
    baselineHash: null
  });
  assert.equal(created.drift, "UNKNOWN");
  assert.equal(created.missingIn, "local");

  const deleted = classify({
    ...base,
    localHash: "B",
    orgHash: null,
    baselineHash: "B"
  });
  assert.equal(deleted.drift, "UNKNOWN");
  assert.equal(deleted.missingIn, "org");
});

test("a new local component is a pending deployment", () => {
  const result = classify({
    ...base,
    localHash: "L",
    orgHash: null,
    baselineHash: null
  });
  assert.equal(result.drift, null);
  assert.equal(result.pendingDeploy, true);
  assert.equal(result.missingIn, "org");
});

test("without a baseline every difference is UNKNOWN", () => {
  const input = {
    localHash: "L",
    orgHash: "O",
    baselineHash: null,
    hasBaseline: false
  };
  assert.equal(classify(input).drift, "UNKNOWN");
  assert.equal(
    classify({ ...input, orgHash: "L" }).drift,
    null,
    "identical sides need no baseline"
  );
});

function map(entries) {
  return new Map(
    Object.entries(entries).map(([key, hash]) => [
      key,
      {
        key,
        type: key.split(":")[0],
        name: key.split(":")[1],
        hash,
        lastModifiedBy: "Org User",
        lastModifiedDate: "2026-10-31T10:00:00.000+0000"
      }
    ])
  );
}

test("analyze classifies every component and keeps the org author", () => {
  const rows = analyze({
    local: map({ "ApexClass:A": "a", "ApexClass:B": "b2", "ApexClass:C": "c" }),
    org: map({ "ApexClass:A": "a", "ApexClass:B": "b", "ApexClass:C": "hot" }),
    baseline: map({
      "ApexClass:A": "a",
      "ApexClass:B": "b",
      "ApexClass:C": "c",
      "ApexClass:Gone": "g"
    }),
    exceptions: []
  });
  assert.deepEqual(
    rows.map((row) => [row.component, row.drift, row.pendingDeploy]),
    [
      ["ApexClass:A", null, false],
      ["ApexClass:B", null, true],
      ["ApexClass:C", "UNKNOWN", false]
    ]
  );
  assert.equal(rows[2].lastModifiedBy, "Org User");
  assert.deepEqual(summarize(rows), {
    components: 3,
    fresh: 1,
    stale: 2,
    missing: 0,
    pendingDeploy: 1,
    known: 0,
    intentional: 0,
    unknown: 1
  });
});

test("analyze records the reason of an intentional drift and rejects unjustified exceptions", () => {
  const sides = {
    local: map({ "ApexClass:C": "c" }),
    org: map({ "ApexClass:C": "hot" }),
    baseline: map({ "ApexClass:C": "c" })
  };
  const [row] = analyze({
    ...sides,
    exceptions: [{ component: "ApexClass:C", reason: "Hotfix kept until Q4" }]
  });
  assert.equal(row.drift, "INTENTIONAL");
  assert.equal(row.reason, "Hotfix kept until Q4");
  assert.throws(
    () => analyze({ ...sides, exceptions: [{ component: "ApexClass:C" }] }),
    /needs a component and a reason/
  );
});

test("the Markdown report lists only notable components", () => {
  const rows = analyze({
    local: map({ "ApexClass:A": "a", "ApexClass:C": "c" }),
    org: map({ "ApexClass:A": "a", "ApexClass:C": "hot" }),
    baseline: map({ "ApexClass:A": "a", "ApexClass:C": "c" }),
    exceptions: []
  });
  const markdown = toMarkdown({
    targetOrg: "ci",
    baselineTag: "deploy/ci/20261031-100000",
    commit: "abc1234",
    rows
  });
  assert.match(markdown, /\| 2 \| 1 \| 1 \| 0 \| 0 \| 0 \| 0 \| 1 \|/);
  assert.match(markdown, /\| ApexClass:C \| stale \| \*\*UNKNOWN\*\* \|/);
  assert.doesNotMatch(markdown, /ApexClass:A \|/);
});
