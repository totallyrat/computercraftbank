-- The Bank repairs its /updates/ depot from the published manifest instead of
-- from checksums pinned into bank_server.lua, and stamps it once it matches.

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
}
-- A ComputerCraft computer holds 1000 KiB by default.
local DISK = 1000 * 1000
fs.getFreeSpace = function()
    local used = 0
    for _, body in pairs(files) do used = used + #body end
    return DISK - used
end
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

local fetched, available = {}, {}
package.loaded["lib.update"] = {
    isNewer = function() return false end,
    checksum = util.checksum,
    fetchFile = function(_, file)
        fetched[#fetched + 1] = file.path
        return available[file.path]
    end,
}

local config = require("config")
PUMPE_TEST_MODE = true
local bank = assert(loadfile("../bank_server.lua"))()
PUMPE_TEST_MODE = nil

local function entry(path, body)
    return { path = path, source = path, size = #body,
        checksum = util.checksum(body) }
end

local currentCCG = "-- ccg v6.1\n"
local currentPumpe = "-- pumpe v6.1\n"
local manifest = {
    version = config.version,
    files = {
        entry("bank_server.lua", "-- bank v6.1\n"),
        entry("pumpe.lua", currentPumpe),
        entry("ccg.lua", currentCCG),
    },
}

-- An upgrade from a Bank that published fewer files leaves a stale depot copy.
files["/updates/pumpe.lua"] = currentPumpe
files["/updates/ccg.lua"] = "-- ccg v6.0.3 (stale)\n"
available["ccg.lua"] = currentCCG

assert(not bank.depot_stamped(), "a fresh depot starts unstamped")
assert(bank.verify_depot(manifest, "https://example.test/release_manifest.json"))
assert(files["/updates/ccg.lua"] == currentCCG,
    "a stale depot program must be replaced from the manifest")
assert(files["/updates/pumpe.lua"] == currentPumpe)
assert(#fetched == 1 and fetched[1] == "ccg.lua",
    "only mismatching depot files are downloaded again")
assert(files["/updates/bank_server.lua"] == nil,
    "the Bank runtime is served from its install root, never duplicated")
assert(bank.depot_stamped(), "a verified depot is stamped for this version")

-- A second pass is free: nothing mismatches, so nothing is downloaded.
fetched = {}
assert(bank.verify_depot(manifest, "https://example.test/release_manifest.json"))
assert(#fetched == 0, "a stamped, matching depot must not re-download")

-- When the download fails the depot stays unstamped so the next check retries.
files["/updates/ccg.lua"] = "-- broken\n"
files["/updates/.depot"] = nil
available["ccg.lua"] = nil
assert(bank.verify_depot(manifest, "https://example.test/release_manifest.json")
    == false, "a failed repair must report failure")
assert(not bank.depot_stamped(), "a failed repair must not stamp the depot")

-- Disk space -----------------------------------------------------------------
-- The updater stages a whole second copy of the release before committing.
-- On a full Bank that no longer fits, so the depot is reclaimed first.

local function bytes(count) return string.rep("x", count) end

files["/updates/pumpe.lua"] = bytes(125000)
files["/updates/service_kiosk.lua"] = bytes(39000)
files["/updates/event_kiosk.lua"] = bytes(16000)
files["/updates/tax_controller.lua"] = bytes(15000)
files["/updates/border_controller.lua"] = bytes(14000)
files["/updates/ccg.lua"] = bytes(26000)
files["/bank_server.lua"] = bytes(186000)
files["/startup.lua"] = bytes(46000)
files["/lib/ui.lua"] = bytes(26000)
files["/bank_data_v5.dat"] = bytes(90000)
files["/updates/.depot"] = config.version

local big = {
    version = "9.9.9",
    files = {
        entry("bank_server.lua", bytes(186000)),
        entry("pumpe.lua", bytes(125000)),
        entry("service_kiosk.lua", bytes(39000)),
        entry("startup.lua", bytes(46000)),
        entry("lib/ui.lua", bytes(26000)),
        entry("ccg.lua", bytes(26000)),
        entry("border_controller.lua", bytes(14000)),
    },
}

local before = fs.getFreeSpace("/")
local needed = 0
for _, file in ipairs(big.files) do needed = needed + file.size end
assert(before < needed,
    "the fixture must start without room for the staged release")

assert(bank.update_space_ready(big), "the depot must be reclaimed to make room")
assert(files["/updates/pumpe.lua"] == nil,
    "depot programs are freed before staging")
assert(files["/bank_server.lua"] ~= nil,
    "the running Bank runtime is never touched to make room")
assert(files["/bank_data_v5.dat"] ~= nil, "account data is never touched")
assert(files["/updates/.depot"] == nil,
    "clearing the depot must clear its stamp so it is verified again")
assert(fs.getFreeSpace("/") >= needed, "there is now room for the release")

-- A Bank whose depot was cleared still boots and repairs itself online rather
-- than stopping at the Easy Deployment repair screen.
assert(bank.only_repairable_missing({ "pumpe.lua (local source)", "ccg.lua" }),
    "missing depot programs are repairable from the manifest")
assert(not bank.only_repairable_missing({ "bank_server.lua" }),
    "a missing Bank runtime is not repairable online")
assert(not bank.only_repairable_missing({}), "nothing missing is not a repair")

print("host_bank_depot_test: OK")
