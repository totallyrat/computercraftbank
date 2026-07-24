-- The role launcher checks clients for a newer Bank Server release first.

local calls = {}
fs = {
    getDir = function() return "/pumpe" end,
    combine = function(left, right)
        return tostring(left):gsub("/+$", "") .. "/"
            .. tostring(right):gsub("^/+", "")
    end,
    exists = function() return true end,
}
shell = {
    getRunningProgram = function() return "/pumpe/launcher.lua" end,
    run = function(...)
        calls[#calls + 1] = { ... }
        return true
    end,
}

local launcher = assert(loadfile("../launcher.lua"))
launcher("service")
assert(#calls == 2)
assert(calls[1][1] == "/pumpe/installer.lua")
assert(calls[1][2] == "--auto")
assert(calls[1][3] == "service")
assert(calls[2][1] == "/pumpe/service_kiosk.lua")

calls = {}
launcher("bank")
assert(#calls == 1)
assert(calls[1][1] == "/pumpe/bank_server.lua")

print("host_launcher_update_test: OK")
