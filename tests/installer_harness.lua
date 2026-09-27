-- One computer running Easy Deployment, for tests.
--
-- A disk in memory, a screen that remembers what is on it, GitHub serving
-- this repository's own release, and a script of events: each is either an
-- event or a function that reads the screen and returns one. Nothing on the
-- computer is real, and nothing here touches the host's disk except to read
-- the repository.

local json = require("json_decode")
local harness = {}

local function readRepo(path)
    local handle = io.open("../" .. path, "rb")
    if not handle then return nil end
    local body = handle:read("a")
    handle:close()
    return body
end
harness.readRepo = readRepo
harness.installer = readRepo("startup.lua")
harness.manifest = json.decode(readRepo("release_manifest.json"))

-- Where each published path is downloaded from.
harness.sources = {}
for _, key in ipairs({ "files", "extra_files", "optional_files" }) do
    for _, entry in ipairs(harness.manifest[key] or {}) do
        harness.sources[entry.path] = entry.source or entry.path
    end
end

function harness.published(path)
    return readRepo(harness.sources[path] or path)
end

local function norm(path)
    path = tostring(path or ""):gsub("\\", "/"):gsub("/+", "/")
    return (path:gsub("^/", ""):gsub("/$", ""))
end
harness.norm = norm

local function under(name, dir) return dir == "" or name:sub(1, #dir + 1) == dir .. "/" end

local function serialize(value, indent)
    indent = indent or ""
    if type(value) == "table" then
        local keys, parts = {}, {}
        for key in pairs(value) do keys[#keys + 1] = key end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, key in ipairs(keys) do
            local name = type(key) == "number" and ("[" .. key .. "]")
                or ("[" .. string.format("%q", key) .. "]")
            parts[#parts + 1] = indent .. "  " .. name .. " = "
                .. serialize(value[key], indent .. "  ")
        end
        return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
    elseif type(value) == "string" then
        return string.format("%q", value)
    end
    return tostring(value)
end
harness.serialize = serialize

harness.keys = { enter = 28, numPadEnter = 156, up = 200, down = 208,
    backspace = 14, escape = 1 }

-- Typing, one character at a time, as ComputerCraft sends it.
function harness.typed(text)
    local events = {}
    for character in text:gmatch(".") do events[#events + 1] = { "char", character } end
    return events
end

function harness.key(name) return { "key", harness.keys[name] } end

-- A new computer. `disk` maps paths (no leading slash) to contents.
function harness.computer(options)
    options = options or {}
    return {
        disk = options.disk or {},
        width = options.width or 26,
        height = options.height or 20,
        http = options.http ~= false,
        served = options.served or {},
        free = options.free or 1000 * 1024,
        id = options.id or 7,
        fetched = {},
    }
end

-- The globals a program on the computer sees, as if `running` were the
-- program running, answering events from `script`.
function harness.environment(computer, script, running)
    running = norm(running or "startup.lua")
    script = script or {}
    local disk = computer.disk
    local outcome = { launched = {}, drawn = {}, screens = {} }
    local grid, cursorX, cursorY = {}, 1, 1
    local function blank()
        for y = 1, computer.height do grid[y] = string.rep(" ", computer.width) end
    end
    blank()
    local function lines()
        local copy = {}
        for y = 1, computer.height do copy[y] = grid[y] end
        return copy
    end
    outcome.screen = lines

    local display = {
        getSize = function() return computer.width, computer.height end,
        isColor = function() return true end, isColour = function() return true end,
        setBackgroundColor = function() end, setBackgroundColour = function() end,
        setTextColor = function() end, setTextColour = function() end,
        setCursorBlink = function() end,
        clear = blank,
        clearLine = function() grid[cursorY] = string.rep(" ", computer.width) end,
        getCursorPos = function() return cursorX, cursorY end,
        setCursorPos = function(x, y) cursorX, cursorY = x, y end,
        write = function(text)
            text = tostring(text)
            outcome.drawn[#outcome.drawn + 1] = text
            local row = grid[cursorY]
            if row and cursorX <= computer.width and cursorX + #text - 1 >= 1 then
                local from = math.max(1, cursorX)
                local visible = text:sub(from - cursorX + 1,
                    computer.width - cursorX + 1)
                grid[cursorY] = row:sub(1, from - 1) .. visible
                    .. row:sub(from + #visible)
            end
            cursorX = cursorX + #text
        end,
        scroll = function() end, blit = function() end,
    }

    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.colors = { white = 1, orange = 2, magenta = 4, lightBlue = 8, yellow = 16,
        lime = 32, pink = 64, gray = 128, lightGray = 256, cyan = 512,
        purple = 1024, blue = 2048, brown = 4096, green = 8192, red = 16384,
        black = 32768 }
    env.colours = env.colors
    env.keys = harness.keys
    env.term = { current = function() return display end,
        native = function() return display end, redirect = function() end }
    env.print = function() end
    env.write = function() end
    env.sleep = function() end
    env.rednet = nil
    env.peripheral = nil

    env.fs = {
        combine = function(a, b) return norm(tostring(a) .. "/" .. tostring(b)) end,
        getDir = function(path)
            path = norm(path)
            return path:match("^(.*)/[^/]*$") or ""
        end,
        getName = function(path) return norm(path):match("([^/]*)$") end,
        exists = function(path)
            path = norm(path)
            if path == "" or disk[path] then return true end
            for name in pairs(disk) do if under(name, path) then return true end end
            return false
        end,
        isDir = function(path)
            path = norm(path)
            if path == "" then return true end
            if disk[path] then return false end
            for name in pairs(disk) do if under(name, path) then return true end end
            return false
        end,
        makeDir = function() end,
        list = function(path)
            path = norm(path)
            local out, seen = {}, {}
            for name in pairs(disk) do
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
            disk[path] = nil
            for name in pairs(disk) do if under(name, path) then disk[name] = nil end end
        end,
        move = function(from, to)
            from, to = norm(from), norm(to)
            if env.fs.exists(to) then error("File exists", 2) end
            if not env.fs.exists(from) then error("No such file", 2) end
            if disk[from] then
                disk[to], disk[from] = disk[from], nil
                return
            end
            for name, body in pairs(disk) do
                if under(name, from) then
                    disk[to .. name:sub(#from + 1)], disk[name] = body, nil
                end
            end
        end,
        getSize = function(path) return #(disk[norm(path)] or "") end,
        getFreeSpace = function()
            local used = 0
            for _, body in pairs(disk) do used = used + #body end
            return computer.free - used
        end,
        open = function(path, mode)
            path = norm(path)
            if mode == "r" or mode == "rb" then
                local body = disk[path]
                if not body then return nil end
                return { readAll = function() return body end,
                    close = function() end }
            end
            if path:sub(1, 4) == "rom/" then return nil end
            local parts = {}
            return { write = function(text) parts[#parts + 1] = tostring(text) end,
                writeLine = function(text) parts[#parts + 1] = tostring(text) .. "\n" end,
                flush = function() end,
                close = function() disk[path] = table.concat(parts) end }
        end,
    }

    local base = "https://raw.githubusercontent.com/totallyrat/computercraftbank/main/"
    if computer.http then
        env.http = { get = function(request)
            assert(type(request) == "table" and request.redirect == false,
                "downloads never follow redirects")
            local url = request.url
            assert(url:sub(1, #base) == base, "only the release is fetched: " .. url)
            local source = url:sub(#base + 1):match("^([^?]+)")
            computer.fetched[#computer.fetched + 1] = source
            local body = computer.served[source]
            if body == nil then body = readRepo(source) end
            if body == false or body == nil then return nil, "404 Not Found" end
            local at = 1
            return {
                read = function(count)
                    if at > #body then return nil end
                    local chunk = body:sub(at, at + (count or #body) - 1)
                    at = at + #chunk
                    return chunk
                end,
                close = function() end,
            }
        end }
    end
    env.textutils = {
        serialize = function(value) return serialize(value) end,
        unserializeJSON = function(body)
            local ok, value = pcall(json.decode, body)
            return ok and value or nil
        end,
    }

    local queue, step = {}, 0
    local function nextEvent(filter)
        for index, event in ipairs(queue) do
            if not filter or event[1] == filter then
                table.remove(queue, index)
                return table.unpack(event)
            end
        end
        step = step + 1
        local entry = script[step]
        if entry == nil then error("__OUT_OF_EVENTS__", 0) end
        outcome.screens[#outcome.screens + 1] = lines()
        if type(entry) == "function" then entry = entry(lines(), outcome) end
        return table.unpack(entry)
    end
    local clock = 1000
    env.os = setmetatable({
        epoch = function() clock = clock + 1 return clock end,
        clock = function() return clock / 1000 end,
        day = function() return 3 end,
        getComputerID = function() return computer.id end,
        startTimer = function() return 1 end,
        cancelTimer = function() end,
        queueEvent = function(...) queue[#queue + 1] = { ... } end,
        pullEvent = nextEvent,
        pullEventRaw = function(filter) return nextEvent(filter) end,
        reboot = function() error("__REBOOT__", 0) end,
        shutdown = function() error("__SHUTDOWN__", 0) end,
    }, { __index = os })
    env.shell = {
        getRunningProgram = function() return running end,
        run = function(path, ...)
            outcome.launched[#outcome.launched + 1] = norm(path)
            outcome.launchArgs = { ... }
            return true
        end,
    }
    env.load = function(chunk, name, mode, chunkEnv)
        return load(chunk, name, mode, chunkEnv or env)
    end
    env.loadfile = function(path, mode, chunkEnv)
        local body = disk[norm(path)]
        if not body then return nil, "File not found" end
        return load(body, "=" .. path, mode, chunkEnv or env)
    end
    outcome.env = env
    -- Modules from this repository, loaded on the computer.
    local modules = {}
    env.require = function(name)
        if modules[name] == nil then
            local path = name:gsub("%.", "/") .. ".lua"
            modules[name] = assert(load(assert(readRepo(path), path), "=" .. path,
                "t", env))()
        end
        return modules[name]
    end
    return env, outcome
end

-- Runs a file on the computer (by default its /startup.lua) with `args`,
-- answering its events from `script`. Returns what happened.
function harness.run(computer, script, args, running)
    running = norm(running or "startup.lua")
    local env, outcome = harness.environment(computer, script, running)
    local disk = computer.disk
    local body = assert(disk[running], "nothing at " .. running)
    local chunk = assert(load(body, "=" .. running, "t", env))
    local ok, result = pcall(chunk, table.unpack(args or {}))
    outcome.ok, outcome.result = ok, result
    outcome.rebooted = not ok and result == "__REBOOT__"
    outcome.stopped = ok or result == "__OUT_OF_EVENTS__" or outcome.rebooted
    assert(outcome.stopped, running .. " failed: " .. tostring(result))
    outcome.pullEvent = env.os.pullEvent
    return outcome
end

-- Screen helpers.
function harness.has(screen, text)
    for _, line in ipairs(screen) do
        if line:find(text, 1, true) then return true end
    end
    return false
end

function harness.where(screen, text)
    for y, line in ipairs(screen) do
        local x = line:find(text, 1, true)
        if x then return x, y end
    end
    return nil
end

-- A tap on the text, which must be on the screen.
function harness.tap(text)
    return function(screen)
        local x, y = harness.where(screen, text)
        assert(x, "nothing on the screen says " .. text .. ":\n"
            .. table.concat(screen, "\n"))
        return { "mouse_click", 1, x, y }
    end
end

-- Checks the screen before answering with `event`.
function harness.expect(text, event)
    return function(screen)
        assert(harness.has(screen, text), "the screen should say " .. text .. ":\n"
            .. table.concat(screen, "\n"))
        if type(event) == "function" then return event(screen) end
        return event
    end
end

function harness.concat(...)
    local out = {}
    for _, list in ipairs({ ... }) do
        if type(list) == "function" or type(list[1]) == "string" then
            out[#out + 1] = list
        else
            for _, item in ipairs(list) do out[#out + 1] = item end
        end
    end
    return out
end

return harness
