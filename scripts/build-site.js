#!/usr/bin/env node
"use strict";
/**
 * Builds the GitHub Pages showcase from a CI proof artifact. Every number comes from the measured files.
 *   node scripts/build-site.js --proof <artifact dir> --out <site dir> [--history <history.json>] [--video <mp4>]
 * The proof directory holds scripts/out/ (metrics.json, bulk.json, drift.json) and docs/screenshots/.
 */
const fs = require("node:fs");
const path = require("node:path");
const { parseArgs } = require("node:util");
const {
  CATALOG,
  headline,
  cardSvg,
  appendHistory,
  durationsOf,
  escapeXml: escape,
  seconds
} = require("./lib/site-data");

const REPO_URL = "https://github.com/DavF27/sf-portfolio";
const TRAILBLAZER_URL = "https://www.salesforce.com/trailblazer/davfrancisco";
const ROOT = path.resolve(__dirname, "..");

const CAPTIONS = {
  "panel.png": "Demo panel",
  "before.png": "BEFORE",
  "after.png": "AFTER",
  "chaos.png": "AFTER with an injected failure (Chaos)",
  "race.png": "Race: AFTER finished, BEFORE still running",
  "race-finished.png": "Race finished"
};

function readJson(file, fallback) {
  return fs.existsSync(file)
    ? JSON.parse(fs.readFileSync(file, "utf8"))
    : fallback;
}

function readProvenance(proof) {
  const file = path.join(proof, "docs", "screenshots", "PROVENANCE.txt");
  const provenance = {};
  if (fs.existsSync(file)) {
    for (const line of fs.readFileSync(file, "utf8").split("\n")) {
      const [key, ...rest] = line.split("=");
      if (key && rest.length) {
        provenance[key.trim()] = rest.join("=").trim();
      }
    }
  }
  return provenance;
}

function layout(title, body, depth = 0) {
  const up = "../".repeat(depth);
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escape(title)}</title>
<link rel="stylesheet" href="${up}assets/style.css">
</head>
<body>
<header class="top"><a href="${up}index.html">Executable Salesforce portfolio</a>
<nav><a href="${up}index.html#demos">Demos</a><a href="${up}history.html">History</a><a href="${REPO_URL}">Source</a><a href="${TRAILBLAZER_URL}">Trailblazer profile</a></nav></header>
<main>
${body}
</main>
<footer>Every screenshot, video and number on this site is produced by the CI on a fresh scratch org. Nothing is edited by hand.</footer>
<script type="module">
import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs";
mermaid.initialize({ startOnLoad: true, theme: "neutral" });
</script>
</body>
</html>
`;
}

async function renderMarkdown(file) {
  const { marked } = await import("marked");
  const renderer = new marked.Renderer();
  const defaultCode = renderer.code.bind(renderer);
  renderer.code = function code(token) {
    if (token.lang === "mermaid") {
      return `<pre class="mermaid">${escape(token.text)}</pre>\n`;
    }
    return defaultCode(token);
  };
  return marked.parse(fs.readFileSync(path.join(ROOT, file), "utf8"), {
    renderer
  });
}

function metricsTable(runs) {
  if (runs.length === 0) {
    return "";
  }
  const rows = runs
    .map(
      (run) => `<tr class="${run.Status__c === "Succeeded" ? "ok" : "ko"}">
<td>${escape(run.Mode__c)}${run.Chaos__c ? " + Chaos" : ""}</td><td>${run.Volume__c}</td><td>${escape(run.Status__c)}</td>
<td>${run.SOQL_Queries__c} / ${run.SOQL_Limit__c}</td><td>${run.DML_Statements__c} / ${run.DML_Limit__c}</td>
<td>${run.CPU_Time_Ms__c ?? ""}</td><td>${seconds(run.Duration_Ms__c)}</td><td>${run.Records_Processed__c ?? ""}</td>
<td>${run.Records_Failed__c ?? ""}</td><td>${run.Async_Executions__c ?? ""}</td><td class="error">${escape(run.Error_Message__c || "")}</td></tr>`
    )
    .join("\n");
  return `<h2>Measured runs</h2>
