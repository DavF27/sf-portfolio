"use strict";
const crypto = require("node:crypto");

/**
 * Metadata covered by the tools: code only. The org returns Apex bodies and LWC sources exactly as
 * deployed, so a content hash is reliable; XML metadata (flows, objects) is rewritten by the org.
 */
const TYPES = Object.freeze({
  APEX_CLASS: "ApexClass",
  APEX_TRIGGER: "ApexTrigger",
  LWC: "LightningComponentBundle"
});

const PATTERNS = [
  { type: TYPES.APEX_CLASS, regex: /(?:^|\/)classes\/([^/]+)\.cls$/ },
  { type: TYPES.APEX_TRIGGER, regex: /(?:^|\/)triggers\/([^/]+)\.trigger$/ },
  { type: TYPES.LWC, regex: /(?:^|\/)lwc\/([^/.][^/]*)\/(.+)$/ }
];

/** Maps a file path to its component, or null when the file is not covered (tests, config, XML). */
function classifyPath(filePath) {
  const normalized = filePath.replace(/\\/g, "/");
  for (const { type, regex } of PATTERNS) {
    const match = normalized.match(regex);
    if (!match) {
      continue;
    }
    // Jest tests and mocks live inside LWC bundles but are never deployed.
    if (type === TYPES.LWC && /(^|\/)__[^/]*__(\/|$)/.test(match[2])) {
      return null;
    }
    return {
      key: `${type}:${match[1]}`,
      type,
      name: match[1],
      entry: type === TYPES.LWC ? match[2] : ""
    };
  }
  return null;
}

/** Line endings, BOM and trailing whitespace differ between Windows checkouts, Linux and the org. */
function normalize(content) {
  return String(content)
    .replace(/^\uFEFF/, "")
    .replace(/\r\n?/g, "\n")
    .trimEnd();
}

function hashEntries(entries) {
  const hash = crypto.createHash("sha256");
  [...entries]
    .sort((a, b) => a.entry.localeCompare(b.entry))
    .forEach(({ entry, content }) => {
      hash.update(`${entry}\n${normalize(content)}\0`);
    });
  return hash.digest("hex");
}

/**
 * Groups files ({ path, content }) into components and hashes each one.
 * Returns a Map: key -> { key, type, name, hash, files }.
 */
function buildComponents(files) {
  const grouped = new Map();
  for (const file of files) {
    const component = classifyPath(file.path);
    if (!component) {
      continue;
    }
    if (!grouped.has(component.key)) {
      grouped.set(component.key, { ...component, entries: [] });
    }
    grouped
      .get(component.key)
      .entries.push({ entry: component.entry, content: file.content });
  }
  const components = new Map();
  for (const [key, { type, name, entries }] of grouped) {
    components.set(key, {
      key,
      type,
      name,
      hash: hashEntries(entries),
      files: entries.length
    });
  }
  return components;
}

module.exports = { TYPES, classifyPath, normalize, buildComponents };
