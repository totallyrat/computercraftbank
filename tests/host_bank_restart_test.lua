-- Root-installed Bank Servers must cache the standalone installer, replace
-- /startup.lua with a direct Easy Deployment boot, and still serve it.

package.path = "../?.lua;../?/init.lua;" .. package.path

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

local files = {}
local directories = { ["/"] = true }
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
        local prefix = path .. "/"
        for item in pairs(files) do
            if item:sub(1, #prefix) == prefix then files[item] = nil end
        end
        for item in pairs(directories) do
            if item:sub(1, #prefix) == prefix then directories[item] = nil end
        end
    end,
    move = function(source, destination)
        source, destination = canonical(source), canonical(destination)
        assert(files[source], "missing move source " .. source)
        files[destination] = files[source]
        files[source] = nil
    end,
}
shell = {
    getRunningProgram = function() return "bank_server.lua" end,
}
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

local standalone = "-- PUMPE EASY DEPLOYMENT\n"
    .. "-- This file is intentionally standalone.\n"
    .. "print('installer')\n"
files["/startup.lua"] = standalone

PUMPE_TEST_MODE = true
local bank = assert(loadfile("../bank_server.lua"))()
PUMPE_TEST_MODE = nil

assert(bank.ensure_bank_startup(standalone))
assert(files["/startup.lua"]:find("-- PUMPE ROLE STARTUP", 1, true))
assert(files["/startup.lua"]:find(
    'shell.run("/installer.lua", "--boot", "bank")', 1, true))
assert(files["/installer.lua"] == standalone)
assert(files["/.easy_deployment_source.lua"] == nil)
assert(bank.local_update_body("startup.lua") == standalone)

files["/bank_server.lua"] = "bank runtime"
files["/updates/bank_server.lua"] = "duplicate bank runtime"
files["/pumpe.lua"] = "client program"
files["/updates/pumpe.lua"] = "client program"
files["/.easy_deployment_source.lua"] = standalone
directories["/.online_update_stage"] = true
files["/.online_update_stage/partial.lua"] = "partial"
bank.compact_bank_storage()
assert(files["/bank_server.lua"] == "bank runtime")
assert(files["/updates/bank_server.lua"] == nil)
assert(files["/pumpe.lua"] == nil)
assert(files["/updates/pumpe.lua"] == "client program")
assert(files["/.easy_deployment_source.lua"] == nil)
assert(not directories["/.online_update_stage"])
files["/lib/ui.lua"] = "shared runtime library"
files["/updates/public/config.lua"] = "sanitized config"
assert(bank.deployment_body("lib/ui.lua") == "shared runtime library")
assert(bank.deployment_body("pumpe.lua") == "client program")
assert(bank.deployment_body("public/config.lua") == "sanitized config")

print("host_bank_restart_test: OK")
