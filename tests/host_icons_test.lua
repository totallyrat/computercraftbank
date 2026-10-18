-- App icons and Icon Creator, FoxyOS 17.
--
-- An icon is 8x6 pixels, drawn 2x3 to a screen cell with ComputerCraft's
-- block characters -- which have two colours a cell. Every icon FoxyOS ships
-- is drawn so that each 2x3 block has two colours at most, and so shows on
-- the Home Screen exactly as it was painted: this checks that, cell by cell,
-- by reading the drawn character and colours back into pixels.
--
-- Then Icon Creator, on the real lib/ui: a colour tapped, pixels tapped and
-- dragged across, Fill, Done -- and Cancel giving nothing back.

package.path = "../?.lua;../?/init.lua;" .. package.path
local screen = dofile("screen_harness.lua")
os.epoch = os.epoch or function() return 0 end
local util = dofile("../lib/util.lua")
package.loaded["lib.util"] = util

local function read(path)
    local handle = assert(io.open(path, "r"), "cannot read " .. path)
    local body = handle:read("a")
    handle:close()
    return body
end

-- Every icon FoxyOS has ------------------------------------------------------------------

local icons = {}
local SHIPPED = { "foxy", "foxmail", "yap", "foxycloud", "company", "shop", "internet",
    "wc", "invt", "buckapp", "revolution", "brickbreaker" }
for _, name in ipairs(SHIPPED) do
    local icon = util.appIcon(read("../" .. name .. ".lua"))
    assert(icon, name .. ".lua declares no icon")
    icons[name] = icon
end
-- The Pocket's own apps, in its catalogue.
local pumpe = read("../pumpe.lua")
local catalogue = pumpe:match("local APPS = {(.-)\nlocal APP_ORDER")
assert(catalogue, "the Home Screen catalogue was not found")
local builtIn = 0
for id, icon in catalogue:gmatch("\n    (%w+) = { name = .-icon = \"([0-9a-f/]+)\"") do
    assert(util.validIcon(icon), id .. "'s icon is not 8x6")
    icons[id] = icon
    builtIn = builtIn + 1
end
local order = pumpe:match("local APP_ORDER = {(.-)}")
for id in order:gmatch("\"(%w+)\"") do
    assert(icons[id], "the built-in app " .. id .. " has no icon")
end
assert(builtIn == 10, "ten built-in apps, each with an icon: " .. builtIn)

-- Drawn exactly: each cell read back into its six pixels.
local ui = dofile("../lib/ui.lua")
local BITS = { 1, 2, 4, 8, 16 }
for name, icon in pairs(icons) do
    local rows = ui.iconRows(icon)
    for cellY = 0, 1 do
        for cellX = 0, 3 do
            local pixels = {}
            for dy = 1, 3 do
                for dx = 1, 2 do
                    local at = cellX * 2 + dx
                    pixels[#pixels + 1] = rows[cellY * 3 + dy]:sub(at, at)
                end
            end
            local char, fore, back = ui.iconCell(pixels)
            local code = string.byte(char) - 128
            assert(code >= 0 and code < 32, name .. ": not a block character")
            for index = 1, 6 do
                local lit = index < 6 and (code // BITS[index]) % 2 == 1
                local shown = lit and fore or back
                assert(shown == pixels[index], string.format(
                    "%s: cell %d,%d pixel %d shows %s, painted %s", name, cellX + 1,
                    cellY + 1, index, shown, pixels[index]))
            end
        end
    end
end

-- A cell painted in three colours shows its two most common, and draws.
local char, fore, back = ui.iconCell({ "e", "e", "e", "0", "0", "b" })
assert((fore == "e" or back == "e") and (fore == "0" or back == "0"),
    "the two it has most of")
assert(#char == 1)

-- On a screen: the right characters, in the right colours, in the right place.
local terminal = screen.terminal(26, 20)
ui.icon(terminal, 5, 7, icons.foxy)
local chosen, foreAt = ui.iconCell({ "1", "1", "1", "1", "1", "f" })
assert(terminal.backAt(5, 7) ~= nil)
for cellX = 0, 3 do
    for cellY = 0, 1 do
        assert(terminal.backAt(5 + cellX, 7 + cellY), "drawn at " .. cellX .. "," .. cellY)
    end
end
assert(terminal.backAt(4, 7) == colors.black and terminal.backAt(9, 7) == colors.black,
    "and nothing beside it")
assert(chosen and foreAt)

-- The colour down an icon's sides, for padding a wider tile.
assert(ui.iconEdge(icons.foxy) == colors.orange)
assert(ui.iconEdge(icons.ccg) == colors.magenta)

-- Header lines ------------------------------------------------------------------------------

local painted = "eeeeeeee/e000000e/e0eeee0e/e0eeee0e/e000000e/eeeeeeee"
local dev = "-- PUMPE APP: Mine\nreturn function(api) end\n"
local withIcon = util.withIcon(dev, painted)
assert(withIcon:match("^%-%- PUMPE APP: Mine\n%-%- PUMPE APP ICON: "),
    "under the app's own header, where the Pocket reads it")
assert(util.appIcon(withIcon) == painted)
assert(assert(load(withIcon))(), "and the app still runs")
local again = util.withIcon(withIcon, icons.foxy)
assert(util.appIcon(again) == icons.foxy and select(2, again:gsub("PUMPE APP ICON", "")) == 1,
    "painting it again replaces the line")
assert(util.withIcon("return 1", "nope") == "return 1", "a bad icon changes nothing")

-- Icon Creator ------------------------------------------------------------------------------

local function creator(steps, start)
    local display = screen.terminal(26, 20)
    local real, state = screen.install({ display = display, steps = steps })
    local result = real.iconCreator(display, start, "My App")
    assert(#state.steps == 0, #state.steps .. " steps left over")
    return result, display
end
-- Pixel x,y on a 26x20 Pocket: two cells across, two down, from 2,4.
local function at(x, y) return 2 + (x - 1) * 2, 4 + (y - 1) * 2 end

local steps = {}
screen.push(steps, function(state)
    assert(state.display.has("Icon Creator") and state.display.has("Real"),
        "the canvas and the real-size preview\n" .. state.display.dump())
    return "pen:e"
end, "px:1:1", function()
    local x, y = at(2, 1)
    return { raw = { "mouse_drag", 1, x, y } }
end, function()
    local x, y = at(3, 1)
    return { raw = { "mouse_drag", 1, x, y } }
end, "pen:4", "px:8:6", function(state)
    local x, y = at(1, 1)
    assert(state.display.backAt(x, y) == colors.red, "painted red")
    return "done"
end)
local icon = creator(steps)
local rows = ui.iconRows(icon)
assert(util.validIcon(icon))
assert(rows[1] == "eeebbbbb", "one tap and two drags in red: " .. rows[1])
assert(rows[6] == "bbbbbbb4", "a yellow corner: " .. rows[6])

steps = {}
screen.push(steps, "pen:0", "fill", "done")
assert(creator(steps, painted) == "00000000/00000000/00000000/00000000/00000000/00000000",
    "Fill paints every pixel")

steps = {}
screen.push(steps, "px:1:1", "cancel")
assert(creator(steps, painted) == nil, "Cancel gives nothing back")

steps = {}
screen.push(steps, "done")
assert(creator(steps, painted) == painted, "it starts from the icon it was given")

print("host_icons_test: OK")
