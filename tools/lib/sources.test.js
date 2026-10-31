"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const sources = require("./sources");

function git(cwd, ...args) {
  const result = spawnSync(
    "git",
    ["-c", "user.name=test", "-c", "user.email=test@example.com", ...args],
    { cwd, encoding: "utf8" }
  );
  assert.equal(result.status, 0, result.stderr);
  return result.stdout;
}

function write(root, file, content) {
  fs.mkdirSync(path.dirname(path.join(root, file)), { recursive: true });
  fs.writeFileSync(path.join(root, file), content);
}

test("reads committed files at a tag and finds the latest deployment tag", (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "sf-tools-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  git(root, "init", "-q");
  write(
    root,
    "sfdx-project.json",
    JSON.stringify({ packageDirectories: [{ path: "app" }] })
  );
  write(root, "app/classes/A.cls", "class A { /* v1 */ }\n");
  write(root, "app/lwc/p/p.js", "export default 1;\n");
  write(root, "other/ignored.cls", "ignored");
  git(root, "add", ".");
  git(root, "commit", "-q", "-m", "v1");
  git(root, "tag", "-a", "deploy/ci/20261030-090000", "-m", "first");
  write(root, "app/classes/A.cls", "class A { /* v2 */ }\n");
  git(root, "commit", "-q", "-am", "v2");
  git(root, "tag", "-a", "deploy/ci/20261031-090000", "-m", "second");
  git(root, "tag", "-a", "deploy/other/20261231-000000", "-m", "other org");

  const directories = sources.packageDirectories(root);
  assert.deepEqual(directories, ["app"]);
  assert.equal(
    sources.latestDeployTag(root, "ci"),
    "deploy/ci/20261031-090000"
  );
  assert.equal(sources.latestDeployTag(root, "none"), null);

  const files = sources.gitFiles(
    root,
    "deploy/ci/20261030-090000",
    directories
  );
  assert.deepEqual(
    files.map((file) => [file.path, file.content]),
    [
      ["app/classes/A.cls", "class A { /* v1 */ }\n"],
      ["app/lwc/p/p.js", "export default 1;\n"]
    ]
  );

  assert.deepEqual(sources.uncommittedChanges(root, directories), []);
  write(root, "app/classes/A.cls", "class A { /* v3 */ }\n");
  assert.equal(sources.uncommittedChanges(root, directories).length, 1);
  assert.equal(
    sources
      .localFiles(root, directories)
      .find((f) => f.path === "app/classes/A.cls").content,
    "class A { /* v3 */ }\n"
  );
});

test("deployment tags sort chronologically", () => {
  assert.equal(
    sources.timestamp(new Date("2026-10-31T09:05:07.123Z")),
    "20261031-090507"
  );
});
