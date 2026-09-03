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

-- A Bank that nobody has installed from holds no role programs at all.
assert(files["/updates/pumpe.lua"] == nil,
    "the depot starts empty instead of stockpiling every role")

-- The first client to ask for a role pulls it down and caches it.
assert(bank.deployment_body("pumpe.lua") == "-- pumpe program\n",
    "a requested role program is fetched on demand")
assert(files["/updates/pumpe.lua"] == "-- pumpe program\n",
    "the fetched program is cached for the next client")
assert(#fetched == 1 and fetched[1] == "pumpe.lua")

-- A second request is served from the cache, not the internet.
assert(bank.deployment_body("pumpe.lua") == "-- pumpe program\n")
assert(#fetched == 1, "a cached program is never downloaded twice")

-- Only role programs are fetched this way; the Bank's own runtime is local.
files["/lib/ui.lua"] = "-- shared library\n"
assert(bank.deployment_body("lib/ui.lua") == "-- shared library\n")
assert(#fetched == 1, "the Bank serves its own runtime without the internet")

-- An unpublished role reports missing rather than serving something wrong.
assert(bank.deployment_body("service_kiosk.lua") == nil,
    "a role missing from the release is not invented")

-- A Bank with no role programs still starts: they are not required locally.
assert(#bank.deployment_files("pumpe") > 0)

print("host_bank_depot_test: OK")
