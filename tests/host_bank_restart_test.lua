-- Root-installed Bank Servers must cache the standalone installer, replace
-- /startup.lua with the Bank role launcher, and still serve the installer.

package.path = "../?.lua;../?/init.lua;" .. package.path

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

local files = {}
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
    exists = function(path) return files[canonical(path)] ~= nil end,
    isDir = function() return false end,
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
    'shell.run("/launcher.lua", "bank")', 1, true))
assert(files["/.easy_deployment_source.lua"] == standalone)
assert(bank.local_update_body("startup.lua") == standalone)

print("host_bank_restart_test: OK")
