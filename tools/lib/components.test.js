"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { classifyPath, normalize, buildComponents } = require("./components");

test("maps code files to their component", () => {
  assert.deepEqual(
    classifyPath("force-app/core/main/default/classes/Foo.cls"),
    {
      key: "ApexClass:Foo",
      type: "ApexClass",
      name: "Foo",
      entry: ""
    }
  );
  assert.equal(
    classifyPath("force-app\\x\\triggers\\T.trigger").key,
    "ApexTrigger:T"
  );
  assert.deepEqual(classifyPath("lwc/panel/panel.js-meta.xml"), {
    key: "LightningComponentBundle:panel",
    type: "LightningComponentBundle",
    name: "panel",
    entry: "panel.js-meta.xml"
  });
});

test("ignores XML metadata, Jest tests and LWC configuration", () => {
  for (const file of [
    "force-app/core/main/default/classes/Foo.cls-meta.xml",
    "force-app/core/main/default/objects/A__c/A__c.object-meta.xml",
    "force-app/core/main/default/lwc/panel/__tests__/panel.test.js",
    "force-app/core/main/default/lwc/panel/__mocks__/data.json",
    "force-app/core/main/default/lwc/jsconfig.json",
    "force-app/core/main/default/lwc/.eslintrc.json"
  ]) {
    assert.equal(classifyPath(file), null, file);
  }
});

test("normalizes line endings, BOM and trailing whitespace", () => {
  assert.equal(normalize("\uFEFFa\r\nb\rc\n\n"), "a\nb\nc");
});

test("hashes a component the same way whatever the platform or file order", () => {
  const windows = buildComponents([
    { path: "x/lwc/p/p.html", content: "<template></template>\r\n" },
    { path: "x/lwc/p/p.js", content: "export default 1;\r\n" }
  ]);
  const org = buildComponents([
    { path: "lwc/p/p.js", content: "export default 1;" },
    { path: "lwc/p/p.html", content: "<template></template>" }
  ]);
  assert.equal(
    windows.get("LightningComponentBundle:p").hash,
    org.get("LightningComponentBundle:p").hash
  );
  assert.equal(windows.get("LightningComponentBundle:p").files, 2);
});

test("a change in any file of a bundle changes its hash", () => {
  const before = buildComponents([
    { path: "lwc/p/p.js", content: "a" },
    { path: "lwc/p/p.css", content: "b" }
  ]);
  const after = buildComponents([
    { path: "lwc/p/p.js", content: "a" },
    { path: "lwc/p/p.css", content: "c" }
  ]);
  assert.notEqual(
    before.get("LightningComponentBundle:p").hash,
    after.get("LightningComponentBundle:p").hash
  );
});
