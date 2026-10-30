"use strict";
// Pure helpers shared by the scripts; covered by scripts/lib/report.test.js.

const RUN_KEY_PATTERN = /^[A-Za-z0-9-]{8,36}$/;
const API_NAME_PATTERN = /^[A-Za-z][A-Za-z0-9_]{0,79}$/;
const MODES = ["BEFORE", "AFTER"];
const TERMINAL_STATUSES = ["Succeeded", "Failed"];

function assertApiName(value, what) {
  if (!API_NAME_PATTERN.test(String(value))) {
    throw new Error(`Invalid ${what}: ${value}`);
  }
}

function assertRun({ demo, mode, volume, runKey }) {
  assertApiName(demo, "demo name");
  if (!MODES.includes(mode)) {
    throw new Error(`Invalid mode: ${mode}`);
  }
  if (!Number.isInteger(volume) || volume < 1) {
    throw new Error(`Invalid volume: ${volume}`);
  }
  if (!RUN_KEY_PATTERN.test(runKey)) {
    throw new Error(`Invalid run key: ${runKey}`);
  }
}

function apexString(value) {
  return `'${String(value).replace(/\\/g, "\\\\").replace(/'/g, "\\'").replace(/\r?\n/g, " ")}'`;
}

/** Anonymous Apex running one demo with the Script source; inputs are validated first. */
function buildRunApex(run) {
  assertRun(run);
  return [
    `DemoRunService.Request request = new DemoRunService.Request('${run.demo}', '${run.mode}', ${run.volume});`,
    `request.runKey = '${run.runKey}';`,
    `request.source = DemoRunService.SOURCE_SCRIPT;`,
    `request.chaos = ${run.chaos === true};`,
    `DemoRunService.Response response = DemoRunService.run(request);`,
    `System.debug(LoggingLevel.ERROR, 'DEMO_RESPONSE ' + JSON.serialize(response));`
  ].join("\n");
}

/** Anonymous Apex recording a failure the platform did not let the run catch. */
function buildUncaughtFailureApex(run, message) {
  assertRun(run);
  return [
    `DemoRunService.Request request = new DemoRunService.Request('${run.demo}', '${run.mode}', ${run.volume});`,
    `request.runKey = '${run.runKey}';`,
    `request.source = DemoRunService.SOURCE_SCRIPT;`,
    `request.chaos = ${run.chaos === true};`,
    `DemoRunService.recordUncaughtFailure(request, ${apexString(String(message).slice(0, 32000))});`
  ].join("\n");
}

/** Anonymous Apex asking the demo monitor whether a run is stuck (asynchronous demos). */
function buildMonitorApex(run) {
  assertRun(run);
  return [
    `DemoRunService.Request request = new DemoRunService.Request('${run.demo}', '${run.mode}', ${run.volume});`,
    `request.runKey = '${run.runKey}';`,
    `request.source = DemoRunService.SOURCE_SCRIPT;`,
    `request.chaos = ${run.chaos === true};`,
    `DemoRunService.Response response = DemoRunService.monitor(request);`,
    `System.debug(LoggingLevel.ERROR, 'DEMO_RESPONSE ' + JSON.serialize(response));`
  ].join("\n");
}

function buildSeedApex(demo, volume) {
  assertApiName(demo, "demo name");
  if (!Number.isInteger(volume) || volume < 1) {
    throw new Error(`Invalid volume: ${volume}`);
  }
  return `System.debug(LoggingLevel.ERROR, 'SEEDED ' + DemoDataService.seed('${demo}', ${volume}));`;
}

/** Normalises the JSON printed by `sf apex run --json`. */
function parseApexRun(json) {
  const result = json?.result ?? {};
  if (result.compiled === false) {
    return {
      success: false,
      message: `Compile error line ${result.line}: ${result.compileProblem}`
    };
  }
  if (result.success === false) {
    return {
      success: false,
      message: result.exceptionMessage || "Unknown Apex error"
    };
  }
  if (json?.status && json.status !== 0 && !json.result) {
    return { success: false, message: json.message || "sf apex run failed" };
  }
  const match = /DEMO_RESPONSE (\{.*\})/.exec(result.logs || "");
  return { success: true, response: match ? JSON.parse(match[1]) : null };
}

function isTerminal(run) {
  return TERMINAL_STATUSES.includes(run?.Status__c);
}

/** "101 / 100": consumption next to the limit of the transaction that ran the demo. */
function withLimit(value, limit) {
  const formatted = formatNumber(value);
  return formatted && limit ? `${formatted} / ${limit}` : formatted;
}

function formatNumber(value) {
  return value === null || value === undefined ? "" : String(value);
}

/** Markdown table of Demo_Run__c records, used in the job summary. */
function toMarkdown(runs, { title = "Demo metrics", commit, date } = {}) {
  const lines = [`## ${title}`, ""];
  if (commit || date) {
    lines.push(`Commit \`${commit || "local"}\` · ${date || ""}`.trim(), "");
  }
  lines.push(
    "| Demo | Mode | Chaos | Volume | Status | SOQL | DML | CPU (ms) | Duration (ms) | Processed | Failed | Async executions | Error |",
    "|---|---|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---|"
  );
  for (const run of runs) {
    const error = (run.Error_Message__c || "")
      .replace(/\|/g, "\\|")
      .replace(/\r?\n/g, " ")
      .slice(0, 120);
    lines.push(
      `| ${run.Demo__c} | ${run.Mode__c} | ${run.Chaos__c ? "yes" : "no"} | ${formatNumber(run.Volume__c)} | ${run.Status__c === "Succeeded" ? "✅" : "❌"} ${run.Status__c} | ${withLimit(run.SOQL_Queries__c, run.SOQL_Limit__c)} | ${withLimit(run.DML_Statements__c, run.DML_Limit__c)} | ${formatNumber(run.CPU_Time_Ms__c)} | ${formatNumber(run.Duration_Ms__c)} | ${formatNumber(run.Records_Processed__c)} | ${formatNumber(run.Records_Failed__c)} | ${formatNumber(run.Async_Executions__c)} | ${error} |`
    );
  }
  return `${lines.join("\n")}\n`;
}

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    const token = argv[i];
    if (!token.startsWith("--")) {
      continue;
    }
    const key = token.slice(2);
    const next = argv[i + 1];
    if (next === undefined || next.startsWith("--")) {
      args[key] = true;
    } else {
      args[key] = next;
      i++;
    }
  }
  return args;
}

module.exports = {
  RUN_KEY_PATTERN,
  assertRun,
  buildRunApex,
  buildUncaughtFailureApex,
  buildMonitorApex,
  buildSeedApex,
  parseApexRun,
  isTerminal,
  toMarkdown,
  withLimit,
  parseArgs
};
