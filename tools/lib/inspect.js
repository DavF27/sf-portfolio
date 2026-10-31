"use strict";
const fs = require("node:fs");
const path = require("node:path");
const { buildComponents } = require("./components");
const { analyze, summarize, toMarkdown } = require("./drift");
const sources = require("./sources");

const EXCEPTIONS_FILE = "tools/drift-exceptions.json";

function readExceptions(root) {
  const file = path.join(root, EXCEPTIONS_FILE);
  if (!fs.existsSync(file)) {
    return [];
  }
  return JSON.parse(fs.readFileSync(file, "utf8")).exceptions || [];
}

/** Reads the three sides (working copy, org, last deployment tag) and classifies every component. */
function inspect(targetOrg, { root = sources.repoRoot() } = {}) {
  const directories = sources.packageDirectories(root);
  const local = buildComponents(sources.localFiles(root, directories));
  const org = sources.orgComponents(targetOrg);
  const baselineTag = sources.latestDeployTag(root, targetOrg);
  const baseline = baselineTag
    ? buildComponents(sources.gitFiles(root, baselineTag, directories))
    : null;
  const rows = analyze({
    local,
    org,
    baseline,
    exceptions: readExceptions(root)
  });
  return {
    root,
    directories,
    targetOrg,
    baselineTag,
    commit: sources.headCommit(root),
    rows,
    summary: summarize(rows)
  };
}

/** Writes <name>.json and <name>.md into outDir, and appends the Markdown to the GitHub job summary. */
function writeReport(report, outDir, name) {
  const markdown = toMarkdown(report);
  if (outDir) {
    fs.mkdirSync(outDir, { recursive: true });
    const { root, directories, ...data } = report; // eslint-disable-line no-unused-vars
    fs.writeFileSync(
      path.join(outDir, `${name}.json`),
      JSON.stringify(data, null, 2) + "\n"
    );
    fs.writeFileSync(path.join(outDir, `${name}.md`), markdown);
  }
  if (process.env.GITHUB_STEP_SUMMARY) {
    fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, markdown + "\n");
  }
  return markdown;
}

module.exports = { inspect, writeReport, EXCEPTIONS_FILE };
