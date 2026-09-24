-- Publishing guard: release_manifest.json must describe the files actually in
-- this repository, in the shape older Bank Servers still accept.

local function readFile(path)
    local handle = assert(io.open(path, "rb"), "missing " .. path)
    local body = handle:read("*a")
    handle:close()
    return body
end

local function checksum(body)
    local hash = 5381
    for index = 1, #body do
        hash = (hash * 33 + string.byte(body, index)) % 4294967296
    end
    return string.format("%08x", hash)
end

-- The manifest is machine generated, so a narrow reader is enough here and
-- keeps the test free of dependencies.
local function readEntries(section)
    local entries = {}
    for path, source, size, sum in section:gmatch(
        '"path":%s*"([^"]+)",%s*"source":%s*"([^"]+)",'
        .. '%s*"size":%s*(%d+),%s*"checksum":%s*"(%x+)"') do
        entries[#entries + 1] = {
            path = path, source = source,
            size = tonumber(size), checksum = sum,
        }
    end
    return entries
end

local manifest = readFile("../release_manifest.json")
assert(manifest:find('"schema": 1', 1, true), "manifest schema must stay 1")
assert(manifest:find('"channel": "stable"', 1, true), "stable channel expected")

local version = manifest:match('"version":%s*"([%d%.]+)"')
local configVersion = readFile("../config.lua"):match('version%s*=%s*"([%d%.]+)"')
assert(version == configVersion,
    "manifest v" .. tostring(version) .. " does not match config v"
        .. tostring(configVersion) .. "; rerun the release builder")

local filesSection = manifest:match('"files":%s*%[(.-)%]')
local extraSection = manifest:match('"extra_files":%s*%[(.-)%]')
assert(filesSection and extraSection, "both file arrays must be published")

-- Keep `files` byte-compatible with the v5.2.1 updater, which rejects any
-- entry it does not know. New roles belong in `extra_files`.
local expectedFiles = {
    "bank_server.lua", "pumpe.lua", "service_kiosk.lua", "event_kiosk.lua",
    "tax_controller.lua", "startup.lua", "launcher.lua", "config.lua",
    "lib/net.lua", "lib/ui.lua", "lib/update.lua", "lib/util.lua",
}
-- Frozen: Bank Servers older than 7.0.1 reject any entry here they do not
-- already know, so nothing new may ever join this array.
local expectedExtra = { "border_controller.lua", "ccg.lua" }
-- Everything added since. Older updaters never read this array at all.
local expectedForward = { "gps_anchor.lua", "admin_terminal.lua",
    "app_server.lua", "foxy.lua", "bank_app_server.lua", "buckapp.lua",
    "ccg_server.lua", "revolution.lua", "bank_vault.lua",
    -- The web, new in 10.0: the server that holds everybody's pages, and
    -- the two apps that write and read them.
    "internet_server.lua", "wc.lua", "internet.lua",
    -- The Shop, new in 10.2: the terminal that delivers orders, and the
    -- app that places them.
    "delivery_terminal.lua", "shop.lua",
    -- FoxMail, 11.0.
    "foxmail.lua" }

