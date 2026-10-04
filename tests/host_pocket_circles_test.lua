-- The Pocket's circles, FoxyOS 14, drawn by the real lib/ui on a 26x20 grid.
--
-- Starting: the theme colour opens from the middle until it covers the
-- screen, then black opens over it the same way, three times; POCKET lands
-- on black, then "Powered by FoxyOS" and the version. Updating plays the
-- same circles, and installing plays them for fifteen seconds.

package.path = "../?.lua;../?/init.lua;" .. package.path
local screen = dofile("screen_harness.lua")
local display = screen.terminal(26, 20)
local ui = screen.install({ display = display, steps = {}, event = "mouse_click" })
ui.setMainColor("orange")
local accent = ui.theme.accent

local function everywhere(colour)
    for y = 1, 20 do
        if display.count(y, colour) ~= 26 then return false end
    end
    return true
end

-- One circle: the middle first, the corners last, all of it in the end.
ui.clear(display, colors.black)
local frames = {}
sleep = function()
    frames[#frames + 1] = { middle = display.backAt(13, 10),
        corner = display.backAt(1, 1) }
end
ui.circleWipe(display, accent)
assert(#frames == ui.CIRCLE_FRAMES)
assert(frames[1].middle == accent and frames[1].corner == colors.black,
    "it opens from the middle")
assert(everywhere(accent), "and covers the whole screen")

-- Starting: three rounds, colour then black, then POCKET, then FoxyOS.
ui.clear(display, colors.black)
local ends, seen, slept = {}, {}, 0
local count = 0
sleep = function(seconds)
    slept = slept + seconds
    count = count + 1
    if count % ui.CIRCLE_FRAMES == 0 and #ends < 6 then
        ends[#ends + 1] = everywhere(accent) and "colour"
            or everywhere(colors.black) and "black" or "partly"
    end
    if count > 6 * ui.CIRCLE_FRAMES then
        local lit = 0
        for y = 1, 20 do lit = lit + display.count(y, accent) end
        seen[#seen + 1] = { text = display.dump(), lit = lit }
    end
end
ui.pocketStart(display, "14.0.0")
assert(table.concat(ends, ",") == "colour,black,colour,black,colour,black",
    "three rounds of colour, then black: " .. table.concat(ends, ","))
-- POCKET is drawn in big letters of the theme colour on black: some of the
-- screen lit, most of it not.
assert(seen[1].lit > 40 and seen[1].lit < 26 * 20 / 2, "POCKET lands, on black")
assert(seen[2].text:find("Powered by FoxyOS 14.0.0", 1, true),
    "then what it runs on:\n" .. seen[2].text)
assert(seen[2].lit == 0, "on black")
assert(slept < 6, "and it does not keep the phone waiting: " .. slept .. "s")

-- Installing: fifteen seconds of circles, the bar full at the end.
slept = 0
sleep = function(seconds) slept = slept + seconds end
ui.pocketInstalling(display, 15)
assert(slept >= 15 and slept < 15.8, "fifteen seconds: " .. slept)
assert(display.count(20, ui.theme.panel) == 26, "the bar along the bottom is full")

-- Downloading: whatever the download returns comes back.
local a, b = ui.pocketUpdating(display, function(progress)
    progress(0.5)
    return "done", 2
end)
assert(a == "done" and b == 2)

-- The question is asked under POCKET.
local asked = screen.install({ display = display, event = "mouse_click",
    steps = { "install" } })
assert(asked.updateReady(display, { word = "POCKET", title = "FoxyOS 14",
    version = "14.0.0", what = "For this Pocket" }) == true)
assert(display.has("FoxyOS 14") and display.has("Version 14.0.0"))

print("host_pocket_circles_test: OK")