<div class="scroll"><table><thead><tr><th>Mode</th><th>Volume</th><th>Status</th><th>SOQL</th><th>DML</th><th>CPU (ms)</th>
<th>Duration</th><th>Processed</th><th>Failed</th><th>Async executions</th><th>Error</th></tr></thead><tbody>
${rows}
</tbody></table></div>`;
}

function bulkTable(jobs) {
  if (!jobs || jobs.length === 0) {
    return "";
  }
  const rows = jobs
    .map(
      (
        job
      ) => `<tr class="${job.failed === 0 ? "ok" : "ko"}"><td>${escape(job.mode)}${job.chaos ? " + Chaos" : ""}</td>
<td>${job.rows}</td><td>${job.succeeded}</td><td>${job.failed}</td><td class="error">${escape(job.firstError || "")}</td></tr>`
    )
    .join("\n");
  return `<h2>Real Bulk API 2.0 jobs</h2>
<div class="scroll"><table><thead><tr><th>Mode</th><th>Rows</th><th>Succeeded</th><th>Failed</th><th>First error</th></tr></thead><tbody>
${rows}
</tbody></table></div>`;
}

function driftTable(drift) {
  if (!drift || !drift.rows) {
    return "";
  }
  const notable = drift.rows.filter(
    (row) => row.freshness !== "fresh" || row.drift
  );
  const s = drift.summary;
  const rows = notable
    .map(
      (
        row
      ) => `<tr class="${row.drift === "UNKNOWN" ? "ko" : ""}"><td>${escape(row.component)}</td><td>${row.freshness}</td>
<td>${row.drift || ""}</td><td>${escape(row.lastModifiedDate || "")}</td><td>${escape(row.lastModifiedBy || "")}</td></tr>`
    )
    .join("\n");
  return `<h2>Drift report of the CI scratch org</h2>
<p>Baseline <code>${escape(drift.baselineTag || "none")}</code>: ${s.components} components, ${s.fresh} fresh,
${s.known} KNOWN, ${s.intentional} INTENTIONAL, <strong>${s.unknown} UNKNOWN</strong>.</p>
<div class="scroll"><table><thead><tr><th>Component</th><th>Freshness</th><th>Drift</th><th>Last modified in the org</th><th>By</th></tr></thead><tbody>
${rows}
</tbody></table></div>`;
}

function copyMedia(proof, slug, out) {
  const source = path.join(proof, "docs", "screenshots", slug);
  if (!fs.existsSync(source)) {
    return [];
  }
  const target = path.join(out, "screenshots", slug);
  fs.mkdirSync(target, { recursive: true });
  const files = fs
    .readdirSync(source)
    .filter((name) => /\.(png|gif)$/.test(name));
  files.forEach((name) =>
    fs.copyFileSync(path.join(source, name), path.join(target, name))
  );
  const order = Object.keys(CAPTIONS);
  return files.sort((a, b) => {
    const rank = (name) =>
      name.endsWith(".gif") ? -1 : order.indexOf(name) + 1 || 99;
    return rank(a) - rank(b);
  });
}

function mediaHtml(slug, files) {
  const gif = files.find((name) => name.endsWith(".gif"));
  const images = files.filter((name) => name.endsWith(".png"));
  const parts = [];
  if (gif) {
    parts.push(
      `<figure class="wide"><img src="../screenshots/${slug}/${gif}" alt="Recording of the demo run by the CI" loading="lazy"><figcaption>Recorded by Playwright in the CI</figcaption></figure>`
    );
  }
  if (images.length) {
    parts.push(
      `<div class="gallery">${images
        .map(
          (name) =>
            `<figure><a href="../screenshots/${slug}/${name}"><img src="../screenshots/${slug}/${name}" alt="${escape(CAPTIONS[name] || name)}" loading="lazy"></a><figcaption>${escape(CAPTIONS[name] || name)}</figcaption></figure>`
        )
        .join("")}</div>`
    );
  }
  return parts.join("\n");
}

/** Minimal SVG line chart of BEFORE/AFTER durations over the history (oldest left). */
function trendSvg(history, demo) {
  const points = [...history]
    .reverse()
    .map((entry) => ({
      before: entry.durations?.[`${demo}:BEFORE`],
      after: entry.durations?.[`${demo}:AFTER`]
    }))
    .filter(
      (point) => Number.isFinite(point.before) || Number.isFinite(point.after)
    );
  if (points.length < 2) {
    return '<p class="muted">The trend appears after two CI runs.</p>';
  }
  const width = 600;
  const height = 140;
  const max = Math.max(
    1,
    ...points.flatMap((point) =>
      [point.before, point.after].filter(Number.isFinite)
    )
  );
  const x = (index) => 30 + (index * (width - 40)) / (points.length - 1);
  const y = (value) => height - 20 - (value / max) * (height - 40);
  const line = (key, color) => {
    const coords = points
      .map((point, index) =>
        Number.isFinite(point[key])
          ? `${x(index).toFixed(1)},${y(point[key]).toFixed(1)}`
          : null
      )
      .filter(Boolean)
      .join(" ");
    return `<polyline fill="none" stroke="${color}" stroke-width="2" points="${coords}"/>`;
  };
  return `<svg viewBox="0 0 ${width} ${height}" role="img" aria-label="Duration trend of ${escape(demo)}" class="trend">
