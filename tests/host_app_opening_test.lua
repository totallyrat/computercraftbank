-- Opening an app, FoxyOS 13, drawn by the real lib/ui on a 26x20 grid.
--
-- Every app has a motion of its own, in its own colour: the built-in apps
-- and the ones FoxyOS ships each get one nobody else has, and any other app
-- gets one of a set, chosen from its id so it always opens the same way.
-- The motion grows out of the icon that was tapped, ends on the app's
-- colour with its icon and name, and is quick about it.

package.path = "../?.lua;../?/init.lua;" .. package.path
local screen = dofile("screen_harness.lua")
local display = screen.terminal(26, 20)
local ui = screen.install({ display = display, steps = {}, event = "mouse_click" })

local util = dofile("../lib/util.lua")
util.loadTable = function(_, fallback) return fallback end
util.saveTable = function() end
package.loaded["lib.util"] = util
package.loaded["lib.ui"] = ui
package.loaded.config = { version = "13.0.0", currency = "$" }
package.loaded["lib.net"] = { client = function()
    return { request = function() return nil, "offline" end, discover = function() end }
end }
term = { current = function() return display end }
fs = { getDir = function() return "/pumpe" end,
    combine = function(a, b) return tostring(a):gsub("/+$", "") .. "/" .. tostring(b) end,
    exists = function() return false end }
shell = { getRunningProgram = function() return "/pumpe/pumpe.lua" end }

local slept = 0
PUMPE_OPENING_TEST = true
local opening = assert(loadfile("../pumpe.lua"))()
PUMPE_OPENING_TEST = nil
sleep = function(seconds) slept = slept + seconds end

local APPS = {
    friends = { name = "Friends", glyph = "@", color = colors.cyan },
    tickets = { name = "Tickets", glyph = "#", color = colors.orange },
    myid = { name = "MyID", glyph = "I", color = colors.lightBlue },
    ccg = { name = "CCG", glyph = "?", color = colors.magenta },
    subs = { name = "Subs", glyph = "~", color = colors.magenta },
    reminders = { name = "Reminders", glyph = "!", color = colors.yellow },
    quick = { name = "Quick", glyph = "&", color = colors.lime },
    browser = { name = "Apps", glyph = "+", color = colors.blue },
    settings = { name = "Settings", glyph = "*", color = colors.gray },
    ["ext:FOXY"] = { name = "Foxy", glyph = "F", color = colors.orange },
    ["ext:MAIL"] = { name = "FoxMail", glyph = "M", color = colors.purple },
    ["ext:SHOP"] = { name = "Shop", glyph = "S", color = colors.lime },
    ["ext:COMPANY"] = { name = "Company", glyph = "C", color = colors.pink },
    ["ext:NET"] = { name = "Internet", glyph = "N", color = colors.lightBlue },
    ["ext:WC"] = { name = "Website Crafter", glyph = "W", color = colors.yellow },
    ["ext:BUCK"] = { name = "BuckApp", glyph = "B", color = colors.orange },
    ["ext:REVO"] = { name = "Revolution", glyph = "R", color = colors.purple },
}

-- Every one of these opens its own way.
local styles = {}
for id in pairs(APPS) do
    local style = opening.style(id)
    assert(not styles[style], id .. " opens like " .. tostring(styles[style]))
    styles[style] = id
end
-- Any other app gets a shape from the set, the same one every time.
local others = {}
for index = 1, 40 do
    local id = "ext:APP" .. string.format("%05d", index)
    local style = opening.style(id)
    assert(style == opening.style(id), "the same app, the same opening")
    assert(not styles[style], "a third-party app never borrows a built-in's opening")
    others[style] = true
end
local count = 0
for _ in pairs(others) do count = count + 1 end
assert(count >= 4, "third-party apps are spread across the shapes")

-- Played: on screen, from the icon, onto the app's colour, and quick.
local function colourCount(colour)
    local total = 0
    for y = 1, 20 do total = total + display.count(y, colour) end
    return total
end
local firstFrames = {}
for id, app in pairs(APPS) do
    ui.clear(display, colors.black)
    opening.spots = { [id] = { 5, 4 } }
    local frames, snapshot = 0, nil
    sleep = function(seconds)
        slept = slept + seconds
        frames = frames + 1
        if frames == 1 then
            local cells = {}
            for y = 1, 20 do
                for x = 1, 26 do cells[#cells + 1] = tostring(display.backAt(x, y)) end
            end
            snapshot = table.concat(cells, ",")
        end
    end
    slept = 0
    opening.play(id, app)
    assert(slept <= 0.5, id .. " takes " .. slept .. "s to open")
    assert(display.has(app.name:sub(1, 24)) and display.has(app.glyph),
        id .. " ends on its icon and name")
    assert(colourCount(app.color) >= 26 * 20 - 30, id .. " ends on its colour")
    for other, seenSnapshot in pairs(firstFrames) do
        assert(seenSnapshot ~= snapshot, id .. " starts just like " .. other)
    end
    firstFrames[id] = snapshot
end

-- The motion starts where the icon is: the ripple near a corner icon has
-- painted that corner first.
ui.clear(display, colors.black)
opening.spots = { friends = { 2, 2 } }
local frames = 0
sleep = function()
    frames = frames + 1
    if frames == 1 then
        assert(display.backAt(2, 2) ~= colors.black, "it grows out of the icon")
        assert(display.backAt(25, 19) == colors.black, "not out of the far corner")
    end
end
opening.play("friends", APPS.friends)

print("host_app_opening_test: OK")
