-- The CCG console starting up, 12.0 Final: the real lib/ui on a 1x1 Advanced
-- Monitor, every tap aimed at a button that is really on it.
--
-- Until 12.0 a console that could not reach its CCG Server said "BANK
-- OFFLINE" -- with a Bank right there -- and stopped: no Home Mode, no Bet
-- Play, no PIN. Now it starts on a menu that needs no server at all, Home
-- Mode is always there, and Bet Play says exactly what it is missing.

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
    shell = { getRunningProgram = function() return "/pumpe/ccg.lua" end }
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
    local ok, err = pcall(assert(loadfile("../ccg.lua")))
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

-- A new console, no CCG Server and no Bank on the network ---------------------------

local steps = {}
screen.push(steps, "done", pin("1234", "1234"), function(state)
    local monitor = state.display
    assert(monitor.has("HOME MODE") and monitor.has("BET PLAY"),
        "it reaches a menu with both modes, with nothing on the network\n" .. monitor.dump())
    assert(monitor.has("CCG SERVER  NOT FOUND") and monitor.has("BANK  NOT FOUND"),
        "and says what it looked for")
    return "bet"
end, function(state)
    assert(state.display.has("No CCG Server answers"),
        "Bet Play says what it is missing, and what to do about it")
    return "ok"
end, "home", pin("1234"), function(state)
    assert(state.display.has("PAIR A PUMPE"), "Home Mode opens, and shows a code")
    local width, height = state.display.getSize()
    return { raw = { "monitor_touch", "top", width - 5, height } }
end, "close")
local run = boot({ steps = steps })
local pinSaved = false
for _, value in ipairs(run.saved) do
    if value.home_pin then pinSaved = true end
end
assert(pinSaved, "the Home PIN was set on the monitor")

-- A console that already has its PIN, next to a Bank and a CCG Server -----------------

steps = {}
screen.push(steps, function(state)
    assert(state.display.has("CCG SERVER  FOUND") and state.display.has("BANK  FOUND"), state.display.dump())
    return "bet"
end, function(state)
    assert(state.display.has("SELECT A GAME"), "signed in, Bet Play shows its games")
    return "back"
end, "close")
run = boot({ steps = steps, ccg = 7, bank = 1, color = { color = "blue" },
    device = { console_id = "CCGC00001", console_token = "T", name = "Arcade",
        home_pin = "anything", home_best = {} } })
assert(run.requests[1] == "CCG_REGISTER", "the console signs in when Bet Play is opened")

-- An arena in Auto Mode with its CCG Server down --------------------------------------
-- It asks nobody for a colour or a PIN, waits for its server, and still
-- offers STOP AUTO with the code it was started with.

local util = dofile("../lib/util.lua")
local hash = util.checksum("ARCADE1")
steps = {}
screen.push(steps, function(state)
    assert(state.display.has("CCG SERVER OFFLINE"),
        "an arena waits for its CCG Server instead of stopping\n" .. state.display.dump())
    return { tick = true }
end, "stop", screen.typed("ARCADE1"), function(state)
    assert(state.display.has("No CCG Server answers"))
    return "ok"
end, "close")
boot({ steps = steps, device = { console_id = "CCGC00001", console_token = "T",
    name = "Arena", home_best = {}, auto = { game = "rotate", hash = hash, index = 0 } } })

print("host_ccg_start_test: OK")