<line x1="30" y1="${height - 20}" x2="${width - 10}" y2="${height - 20}" stroke="#c9c9c9"/>
<text x="30" y="14" font-size="11" fill="#444">max ${seconds(max)}</text>
${line("before", "#ba0517")}${line("after", "#2e844a")}
<text x="${width - 150}" y="14" font-size="11" fill="#ba0517">BEFORE</text><text x="${width - 90}" y="14" font-size="11" fill="#2e844a">AFTER</text>
</svg>`;
}

function cardHtml(item, data, depth) {
  const up = "../".repeat(depth);
  const image = data
    ? `<img src="${up}cards/${item.slug}.svg" alt="${escape(`${item.title}: before ${data.before.value}, after ${data.after.value}`)}">`
    : "";
  return image;
}

async function main() {
  const { values } = parseArgs({
    options: {
      proof: { type: "string" },
      out: { type: "string" },
      history: { type: "string" },
      video: { type: "string" }
    }
  });
  if (!values.proof || !values.out) {
    console.error(
      "Usage: node scripts/build-site.js --proof <dir> --out <dir> [--history <file>] [--video <mp4>]"
    );
    return 1;
  }
  const proof = path.resolve(values.proof);
  const out = path.resolve(values.out);
  fs.rmSync(out, { recursive: true, force: true });
  fs.mkdirSync(path.join(out, "demo"), { recursive: true });
  fs.mkdirSync(path.join(out, "cards"), { recursive: true });
  fs.mkdirSync(path.join(out, "assets"), { recursive: true });
  fs.copyFileSync(
    path.join(ROOT, "scripts", "site", "style.css"),
    path.join(out, "assets", "style.css")
  );

  const outDir = path.join(proof, "scripts", "out");
  const sources = {
    metrics: readJson(path.join(outDir, "metrics.json"), []),
    bulk: readJson(path.join(outDir, "bulk.json"), []),
    drift: readJson(path.join(outDir, "drift.json"), null)
  };
  const provenance = readProvenance(proof);
  const commit = (provenance.commit || "").slice(0, 7);
  const runUrl = provenance.run || REPO_URL;
  const runId = runUrl.split("/").pop();
  const stamp = `Measured by CI run ${runId} · commit ${commit} · ${provenance.date || ""}`;

  const history = appendHistory(
    values.history ? readJson(values.history, []) : [],
    {
      run: runId,
      runUrl,
      commit,
      date: provenance.date || null,
      headlines: Object.fromEntries(
        CATALOG.map((item) => [item.slug, headline(item, sources)])
      ),
      durations: durationsOf(sources.metrics)
    }
  );
  fs.writeFileSync(
    path.join(out, "history.json"),
    JSON.stringify(history, null, 2) + "\n"
  );

  const cards = [];
  for (const item of CATALOG) {
    const data = headline(item, sources);
    if (data) {
      fs.writeFileSync(
        path.join(out, "cards", `${item.slug}.svg`),
        cardSvg(item.title, data, stamp)
      );
    }
    const media = copyMedia(proof, item.slug, out);
    let tables = "";
    if (item.slug === "bulk-all-or-nothing") {
      tables = bulkTable(sources.bulk);
    } else if (item.slug === "drift-guard") {
      tables = driftTable(sources.drift);
    }
    if (item.demo) {
      tables += metricsTable(
        sources.metrics.filter((run) => run.Demo__c === item.demo)
      );
    }
    const writeUp = item.doc
      ? `<h2>Write-up <span class="muted">(in French)</span></h2><article class="doc">${await renderMarkdown(item.doc)}</article>`
      : "";
    const trend = item.demo
      ? `<h2>Duration over the CI runs</h2>${trendSvg(history, item.demo)}`
      : "";
    const body = `<h1>${escape(item.title)}</h1>
