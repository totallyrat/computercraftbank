-- Standalone installer smoke test on an Advanced Pocket Computer-sized screen.

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

local width, height = 26, 20
local cursorX = 1
local written = {}
local events, eventIndex
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
        written[#written + 1] = tostring(value)
    end,
}

term = { current = function() return display end }
fs = {
    getDir = function() return "" end,
    combine = function(left, right)
        return tostring(left):gsub("/+$", "") .. "/" .. tostring(right):gsub("^/+", "")
    end,
    exists = function() return false end,
    isDir = function() return false end,
}
shell = {
    getRunningProgram = function() return "../startup.lua" end,
    run = function() error("Missing local Bank files must not start a role") end,
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
os.pullEvent = function()
    eventIndex = eventIndex + 1
    assert(events[eventIndex], "installer requested too many events")
    return table.unpack(events[eventIndex])
end

local installer = assert(loadfile("../startup.lua"))

-- Pick the protected Bank Server entry, enter 4040, and confirm a computer
-- with no local release says so instead of starting anything. Every write is
-- bounds checked, so the layout cannot run off either screen.
local function pickBankServer(screenWidth, screenHeight, script)
    width, height = screenWidth, screenHeight
    written, eventIndex = {}, 0
    events = script
    installer()
    assert(eventIndex == #events, "the scripted run did not finish")
    local screen = table.concat(written, "\n")
    assert(screen:find("PROTECTED DOWNLOAD", 1, true),
        "the Bank Server entry must ask for the protected download code")
    assert(screen:find("LOCAL BANK FILES MISSING", 1, true),
        "a Bank without local release files must say so")
    assert(screen:find("Nothing installed yet", 1, true),
        "an unassigned computer must report that no role is installed")
    -- 8.0: the update check runs before anything is drawn, the PUMPE gets a
    -- panel to itself, and the down arrow is the way to the other roles.
    assert(screen:find("CHECKING FOR UPDATES", 1, true),
        "Easy Deployment checks itself before the menu opens")
    assert(screen:find("PERSONAL PUMPE", 1, true),
        "the PUMPE gets a full screen of its own")
    assert(screen:find("INSTALL PUMPE", 1, true),
        "the PUMPE panel installs straight from its own button")
    assert(screen:find("OTHER ROLES", 1, true),
        "the down arrow leads to every other role")
end

-- Pocket-sized screen: the PUMPE panel first, then one column of roles.
pickBankServer(26, 20, {
    { "mouse_click", 1, 3, 19 }, -- v OTHER ROLES
    { "mouse_click", 1, 5, 11 }, -- Bank Server, fourth row
    { "mouse_click", 1, 4, 13 }, -- 4
    { "mouse_click", 1, 11, 17 }, -- 0
    { "mouse_click", 1, 4, 13 }, -- 4
    { "mouse_click", 1, 11, 17 }, -- 0
    { "mouse_click", 1, 2, 20 }, -- EXIT, back on the PUMPE panel
})

-- Advanced Computer: two columns of role cards with room for the detail line.
pickBankServer(51, 19, {
    { "mouse_click", 1, 3, 18 }, -- v OTHER ROLES
    { "mouse_click", 1, 30, 9 }, -- Bank Server, right column, second row
    { "mouse_click", 1, 12, 12 }, -- 4
    { "mouse_click", 1, 22, 16 }, -- 0
    { "mouse_click", 1, 12, 12 }, -- 4
    { "mouse_click", 1, 22, 16 }, -- 0
    { "mouse_click", 1, 2, 19 }, -- EXIT, back on the PUMPE panel
})

-- Automatic checks stay quiet when the Bank Server is offline and return to
-- the direct role boot instead of opening the role picker.
width, height = 26, 20
events, eventIndex = {}, 0
installer("--auto", "service")

print("host_installer_ui_test: OK")
