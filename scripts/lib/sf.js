"use strict";
const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const isWindows = process.platform === "win32";

// sf is a .cmd shim on Windows, which requires a shell; arguments must then be quoted by hand.
function quote(arg) {
  return isWindows && /[\s"&|<>^]/.test(arg)
    ? `"${arg.replace(/"/g, '""')}"`
    : arg;
}

/** Runs an sf CLI command with --json and returns the parsed output (even on a non-zero exit). */
function sf(args) {
  const result = spawnSync("sf", [...args, "--json"].map(quote), {
    encoding: "utf8",
    shell: isWindows,
    maxBuffer: 64 * 1024 * 1024,
    env: {
      ...process.env,
      SF_DISABLE_COLORS: "true",
      SF_SKIP_NEW_VERSION_CHECK: "true"
    }
  });
  const stdout = (result.stdout || "").trim();
  const start = stdout.indexOf("{");
  if (start < 0) {
    throw new Error(
      `sf ${args[0]} returned no JSON: ${result.stderr || stdout}`
    );
  }
  return JSON.parse(stdout.slice(start));
}

function runAnonymousApex(apex, targetOrg) {
  const file = path.join(
    fs.mkdtempSync(path.join(os.tmpdir(), "sf-portfolio-")),
    "run.apex"
  );
  fs.writeFileSync(file, apex);
  try {
    return sf(["apex", "run", "--file", file, "--target-org", targetOrg]);
  } finally {
    fs.rmSync(path.dirname(file), { recursive: true, force: true });
  }
}

function query(soql, targetOrg) {
  const json = sf([
    "data",
    "query",
    "--query",
    soql,
    "--target-org",
    targetOrg
  ]);
  if (json.status !== 0) {
    throw new Error(json.message || "Query failed");
  }
  return json.result.records;
}

module.exports = { sf, runAnonymousApex, query };
