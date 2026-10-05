-- Beta Updates, FoxyOS 14.1, in the updater itself.
--
-- A beta is numbered half way to the release it comes before (FoxyOS 15
-- Beta is 14.5) and published in a manifest of its own, beside the
-- release's, on the "beta" channel. Three things matter here:
--
--   * a minor version of 5 is a beta wherever it turns up, and only a device
--     that signed up takes one -- even from the release's own manifest;
--   * a beta is downloaded from the beta's folder, not the release's;
--   * looking for a beta never falls back to the Bank's depot, which holds
--     the release: a Pocket that could not read the beta must not install
--     something else instead.

package.path = "../?.lua;../?/init.lua;" .. package.path

os.day = function() return 1 end
os.time = function() return 12 end
os.epoch = function() return 1 end
os.getComputerID = function() return 1 end

local update = require("lib.update")
local net = require("lib.net")

-- An in-memory computer ----------------------------------------------------

local files, directories = {}, { ["/"] = true }
fs = {}
fs.combine = function(left, right)
    return tostring(left):gsub("/+$", "") .. "/"
        .. tostring(right):gsub("^/+", "")
end
fs.getDir = function(path) return tostring(path):match("^(.*)/[^/]+$") or "" end
fs.exists = function(path)
    return files[path] ~= nil or directories[path] == true
