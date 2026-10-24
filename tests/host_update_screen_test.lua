-- The FoxyOS 12 update screen, drawn by the real lib/ui on a Pocket-sized
-- screen that remembers colours.
--
-- While a release comes down: FOXY in the middle, blinking, and a thin grey
-- bar along the bottom row, side to side. FoxyOS 18.3.1: every device plays
-- the Pocket's circles instead. When a device asks before installing, the
-- question rises under FOXY: the release, its version, what it is, Install
-- over Cancel & Delete -- and, 18.3.1, how long until it installs itself.

package.path = "../?.lua;../?/init.lua;" .. package.path
local screen = dofile("screen_harness.lua")

local display = screen.terminal(26, 20)
local steps = {}
local ui, state = screen.install({ display = display, steps = steps })
local ORANGE, GREY, BLACK = colors.orange, colors.gray, colors.black

local function orangeRows()
    local rows = {}
    for y = 1, 20 do
        if display.count(y, ORANGE) > 0 then rows[#rows + 1] = y end
    end
    return rows
end

-- Downloading ----------------------------------------------------------------------------

ui.updateFrame(display, 0.5, true, "FoxyOS 12")
local lit = orangeRows()
assert(#lit == 5, "FOXY is five rows tall in the middle: " .. #lit)
assert(display.count(20, GREY) == 13 and display.count(20, BLACK) == 13,
    "half the bottom row is the bar, grey on black")
for y = 1, 19 do
    assert(display.count(y, GREY) == 0, "and nothing else is grey: row " .. y)
end
assert(display.has("FoxyOS 12"), "what is coming down, small")
ui.updateFrame(display, 0.5, false, "FoxyOS 12")
assert(#orangeRows() == 0, "FOXY blinks: off")
ui.updateFrame(display, 1, true)
assert(display.count(20, GREY) == 26, "a full bar reaches side to side")

-- ui.updating: the work runs with the screen up, and the circles go round
-- while it does. A stand-in for parallel runs them between the work's steps.
local realParallel, realSleep = parallel, sleep
sleep = function() coroutine.yield() end
parallel = { waitForAny = function(work, blink)
    local blinker = coroutine.create(blink)
    coroutine.resume(blinker)
    local runner = coroutine.create(work)
    while coroutine.status(runner) ~= "dead" do
        assert(coroutine.resume(runner))
        coroutine.resume(blinker)
    end
end }
local blinked = {}
local a, b = ui.updating(display, function(progress)
    progress(0.25)
    blinked[#blinked + 1] = #orangeRows()
    coroutine.yield()
    blinked[#blinked + 1] = #orangeRows()
    progress(1)
    return true, "12.1.0"
end, "FoxyOS 12")
parallel, sleep = realParallel, realSleep
assert(a == true and b == "12.1.0", "what the work returned comes back")
assert(blinked[1] ~= blinked[2], "the circles moved while it ran")
for y = 1, 20 do
    assert(display.count(y, BLACK) == 26, "and it ends on black, ready for the question")
end

-- The question ---------------------------------------------------------------------------

local function ask(answer)
    screen.push(steps, function()
        assert(display.has("FoxyOS 12") and display.has("Version 12.1.0")
            and display.has("Pocket  290 KiB"), "the release, its version and what it is\n"
            .. display.dump())
        local installY, cancelY
        for y, line in ipairs(display.lines()) do
            if line:find("Install", 1, true) then installY = y end
            if line:find("Cancel & Delete", 1, true) then cancelY = y end
        end
        assert(installY and cancelY and installY < cancelY,
            "Install over Cancel & Delete")
        assert(#orangeRows() >= 5, "under FOXY, which stays")
        return answer
    end)
    return ui.updateReady(display, { title = "FoxyOS 12", version = "12.1.0",
        what = "Pocket  290 KiB" })
end
ui.updateFrame(display, 1, true, "FoxyOS 12")
assert(ask("install") == true, "Install installs")
ui.updateFrame(display, 1, true, "FoxyOS 12")
assert(ask("cancel") == false, "Cancel & Delete does not")
assert(#state.steps == 0)

-- A computer's screen, 51x19, has room for the same.
display = screen.terminal(51, 19)
steps = {}
ui, state = screen.install({ display = display, steps = steps })
ui.updateFrame(display, 0.2, true)
assert(#orangeRows() == 5 and display.count(19, GREY) == 10)
screen.push(steps, "install")
assert(ui.updateReady(display, { title = "FoxyOS 12", version = "12.1.0",
    what = "Service Kiosk" }))

-- FoxyOS 18.3.1: thirty seconds to say no, counted down; then it installs.
screen.push(steps, function()
    assert(display.has("Installing by itself in 30s"), display.dump())
    return "cancel"
end)
assert(ui.updateReady(display, { title = "FoxyOS 18", version = "18.3.1",
    what = "Service Kiosk" }, nil, 30) == false, "Cancel & Delete is still a no")
assert(ui.updateReady(display, { title = "FoxyOS 18", version = "18.3.1",
    what = "Service Kiosk" }, nil, 0) == true, "and nobody answering is a yes")
assert(#state.steps == 0)
-- The banner over a running server, the same.
assert(ui.askUpdate(display, { title = "FoxyOS 18", version = "18.3.1" },
    { banner = true, auto = 0 }) == true, "a banner nobody answers installs too")

print("host_update_screen_test: OK")
