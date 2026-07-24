-- Host-side render smoke test for the three important screen sizes.

package.path = "../?.lua;../?/init.lua;" .. package.path

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

os.day = function() return 1 end
os.time = function() return 12 end
os.epoch = function() return 1 end
os.getComputerID = function() return 1 end

local function mockTerminal(width, height)
    local cursorX, cursorY = 1, 1
    return {
        getSize = function() return width, height end,
        isColor = function() return true end,
        setBackgroundColor = function() end,
        setTextColor = function() end,
        clear = function() end,
        setCursorBlink = function() end,
        setCursorPos = function(x, y)
            assert(x >= 1 and x <= width, "cursor x out of bounds")
            assert(y >= 1 and y <= height, "cursor y out of bounds")
            cursorX, cursorY = x, y
        end,
        write = function(value)
            assert(cursorX + #tostring(value) - 1 <= width,
                "write exceeds screen width")
        end,
    }
end

term = { current = function() return mockTerminal(51, 19) end }

local ui = require("lib.ui")

for _, dimensions in ipairs({ { 26, 20 }, { 51, 19 }, { 29, 12 } }) do
    local display = mockTerminal(dimensions[1], dimensions[2])
    ui.clear(display)
    ui.header(display, "PUMPE TEST", "Responsive screen", "12:00")
    ui.card(display, 2, 5, dimensions[1] - 2, 3, colors.cyan)
    ui.progress(display, 3, 8, dimensions[1] - 4, 5, 10)
    local scene = ui.scene(display)
    scene:button("left", 2, 10, math.floor((dimensions[1] - 3) / 2),
        2, "LEFT")
    scene:button("right", math.floor(dimensions[1] / 2) + 1, 10,
        math.floor((dimensions[1] - 2) / 2), 2, "RIGHT")
    assert(scene:hit(2, 10) == "left")
    assert(scene:hit(math.floor(dimensions[1] / 2) + 1, 10) == "right")
end

-- Regression test: older key maps may not expose keys.escape. The previous
-- PIN screen built a table with a nil key and crashed as soon as Sign In or
-- Create Account opened the pad.
keys = { backspace = 14, enter = 28 }
sleep = function() end
local timerId = 0
os.startTimer = function()
    timerId = timerId + 1
    return timerId
end

local function pinWithEvents(events)
    local index = 0
    os.pullEvent = function()
        index = index + 1
        assert(events[index], "PIN pad requested too many events")
        return table.unpack(events[index])
    end
    return ui.pin(mockTerminal(26, 20), "ACCOUNT PIN", true)
end

assert(pinWithEvents({
    { "char", "1" }, { "char", "2" },
    { "char", "3" }, { "char", "4" },
}) == "1234")

assert(pinWithEvents({
    { "mouse_click", 1, 4, 11 },
    { "mouse_click", 1, 11, 11 },
    { "mouse_click", 1, 18, 11 },
    { "mouse_click", 1, 4, 13 },
}) == "1234")

-- Static pages must wait for a real choice. Previously Scene:wait started an
-- implicit 0.5 second timer, causing confirmations and read-only pages to
-- disappear before their buttons could be read.
os.startTimer = function()
    error("static confirmation unexpectedly started a timer")
end
os.pullEvent = function()
    return "mouse_click", 1, 16, 17
end
assert(ui.confirm(mockTerminal(26, 20), "CONFIRM", "Keep this page open?",
    "YES", "NO") == true)

print("host_ui_test: OK")
