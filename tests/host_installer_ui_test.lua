-- Standalone installer smoke test on an Advanced Pocket Computer-sized screen.

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

local width, height = 26, 20
local cursorX = 1
local display = {
    getSize = function() return width, height end,
    setBackgroundColor = function() end,
    setTextColor = function() end,
    clear = function() end,
    setCursorPos = function(x, y)
        assert(x >= 1 and x <= width)
        assert(y >= 1 and y <= height)
        cursorX = x
    end,
    write = function(value)
        assert(cursorX + #tostring(value) - 1 <= width)
    end,
}

term = { current = function() return display end }
fs = {
    combine = function(left, right)
        return tostring(left):gsub("/+$", "") .. "/" .. tostring(right):gsub("^/+", "")
    end,
}
peripheral = {
    getNames = function() return { "back" } end,
    getType = function() return "modem" end,
}
rednet = {
    isOpen = function() return false end,
    open = function() end,
    lookup = function() return nil end,
}
sleep = function() end
os.getComputerID = function() return 7 end
os.epoch = function() return 123456789 end
local events = {
    { "mouse_click", 1, 5, 13 }, -- Bank Server role
    { "mouse_click", 1, 4, 13 }, -- 4
    { "mouse_click", 1, 11, 17 }, -- 0
    { "mouse_click", 1, 4, 13 }, -- 4
    { "mouse_click", 1, 11, 17 }, -- 0
    { "mouse_click", 1, 1, 20 }, -- Exit after offline-bank message
}
local eventIndex = 0
os.pullEvent = function()
    eventIndex = eventIndex + 1
    assert(events[eventIndex], "installer requested too many events")
    return table.unpack(events[eventIndex])
end

local installer = assert(loadfile("../startup.lua"))
installer()

-- Automatic checks stay quiet when the Bank Server is offline and return to
-- the launcher instead of opening the role picker.
installer("--auto", "service")

print("host_installer_ui_test: OK")
