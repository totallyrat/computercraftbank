-- Notices, FoxyOS 15, drawn by the real lib/ui on a grid.
--
-- A notice used to take the whole screen. It is a banner across the middle
-- now, over whatever was there: it opens from a line drawn out from the
-- centre, and its border and its words are green when something went right
-- and red when it did not. Everything outside it is left as it was.

package.path = "../?.lua;../?/init.lua;" .. package.path
local screen = dofile("screen_harness.lua")

local function check(width, height)
    local display = screen.terminal(width, height)
    local ui = screen.install({ display = display, steps = {}, event = "mouse_click" })
    -- The screen behind it: blue, with a title on top.
    local function behind()
        ui.fill(display, 1, 1, width, height, colors.blue)
        ui.text(display, 2, 1, "HOME SCREEN", colors.white, colors.blue)
    end

    local frames = {}
    local function snapshot()
        local rows = {}
        for y = 1, height do rows[y] = display.count(y, ui.theme.success)
            + display.count(y, ui.theme.danger) end
        frames[#frames + 1] = rows
    end

    -- Success: green.
    behind()
    frames = {}
    local held = 0
    sleep = function(seconds)
        if seconds >= 0.5 then held = held + seconds else snapshot() end
    end
    ui.message(display, "success", "Paid", "Kit Wolf")
    assert(held >= 0.5, "it stays up for a moment")
    assert(display.has("HOME SCREEN") and display.backAt(1, 1) == colors.blue,
        width .. "x" .. height .. ": the screen behind is still there")
    assert(display.backAt(1, math.floor(height / 2)) == colors.blue
        and display.backAt(width, math.floor(height / 2)) == colors.blue,
        "the banner stops short of both edges")
    local top, bottom
    for y = 1, height do
        if display.count(y, ui.theme.success) == width - 2 then
            top = top or y
            bottom = y
        end
    end
    assert(top and bottom and bottom - top + 1 == 6,
        "a border above and below, two lines of words between, a space either side: "
            .. tostring(top) .. "-" .. tostring(bottom))
    assert(math.abs((top - 1) - (height - bottom)) <= 1, "in the middle of the screen")
    for y = top + 1, bottom - 1 do
        assert(display.backAt(2, y) == ui.theme.success
            and display.backAt(width - 1, y) == ui.theme.success, "bordered at the sides")
        assert(display.backAt(5, y) == ui.theme.background, "and plain inside")
    end
    local x, y = display.find("Paid")
    assert(y == top + 2 and display.foreAt(x, y) == ui.theme.success, "the title, in green")
    x, y = display.find("Kit Wolf")
    assert(y == top + 3 and display.foreAt(x, y) == ui.theme.success, "and the rest")
    assert(display.backAt(1, top - 1) == colors.blue and display.count(top - 1,
        colors.blue) == width, "nothing above it is touched")

    -- It opens: first a line in the middle only, then wider and taller.
    local first = frames[1]
    local rowsLit = 0
    for _, lit in ipairs(first) do if lit > 0 then rowsLit = rowsLit + 1 end end
    assert(rowsLit == 1 and first[math.floor((top + bottom) / 2)] > 0
        and first[math.floor((top + bottom) / 2)] < width - 2,
        "it starts as a short line across the middle")
    assert(#frames >= 4, "and opens over a few frames")

    -- Anything else: red, whatever kind.
    for _, kind in ipairs({ "error", "warning", "info" }) do
        behind()
        ui.message(display, kind, "Wrong PIN", "Try again")
        local rx, ry = display.find("Wrong PIN")
        assert(rx and display.foreAt(rx, ry) == ui.theme.danger, kind .. " is red")
        assert(display.count(ry - 2, ui.theme.danger) == width - 2, kind .. ": a red border")
        assert(display.count(ry - 2, ui.theme.success) == 0, "not green")
    end

    -- A long one is wrapped inside it, and never past the screen.
    behind()
    ui.message(display, "error", "That did not go through at all this time",
        string.rep("The Bank did not answer in time. ", 12))
    for row = 1, height do
        assert(display.backAt(1, row) == colors.blue and display.backAt(width, row) == colors.blue,
            "a long notice still leaves the edges")
        local line = display.lines()[row]
        assert(line:sub(2, 3):match("^%s*$") or display.backAt(3, row) ~= ui.theme.background,
            "no words on the border's space")
    end
    assert(display.has("That did not go"), "the title shows")
end

check(26, 20)   -- a Pocket
check(51, 19)   -- a computer

print("host_banner_test: OK")
