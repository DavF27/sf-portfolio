"use strict";
const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const { toolingQuery } = require("../../scripts/lib/sf");
const { buildComponents } = require("./components");

const TAG_PREFIX = "deploy";

function git(args, { cwd, input, binary = false } = {}) {
  const result = spawnSync("git", args, {
    cwd,
    input,
    encoding: binary ? undefined : "utf8",
    maxBuffer: 256 * 1024 * 1024
  });
  if (result.status !== 0) {
    const stderr = Buffer.isBuffer(result.stderr)
      ? result.stderr.toString("utf8")
      : result.stderr;
    throw new Error(`git ${args[0]} failed: ${(stderr || "").trim()}`);
  }
  return result.stdout;
}

function repoRoot(cwd = process.cwd()) {
  return git(["rev-parse", "--show-toplevel"], { cwd }).trim();
}

function packageDirectories(root) {
  const project = JSON.parse(
    fs.readFileSync(path.join(root, "sfdx-project.json"), "utf8")
  );
  return project.packageDirectories.map((item) =>
    item.path.replace(/\\/g, "/")
  );
}

/** Files of the working copy (what a deployment would send). */
function localFiles(root, directories) {
  const files = [];
  const walk = (directory) => {
    if (!fs.existsSync(directory)) {
      return;
    }
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const full = path.join(directory, entry.name);
      if (entry.isDirectory()) {
        walk(full);
      } else {
        files.push({
          path: path.relative(root, full).replace(/\\/g, "/"),
          content: fs.readFileSync(full, "utf8")
        });
      }
    }
  };
  directories.forEach((directory) => walk(path.join(root, directory)));
  return files;
}

/** Files of the package directories as committed at a Git ref, read in one cat-file batch. */
function gitFiles(root, ref, directories) {
  const listing = git(["ls-tree", "-r", "-z", ref, "--", ...directories], {
    cwd: root
  });
  const blobs = listing
    .split("\0")
    .filter(Boolean)
    .map((line) => {
      const [meta, filePath] = line.split("\t");
      const [, type, sha] = meta.split(" ");
      return { type, sha, path: filePath };
    })
    .filter((item) => item.type === "blob");
  if (blobs.length === 0) {
    return [];
  }
  const output = git(["cat-file", "--batch"], {
    cwd: root,
    input: blobs.map((blob) => blob.sha).join("\n") + "\n",
    binary: true
  });
  const files = [];
  let offset = 0;
  for (const blob of blobs) {
    const headerEnd = output.indexOf(0x0a, offset);
    const size = Number(
      output.toString("utf8", offset, headerEnd).split(" ")[2]
    );
    const start = headerEnd + 1;
    files.push({
      path: blob.path,
      content: output.toString("utf8", start, start + size)
    });
    offset = start + size + 1;
  }
  return files;
}

/** Latest deployment tag of an org (tag names sort chronologically), or null. */
function latestDeployTag(root, targetOrg) {
  const tags = git(
    ["tag", "--list", `${TAG_PREFIX}/${targetOrg}/*`, "--sort=-refname"],
    { cwd: root }
  )
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
  return tags[0] || null;
}

function timestamp(date = new Date()) {
  return date.toISOString().replace(/[-:]/g, "").replace("T", "-").slice(0, 15);
}

function createDeployTag(root, targetOrg, message) {
  const tag = `${TAG_PREFIX}/${targetOrg}/${timestamp()}`;
  git(["tag", "--annotate", tag, "--message", message], { cwd: root });
  return tag;
}

function headCommit(root) {
  return git(["rev-parse", "--short", "HEAD"], { cwd: root }).trim();
}

/** Uncommitted changes in the package directories: a tag would then not describe what was deployed. */
function uncommittedChanges(root, directories) {
  return git(["status", "--porcelain", "--", ...directories], { cwd: root })
    .split("\n")
    .filter(Boolean);
}

/** Components of the org, read through the Tooling API (no retrieve, no temporary files). */
function orgComponents(targetOrg) {
  const files = [];
  const owners = new Map();
  const remember = (key, record) => {
    owners.set(key, {
      lastModifiedBy: record.LastModifiedBy?.Name || null,
      lastModifiedDate: record.LastModifiedDate || null
    });
  };

  const classes = toolingQuery(
    "SELECT Name, Body, LastModifiedDate, LastModifiedBy.Name FROM ApexClass WHERE NamespacePrefix = null",
    targetOrg
  );
  classes.forEach((record) => {
    files.push({ path: `classes/${record.Name}.cls`, content: record.Body });
    remember(`ApexClass:${record.Name}`, record);
  });

  const triggers = toolingQuery(
    "SELECT Name, Body, LastModifiedDate, LastModifiedBy.Name FROM ApexTrigger WHERE NamespacePrefix = null",
    targetOrg
  );
  triggers.forEach((record) => {
    files.push({
      path: `triggers/${record.Name}.trigger`,
      content: record.Body
    });
    remember(`ApexTrigger:${record.Name}`, record);
  });

  const bundles = toolingQuery(
    "SELECT DeveloperName, LastModifiedDate, LastModifiedBy.Name FROM LightningComponentBundle WHERE NamespacePrefix = null",
    targetOrg
  );
  bundles.forEach((record) =>
    remember(`LightningComponentBundle:${record.DeveloperName}`, record)
  );
  const resources = toolingQuery(
    "SELECT FilePath, Source FROM LightningComponentResource WHERE LightningComponentBundle.NamespacePrefix = null",
    targetOrg
  );
  resources.forEach((record) =>
    files.push({ path: record.FilePath, content: record.Source })
  );

  const components = buildComponents(files);
  for (const [key, component] of components) {
    Object.assign(component, owners.get(key));
  }
  return components;
}

module.exports = {
  repoRoot,
  packageDirectories,
  localFiles,
  gitFiles,
  latestDeployTag,
  createDeployTag,
  headCommit,
  uncommittedChanges,
  orgComponents,
  timestamp
};