local function verify(section, expected, label)
    local entries = readEntries(section)
    assert(#entries == #expected,
        label .. " lists " .. #entries .. " files, expected " .. #expected)
    for index, entry in ipairs(entries) do
        assert(entry.path == expected[index],
            label .. " entry " .. index .. " is " .. entry.path)
        assert(entry.source == entry.path,
            entry.path .. " must be served from its own path")
        local body = readFile("../" .. entry.path)
        assert(entry.size == #body,
            entry.path .. " size is stale; rerun the release builder")
        assert(entry.checksum == checksum(body),
            entry.path .. " checksum is stale; rerun the release builder")
    end
end

verify(filesSection, expectedFiles, "files")
verify(extraSection, expectedExtra, "extra_files")
local forwardSection = manifest:match('"optional_files":%s*%[(.-)%]')
assert(forwardSection, "forward-optional files must be published")
verify(forwardSection, expectedForward, "optional_files")

-- Both public entry points must stay identical, because Easy Deployment
-- installs startup.lua as /pumpe/installer.lua.
local startup = readFile("../startup.lua")
assert(startup == readFile("../installer.lua"),
    "installer.lua and startup.lua have drifted apart")

-- Easy Deployment replaces itself only when the downloaded file reports a
-- newer version. A stale stamp here would make it reinstall the same file and
-- reboot forever, so it has to track config.lua exactly.
local installerVersion = startup:match('INSTALLER_VERSION = "([%d%.]+)"')
assert(installerVersion == configVersion,
    "startup.lua reports v" .. tostring(installerVersion) .. " but config is v"
        .. tostring(configVersion) .. "; rerun the release builder")

-- Easy Deployment's Bank repair must cover every shared runtime file, not a
-- subset. Repairing only some of them and then bumping config.lua made the
-- Bank advertise a release it was not running, and it went on to serve
-- clients a new program beside an old library.
local repairBlock = startup:match(
    "local BANK_RUNTIME_REPAIR = {(.-)\n}")
assert(repairBlock, "startup.lua must list the Bank runtime repair set")
local repaired = {}
for path in repairBlock:gmatch('source = "([^"]+)"') do repaired[path] = true end

local bank = readFile("../bank_server.lua")
local shared = { "bank_server.lua" }
do
    local block = bank:match("RELEASE%.common = {(.-)\n}")
    assert(block, "bank_server.lua must list the files every role receives")
    for path in block:gmatch('source = "([^"]+)"') do
        shared[#shared + 1] = path
    end
end
for _, path in ipairs(shared) do
    assert(repaired[path],
        path .. " is served to clients but Easy Deployment never repairs it")
end

-- The release's own name and change list. A phone asks before it installs
-- anything now, so it has to be able to say what it is asking about. Both are
-- derived by the builder from files in this repository -- the label from
-- config.lua, the changes from CHANGELOG.md -- which leaves exactly one way
-- for them to be wrong: the changelog not covering this release at all. That
-- is what this checks, because showing the previous release's notes is worse
-- than showing none.
local configSource = readFile("../config.lua")
local releaseName = configSource:match('release_name%s*=%s*"([^"]*)"')
assert(releaseName and releaseName ~= "",
    "config.lua must name the release")
assert(manifest:find('"label": "' .. releaseName .. '"', 1, true),
    "the manifest must publish config.lua's release_name as its label")

local changelog = readFile("../CHANGELOG.md")
local topHeading = changelog:match("\n## ([^\n]+)")
assert(topHeading and topHeading:gsub("%s+$", "") == version,
    "CHANGELOG.md starts at " .. tostring(topHeading) .. ", not " .. version
        .. "; the release has no notes to show")

local section = changelog:match("\n## " .. version:gsub("%.", "%%.")
    .. "\n(.-)\n## ")
assert(section, "CHANGELOG.md has no closed section for " .. version)
local expectedChanges = {}
for line in (section .. "\n"):gmatch("([^\n]*)\n") do
    local headline = line:match("^%*%*(.-)%*%*")
        or line:match("^[%-%*] %*%*(.-)%*%*")
    if headline and #expectedChanges < 16 then
        assert(not headline:find('"', 1, true),
            "a change headline cannot contain a quote: " .. headline)
        expectedChanges[#expectedChanges + 1] = headline:gsub("%s+", " ")
    end
end
assert(#expectedChanges > 0,
    "the " .. version .. " changelog section has no bold headlines, so the"
        .. " update alert would list nothing")

local publishedChanges = {}
local changesSection = manifest:match('"changes":%s*%[(.-)%]')
assert(changesSection, "the manifest must publish a change list")
for entry in changesSection:gmatch('"(.-)"') do
    publishedChanges[#publishedChanges + 1] = entry
end
assert(#publishedChanges == #expectedChanges,
    "the manifest lists " .. #publishedChanges .. " changes but the changelog"
        .. " has " .. #expectedChanges .. "; rerun the release builder")
for index, expectedChange in ipairs(expectedChanges) do
    assert(publishedChanges[index] == expectedChange,
        "change " .. index .. " is \"" .. tostring(publishedChanges[index])
            .. "\" but the changelog says \"" .. expectedChange .. "\"")
end

print("host_release_manifest_test: OK")
