-- Easy Deployment updates its own single file before showing or booting a role.

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

local files = {
    ["/installer.lua"] = "-- PUMPE EASY DEPLOYMENT\n-- old\n",
}
local function canonical(path)
    path = tostring(path or ""):gsub("/+", "/")
    if path:sub(1, 1) ~= "/" then path = "/" .. path end
    return path
end

fs = {
    combine = function(left, right)
        return canonical(tostring(left):gsub("/+$", "") .. "/"
            .. tostring(right):gsub("^/+", ""))
    end,
    getDir = function(path)
        return canonical(path):match("^(.*)/[^/]+$") or ""
    end,
    exists = function(path) return files[canonical(path)] ~= nil end,
    isDir = function() return false end,
    makeDir = function() end,
    delete = function(path) files[canonical(path)] = nil end,
    move = function(source, destination)
        source, destination = canonical(source), canonical(destination)
        files[destination] = assert(files[source])
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
shell = {
    getRunningProgram = function() return "/installer.lua" end,
}
sleep = function() end
os.getComputerID = function() return 5 end
os.epoch = function() return 1000 end
os.reboot = function() error("__REBOOT__") end
local queuedEvent, yieldCount
yieldCount = 0
os.queueEvent = function(event) queuedEvent = event end
os.pullEvent = function(filter)
    assert(filter == queuedEvent)
    yieldCount = yieldCount + 1
    return filter
end

local function fakeInstaller(version)
    return "-- PUMPE EASY DEPLOYMENT\n"
        .. "-- This file is intentionally standalone.\n"
        .. 'local INSTALLER_VERSION = "' .. version .. '"\n'
        .. string.rep("-- watchdog regression padding\n", 4000)
end
local newInstaller = fakeInstaller("99.0.0")
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
local manifest = {
    schema = 1,
    channel = "stable",
    version = "99.0.0",
    files = {
        {
            path = "startup.lua",
            source = "startup.lua",
            size = #newInstaller,
            checksum = checksum(newInstaller),
        },
    },
}
textutils = {
    unserializeJSON = function() return manifest end,
}

local responses = { "{}", newInstaller }
http = {
    get = function()
        local body = table.remove(responses, 1)
        local read = false
        return {
            read = function()
                if read then return nil end
                read = true
                return body
            end,
            close = function() end,
        }
    end,
}

local installer = assert(loadfile("../startup.lua"))
local ok, err = pcall(installer)
assert(not ok)
assert(tostring(err):find("__REBOOT__", 1, true))
assert(files["/installer.lua"] == newInstaller)
assert(#responses == 0)
assert(yieldCount >= 50, "standalone installer checksum did not yield")

-- A release published with a stale version stamp must not be installed. The
-- manifest claims something newer, but the file itself does not, and blindly
-- trusting the manifest would reinstall the same bytes and reboot forever.
local staleInstaller = fakeInstaller("0.0.1")
manifest.files[1].size = #staleInstaller
manifest.files[1].checksum = checksum(staleInstaller)
files["/installer.lua"] = "-- PUMPE EASY DEPLOYMENT\nprevious\n"
responses = { "{}", staleInstaller }
local kept = files["/installer.lua"]
local quiet, quietError = pcall(installer)
assert(#responses == 0,
    "the stale release must still be fetched and inspected")
assert(quiet or not tostring(quietError):find("__REBOOT__", 1, true),
    "a stale version stamp must never trigger a reboot")
assert(files["/installer.lua"] == kept,
    "a stale version stamp must not replace the running installer")

print("host_installer_self_update_test: OK")
