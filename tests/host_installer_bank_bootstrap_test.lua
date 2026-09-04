-- The first Bank Server is installed entirely from the release beside
-- startup.lua, without finding or contacting a Bank Server.

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

local files, directories = {}, { ["/"] = true, ["/bundle"] = true }
local function canonical(path)
    path = tostring(path or ""):gsub("/+", "/"):gsub("/$", "")
    if path == "" then return "/" end
    if path:sub(1, 1) ~= "/" then path = "/" .. path end
    return path
end
local sources = {
    "bank_server.lua", "pumpe.lua", "service_kiosk.lua",
    "event_kiosk.lua", "tax_controller.lua", "border_controller.lua",
    "ccg.lua",
    "startup.lua", "config.lua", "lib/net.lua", "lib/ui.lua",
    "lib/update.lua", "lib/util.lua",
}
for _, path in ipairs(sources) do
    files[canonical("/bundle/" .. path)] = path == "config.lua"
        and 'return { version = "6.0.0" }\n'
        or ("-- source " .. path .. "\n")
end

fs = {
    combine = function(left, right)
        return canonical(tostring(left):gsub("/+$", "") .. "/"
            .. tostring(right):gsub("^/+", ""))
    end,
    getDir = function(path)
        local parent = canonical(path):match("^(.*)/[^/]+$")
        return parent == "" and "/" or parent or ""
    end,
    exists = function(path)
        path = canonical(path)
        return files[path] ~= nil or directories[path] == true
    end,
    isDir = function(path) return directories[canonical(path)] == true end,
    getDrive = function() return "hdd" end,
    makeDir = function(path) directories[canonical(path)] = true end,
    delete = function(path)
        path = canonical(path)
        files[path], directories[path] = nil, nil
        for item in pairs(files) do
            if item:sub(1, #path + 1) == path .. "/" then files[item] = nil end
        end
        for item in pairs(directories) do
            if item:sub(1, #path + 1) == path .. "/" then
                directories[item] = nil
            end
        end
    end,
    move = function(source, destination)
        source, destination = canonical(source), canonical(destination)
        assert(files[source], "missing move source " .. source)
        files[destination] = files[source]
        files[source] = nil
    end,
    open = function(path, mode)
        path = canonical(path)
        if mode == "r" then
            if not files[path] then return nil end
            return {
                readAll = function() return files[path] end,
                close = function() end,
            }
        end
        local chunks = {}
        return {
            write = function(value) chunks[#chunks + 1] = value end,
            close = function() files[path] = table.concat(chunks) end,
        }
    end,
}

local display = {
    getSize = function() return 26, 20 end,
    setBackgroundColor = function() end,
    setTextColor = function() end,
    clear = function() end,
    setCursorPos = function() end,
    write = function() end,
}
term = { current = function() return display end }
peripheral = { getNames = function() return {} end }
rednet = {
    isOpen = function() return false end,
    open = function() end,
    lookup = function() error("Local Bank install must not discover a Bank") end,
}
local launched
shell = {
    getRunningProgram = function() return "/bundle/startup.lua" end,
    run = function(path)
        launched = canonical(path)
        return true
    end,
}
sleep = function() end
os.getComputerID = function() return 9 end
os.epoch = function() return 12345 end

-- 8.0 opens on the PUMPE panel, so the run drops to the other roles first
-- and the Bank Server is the fourth entry there rather than the fifth.
local events = {
    { "char", "m" },
    { "char", "4" },
    { "char", "4" }, { "char", "0" },
    { "char", "4" }, { "char", "0" },
}
os.pullEvent = function()
    local event = table.remove(events, 1)
    assert(event, "installer requested an unexpected event")
    return table.unpack(event)
end

assert(loadfile("../startup.lua"))()
assert(#events == 0)
assert(launched == "/pumpe/bank_server.lua")
assert(files["/pumpe/bank_server.lua"] == "-- source bank_server.lua\n")
assert(files["/updates/ccg.lua"] == "-- source ccg.lua\n")
assert(files["/updates/pumpe.lua"] == "-- source pumpe.lua\n")
assert(files["/pumpe/ccg.lua"] == nil)
assert(files["/pumpe/pumpe.lua"] == nil)
assert(files["/pumpe/startup.lua"] == nil)
assert(files["/pumpe/installer.lua"] == "-- source startup.lua\n")
assert(files["/pumpe/launcher.lua"] == nil)
assert(files["/startup.lua"]:find(
    'shell.run("/pumpe/installer.lua", "--boot", "bank")', 1, true))
for _, path in ipairs(sources) do
    assert(files[canonical("/bundle/" .. path)] == nil,
        "same-drive Bank source was not moved: " .. path)
end

-- After Easy Deployment self-updates, it repairs the small shared utility
-- before booting an older Bank. That lets the Bank checksum and install the
-- rest of the internet release without hitting the watchdog first.
local repairedUtil = "-- cooperative Bank checksum utility\n"
local repairedBank = "-- compact Bank Server v6.0.2\n"
local function checksum(body)
    local hash = 5381
    for index = 1, #body do
        hash = (hash * 33 + string.byte(body, index)) % 4294967296
    end
    local alphabet, output = "0123456789abcdef", {}
    for index = 8, 1, -1 do
        local digit = hash % 16
        output[index] = alphabet:sub(digit + 1, digit + 1)
        hash = math.floor(hash / 16)
    end
    return table.concat(output)
end
local function entry(path, body)
    return { path = path, source = path, size = #body, checksum = checksum(body) }
end
-- Deliberately incomplete: the shared libraries a client also receives are
-- missing, so this repair cannot make the Bank whole.
local repairManifest = {
    schema = 1,
    channel = "stable",
    version = "6.0.2",
    files = {
        entry("bank_server.lua", repairedBank),
        entry("lib/util.lua", repairedUtil),
    },
}
textutils = { unserializeJSON = function() return repairManifest end }
http = {
    get = function(request)
        if request.url:find("bank_server.lua", 1, true) then
            assert(files["/updates/bank_server.lua"] == nil,
                "legacy duplicate was not freed before Bank download")
            assert(files["/updates/lib/util.lua"] == nil,
                "legacy library duplicate was not freed before Bank download")
        end
        local body = request.url:find("lib/util.lua", 1, true)
            and repairedUtil
            or request.url:find("bank_server.lua", 1, true)
                and repairedBank
                or "{}"
        local sent = false
        return {
            read = function()
                if sent then return nil end
                sent = true
                return body
            end,
            close = function() end,
        }
    end,
}
files["/updates/bank_server.lua"] = "-- redundant Bank copy\n"
files["/updates/lib/util.lua"] = "-- redundant util copy\n"
launched = nil
assert(loadfile("../startup.lua"))("--boot", "bank")
assert(files["/pumpe/lib/util.lua"] == repairedUtil)
assert(files["/pumpe/bank_server.lua"] == repairedBank)
assert(files["/updates/bank_server.lua"] == nil)
assert(files["/updates/lib/util.lua"] == nil)
assert(launched == "/pumpe/bank_server.lua")

-- A partial repair must NOT claim the new version. Bumping config.lua while a
-- shared library stayed behind made the Bank advertise a release it was not
-- running, and it then served clients a new program beside an old library.
assert(files["/pumpe/config.lua"]:find('version = "6.0.0"', 1, true),
    "an incomplete repair must leave the installed version alone")

-- With every shared runtime file available the repair completes, and only
-- then does the Bank report the new version.
local repairedUi = "-- repaired ui\n"
local repairedNet = "-- repaired net\n"
local repairedUpdate = "-- repaired update\n"
local repairedInstaller = "-- PUMPE EASY DEPLOYMENT\n-- repaired installer\n"
local bodies = {
    ["bank_server.lua"] = repairedBank,
    ["lib/util.lua"] = repairedUtil,
    ["lib/ui.lua"] = repairedUi,
    ["lib/net.lua"] = repairedNet,
    ["lib/update.lua"] = repairedUpdate,
    ["startup.lua"] = repairedInstaller,
}
repairManifest.files = {}
for path, body in pairs(bodies) do
    repairManifest.files[#repairManifest.files + 1] = entry(path, body)
end
http.get = function(request)
    local body = "{}"
    for path, candidate in pairs(bodies) do
        if request.url:find(path, 1, true) then body = candidate end
    end
    local sent = false
    return {
        read = function()
            if sent then return nil end
            sent = true
            return body
        end,
        close = function() end,
    }
end
launched = nil
assert(loadfile("../startup.lua"))("--boot", "bank")
assert(files["/pumpe/lib/ui.lua"] == repairedUi,
    "a complete repair replaces every shared library")
assert(files["/pumpe/lib/net.lua"] == repairedNet)
assert(files["/pumpe/installer.lua"] == repairedInstaller)
assert(files["/pumpe/config.lua"]:find('version = "6.0.2"', 1, true),
    "a complete repair reports the version it now runs")
assert(launched == "/pumpe/bank_server.lua")

print("host_installer_bank_bootstrap_test: OK")
