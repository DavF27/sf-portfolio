"use strict";
// Pure helpers of scripts/bulk-demo.js; covered by scripts/lib/bulk.test.js.
const { RUN_KEY_PATTERN, withLimit } = require("./report");

const DEMO = "Bulk_All_Or_Nothing";
const SOBJECT = "Contract_Demo__c";
const EXTERNAL_ID = "External_Id__c";
const MODES = ["BEFORE", "AFTER"];

/** Same keys as BulkActivationDemo.contractKey(row) in Apex. */
function contractKey(row) {
  return `CTR-${String(row).padStart(5, "0")}`;
}

function assertVolume(volume) {
  if (!Number.isInteger(volume) || volume < 1 || volume > 10000) {
    throw new Error(`Invalid volume: ${volume}`);
  }
}

/** Anonymous Apex resetting the demo data to N Draft contracts (chaos: one deal without amount). */
function buildPrepareApex(volume, chaos) {
  assertVolume(volume);
  return `BulkActivationDemo.prepare(${volume}, ${chaos === true}, new SyntheticDataGenerator(DemoDataService.DEFAULT_SEED));`;
}

/** CSV of the Bulk API job: one row per contract, activating it with the mode and run key of the run. */
function buildCsv(volume, mode, runKey) {
  assertVolume(volume);
  if (!MODES.includes(mode)) {
    throw new Error(`Invalid mode: ${mode}`);
  }
  if (!RUN_KEY_PATTERN.test(runKey)) {
    throw new Error(`Invalid run key: ${runKey}`);
  }
  const lines = [`${EXTERNAL_ID},Status__c,Processing_Mode__c,Run_Key__c`];
  for (let row = 1; row <= volume; row++) {
    lines.push(`${contractKey(row)},Active,${mode},${runKey}`);
  }
  return `${lines.join("\n")}\n`;
}

/**
 * The job Id is in result.jobInfo.id (observed with the CLI installed by the CI), in result.jobId
 * (newer plugin-data) or in data.jobId when rows failed.
 */
function parseJobId(json) {
  const jobId =
    json?.result?.jobInfo?.id ??
    json?.result?.jobId ??
    json?.data?.jobId ??
    // Last resort: Bulk ingest job Ids start with the 750 key prefix.
    /\b(750[A-Za-z0-9]{12}(?:[A-Za-z0-9]{3})?)\b/.exec(
      json?.message || ""
    )?.[1];
  if (!jobId) {
    throw new Error(
      `Bulk API job did not start: ${json?.message || JSON.stringify(json)}`
    );
  }
  return jobId;
}

/** Minimal RFC 4180 parser (quoted fields, doubled quotes, embedded commas and newlines). */
function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = "";
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const char = text[i];
    if (quoted) {
      if (char === '"' && text[i + 1] === '"') {
        field += '"';
        i++;
      } else if (char === '"') {
        quoted = false;
      } else {
        field += char;
      }
    } else if (char === '"') {
      quoted = true;
    } else if (char === ",") {
      row.push(field);
      field = "";
    } else if (char === "\n" || char === "\r") {
      if (char === "\r" && text[i + 1] === "\n") {
        i++;
      }
      row.push(field);
      rows.push(row);
      row = [];
      field = "";
    } else {
      field += char;
    }
  }
  if (field !== "" || row.length > 0) {
    row.push(field);
    rows.push(row);
  }
  const [header = [], ...records] = rows.filter(
    (cells) => cells.length > 1 || cells[0] !== ""
  );
  return records.map((cells) =>
    Object.fromEntries(header.map((name, index) => [name, cells[index]]))
  );
}

/** Failed rows of the job (1-based batch positions) and the first platform error. */
function summarizeFailures(failedCsv) {
  return summarizeFailureRecords(failedCsv ? parseCsv(failedCsv) : []);
}

function summarizeFailureRecords(records) {
  const failedRows = records
    .map((record) => Number(String(record[EXTERNAL_ID] || "").split("-")[1]))
    .filter((row) => Number.isInteger(row) && row > 0)
    .sort((a, b) => a - b);
  return {
    failedRows,
    firstError: records.find((record) => record.sf__Error)?.sf__Error || null
  };
}

/**
 * Older CLI versions return the whole job inline (result.jobInfo + result.records); newer ones only
 * return counters and need `sf data bulk results`. Returns null when the outcome is not inline.
 */
function inlineJobOutcome(json) {
  const jobInfo = json?.result?.jobInfo;
  const records = json?.result?.records;
  if (!jobInfo || !records) {
    return null;
  }
  const processed = Number(jobInfo.numberRecordsProcessed ?? 0);
  const failed = Number(jobInfo.numberRecordsFailed ?? 0);
  return {
    results: {
      processedRecords: processed,
      successfulRecords: processed - failed,
      failedRecords: failed
    },
    failures: summarizeFailureRecords(records.failedResults || [])
  };
}

function isWholeBatchFailure(results) {
  return (
    Number(results.processedRecords) > 0 &&
    Number(results.failedRecords) === Number(results.processedRecords)
  );
}

function cell(value) {
  return value === null || value === undefined
    ? ""
    : String(value).replace(/\|/g, "\\|").replace(/\r?\n/g, " ").slice(0, 140);
}

/** Markdown table of the real Bulk API jobs, joined with the Demo_Run__c measured by the trigger. */
function toBulkMarkdown(rows, { commit, date } = {}) {
  const lines = ["## Bulk API job (real) — all-or-nothing", ""];
  if (commit || date) {
    lines.push(`Commit \`${commit || "local"}\` · ${date || ""}`.trim(), "");
  }
  lines.push(
    "| Mode | Chaos | Rows | Job succeeded | Job failed | SOQL | DML | CPU (ms) | Run | Error |",
    "|---|---|---:|---:|---:|---:|---:|---:|---|---|"
  );
  for (const row of rows) {
    const verdict =
      row.failed === 0 ? "✅" : row.failed === row.rows ? "❌" : "⚠️";
    lines.push(
      `| ${row.mode} | ${row.chaos ? "yes" : "no"} | ${row.rows} | ${row.succeeded} | ${verdict} ${row.failed} | ${cell(withLimit(row.run?.SOQL_Queries__c, row.run?.SOQL_Limit__c))} | ${cell(withLimit(row.run?.DML_Statements__c, row.run?.DML_Limit__c))} | ${cell(row.run?.CPU_Time_Ms__c)} | ${cell(row.run?.Status__c)} | ${cell(row.firstError)} |`
    );
  }
  return `${lines.join("\n")}\n`;
}

module.exports = {
  DEMO,
  SOBJECT,
  EXTERNAL_ID,
  contractKey,
  buildPrepareApex,
  buildCsv,
  parseJobId,
  parseCsv,
  summarizeFailures,
  inlineJobOutcome,
  isWholeBatchFailure,
  toBulkMarkdown
};
