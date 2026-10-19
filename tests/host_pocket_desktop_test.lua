-- The Pocket Desktop in the Pocket itself, FoxyOS 18: the real pumpe.lua,
-- lib/desktop and lib/ui on a 51x19 standing computer with a speaker beside
-- it, against a real Bank Core and Vault, five Cloud Servers and a Music
-- Server -- run the way ComputerCraft runs it, with os.pullEvent yielding.
--
-- The desktop shows who is signed in and every app. Settings opens in a
-- window with its tabs down a sidebar, and has the Pocket Desktop switch.
-- The computer's speaker makes the desktop a Music Player of its own --
-- "Ana Fox's Desktop" in the Music app -- so a song picked for it plays
-- right here, its title on the taskbar, and the taskbar pauses it. Start
-- opens the notification centre in a window. And the switch in Settings
-- takes the desktop away again, back to the phone layout.

package.path = "../?.lua;../?/init.lua;" .. package.path
sleep = function() end
require("config").cloud_chunk_size = 6000
local harness = require("bank_pair_harness")
local bank = harness.pair()
local config = require("config")
local net = require("lib.net")

local world = require("cloud_harness").start(harness, bank)
local as = world.as
world.beatAll()
local POCKET, MUSIC_ID = world.pocket, 30

local ana = bank.register("Ana Fox", "1234")
bank.fund(ana, 1000)
local server = world.attach(MUSIC_ID, "music_server.lua", config.music_protocol, "music_server")
local registered = bank.core.actions.MUSIC_SERVER_REGISTER({ code = "4040" }, MUSIC_ID)
server.state.server_token, server.state.server_id = registered.server_token,
    registered.server_id
as(MUSIC_ID, server.background.step)
world.beatAll()
local trot = as(MUSIC_ID, server.library.import, { title = "Fox Trot", artist = "Ana",
    kind = "song", uploader_name = "Foxy Records" }, string.rep("t", 9000))

-- The computer: a 51x19 screen, a modem at the back and a speaker on the left.
local screen = dofile("screen_harness.lua")
local display = screen.terminal(51, 19)
window = dofile("window_stub.lua")
-- A speaker that is full every other time it is given something, as a real
-- one is while it plays: a song takes a few ticks to get through.
local played, full = 0, false
local speaker = { stop = function() end, playAudio = function(samples)
    full = not full
    if full then return false end
    played = played + #samples
    return true
end }
peripheral = {
    getNames = function() return { "back", "left" } end,
    getType = function(name) return ({ back = "modem", left = "speaker" })[name] end,
    wrap = function(name) return ({ left = speaker })[name] end,
    isPresent = function(name) return name == "back" or name == "left" end,
}
package.loaded["cc.audio.dfpwm"] = { make_decoder = function()
    return function(data)
        local samples = {}
        for index = 1, #data do samples[index] = 0 end
        return samples
    end
end }
parallel = { waitForAny = function(first) first() end }

-- ComputerCraft's events: os.pullEventRaw is a yield, and what is queued
-- comes back as an event of its own.
local timers, queued = {}, {}
os.startTimer = function()
    timers[#timers + 1] = #timers + 1
    return #timers
end
os.cancelTimer = function() end
os.queueEvent = function(...) queued[#queued + 1] = table.pack(...) end
os.pullEventRaw = coroutine.yield
os.pullEvent = function(filter)
    local event = table.pack(coroutine.yield(filter))
    if event[1] == "terminate" then error("Terminated", 0) end
    return table.unpack(event, 1, event.n)
end
local current = display
term = {
    current = function() return current end,
    redirect = function(to)
        local before = current
        current = to
        return before
    end,
}
shell = { getRunningProgram = function() return "/pumpe/pumpe.lua" end }
http = nil

local ui = dofile("../lib/ui.lua")
package.loaded["lib.ui"] = ui
PUMPE_DESK_TEST = true
local pocket = as(POCKET, assert(loadfile("../pumpe.lua")))
PUMPE_DESK_TEST = nil
local desk = pocket.desk
assert(desk.fits(), "a standing computer's screen")
assert(as(POCKET, pocket.signIn, "Ana Fox", "1234"), "signed in")
pocket.device.desktop = true
assert(desk.wanted())

local driver = coroutine.create(function() return desk.run() end)
local finished, result
local function send(...)
    local event = table.pack(...)
    while true do
        assert(not finished, "the desktop has already stopped")
        local ok, value = as(POCKET, coroutine.resume, driver, table.unpack(event, 1, event.n))
        assert(ok, value)
        if coroutine.status(driver) == "dead" then finished, result = true, value return end
        event = table.remove(queued, 1)
        if not event then return end
    end
end
local function click(x, y) send("mouse_click", 1, x, y) end
local function at(text)
    local x, y = display.find(text)
    assert(x, "not on the screen: " .. text .. "\n" .. display.dump())
    return x, y
end
local function tap(text) click(at(text)) end
local function tick()
    local due = timers
    timers = {}
    for _, id in ipairs(due) do
        if not finished then send("timer", id) end
    end
end

send()
assert(display.has("Ana Fox  $" .. math.floor(bank.balanceOf(ana))),
    "who is signed in, and their money\n" .. display.dump())
assert(display.has("Settings") and display.has("Friends") and display.has(" Start "),
    display.dump())

-- Settings, in a window: its tabs down the sidebar, and the switch --------------------------------

tap("Settings")
local list = desk.d.windows()
assert(#list == 1 and list[1].id == "settings" and list[1].sidebar, "a window with a sidebar\n"
    .. display.dump() .. #list .. tostring(desk.d.error))
assert(display.has("Pocket Desktop") and display.has("Account"), display.dump())

-- The music: this computer plays it ---------------------------------------------------------------

tick()
local mine
for _, player in pairs(server.state.players) do mine = player end
assert(mine and mine.label == "Ana Fox's Desktop" and mine.computer_id == POCKET,
    "a Music Player of its own, in the Music app")
-- Picked in the Music app, on the Pocket in Ana's hand.
assert(as(POCKET, net.ask, MUSIC_ID, config.music_protocol, "MUSIC_CONTROL",
    { session_token = ana.token, player_id = mine.player_id,
        command = "play", track_id = trot.track_id }, 3))
local onTaskbar = false
for _ = 1, 4 do
    tick()
    if display.lines()[19]:find("Fox Trot", 1, true) then onTaskbar = true break end
end
assert(onTaskbar, "on the taskbar\n" .. display.lines()[19])
for _ = 1, 4 do
    if played > 0 then break end
    tick()
end
assert(played > 0, "through this computer's speaker")
assert(server.state.usage[ana.id].plays == 1, "counted like any song")
-- Paused from the taskbar.
local noteX = at(string.char(14) .. " Fox Trot")
click(noteX + 12, 19)
tick()
assert(mine.paused, "paused at the Music Server")

-- Start: the notification centre, in a window ------------------------------------------------------

click(2, 19)
tap("Notifications")
assert(desk.d.windows()[2].id == "alerts" and display.has("Notifications"), display.dump())

-- Off, from Settings: back to the phone layout ------------------------------------------------------

local settingsX
for column = 1, 51 do
    if display.lines()[19]:sub(column, column + 3) == "Sett" then settingsX = column end
end
assert(settingsX, "Settings on the taskbar\n" .. display.lines()[19])
click(settingsX, 19)
tap("Pocket Desktop")
assert(finished and result == "phone" and pocket.device.desktop == false, tostring(result))
assert(not desk.wanted(), "the phone layout from here on")

io.write("host_pocket_desktop_test: OK\n")