<p class="lead">${escape(item.problem)}</p>
<p>${escape(item.mechanism)}</p>
${cardHtml(item, data, 1)}
<p class="muted">${escape(stamp)} — <a href="${escape(runUrl)}">CI run</a></p>
${mediaHtml(item.slug, media)}
${tables}
${trend}
${writeUp}`;
    fs.writeFileSync(
      path.join(out, "demo", `${item.slug}.html`),
      layout(item.title, body, 1)
    );
    cards.push(
      `<a class="tile" href="demo/${item.slug}.html"><h3>${escape(item.title)}</h3><p>${escape(item.problem)}</p>${cardHtml(item, data, 0)}</a>`
    );
  }

  let video = "";
  if (values.video && fs.existsSync(values.video)) {
    fs.copyFileSync(values.video, path.join(out, "portfolio.mp4"));
    video = `<video controls preload="metadata" src="portfolio.mp4" class="wide">Your browser cannot play this video.</video>`;
  }

  const index = `<h1>Executable Salesforce portfolio</h1>
<p class="lead">Real platform failure modes, reproduced from scratch. Each demo has a BEFORE implementation that fails and an
AFTER implementation that works, both deployed side by side and switched from a Lightning panel.</p>
<p>On every push to main, the CI creates a scratch org, deploys, runs the Apex tests, runs each demo, records the panel with
Playwright and publishes the measurements below. <span class="muted">${escape(stamp)} — <a href="${escape(runUrl)}">CI run</a></span></p>
${video}
<h2 id="demos">Demos</h2>
<div class="tiles">${cards.join("\n")}</div>
<h2>How the proof works</h2>
<ul>
<li>BEFORE and AFTER coexist in the org; a custom metadata record and a strategy interface select the implementation.</li>
<li>Measurements (<code>Limits.*</code>, <code>AsyncApexJob</code>, Bulk API job results) travel through a platform event published immediately, so they survive the rollback of a failing transaction.</li>
<li>Apex tests assert the expected BEFORE failure and the AFTER success; the CI replays everything on a new scratch org.</li>
<li>Synthetic data only, generated by script. No customer code, data or names.</li>
</ul>
<h2>Author</h2>
<p>David Francisco — Salesforce developer. Certifications and Trailhead badges on the
<a href="${TRAILBLAZER_URL}">Trailblazer profile</a>.</p>`;
  fs.writeFileSync(
    path.join(out, "index.html"),
    layout("Executable Salesforce portfolio", index)
  );

  const historyRows = history
    .map(
      (entry) =>
        `<tr><td><a href="${escape(entry.runUrl)}">${escape(entry.run)}</a></td><td>${escape(entry.commit)}</td><td>${escape(entry.date || "")}</td>${CATALOG.map(
          (item) => {
            const data = entry.headlines?.[item.slug];
            return `<td>${data ? `${escape(data.before.value)} → ${escape(data.after.value)}` : ""}</td>`;
          }
        ).join("")}</tr>`
    )
    .join("\n");
  const historyBody = `<h1>History of the CI runs</h1>
<p>Each row is a CI run on a new scratch org: BEFORE → AFTER headline of every demo.</p>
<div class="scroll"><table><thead><tr><th>Run</th><th>Commit</th><th>Date</th>${CATALOG.map((item) => `<th>${escape(item.title)}</th>`).join("")}</tr></thead><tbody>
${historyRows}
</tbody></table></div>`;
  fs.writeFileSync(
    path.join(out, "history.html"),
    layout("History of the CI runs", historyBody)
  );
  fs.writeFileSync(path.join(out, ".nojekyll"), "");
  console.log(
    `Site built in ${out}: ${CATALOG.length} demo pages, ${history.length} run(s) in the history.`
  );
  return 0;
}

main().then(
  (code) => {
    process.exitCode = code;
  },
  (error) => {
    console.error(error);
    process.exitCode = 1;
  }
);
