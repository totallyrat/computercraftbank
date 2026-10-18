-- CCG Home starting up, FoxyOS 17: the real lib/ui on a 1x1 Advanced
-- Monitor, every tap aimed at a button that is really on it.
--
-- Since FoxyOS 17 the console is CCG Home (Home Mode on its own) or a CCG
-- Casino, which has tests of its own. CCG Home needs no server and no Bank:
-- a new one asks for its colour and the owner's Home PIN and goes straight
-- into Home Mode; closing that leaves a menu with Home Mode and Close.

package.path = "../?.lua;../?/init.lua;" .. package.path
local screen = dofile("screen_harness.lua")

local function boot(options)
    local monitor = screen.terminal(options.width or 29, options.height or 19)
    local computer = screen.terminal(51, 19)
    term = { current = function() return computer end, setBackgroundColor = function() end,
        setTextColor = function() end, clear = function() end,
        setCursorPos = function() end }
    peripheral = { getNames = function() return { "top" } end,
        getType = function() return "monitor" end, wrap = function() return monitor end }
    fs = { getDir = function() return "/pumpe" end,
        combine = function(a, b)
            return tostring(a):gsub("/+$", "") .. "/" .. tostring(b):gsub("^/+", "")
        end,
        exists = function(path)
            return options.color ~= nil and tostring(path):find("main_color", 1, true) ~= nil
        end }
    shell = { getRunningProgram = function() return "/pumpe/ccg_home.lua" end }
    os.getComputerID = function() return 5 end
    os.day = function() return 3 end
    os.time = function() return 12 end
    os.epoch = function() return 1000 end
    local hosted = {}
    rednet = { host = function(protocol, name) hosted[protocol] = name end,
        unhost = function(protocol) hosted[protocol] = nil end,
        lookup = function(protocol)
            if protocol == "PUMPE_BANK_V5" then return options.bank end
            return nil
        end }
    -- Home Mode runs a listener beside its screen; here only the screen.
    parallel = { waitForAny = function(_, screenLoop) screenLoop() end }
    local saved = {}
    local util = dofile("../lib/util.lua")
    util.loadTable = function(path, fallback)
        if tostring(path):find("main_color", 1, true) then return options.color or {} end
        return options.device or fallback
    end
    util.saveTable = function(path, value) saved[#saved + 1] = util.copy(value) end
    package.loaded["lib.util"] = util
    local requests = {}
    package.loaded["lib.net"] = {
        client = function()
            local client = {}
            function client:discover()
                self.serverId = options.ccg
                return options.ccg
            end
            function client:request(action, payload)
                requests[#requests + 1] = action
                if not options.ccg then return nil, "Bank server timed out" end
                if action == "CCG_REGISTER" then
                    return { console_id = "CCGC00001", console_token = "T", name = "Arcade" }
                elseif action == "CCG_CONSOLE_STATUS" then
                    return nil, "No active lobby"
                end
                return nil, "unexpected " .. action
            end
            return client
        end,
        autoUpdate = function() end, openModems = function() end, reply = function() end,
    }
    local ui, state = screen.install({ display = monitor, steps = options.steps })
    package.loaded["lib.ui"] = ui
    package.loaded.config = nil
    local ok, err = pcall(assert(loadfile("../ccg_home.lua")))
    assert(ok, err)
    assert(#state.steps == 0, #state.steps .. " scripted steps never used")
    return { monitor = monitor, requests = requests, saved = saved, hosted = hosted }
end

local function has(monitor, text)
    return monitor.has(text)
end
local function pin(...)
    local steps = {}
    for _, digits in ipairs({ ... }) do
        for index = 1, #digits do steps[#steps + 1] = "pin:" .. digits:sub(index, index) end
    end
    return steps
end

-- A new console, nothing on the network ----------------------------------------------

local steps = {}
screen.push(steps, "done", pin("1234", "1234"), pin("1234"), function(state)
    assert(state.display.has("PAIR A POCKET"),
        "straight into Home Mode, behind the new PIN, with a code to pair\n"
        .. state.display.dump())
    local width, height = state.display.getSize()
    return { raw = { "monitor_touch", "top", width - 5, height } }
end, function(state)
    assert(state.display.has("HOME MODE") and state.display.has("CLOSE"),
        "closing Home Mode leaves its menu\n" .. state.display.dump())
    assert(not state.display.has("BET PLAY"), "Bet Play is the CCG Casino's now")
    return "home"
end, pin("1234"), function(state)
    assert(state.display.has("PAIR A POCKET"), "Home Mode again, behind the PIN")
    local width, height = state.display.getSize()
    return { raw = { "monitor_touch", "top", width - 5, height } }
end, "close")
local run = boot({ steps = steps })
local pinSaved
for _, value in ipairs(run.saved) do
    if value.home_pin then pinSaved = value.home_pin end
end
assert(pinSaved, "the Home PIN was set on the monitor")
assert(#run.requests == 0, "and it asked no server for anything")

-- A console that already has its colour and PIN ----------------------------------------

steps = {}
screen.push(steps, pin("1234"), function(state)
    assert(state.display.has("PAIR A POCKET"), state.display.dump())
    local width, height = state.display.getSize()
    return { raw = { "monitor_touch", "top", width - 5, height } }
end, "close")
boot({ steps = steps, color = { color = "blue" },
    device = { name = "Arcade", home_pin = pinSaved, home_best = {} } })

print("host_ccg_start_test: OK")
