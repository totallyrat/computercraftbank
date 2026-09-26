-- Easy Deployment installing a PUMPE from a real Bank Server.
--
-- Two computers on one simulated Rednet: a Bank Core with the files a 11.2
-- Bank really has on its disk, and a blank pocket computer running the real
-- installer. The pocket presses INSTALL PUMPE; what matters is what ends up
-- on the pocket's disk and what it boots into.

package.path = "../?.lua;../?/init.lua;" .. package.path

local function readRepo(path)
    local handle = io.open("../" .. path, "rb")
    if not handle then return nil end
    local body = handle:read("a")
    handle:close()
    return body
end

-- Two disks, one fs: whichever computer is running is the one it sees.
local disks = { [1] = {}, [7] = {} }
local current = 1
local function disk() return disks[current] end
local function norm(path)
    path = tostring(path or ""):gsub("\\", "/"):gsub("/+", "/")
    path = path:gsub("^/", ""):gsub("/$", "")
    return path
end
local function under(name, dir) return dir == "" or name:sub(1, #dir + 1) == dir .. "/" end

fs = {
    combine = function(a, b) return norm(tostring(a) .. "/" .. tostring(b)) end,
    getDir = function(path)
        path = norm(path)
        return path:match("^(.*)/[^/]*$") or ""
    end,
    getName = function(path) return norm(path):match("([^/]*)$") end,
    exists = function(path)
        path = norm(path)
        if path == "" or disk()[path] then return true end
        for name in pairs(disk()) do if under(name, path) then return true end end
        return false
    end,
    isDir = function(path)
        path = norm(path)
        if path == "" then return true end
        if disk()[path] then return false end
        for name in pairs(disk()) do if under(name, path) then return true end end
        return false
    end,
    makeDir = function() end,
    list = function(path)
        path = norm(path)
        local out, seen = {}, {}
        for name in pairs(disk()) do
            if under(name, path) then
                local first = name:sub(path == "" and 1 or #path + 2):match("^[^/]+")
                if first and not seen[first] then
                    seen[first] = true
                    out[#out + 1] = first
                end
            end
        end
        table.sort(out)
        return out
    end,
    delete = function(path)
        path = norm(path)
        disk()[path] = nil
        for name in pairs(disk()) do
            if under(name, path) then disk()[name] = nil end
        end
    end,
    move = function(from, to)
        from, to = norm(from), norm(to)
        if disk()[from] then
            disk()[to], disk()[from] = disk()[from], nil
            return
        end
        for name, body in pairs(disk()) do
            if under(name, from) then
                disk()[to .. name:sub(#from + 1)], disk()[name] = body, nil
            end
        end
    end,
    getSize = function(path) return #(disk()[norm(path)] or "") end,
    getFreeSpace = function() return 1000000 end,
    open = function(path, mode)
        path = norm(path)
        if mode == "r" or mode == "rb" then
            local body = disk()[path]
            if not body then return nil end
            local offset = 0
            return {
                readAll = function() offset = #body return body end,
                read = function() return body end,
                readLine = function()
                    if offset >= #body then return nil end
                    local line = body:match("^([^\n]*)\n?", offset + 1)
                    offset = offset + #line + 1
                    return line
                end,
                close = function() end,
            }
        end
        local parts = {}
        local target = disks[current]
        return { write = function(text) parts[#parts + 1] = tostring(text) end,
            writeLine = function(text) parts[#parts + 1] = tostring(text) .. "\n" end,
            flush = function() end,
            close = function() target[path] = table.concat(parts) end }
    end,
}

colors = { white = 1, orange = 2, magenta = 4, lightBlue = 8, yellow = 16,
    lime = 32, pink = 64, gray = 128, lightGray = 256, cyan = 512,
    purple = 1024, blue = 2048, brown = 4096, green = 8192, red = 16384,
    black = 32768 }
colours = colors
keys = { enter = 28, up = 200, down = 208, backspace = 14, escape = 1 }
local clock = 1000
os.epoch = function() clock = clock + 1 return clock end
os.day = function() return 3 end
os.getComputerID = function() return current end
os.startTimer = function() return 1 end
os.cancelTimer = function() end
sleep = function() end
local screen = {}
local display = {
    getSize = function() return 26, 20 end,
    isColor = function() return true end, isColour = function() return true end,
    setBackgroundColor = function() end, setBackgroundColour = function() end,
    setTextColor = function() end, setTextColour = function() end,
    setCursorBlink = function() end, clear = function() screen = {} end,
    clearLine = function() end, getCursorPos = function() return 1, 1 end,
    setCursorPos = function() end,
    write = function(text) screen[#screen + 1] = tostring(text) end,
    scroll = function() end, blit = function() end,
}
term = { current = function() return display end, redirect = function() end,
    native = function() return display end }
print = function() end
write = function() end
peripheral = { getNames = function() return { "back" } end,
    getType = function() return "modem" end,
    call = function() return true end, isPresent = function() return true end,
    wrap = function() return nil end }
http = nil

-- The network ---------------------------------------------------------------------

local inbox = { [1] = {}, [7] = {} }
local bank
local function deliver(to, from, message, protocol)
    if to == 1 and bank then
        local was = current
        current = 1
        bank.deployment_route(from, message)
        current = was
    else
        table.insert(inbox[to], { from = from, message = message,
            protocol = protocol })
    end
end
rednet = {
    open = function() end, close = function() end,
    isOpen = function() return true end,
    host = function() end, unhost = function() end,
    lookup = function(protocol)
        if protocol == "PUMPE_DEPLOY_V5" then return 1 end
        return nil
    end,
    send = function(to, message, protocol)
        deliver(to, current, message, protocol)
        return true
    end,
    broadcast = function() end,
    receive = function(protocol)
        local box = inbox[current]
        for index, item in ipairs(box) do
            if not protocol or item.protocol == protocol then
                table.remove(box, index)
                return item.from, item.message, item.protocol
            end
        end
        return nil
    end,
}

local function serialize(value, indent)
    if type(value) == "table" then
        local parts = {}
        for key, item in pairs(value) do
            local name = type(key) == "number" and ("[" .. key .. "]")
                or ("[" .. string.format("%q", key) .. "]")
            parts[#parts + 1] = name .. " = " .. serialize(item)
        end
        return "{\n" .. table.concat(parts, ",\n") .. "\n}"
    elseif type(value) == "string" then
        return string.format("%q", value)
    end
    return tostring(value)
end
textutils = { serialize = function(value) return serialize(value) end,
    unserialize = function(body) return load("return " .. body)() end,
    unserializeJSON = function() return nil end }

-- The Bank: an 11.2 Core as its disk really is -------------------------------------

current = 1
local installed = {
    ["pumpe/bank_server.lua"] = readRepo("dist/bank_server.lua"),
    ["pumpe/installer.lua"] = readRepo("startup.lua"),
    ["pumpe/config.lua"] = readRepo("config.lua"),
    ["startup.lua"] = '-- PUMPE ROLE STARTUP\nshell.run("/pumpe/installer.lua", "--boot", "bank")\n',
}
for _, name in ipairs({ "net", "ui", "update", "util" }) do
    installed["pumpe/lib/" .. name .. ".lua"] = readRepo("dist/lib/" .. name .. ".lua")
end
for path, body in pairs(installed) do disks[1][path] = body end
shell = { getRunningProgram = function()
    return current == 1 and "pumpe/bank_server.lua" or "startup.lua"
end, run = function() return true end }

local update = require("lib.update")
local published = {}
do
    local json = readRepo("release_manifest.json")
    published.version = json:match('"version": "([^"]+)"')
    published.files = {}
    for path, source, size, sum in json:gmatch('"path":%s*"([^"]+)",%s*"source":%s*"([^"]+)",%s*"size":%s*(%d+),%s*"checksum":%s*"(%x+)"') do
        published.files[#published.files + 1] = { path = path, source = source,
            size = tonumber(size), checksum = sum }
    end
end
update.fetchManifest = function() return published end
update.fetchFile = function(_, file) return readRepo(file.source) end

local util = require("lib.util")
PUMPE_TEST_MODE = true
bank = assert(loadfile("../bank_server.lua"))()
PUMPE_TEST_MODE = nil

-- From here on loadfile reads the simulated disks, as it does in the game.
local hostLoadfile = loadfile
loadfile = function(path, ...)
    local body = disks[current][norm(path)]
    if body then return load(body, "=" .. path, ...) end
    if tostring(path):sub(1, 3) == "../" then return hostLoadfile(path, ...) end
    return nil, "File not found"
end

-- The pocket: a blank computer running the installer ---------------------------------

current = 7
disks[7]["startup.lua"] = readRepo("startup.lua")
local events = {
    { "char", "i" },             -- INSTALL PUMPE, on the first screen
    { "terminate" },             -- leave the success screen
    { "terminate" },             -- and the menu
}
os.queueEvent = function() end
os.pullEvent = function(filter)
    -- Both programs yield to the watchdog by waiting on an event they
    -- queued themselves; that always comes straight back.
    if filter then return filter end
    local event = table.remove(events, 1)
    if not event then error("__OUT_OF_EVENTS__", 0) end
    return table.unpack(event)
end
os.pullEventRaw = os.pullEvent
os.reboot = function() error("__REBOOT__", 0) end
os.shutdown = function() error("__SHUTDOWN__", 0) end
local ok, err = pcall(assert(loadfile("../startup.lua")))
assert(ok or err == "__OUT_OF_EVENTS__" or err == "__REBOOT__",
    "the installer failed: " .. tostring(err))

local pocket = disks[7]
local boot = pocket["startup.lua"] or ""
assert(boot:find('"--boot", "pumpe"', 1, true),
    "the pocket boots into the PUMPE: " .. boot)
assert(pocket["pumpe/pumpe.lua"] == readRepo("pumpe.lua"),
    "the PUMPE program is on it")
assert(not pocket["pumpe/bank_server.lua"], "and the Bank's is not")
local installedConfig = load(pocket["pumpe/config.lua"])()
assert(installedConfig.government_key == "CLIENT-NO-GOVERNMENT-ACCESS",
    "with a config that has no government key")
assert(installedConfig.version == published.version)
assert(pocket["pumpe/installer.lua"]
    and pocket["pumpe/installer.lua"]:find("-- PUMPE EASY DEPLOYMENT", 1, true))

-- Then it reboots: /startup.lua hands over to the installer it was given,
-- which checks with the Bank and starts whatever this computer is.
local launched = {}
shell.run = function(path, ...)
    path = tostring(path):gsub("^/", "")
    if path:find("pumpe%.lua$") or path:find("bank_server%.lua$") then
        launched[#launched + 1] = path
        return true
    end
    local body = disks[current][path]
    assert(body, "the pocket tried to run " .. path .. ", which it does not have")
    local chunk = assert(load(body, "=" .. path))
    local okRun, runErr = pcall(chunk, ...)
    assert(okRun or runErr == "__OUT_OF_EVENTS__" or runErr == "__REBOOT__",
        path .. " failed: " .. tostring(runErr))
    return true
end
events = { { "terminate" } }
assert(load(pocket["startup.lua"], "=startup.lua"))()
assert(#launched == 1 and launched[1] == "pumpe/pumpe.lua",
    "after a reboot the pocket starts the PUMPE: " .. table.concat(launched, ", "))

print = _G.print
io.write("host_easy_deployment_test: OK\n")
