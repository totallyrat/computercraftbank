-- The first Bank Server in a world installs itself from the public release
-- manifest over HTTPS, with no release package on any drive and no Bank
-- Server to ask. The local package stays as the offline fallback.

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

local function canonical(path)
    path = tostring(path or ""):gsub("/+", "/"):gsub("/$", "")
    if path == "" then return "/" end
    if path:sub(1, 1) ~= "/" then path = "/" .. path end
    return path
end

-- The same DJB2 the installer, the builder and lib/util all use.
local function checksum(body)
    local hash = 5381
    for index = 1, #body do
        hash = (hash * 33 + body:byte(index)) % 4294967296
    end
    return string.format("%08x", hash)
end

local RELEASE = {
    ["bank_server.lua"] = "-- published bank_server\n",
    -- Deliberately older than the running installer, so the self-update check
    -- declines it and this test exercises the Bank install, not a reboot.
    ["startup.lua"] = "-- PUMPE EASY DEPLOYMENT\nlocal INSTALLER_VERSION = \"0.0.1\"\n",
    ["config.lua"] = 'return { version = "9.9.9" }\n',
    ["lib/net.lua"] = "-- published net\n",
    ["lib/ui.lua"] = "-- published ui\n",
    ["lib/update.lua"] = "-- published update\n",
    ["lib/util.lua"] = "-- published util\n",
    -- Depot programs are published too, and must NOT be downloaded here.
    ["pumpe.lua"] = "-- published pumpe\n",
    ["ccg.lua"] = "-- published ccg\n",
    ["service_kiosk.lua"] = "-- published kiosk\n",
    ["event_kiosk.lua"] = "-- published events\n",
    ["tax_controller.lua"] = "-- published tax\n",
    ["launcher.lua"] = "-- published launcher\n",
}

