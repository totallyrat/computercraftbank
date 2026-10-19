-- The interactive guide and the app pop-up, FoxyOS 18: the real pumpe.lua and
-- lib/ui on a Pocket's 26x20 screen, against a real Bank Core and Vault, run
-- the way ComputerCraft runs it.
--
-- The guide is the Home Screen itself. Each step lights up one thing and
-- waits for a tap on exactly that: anything else is left alone. It turns a
-- page and back, opens Search, passes over Foxy (not on this Pocket), opens
-- the dock's picker, and ends on Locking with Done. Skip ends it early, and
-- How Pocket Works in Settings starts it again. And an app just downloaded
-- pops up where it lands: a dot, growing, a little too big, then itself.

package.path = "../?.lua;../?/init.lua;" .. package.path
local harness = require("bank_pair_harness")
local bank = harness.pair()
local world = require("cloud_harness").start(harness, bank)
local as = world.as
local POCKET = world.pocket
local ana = bank.register("Ana Fox", "1234")

local screen = dofile("screen_harness.lua")
local display = screen.terminal(26, 20)
pocket = {}
window = nil
peripheral = { getNames = function() return { "back" } end,
    getType = function() return "modem" end, wrap = function() return nil end,
    isPresent = function() return true end }
local slept = {}
sleep = function(seconds) slept[#slept + 1] = seconds end

local timers = {}
os.startTimer = function()
    timers[#timers + 1] = #timers + 1
    return #timers
end
os.cancelTimer = function() end
os.queueEvent = function() end
os.pullEventRaw = coroutine.yield
os.pullEvent = function(filter)
    local event = table.pack(coroutine.yield(filter))
    if event[1] == "terminate" then error("Terminated", 0) end
    return table.unpack(event, 1, event.n)
end
term = { current = function() return display end, redirect = function() return display end }
shell = { getRunningProgram = function() return "/pumpe/pumpe.lua" end }

local ui = dofile("../lib/ui.lua")
package.loaded["lib.ui"] = ui
PUMPE_DESK_TEST = true
local phone = as(POCKET, assert(loadfile("../pumpe.lua")))
PUMPE_DESK_TEST = nil
assert(not phone.desk.fits(), "a Pocket is a Pocket")
assert(as(POCKET, phone.signIn, "Ana Fox", "1234"))
phone.device.favorites = { "friends" }
local guide = phone.guide

local driver = coroutine.create(function() return phone.mainMenu() end)
local function send(...)
    local ok, err = as(POCKET, coroutine.resume, driver, ...)
    assert(ok, err)
end
local function at(text, row)
    for y, line in ipairs(display.lines()) do
        local x = line:find(text, 1, true)
        if x and (not row or row == y) then return x, y end
    end
    error("not on the screen: " .. text .. "\n" .. display.dump(), 0)
end
local function tap(text, row)
    local x, y = at(text, row)
    send("mouse_click", 1, x, y)
end
local function step() return guide.active and guide.tour[guide.active].id end
local function tick()
    local due = timers
    timers = {}
    for _, id in ipairs(due) do send("timer", id) end
end

guide.active = 1
send()
assert(display.has("Pages 1/6") and display.has("Skip"), display.dump())

-- Anything but the thing lit up is left alone.
tap("Subs")
assert(step() == "next" and display.has("Pages 1/6"), "Subs did not open")

-- A page on, and back.
tap(">", 19)
assert(step() == "prev" and display.has("Notifications 2/6"), display.dump())
tap("<", 19)
assert(step() == "search" and display.has("Search 3/6"), display.dump())

-- Search, then home again. Foxy is not on this Pocket: that step is passed over.
tap("Search everything")
assert(display.has("Apps, actions, settings"), "Search is open\n" .. display.dump())
tap("CANCEL")
assert(step() == "edit" and display.has("Your dock 5/6"), display.dump())

-- The dock's picker: its own screen, then back.
local plus = select(1, at("+", 17))
local arrow = display.lines()[8]:find("v", 3, true)
assert(arrow and math.abs(arrow - plus) <= 1, "the bubble points at it\n" .. display.dump())
assert(display.has("Search everything"), "and draws over nothing else")
send("mouse_click", 1, plus, 17)
assert(not display.has("Your dock 5/6"), "the picker is open\n" .. display.dump())
tap("< Done")
assert(step() == "lock" and display.has("Locking 6/6") and display.has("Done"),
    display.dump())
tap("Done")
assert(guide.active == nil and not display.has("Skip"), "the guide is over")

-- Skip ends it early.
guide.active = 1
tick()
assert(display.has("Pages 1/6"), display.dump())
tap("Skip")
assert(guide.active == nil, "skipped")

-- An app just downloaded pops up where it lands.
slept = {}
phone.opening.pop = "settings"
tick()
local frames = 0
for _, seconds in ipairs(slept) do
    if seconds == 0.07 then frames = frames + 1 end
end
assert(frames == 4, "a dot, a bar, the width, a little too big: " .. frames)
assert(display.has("Settings") and phone.opening.pop == nil, "then itself, once")

io.write("host_pocket_guide_test: OK\n")
