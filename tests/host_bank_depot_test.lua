-- Role programs are no longer stockpiled. The Bank fetches one from the
-- public manifest the first time a client actually installs that role.

package.path = "../?.lua;../?/init.lua;" .. package.path

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

local files, directories = {}, { ["/"] = true }
local function canonical(path)
    path = tostring(path or ""):gsub("^%./", ""):gsub("/+", "/")
    if path:sub(1, 1) ~= "/" then path = "/" .. path end
    return path
end

fs = {
    getDir = function() return "" end,
    combine = function(left, right)
        if left == "." or left == "" then return tostring(right) end
        return tostring(left):gsub("/+$", "") .. "/"
            .. tostring(right):gsub("^/+", "")
    end,
    exists = function(path)
        path = canonical(path)
        return files[path] ~= nil or directories[path] == true
    end,
    isDir = function(path) return directories[canonical(path)] == true end,
    makeDir = function(path) directories[canonical(path)] = true end,
    delete = function(path)
        path = canonical(path)
        files[path], directories[path] = nil, nil
        for item in pairs(files) do
            if item:sub(1, #path + 1) == path .. "/" then files[item] = nil end
        end
    end,
    move = function(source, destination)
        source, destination = canonical(source), canonical(destination)
        files[destination], files[source] = files[source], nil
    end,
    getSize = function(path) return #(files[canonical(path)] or "") end,
    getFreeSpace = function() return 900 * 1000 end,
}
shell = { getRunningProgram = function() return "bank_server.lua" end }
os.day = function() return 1 end
os.time = function() return 12 end
os.epoch = function() return 123456789 end
os.getComputerID = function() return 1 end

textutils = { serialize = function(value)
    local parts = {}
    for key, item in pairs(value) do
        parts[#parts + 1] = tostring(key) .. " = " .. string.format("%q", tostring(item))
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end }

local util = require("lib.util")
util.readFile = function(path) return files[canonical(path)] end
util.writeFile = function(path, body) files[canonical(path)] = body end
util.loadTable = function(_, fallback) return util.copy(fallback) end
util.saveTable = function() end
package.loaded["lib.util"] = util

local config = require("config")
local fetched, published = {}, {}
package.loaded["lib.update"] = {
    isNewer = function() return false end,
    checksum = util.checksum,
    selfUpdate = function() return false, "current" end,
    fetchManifest = function()
        local list = {}
        for path, body in pairs(published) do
            list[#list + 1] = { path = path, source = path, size = #body,
                checksum = util.checksum(body) }
        end
        return { version = config.version, files = list }
    end,
    fetchFile = function(_, file)
        fetched[#fetched + 1] = file.path
        return published[file.path]
    end,
}

PUMPE_TEST_MODE = true
local bank = assert(loadfile("../bank_server.lua"))()
PUMPE_TEST_MODE = nil

published["pumpe.lua"] = "-- pumpe program\n"
published["ccg.lua"] = "-- ccg program\n"

-- Since 11.2 nothing about deployment touches the disk: role programs are
-- held in memory, and a Core that has handed out every role still has the
-- same free space it started with.
local function diskFiles()
    local count = 0
    for path in pairs(files) do
        if path:find("^/updates") then count = count + 1 end
    end
    return count
end

-- The first client to ask for a role pulls it down and keeps it in memory.
assert(bank.deployment_body("pumpe.lua") == "-- pumpe program\n",
    "a requested role program is fetched on demand")
assert(#fetched == 1 and fetched[1] == "pumpe.lua")
assert(diskFiles() == 0, "and nothing is written to /updates")

-- A second request is served from memory, not the internet: a client
-- downloads a program in dozens of chunks.
assert(bank.deployment_body("pumpe.lua") == "-- pumpe program\n")
assert(#fetched == 1, "a held program is never downloaded twice")

-- Only role programs are fetched this way; the Bank's own runtime is local.
files["/lib/ui.lua"] = "-- shared library\n"
assert(bank.deployment_body("lib/ui.lua") == "-- shared library\n")
assert(#fetched == 1, "the Bank serves its own runtime without the internet")

-- An unpublished role reports missing rather than serving something wrong.
assert(bank.deployment_body("service_kiosk.lua") == nil,
    "a role missing from the release is not invented")

-- The client config is made on the spot, without the government key.
local public = bank.deployment_body("public/config.lua")
assert(public and public:find("CLIENT-NO-GOVERNMENT-ACCESS", 1, true),
    "clients get this Bank's settings without its government key")
assert(diskFiles() == 0)

-- Memory is bounded too: the oldest program goes when the limit is reached.
bank.depot.limit = 40
published["event_kiosk.lua"] = string.rep("e", 30) .. "\n"
assert(bank.deployment_body("ccg.lua") and bank.deployment_body("event_kiosk.lua"))
assert(bank.depot.cache["pumpe.lua"] == nil and bank.depot.bytes <= 40,
    "the oldest is let go")

-- What earlier releases left on the disk goes at start-up: it is exactly the
-- room a full Core needs back.
files["/updates/pumpe.lua"] = "-- cached by 11.1\n"
files["/updates/.cache_version"] = "11.1.0"
directories["/updates"] = true
assert(bank.free_old_depot() >= 1)
assert(diskFiles() == 0, "the old /updates cache is gone")

-- A Bank with no role programs still starts: they are not required locally.
assert(#bank.deployment_files("pumpe") > 0)

-- Every role receives the updater itself, or it can never self-update and is
-- stuck on the Bank fallback forever.
for _, role in ipairs({ "pumpe", "service", "event", "tax", "border", "ccg" }) do
    local hasUpdater = false
    for _, file in ipairs(bank.deployment_files(role)) do
        if file.path == "lib/update.lua" then hasUpdater = true end
    end
    assert(hasUpdater, role .. " must receive lib/update.lua to self-update")
end

print("host_bank_depot_test: OK")
