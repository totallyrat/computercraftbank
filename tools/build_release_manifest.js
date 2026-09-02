#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const projectRoot = path.resolve(__dirname, "..");

// `files` stays byte-for-byte compatible with the v5.2.1 updater, which
// rejects any manifest entry it does not already know about. Everything added
// since then goes in `extra_files`, which older updaters ignore and current
// Bank Servers download in the same verified, atomic commit.
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
const extraReleaseFiles = [
  "border_controller.lua",
  "ccg.lua",
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

// Easy Deployment reports its own version, and it only replaces itself when
// the downloaded file says it is newer. Keeping that in step with config.lua
// here removes the one manual step that could strand an installer.
const startupPath = path.join(projectRoot, "startup.lua");
const startupSource = fs.readFileSync(startupPath, "utf8");
const stampedStartup = startupSource.replace(
  /local INSTALLER_VERSION = "\d+\.\d+\.\d+"/,
  `local INSTALLER_VERSION = "${versionMatch[1]}"`,
);
if (!stampedStartup.includes(`INSTALLER_VERSION = "${versionMatch[1]}"`)) {
  throw new Error("Could not stamp INSTALLER_VERSION into startup.lua");
}
if (stampedStartup !== startupSource) fs.writeFileSync(startupPath, stampedStartup);

// Keep both public one-file entry points identical. startup.lua starts
// automatically at the computer root; installer.lua is the manual filename.
fs.copyFileSync(startupPath, path.join(projectRoot, "installer.lua"));

const describe = (relativePath) => {
  const body = fs.readFileSync(path.join(projectRoot, relativePath));
  return {
    path: relativePath,
    source: relativePath,
    size: body.length,
    checksum: checksum(body),
  };
};

const manifest = {
  schema: 1,
  channel: "stable",
  version: versionMatch[1],
  notes: "PUMPE + ComputerCraftGaming automatic internet release",
  files: releaseFiles.map(describe),
  extra_files: extraReleaseFiles.map(describe),
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
  ...extraReleaseFiles,
];
const uniqueReleaseBytes = [...bankRuntimeFiles, ...depotOnlyFiles]
  .reduce((total, relativePath) => total + fileSize(relativePath), 0);
const compactBankBytes = uniqueReleaseBytes + fileSize("config.lua") * 2;
const legacyBankBytes = uniqueReleaseBytes * 2 + fileSize("startup.lua") * 2;
// A tripwire against the v6.0 regression that kept a second copy of the whole
// release in /updates, not the real ceiling: ComputerCraft allows 1000 KiB per
// computer by default, and account data has to fit alongside this.
const FOOTPRINT_GUARD_KIB = 640;
if (compactBankBytes > FOOTPRINT_GUARD_KIB * 1024) {
  throw new Error(
    `Compact Bank footprint exceeded ${FOOTPRINT_GUARD_KIB} KiB: `
      + `${compactBankBytes}`,
  );
}
console.log(`Built release_manifest.json for PUMPE v${manifest.version}`);
console.log(
  `Published ${manifest.files.length} required and `
    + `${manifest.extra_files.length} optional files`,
);
console.log(
  `Bank footprint guard: ${Math.ceil(legacyBankBytes / 1024)} KiB legacy -> `
    + `${Math.ceil(compactBankBytes / 1024)} KiB compact`,
);
