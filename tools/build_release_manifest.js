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

// Keep both public one-file entry points identical. startup.lua starts
// automatically at the computer root; installer.lua is the manual filename.
fs.copyFileSync(
  path.join(projectRoot, "startup.lua"),
  path.join(projectRoot, "installer.lua"),
);

const borderSource = fs.readFileSync(
  path.join(projectRoot, "border_controller.lua"),
);
const borderChecksum = checksum(borderSource);
const bankPath = path.join(projectRoot, "bank_server.lua");
const originalBankSource = fs.readFileSync(bankPath, "utf8");
const updatedBankSource = originalBankSource.replace(
  /local BORDER_CONTROLLER_CHECKSUM = "[0-9a-f]{8}"/,
  `local BORDER_CONTROLLER_CHECKSUM = "${borderChecksum}"`,
);
if (updatedBankSource === originalBankSource &&
    !originalBankSource.includes(`BORDER_CONTROLLER_CHECKSUM = "${borderChecksum}"`)) {
  throw new Error("Could not update the Border Controller checksum");
}
fs.writeFileSync(bankPath, updatedBankSource);

const ccgSource = fs.readFileSync(
  path.join(projectRoot, "ccg.lua"),
);
const ccgChecksum = checksum(ccgSource);
const bankWithCcgChecksum = fs.readFileSync(bankPath, "utf8").replace(
  /local CCG_CHECKSUM = "[0-9a-f]{8}"/,
  `local CCG_CHECKSUM = "${ccgChecksum}"`,
);
if (bankWithCcgChecksum === fs.readFileSync(bankPath, "utf8") &&
    !bankWithCcgChecksum.includes(`CCG_CHECKSUM = "${ccgChecksum}"`)) {
  throw new Error("Could not update the CCG checksum");
}
fs.writeFileSync(bankPath, bankWithCcgChecksum);

const manifest = {
  schema: 1,
  channel: "stable",
  version: versionMatch[1],
  notes: "PUMPE + ComputerCraftGaming automatic internet release",
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

const fileSize = (relativePath) =>
  fs.statSync(path.join(projectRoot, relativePath)).size;
const bankRuntimeFiles = [
  "bank_server.lua",
  "startup.lua",
  "config.lua",
  "lib/net.lua",
  "lib/ui.lua",
  "lib/update.lua",
  "lib/util.lua",
];
const depotOnlyFiles = [
  "pumpe.lua",
  "service_kiosk.lua",
  "event_kiosk.lua",
  "tax_controller.lua",
  "border_controller.lua",
  "ccg.lua",
];
const uniqueReleaseBytes = [...bankRuntimeFiles, ...depotOnlyFiles]
  .reduce((total, relativePath) => total + fileSize(relativePath), 0);
const compactBankBytes = uniqueReleaseBytes + fileSize("config.lua") * 2;
const legacyBankBytes = uniqueReleaseBytes * 2 + fileSize("startup.lua") * 2;
if (compactBankBytes > 500 * 1024) {
  throw new Error(`Compact Bank footprint exceeded 500 KiB: ${compactBankBytes}`);
}
console.log(`Built release_manifest.json for PUMPE v${manifest.version}`);
console.log(
  `Bank footprint guard: ${Math.ceil(legacyBankBytes / 1024)} KiB legacy -> `
    + `${Math.ceil(compactBankBytes / 1024)} KiB compact`,
);
