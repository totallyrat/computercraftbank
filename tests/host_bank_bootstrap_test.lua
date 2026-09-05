-- The Bank Server's load-time depot bootstrap, which PUMPE_TEST_MODE skips.
-- Everything before that guard runs on a real Bank the moment the file is
-- loaded, so a helper it reaches before that helper is declared kills the
-- Bank on start-up with no test ever seeing it. v8.1.1 shipped exactly that:
-- a stale depot cache logged to a logActivity defined 200 lines further down.

package.path = "../?.lua;../?/init.lua;" .. package.path

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

local files, directories
local function canonical(path)
    path = tostring(path or ""):gsub("^%./", ""):gsub("/+", "/"):gsub("/$", "")
    if path == "" then return "/" end
    if path:sub(1, 1) ~= "/" then path = "/" .. path end
    return path
end

fs = {
    getDir = function(path)
        local parent = canonical(path):match("^(.*)/[^/]+$")
        return parent == "" and "/" or parent or ""
    end,
    combine = function(left, right)
        return canonical(tostring(left):gsub("/+$", "") .. "/"
            .. tostring(right):gsub("^/+", ""))
    end,
    exists = function(path)
        path = canonical(path)
        return files[path] ~= nil or directories[path] == true
    end,
    isDir = function(path) return directories[canonical(path)] == true end,
    makeDir = function(path) directories[canonical(path)] = true end,
    getSize = function(path) return #(files[canonical(path)] or "") end,
    getFreeSpace = function() return 500 * 1024 end,
    list = function() return {} end,
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
    open = function(path, mode)
        path = canonical(path)
        if mode and mode:find("r") then
            if not files[path] then return nil end
            return { readAll = function() return files[path] end,
                read = function() return files[path] end,
                close = function() end }
        end
        local chunks = {}
        return { write = function(value) chunks[#chunks + 1] = tostring(value) end,
            close = function() files[path] = table.concat(chunks) end }
    end,
}

local drawn
local display = {
    getSize = function() return 51, 19 end,
    isColor = function() return true end,
    setBackgroundColor = function() end,
    setTextColor = function() end,
    setCursorBlink = function() end,
    clear = function() end,
    setCursorPos = function() end,
    write = function(value) drawn[#drawn + 1] = tostring(value) end,
}
term = { current = function() return display end }
shell = { getRunningProgram = function() return "/pumpe/bank_server.lua" end }
sleep = function() end
os.day = function() return 7 end
os.time = function() return 12 end
os.epoch = function() return 1000 end
os.getComputerID = function() return 11 end
rednet = { host = function() end, unhost = function() end,
    isOpen = function() return true end, open = function() end }
peripheral = { getNames = function() return {} end,
    getType = function() return "modem" end }
textutils = {
    serialize = function(value)
        local function render(item)
            if type(item) ~= "table" then return string.format("%q", tostring(item)) end
            local parts = {}
            for key, entry in pairs(item) do
                parts[#parts + 1] = ("[%q] = %s"):format(tostring(key), render(entry))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
        return render(value)
    end,
    unserializeJSON = function() return nil end,
}
package.loaded["lib.net"] = {
    host = function() end, unhost = function() end,
    receive = function() return nil end,
    reply = function() end, send = function() end,
}
-- The Bank runs forever once it is up; stop it the moment it gets there.
parallel = { waitForAny = function() error("__BANK_STARTED__", 0) end }

local function loadBank()
    drawn = {}
    local ok, err = pcall(assert(loadfile("../bank_server.lua")))
    assert(not ok, "the Bank should have reached its main loop")
    assert(tostring(err) == "__BANK_STARTED__",
        "the Bank failed before its main loop: " .. tostring(err))
end

local function seed()
    files, directories = {}, { ["/"] = true, ["/pumpe"] = true,
        ["/updates"] = true }
    files["/pumpe/installer.lua"] =
        "-- PUMPE EASY DEPLOYMENT\n-- This file is intentionally standalone.\n"
    for _, path in ipairs({ "bank_server.lua", "config.lua", "lib/net.lua",
        "lib/ui.lua", "lib/update.lua", "lib/util.lua" }) do
        files["/pumpe/" .. path] = "-- installed " .. path .. "\n"
    end
end

-- 1. A depot cache left over from an earlier release. Dropping it logs, and
-- that log is the line v8.1.1 died on.
seed()
files["/updates/.cache_version"] = "7.0.0"
files["/updates/pumpe.lua"] = "-- cached pumpe\n"
files["/updates/ccg.lua"] = "-- cached ccg\n"
loadBank()
assert(files["/updates/pumpe.lua"] == nil,
    "a cache from another release must be dropped")
assert(files["/updates/ccg.lua"] == nil)
-- Reaching the main loop at all is the assertion: a non-empty drop calls
-- logActivity, which is what "attempt to call a nil value" died on.
assert(#drawn > 0, "the Bank draws its boot screen")
assert(files["/updates/public/config.lua"],
    "the sanitized client config is written at bootstrap")
assert(files["/startup.lua"] and
    files["/startup.lua"]:find("installer.lua", 1, true),
    "the Bank writes its own boot entry")

-- 2. The same boot after an automatic update restart takes the early exit,
-- which skips the missing-file check entirely.
seed()
files["/updates/.cache_version"] = "7.0.0"
files["/updates/pumpe.lua"] = "-- cached pumpe\n"
files["/pumpe/.bank_auto_restart"] = "8.1.1"
loadBank()
assert(files["/pumpe/.bank_auto_restart"] == nil,
    "the restart marker is consumed")

-- 3. A depot already stamped for this release keeps its cache and still boots.
seed()
local installed = loadfile("../config.lua")()
files["/updates/.cache_version"] = installed.version
files["/updates/pumpe.lua"] = "-- cached pumpe\n"
loadBank()
assert(files["/updates/pumpe.lua"] == "-- cached pumpe\n",
    "a cache stamped for this release is kept")

print("host_bank_bootstrap_test: OK")
