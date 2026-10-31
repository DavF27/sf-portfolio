#!/usr/bin/env node
"use strict";
/**
 * Cuts the 2-3 minute showcase video from the Playwright recordings of a CI proof artifact: a title card per demo
 * with its measured BEFORE/AFTER headline, then the recording sped up. Silent, ready for a voice-over.
 *   node scripts/build-video.js --proof <artifact dir> --out <file.mp4>
 * Needs ffmpeg with drawtext on the PATH (or FFMPEG=<path>) and a TrueType font (or VIDEO_FONT=<path>).
 */
const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { parseArgs } = require("node:util");
const { CATALOG, headline } = require("./lib/site-data");

const SIZE = "1280x720";
const FPS = 25;
const SPEED = 1.5;
const MAX_CLIP_SECONDS = 28;
const CARD_SECONDS = 5;
const FONTS = [
  process.env.VIDEO_FONT,
  "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
  "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
  "C:/Windows/Fonts/segoeuib.ttf",
  "C:/Windows/Fonts/arial.ttf"
];

/** ffmpeg from FFMPEG or the PATH; the title cards need the drawtext filter (libfreetype). */
function ffmpegPath() {
  const ffmpeg = process.env.FFMPEG || "ffmpeg";
  const filters = spawnSync(ffmpeg, ["-hide_banner", "-filters"], {
    encoding: "utf8"
  });
  if (filters.status !== 0) {
    throw new Error(`ffmpeg not found (${ffmpeg}): install it or set FFMPEG.`);
  }
  if (!/\sdrawtext\s/.test(filters.stdout)) {
    throw new Error(`${ffmpeg} has no drawtext filter (needs libfreetype).`);
  }
  return ffmpeg;
}

function run(ffmpeg, args, cwd) {
  const result = spawnSync(
    ffmpeg,
    ["-hide_banner", "-loglevel", "error", "-y", ...args],
    {
      cwd,
      encoding: "utf8"
    }
  );
  if (result.status !== 0) {
    throw new Error(`ffmpeg failed: ${result.stderr || result.error}`);
  }
}

/** Title card: lines of { text, size, color, y }. Text goes through files to avoid filter escaping. */
function card(ffmpeg, work, name, lines, background = "0x032d60") {
  const filters = lines.map((line, index) => {
    const file = `${name}-${index}.txt`;
    fs.writeFileSync(path.join(work, file), line.text);
    return (
      `drawtext=fontfile=font.ttf:textfile=${file}:expansion=none:fontsize=${line.size}:` +
      `fontcolor=${line.color}:x=(w-text_w)/2:y=${line.y}`
    );
  });
  run(
    ffmpeg,
    [
      "-f",
      "lavfi",
      "-i",
      `color=c=${background}:s=${SIZE}:r=${FPS}:d=${CARD_SECONDS}`,
      "-vf",
      filters.join(","),
      "-c:v",
      "libx264",
      "-pix_fmt",
      "yuv420p",
      `${name}.mp4`
    ],
    work
  );
  return `${name}.mp4`;
}

function clip(ffmpeg, work, name, source) {
  fs.copyFileSync(source, path.join(work, `${name}.webm`));
  const [width, height] = SIZE.split("x");
  run(
    ffmpeg,
    [
      "-i",
      `${name}.webm`,
      "-vf",
      `setpts=PTS/${SPEED},scale=${width}:${height}:force_original_aspect_ratio=decrease,` +
        `pad=${width}:${height}:(ow-iw)/2:(oh-ih)/2:color=white,fps=${FPS}`,
      "-an",
      "-t",
      String(MAX_CLIP_SECONDS),
      "-c:v",
      "libx264",
      "-pix_fmt",
      "yuv420p",
      `${name}.mp4`
    ],
    work
  );
  return `${name}.mp4`;
}

function readJson(file, fallback) {
  return fs.existsSync(file)
    ? JSON.parse(fs.readFileSync(file, "utf8"))
    : fallback;
}

function main() {
  const { values } = parseArgs({
    options: { proof: { type: "string" }, out: { type: "string" } }
  });
  if (!values.proof || !values.out) {
    console.error(
      "Usage: node scripts/build-video.js --proof <dir> --out <file.mp4>"
    );
    return 1;
  }
  const proof = path.resolve(values.proof);
  const font = FONTS.find((file) => file && fs.existsSync(file));
  if (!font) {
    console.error("No font found for the title cards: set VIDEO_FONT.");
    return 1;
  }
  const ffmpeg = ffmpegPath();
  const outDir = path.join(proof, "scripts", "out");
  const sources = {
    metrics: readJson(path.join(outDir, "metrics.json"), []),
    bulk: readJson(path.join(outDir, "bulk.json"), []),
    drift: readJson(path.join(outDir, "drift.json"), null)
  };
  const work = fs.mkdtempSync(path.join(os.tmpdir(), "sf-video-"));
  fs.copyFileSync(font, path.join(work, "font.ttf"));
  try {
    const segments = [
      card(ffmpeg, work, "intro", [
        {
          text: "Executable Salesforce portfolio",
          size: 56,
          color: "white",
          y: 230
        },
        {
          text: "Each demo: a BEFORE that fails, an AFTER that works",
          size: 32,
          color: "0xd8e6fe",
          y: 340
        },
        {
          text: "Recorded and measured by the CI on a fresh scratch org",
          size: 28,
          color: "0xd8e6fe",
          y: 400
        }
      ])
    ];
    CATALOG.forEach((item, index) => {
      const data = headline(item, sources);
      const lines = [{ text: item.title, size: 50, color: "white", y: 170 }];
      if (data) {
        lines.push(
          { text: data.label, size: 28, color: "0xd8e6fe", y: 260 },
          {
            text: `BEFORE: ${data.before.value}`,
            size: 40,
            color: "0xfe9a9a",
            y: 350
          },
          {
            text: `AFTER: ${data.after.value}`,
            size: 40,
            color: "0x91db8b",
            y: 420
          }
        );
      }
      segments.push(card(ffmpeg, work, `card${index}`, lines));
      const recording = path.join(
        proof,
        "docs",
        "screenshots",
        item.slug,
        `${item.slug}.webm`
      );
      if (fs.existsSync(recording)) {
        segments.push(clip(ffmpeg, work, `clip${index}`, recording));
      }
    });
    segments.push(
      card(ffmpeg, work, "outro", [
        {
          text: "Source, write-ups and every measured run",
          size: 40,
          color: "white",
          y: 280
        },
        {
          text: "github.com/DavF27/sf-portfolio",
          size: 36,
          color: "0xd8e6fe",
          y: 360
        }
      ])
    );
    fs.writeFileSync(
      path.join(work, "list.txt"),
      segments.map((segment) => `file '${segment}'`).join("\n") + "\n"
    );
    const target = path.resolve(values.out);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    run(
      ffmpeg,
      [
        "-f",
        "concat",
        "-safe",
        "0",
        "-i",
        "list.txt",
        "-c",
        "copy",
        "-movflags",
        "+faststart",
        target
      ],
      work
    );
    console.log(`Video written to ${target} (${segments.length} segments)`);
  } finally {
    fs.rmSync(work, { recursive: true, force: true });
  }
  return 0;
}

process.exitCode = main();
