#!/usr/bin/env node
"use strict";
/**
 * Seeds the synthetic data of one demo through its DemoDataSeeder.
 *
 * Usage: node scripts/seed.js --target-org <alias> --demo <DeveloperName> --volume <n>
 */
const { runAnonymousApex } = require("./lib/sf");
const { buildSeedApex, parseApexRun, parseArgs } = require("./lib/report");

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args["target-org"] || !args.demo || !args.volume) {
    throw new Error(
      "Usage: node scripts/seed.js --target-org <alias> --demo <name> --volume <n>"
    );
  }
  const outcome = parseApexRun(
    runAnonymousApex(
      buildSeedApex(args.demo, Number(args.volume)),
      args["target-org"]
    )
  );
  if (!outcome.success) {
    throw new Error(outcome.message);
  }
  console.log(`Seeded ${args.volume} records for ${args.demo}`);
}

try {
  main();
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
