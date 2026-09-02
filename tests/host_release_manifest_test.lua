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
local expectedExtra = { "border_controller.lua", "ccg.lua" }

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

print("host_release_manifest_test: OK")