local function manifestJson(corruptChecksumFor)
    local parts = {}
    for _, path in ipairs({ "bank_server.lua", "pumpe.lua", "service_kiosk.lua",
        "event_kiosk.lua", "tax_controller.lua", "startup.lua", "launcher.lua",
        "config.lua", "lib/net.lua", "lib/ui.lua", "lib/update.lua",
        "lib/util.lua" }) do
        local body = RELEASE[path]
        parts[#parts + 1] = ('{"path":"%s","source":"%s","size":%d,"checksum":"%s"}')
            :format(path, path, #body,
                path == corruptChecksumFor and "deadbeef" or checksum(body))
    end
    return ('{"schema":1,"channel":"stable","version":"9.9.9",'
        .. '"notes":"test","files":[%s],"extra_files":[],"optional_files":[]}')
        :format(table.concat(parts, ","))
end

local files, directories, fetched, launched, corrupt
local function reset()
    files, directories = {}, { ["/"] = true }
    fetched, launched, corrupt = {}, nil, nil
end
reset()

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
    list = function() return {} end,
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
            return { readAll = function() return files[path] end,
                close = function() end }
        end
        local chunks = {}
        return { write = function(value) chunks[#chunks + 1] = value end,
            close = function() files[path] = table.concat(chunks) end }
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
    lookup = function() error("an online Bank install must not need a Bank") end,
}
shell = {
    getRunningProgram = function() return "/startup.lua" end,
    run = function(path) launched = canonical(path) return true end,
}
sleep = function() end
os.getComputerID = function() return 3 end
os.epoch = function() return 42 end
os.reboot = function() error("an install must not reboot on its own") end

-- Serves the release over the installer's HTTPS fetch, recording every URL so
-- the test can prove the depot programs are left alone.
local BASE = "https://raw.githubusercontent.com/totallyrat/computercraftbank/main/"
local httpEnabled = true
http = {
    get = function(request)
        if not httpEnabled then return nil, "http disabled" end
        local url = type(request) == "table" and request.url or request
        local path = url:sub(#BASE + 1):gsub("%?.*$", "")
        fetched[#fetched + 1] = path
        local body
        if path == "release_manifest.json" then
            body = manifestJson(corrupt)
        else
            body = RELEASE[path]
        end
        if not body then return nil, "404 " .. path end
        local at = 1
        return { read = function(n)
                if at > #body then return nil end
                local chunk = body:sub(at, at + (n or #body) - 1)
                at = at + #chunk
                return chunk
            end, close = function() end }
    end,
}

-- textutils is only used for the manifest, so a small reader is enough.
textutils = { unserializeJSON = function(body)
    local out = {
        schema = tonumber(body:match('"schema":(%d+)')),
        channel = body:match('"channel":"(.-)"'),
        version = body:match('"version":"(.-)"'),
        notes = body:match('"notes":"(.-)"'),
        files = {},
    }
    local block = body:match('"files":%[(.-)%]')
    for entry in (block or ""):gmatch("{(.-)}") do
        out.files[#out.files + 1] = {
            path = entry:match('"path":"(.-)"'),
            source = entry:match('"source":"(.-)"'),
            size = tonumber(entry:match('"size":(%d+)')),
            checksum = entry:match('"checksum":"(.-)"'),
        }
    end
    return out
end }

local installer = assert(loadfile("../startup.lua"))

-- Down to the other roles, Bank Server, code 4040, then EXIT.
local function run(events)
    local index = 0
    os.pullEvent = function()
        index = index + 1
        assert(events[index], "installer requested an unexpected event")
        return table.unpack(events[index])
    end
    installer()
    assert(index == #events, "the scripted run did not finish")
end

local PICK_BANK = {
    { "char", "m" },
    { "char", "4" },
    { "char", "4" }, { "char", "0" },
    { "char", "4" }, { "char", "0" },
}
local function withExit(extra)
    local script = {}
    for _, event in ipairs(PICK_BANK) do script[#script + 1] = event end
    for _, event in ipairs(extra or {}) do script[#script + 1] = event end
    return script
end

-- 1. A clean computer with nothing but startup.lua installs from the manifest.
run(withExit())
assert(launched == "/pumpe/bank_server.lua",
    "the Bank starts straight after an online install")
for path, body in pairs({
    ["/pumpe/bank_server.lua"] = RELEASE["bank_server.lua"],
    ["/pumpe/installer.lua"] = RELEASE["startup.lua"],
    ["/pumpe/config.lua"] = RELEASE["config.lua"],
    ["/pumpe/lib/net.lua"] = RELEASE["lib/net.lua"],
    ["/pumpe/lib/ui.lua"] = RELEASE["lib/ui.lua"],
    ["/pumpe/lib/update.lua"] = RELEASE["lib/update.lua"],
    ["/pumpe/lib/util.lua"] = RELEASE["lib/util.lua"],
}) do
    assert(files[path] == body, "wrong or missing " .. path)
end
assert(files["/startup.lua"]:find(
    'shell.run("/pumpe/installer.lua", "--boot", "bank")', 1, true),
    "the boot marker points at the Bank role")
assert(files["/pumpe/startup.lua"] == nil,
    "startup.lua is installed as installer.lua, never under its own name")

-- The Bank pulls role programs on demand, so a first install must not drag
-- the whole release down with it.
local downloaded = {}
for _, path in ipairs(fetched) do downloaded[path] = true end
assert(downloaded["release_manifest.json"], "the manifest is read first")
for _, path in ipairs({ "pumpe.lua", "ccg.lua", "service_kiosk.lua",
    "event_kiosk.lua", "tax_controller.lua", "launcher.lua" }) do
    assert(not downloaded[path],
        path .. " must not be downloaded for a Bank install")
end

-- 2. A corrupt published file is refused, and nothing is left installed.
reset()
corrupt = "lib/ui.lua"
-- The refused install drops back to the menu, so this run needs its own EXIT.
run(withExit({ { "mouse_click", 1, 3, 20 } }))
assert(launched == nil, "a failed verification must not start the Bank")
assert(files["/pumpe/bank_server.lua"] == nil,
    "a rolled back install leaves nothing behind")

-- 3. With HTTP switched off it falls back to the local release package, which
-- is how a world with no internet still gets its first Bank.
reset()
httpEnabled = false
directories["/bundle"] = true
for path, body in pairs(RELEASE) do
    files[canonical("/bundle/" .. path)] = body
end
files["/bundle/border_controller.lua"] = "-- published border\n"
shell.getRunningProgram = function() return "/bundle/startup.lua" end
run(withExit())
assert(launched == "/pumpe/bank_server.lua",
    "an offline computer still installs from the local release")
assert(files["/pumpe/bank_server.lua"] == RELEASE["bank_server.lua"])
assert(files["/updates/pumpe.lua"] == RELEASE["pumpe.lua"],
    "the local route still seeds the depot it has on hand")

print("host_installer_bank_online_test: OK")
