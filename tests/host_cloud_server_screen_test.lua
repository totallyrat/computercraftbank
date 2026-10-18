-- A Cloud Server starting up for real, FoxyOS 16.3: the real lib/ui on a
-- computer's own 51x19 screen, every tap aimed at a button that is really on
-- it. A wrong operator code, then the right one, then its dashboard -- which
-- says which server it is and that the Bank is answering -- and STOP.

package.path = "../?.lua;../?/init.lua;" .. package.path
local screen = dofile("screen_harness.lua")

local computer = screen.terminal(51, 19)
term = { current = function() return computer end, setBackgroundColor = function() end,
    setTextColor = function() end, clear = function() end,
    setCursorPos = function() end }
peripheral = { getNames = function() return {} end, getType = function() return nil end }
local disk = {}
fs = {
    getDir = function() return "/pumpe" end,
    combine = function(a, b)
        return tostring(a):gsub("/+$", "") .. "/" .. tostring(b):gsub("^/+", "")
    end,
    exists = function(path) return disk[path] ~= nil end,
    makeDir = function(path) disk[path] = "dir" end,
    list = function() return {} end,
    getSize = function() return 0 end,
    getFreeSpace = function() return 700000 end,
}
shell = { getRunningProgram = function() return "/pumpe/cloud_server.lua" end }
os.getComputerID = function() return 21 end
os.day = function() return 3 end
os.time = function() return 12 end
os.epoch = function() return 1000 end
local hosted = {}
rednet = { host = function(protocol, name) hosted[protocol] = name end,
    unhost = function(protocol) hosted[protocol] = nil end,
    receive = function() return nil end }
-- Only the dashboard: the network loops would wait forever here.
parallel = { waitForAny = function(...)
    local loops = { ... }
    loops[#loops]()
end }

local util = dofile("../lib/util.lua")
local saved = {}
util.loadTable = function(_, fallback) return fallback end
util.saveTable = function(_, value) saved[#saved + 1] = util.copy(value) end
package.loaded["lib.util"] = util
local requests = {}
package.loaded["lib.net"] = {
    client = function()
        local client = {}
        function client:discover()
            self.serverId = 1
            return 1
        end
        function client:request(action, payload)
            requests[#requests + 1] = action
            if action == "CLOUD_SERVER_REGISTER" then
                if payload.code ~= "4040" then
                    return nil, "That is not the operator code", "BAD_CODE"
                end
                assert(payload.name == "Cloud 21")
                return { server_id = "CS3", server_token = "CLOUD_T" }
            elseif action == "CLOUD_BEAT" then
                -- What it has, less the room it keeps to update itself.
                assert(payload.server_token == "CLOUD_T" and payload.free < 700000
                    and payload.free > 600000, tostring(payload.free))
                return { server_id = "CS3", name = "Cloud 21", drop = {} }
            end
            return nil, "unexpected " .. action
        end
        return client
    end,
    autoUpdate = function() end, openModems = function() end, reply = function() end,
    host = function(protocol, name) hosted.ever = { protocol, name } end,
}

local function digits(text)
    local steps = {}
    for index = 1, #text do steps[#steps + 1] = "key:" .. text:sub(index, index) end
    return steps
end

local steps = {}
screen.push(steps, function(state)
    assert(state.display.has("OPERATOR CODE"), "it asks for the code first\n"
        .. state.display.dump())
    return "key:1"
end, digits("111"), "ok", { tick = true }, function(state)
    assert(state.display.has("OPERATOR CODE"), "a wrong code is refused and asked again")
    return "key:4"
end, digits("040"), "ok", function(state)
    local display = state.display
    assert(display.has("CLOUD SERVER"), "the dashboard\n" .. display.dump())
    assert(display.has("PIECES") and display.has("FREE"), "with its disk")
    assert(display.has("SERVER  CS3") and display.has("Cloud 21"), "which server it is")
    assert(display.has("BANK  OK at"), "and that the Bank answers")
    return "tab:server"
end, "stop", function(state)
    assert(state.display.has("STOP CLOUD SERVER"))
    return "yes"
end)

local ui, state = screen.install({ display = computer, steps = steps })
local stoppedSaying
print = function(text) stoppedSaying = text end
package.loaded["lib.ui"] = ui
package.loaded.config = nil
local ok, err = pcall(assert(loadfile("../cloud_server.lua")))
assert(ok, err)
assert(#state.steps == 0, #state.steps .. " scripted steps never used")
assert(requests[1] == "CLOUD_SERVER_REGISTER" and requests[2] == "CLOUD_SERVER_REGISTER")
assert(requests[3] == "CLOUD_BEAT", "it tells the Bank it is up straight away")
assert(hosted.ever[1] == require("config").cloud_protocol
    and hosted.ever[2] == "CLOUD_21", "it is on the network under its own name")
assert(hosted[hosted.ever[1]] == nil, "and off it once stopped")
local last = saved[#saved]
assert(last.server_token == "CLOUD_T" and last.server_id == "CS3",
    "and remembers its registration")
assert(stoppedSaying == "Cloud Server stopped safely.", tostring(stoppedSaying))

io.write("host_cloud_server_screen_test: OK\n")
