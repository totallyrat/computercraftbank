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

local newInstaller = "-- PUMPE EASY DEPLOYMENT\n"
    .. "-- This file is intentionally standalone.\n"
    .. "-- v5.5.0\n"
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
    version = "5.5.0",
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

local ok, err = pcall(assert(loadfile("../startup.lua")))
assert(not ok)
assert(tostring(err):find("__REBOOT__", 1, true))
assert(files["/installer.lua"] == newInstaller)
assert(#responses == 0)

print("host_installer_self_update_test: OK")
