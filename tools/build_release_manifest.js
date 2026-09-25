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
// Frozen. Bank Servers published before 7.0.1 reject any entry here they do
// not already know, so nothing new may ever be added to this array.
const extraReleaseFiles = [
  "border_controller.lua",
  "ccg.lua",
];
// Everything added since. Older updaters never read this array at all, and
// 7.0.1 onwards ignores entries it does not recognise, so new roles can be
// published here safely.
const forwardOptionalFiles = [
  "gps_anchor.lua",
  "admin_terminal.lua",
  "app_server.lua",
  // foxy.lua is a PUMPE app rather than a role. It ships here so an App
  // Server can seed itself with Foxy on its first run instead of waiting for
  // somebody to publish it by hand.
  "foxy.lua",
  // A 3rd Party Bank Server: the machine that hosts a bank which is not
  // Foxy. New in 9.0.
  "bank_app_server.lua",
  // BuckApp is a PUMPE app rather than a role, and ships for the same reason
  // foxy.lua does: so an App Server has it to offer on a fresh world.
  "buckapp.lua",
  // ComputerCraftGaming, on its own computer since 9.1.
  "ccg_server.lua",
  // Revolution, the first third-party bank with terms of its own.
  "revolution.lua",
  // The other half of a Bank. New in 9.3: the Core runs bank_server.lua and
  // the Vault runs this, which is what took the Bank back under the size a
  // ComputerCraft computer can update itself through.
  "bank_vault.lua",
  // The web, new in 10.0. The server that holds everybody's pages, and the
  // two apps that write and read them.
  "internet_server.lua",
  "wc.lua",
  "internet.lua",
  // The Shop, new in 10.2: the terminal that delivers the orders, and the
  // app that places them.
  "delivery_terminal.lua",
  "shop.lua",
  // FoxMail, 11.0: installed on every PUMPE, shipped by the App Server.
  "foxmail.lua",
  // The Company app, 11.1: in the App Browser, shipped by the App Server.
  "company.lua",
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

// What the release is called, and what it changed. Both are read out of the
// repository rather than kept in this script: the label is config.lua's
// release_name, and the change list is the headlines of the top section of
// CHANGELOG.md. A version number orders releases; it does not name them, and
// "10.0 Pre" is not a number.
const labelMatch = configSource.match(/\brelease_name\s*=\s*"([^"]*)"/);
const releaseLabel = labelMatch ? labelMatch[1] : versionMatch[1];

// The headlines are the bold lead-ins of the section, in order. Deriving them
// from the changelog rather than from a list kept beside it is the only way
// the two cannot disagree, and a phone showing the previous release's notes
// would be worse than showing none.
function readChanges(version) {
  const body = fs.readFileSync(path.join(projectRoot, "CHANGELOG.md"), "utf8");
  const section = body.split(/^## /m)[1] || "";
  const heading = section.split("\n", 1)[0].trim();
  if (heading !== version) {
    console.warn(
      `WARNING: CHANGELOG.md starts at ${heading}, not ${version}. `
        + "Publishing no change list.",
    );
    return [];
  }
  const changes = [];
  for (const line of section.split("\n")) {
    const headline = line.match(/^(?:[-*] )?\*\*(.+?)\*\*/);
    if (headline) changes.push(headline[1].replace(/\s+/g, " ").trim());
    if (changes.length >= 16) break;
  }
  return changes;
}
const releaseChanges = readChanges(versionMatch[1]);

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

// Stamp each program with the release it belongs to, so a device can tell at
// startup that it is running a program from a different release than its
// config.lua - a partial install that used to go unnoticed.
//
// Derived from what is actually published rather than a list kept by hand.
// The hand-kept version missed every program added after 9.0, so a 3rd Party
// Bank Server shipped for three releases still calling itself 9.0.0.
const publishedPrograms = [
  ...releaseFiles, ...extraReleaseFiles, ...forwardOptionalFiles,
].filter((relativePath) => relativePath.endsWith(".lua")
  && !relativePath.startsWith("lib/"));
let stampedCount = 0;
for (const program of publishedPrograms) {
  const file = path.join(projectRoot, program);
  const source = fs.readFileSync(file, "utf8");
  if (!/local PROGRAM_VERSION = "\d+\.\d+\.\d+"/.test(source)) continue;
  const stamped = source.replace(
    /local PROGRAM_VERSION = "\d+\.\d+\.\d+"/,
    `local PROGRAM_VERSION = "${versionMatch[1]}"`,
  );
  if (!stamped.includes(`PROGRAM_VERSION = "${versionMatch[1]}"`)) {
    throw new Error(`Could not stamp PROGRAM_VERSION into ${program}`);
  }
  if (stamped !== source) fs.writeFileSync(file, stamped);
  stampedCount += 1;
}

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
  label: releaseLabel,
  notes: "PUMPE + ComputerCraftGaming automatic internet release",
  changes: releaseChanges,
  files: releaseFiles.map(describe),
  extra_files: extraReleaseFiles.map(describe),
  optional_files: forwardOptionalFiles.map(describe),
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
  ...forwardOptionalFiles,
];
const uniqueReleaseBytes = [...bankRuntimeFiles, ...depotOnlyFiles]
  .reduce((total, relativePath) => total + fileSize(relativePath), 0);
