#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const projectRoot = path.resolve(__dirname, "..");
const releaseFiles = [
  "bank_server.lua",
  "pumpe.lua",
  "service_kiosk.lua",
  "event_kiosk.lua",
  "tax_controller.lua",
  "startup.lua",
  "launcher.lua",
  "config.lua",
  "lib/net.lua",
  "lib/ui.lua",
  "lib/update.lua",
  "lib/util.lua",
];

function checksum(buffer) {
  let hash = 5381;
  for (const byte of buffer) hash = (hash * 33 + byte) >>> 0;
  return hash.toString(16).padStart(8, "0");
}

const configSource = fs.readFileSync(
  path.join(projectRoot, "config.lua"),
  "utf8",
);
const versionMatch = configSource.match(/\bversion\s*=\s*"(\d+\.\d+\.\d+)"/);
if (!versionMatch) throw new Error("Could not read version from config.lua");

const manifest = {
  schema: 1,
  channel: "stable",
  version: versionMatch[1],
  notes: "PUMPE automatic internet release",
  files: releaseFiles.map((relativePath) => {
    const body = fs.readFileSync(path.join(projectRoot, relativePath));
    return {
      path: relativePath,
      source: relativePath,
      size: body.length,
      checksum: checksum(body),
    };
  }),
};

fs.writeFileSync(
  path.join(projectRoot, "release_manifest.json"),
  `${JSON.stringify(manifest, null, 2)}\n`,
);
console.log(`Built release_manifest.json for PUMPE v${manifest.version}`);