end
fs.isDir = function(path) return directories[path] == true end
fs.makeDir = function(path) directories[path] = true end
fs.delete = function(path)
    files[path], directories[path] = nil, nil
    local prefix = tostring(path):gsub("/+$", "") .. "/"
    for existing in pairs(files) do
        if existing:sub(1, #prefix) == prefix then files[existing] = nil end
    end
end
fs.move = function(source, destination)
    assert(files[source] ~= nil, "missing move source " .. source)
    files[destination], files[source] = files[source], nil
end
fs.open = function(path, mode)
    assert(mode == "w")
    local chunks = {}
    return {
        write = function(value) chunks[#chunks + 1] = tostring(value) end,
        close = function() files[path] = table.concat(chunks) end,
    }
end

-- Two manifests: the release's and the beta's, each with its own files ----

local served = {}
local function manifestFor(channel, version, label, folder)
    local manifest = { schema = 1, channel = channel, version = version,
        label = label, changes = {}, files = {} }
    for _, path in ipairs(update.PUBLISHED_FILES) do
        local body = path == "config.lua"
            and ('return { version = "' .. version .. '" }')
            or (label .. " " .. path)
        served[folder .. "dist/" .. path] = body
        manifest.files[#manifest.files + 1] = { path = path,
            source = "dist/" .. path, size = #body, checksum = update.checksum(body) }
    end
    return manifest
end
local manifests = {
    ["release_manifest.json"] = manifestFor("stable", "14.1.0", "FoxyOS 14.1", ""),
    ["beta/release_manifest.json"] = manifestFor("beta", "14.5.0", "FoxyOS 15 Beta",
        "beta/"),
}

local requested = {}
local current
textutils = { unserializeJSON = function() return current end,
    serialize = function(value)
        local parts = {}
        for key, item in pairs(value) do
            parts[#parts + 1] = tostring(key) .. " = " .. string.format("%q", tostring(item))
        end
        table.sort(parts)
        return "{ " .. table.concat(parts, ", ") .. " }"
    end }
http = {
    get = function(request)
        local source = request.url:match("^https://example%.test/(.-)%?") or ""
        requested[#requested + 1] = source
        local body
        if manifests[source] then
            current = manifests[source]
            body = "{}"
        else
            body = served[source]
        end
        if not body then return nil, "Not Found" end
        local offset = 0
        return {
            read = function(count)
                if offset >= #body then return nil end
                local chunk = body:sub(offset + 1, offset + count)
                offset = offset + #chunk
                return chunk
            end,
            close = function() end,
        }
    end,
}
local realLoadfile = loadfile
loadfile = function(path)
    if path == "/pumpe/.self_update/config.lua" then
        local text = files[path]
        local version = text and text:match('version = "([%d%.]+)"') or "0.0.0"
        return function() return { version = version } end
    end
    return realLoadfile(path)
end
local rebooted = 0
os.reboot = function() rebooted = rebooted + 1 end
local depotRuns = 0
shell = { run = function() depotRuns = depotRuns + 1 return true end }

local BETA = "https://example.test/beta/release_manifest.json"
local config = {
    version = "14.1.0",
    update_manifest_url = "https://example.test/release_manifest.json",
    update_channel = "stable",
    auto_update = true,
    client_update_check_seconds = 30,
}

-- The rule -------------------------------------------------------------------------

assert(update.isBeta("14.5.0") and update.isBeta("14.5.3"), "x.5 is a beta")
assert(not update.isBeta("14.1.0") and not update.isBeta("15.0.0")
    and not update.isBeta("15.50.0"), "nothing else is")

-- A beta in the release's own manifest still waits for somebody who asked.
local saved = manifests["release_manifest.json"]
manifests["release_manifest.json"] = manifests["beta/release_manifest.json"]
manifests["release_manifest.json"].channel = "stable"
local found, why = update.check({ config = config, role = "pumpe" })
assert(found == false and why == "beta", "a beta is only for a device that asked: "
    .. tostring(why))
found = update.check({ config = config, role = "pumpe", beta = true })
assert(found and found.beta and found.version == "14.5.0", "and is offered to one that did")
manifests["beta/release_manifest.json"].channel = "beta"
manifests["release_manifest.json"] = saved

-- The beta manifest is on its own channel: one claiming to be the release
-- is refused, so the two can never be swapped.
manifests["beta/release_manifest.json"].channel = "stable"
found, why = update.check({ config = config, role = "pumpe", beta = true,
    manifestUrl = BETA, channel = "beta" })
assert(found == nil and tostring(why):find("another channel", 1, true),
    "the beta address must carry the beta channel: " .. tostring(why))
manifests["beta/release_manifest.json"].channel = "beta"

-- Looked for from the Pocket: the release first, then the beta ------------------

local client = { request = function() error("the Bank was asked about a beta") end }
local stableAnswer = net.autoUpdate(config, "pumpe", "/pumpe", client, {
    confirm = function() error("the release is not newer: nothing to ask") end,
})
assert(stableAnswer == false, "the release is current")
local before = #requested
local asked
local installed = net.autoUpdate(config, "pumpe", "/pumpe", client, {
    manifestUrl = BETA, channel = "beta", beta = true,
    confirm = function(release)
        asked = release
        assert(files["/pumpe/.self_update/pumpe.lua"] == "FoxyOS 15 Beta pumpe.lua",
            "downloaded first, from the beta's folder, then asked")
        return true
    end,
})
assert(#requested > before, "the beta was looked for straight after the release,"
    .. " not held back by the release's own check timer")
assert(asked and asked.label == "FoxyOS 15 Beta" and asked.version == "14.5.0"
    and asked.beta, "the question names the beta")
assert(installed and rebooted == 1, "and yes installs it")
assert(files["/pumpe/pumpe.lua"] == "FoxyOS 15 Beta pumpe.lua"
    and files["/pumpe/installer.lua"] == "FoxyOS 15 Beta startup.lua",
    "the beta's files landed")
for at = before + 1, #requested do
    assert(requested[at]:sub(1, 5) == "beta/",
        "every beta file came from the beta's folder: " .. requested[at])
end
assert(tostring(files["/pumpe/config.lua"]):find('"14.5.0"', 1, true),
    "and its config names the beta")

-- No beta out ---------------------------------------------------------------------
-- Nothing at the beta address. That is a settled "no", not a reason to ask
-- the Bank, whose depot holds the release.

files = {}
local missing = manifests["beta/release_manifest.json"]
manifests["beta/release_manifest.json"] = nil
local none = net.autoUpdate(config, "pumpe", "/pumpe", client, {
    force = true, manifestUrl = BETA, channel = "beta", beta = true,
    confirm = function() error("nothing to ask about") end,
})
assert(none == false and depotRuns == 0, "no beta, and nothing else instead")
-- The same with nobody to ask: a device on its own does not reach for the
-- depot either.
none = net.autoUpdate(config, "pumpe", "/pumpe", client, {
    force = true, manifestUrl = BETA, channel = "beta", beta = true,
})
assert(none == false and depotRuns == 0 and next(files) == nil,
    "an unattended beta check that finds nothing changes nothing")
manifests["beta/release_manifest.json"] = missing

-- A partial install is repaired from the Bank, as before -- but only by the
-- release's check. The beta's never does it.
files["/pumpe/installer.lua"] = "Easy Deployment"
none = net.autoUpdate({ version = "14.5.0", auto_update = true,
    update_manifest_url = config.update_manifest_url, update_channel = "stable",
    client_update_check_seconds = 30 }, "pumpe", "/pumpe", nil, {
    force = true, manifestUrl = BETA, channel = "beta", beta = true,
    programVersion = "14.1.0",
    confirm = function() return false end,
})
assert(depotRuns == 0, "a beta check never repairs from the Bank's depot")

files["/pumpe/installer.lua"] = nil

-- A beta that turns up in the release's own manifest, on a Pocket that did
-- not sign up: a settled no. Not a reason to ask the Bank what it has.
manifests["release_manifest.json"] = manifests["beta/release_manifest.json"]
manifests["release_manifest.json"].channel = "stable"
local pinged = false
local watching = { request = function() pinged = true return { version = "99.0.0" } end }
none = net.autoUpdate(config, "pumpe", "/pumpe", watching, {
    force = true, confirm = function() error("a beta was offered to a Pocket that did not sign up") end,
})
assert(none == false and not pinged and depotRuns == 0,
    "a beta nobody asked for is not a reason to go to the Bank")

print("host_beta_channel_test: OK")
