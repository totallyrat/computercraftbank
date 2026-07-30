-- The legacy launcher only bridges v5.3 startup files into Easy Deployment.

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
assert(#calls == 1)
assert(calls[1][1] == "/pumpe/installer.lua")
assert(calls[1][2] == "--boot")
assert(calls[1][3] == "service")

calls = {}
launcher("bank")
assert(#calls == 1)
assert(calls[1][1] == "/pumpe/startup.lua")
assert(calls[1][2] == "--boot")
assert(calls[1][3] == "bank")

calls = {}
launcher("border")
assert(#calls == 1)
assert(calls[1][1] == "/pumpe/installer.lua")
assert(calls[1][2] == "--boot")
assert(calls[1][3] == "border")

print("host_launcher_update_test: OK")