const compactBankBytes = uniqueReleaseBytes + fileSize("config.lua") * 2;
const legacyBankBytes = uniqueReleaseBytes * 2 + fileSize("startup.lua") * 2;
// Since v6.3.0 every role updates itself and downloads only its own files,
// and the Bank's /updates is a cache it drops when it needs the room. The
// peak that matters is therefore the largest single role: its installed files
// plus a staged copy of the same set, inside a 1000 KiB computer.
const COMPUTER_LIMIT = 1000 * 1024;
const DATABASE_HEADROOM = 150 * 1024;
const sharedFiles = ["config.lua", "startup.lua", "lib/net.lua", "lib/ui.lua",
  "lib/update.lua", "lib/util.lua"];
const sharedBytes = sharedFiles.reduce((t, p) => t + fileSize(p), 0);
let worstRole = "", worstPeak = 0;
for (const program of ["bank_server.lua", ...depotOnlyFiles]) {
  const peak = (sharedBytes + fileSize(program)) * 2;
  if (peak > worstPeak) { worstPeak = peak; worstRole = program; }
}
if (worstPeak + DATABASE_HEADROOM > COMPUTER_LIMIT) {
  throw new Error(
    `Updating ${worstRole} would peak at ${Math.ceil(worstPeak / 1024)} KiB, `
      + `leaving under ${Math.ceil(DATABASE_HEADROOM / 1024)} KiB for data `
      + `inside ComputerCraft's ${COMPUTER_LIMIT / 1024} KiB computer`,
  );
}

console.log(
  `Built release_manifest.json for PUMPE v${manifest.version} (${releaseLabel}), `
    + `${releaseChanges.length} change headlines`,
);
console.log(
  `Published ${manifest.files.length} required, `
    + `${manifest.extra_files.length} legacy-optional and `
    + `${manifest.optional_files.length} forward-optional files`,
);
console.log(`Stamped ${stampedCount} programs with v${versionMatch[1]}`);
console.log(
  `Bank footprint: ${Math.ceil(legacyBankBytes / 1024)} KiB legacy -> `
    + `${Math.ceil(compactBankBytes / 1024)} KiB compact`,
);
console.log(
  `Worst self-update (${worstRole}): ${Math.ceil(worstPeak / 1024)} KiB of `
    + `${COMPUTER_LIMIT / 1024} KiB, leaving `
    + `${Math.floor((COMPUTER_LIMIT - worstPeak) / 1024)} KiB for data`,
);
