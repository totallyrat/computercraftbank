-- Advanced Computer flow for a configured Border Controller.

local WIDTH, HEIGHT = 51, 19
local actions = { "check", "done", "stop" }
local requests, drawnText, redstoneStates = {}, {}, {}
local oneSecondSleeps = 0

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

term = {
    current = function()
        return { getSize = function() return WIDTH, HEIGHT end }
    end,
}
fs = {
    getDir = function() return "/pumpe" end,
    combine = function(left, right)
        return tostring(left):gsub("/+$", "") .. "/"
            .. tostring(right):gsub("^/+", "")
    end,
}
shell = {
    getRunningProgram = function() return "/pumpe/border_controller.lua" end,
}
os.getComputerID = function() return 77 end
sleep = function(seconds)
    if seconds == 1 then oneSecondSleeps = oneSecondSleeps + 1 end
end
redstone = {
    setOutput = function(side, enabled)
        assert(side == "back")
        redstoneStates[#redstoneStates + 1] = enabled
    end,
}

package.loaded.config = {
    version = "5.3.0",
    auto_update = true,
    update_check_seconds = 10,
}

package.loaded["lib.util"] = {
    loadTable = function()
        return {
            controller_id = "BORDER000001",
            controller_token = "BORDER_TOKEN",
            territory_id = "TER000001",
            territory_name = "Foxy Republic",
            label = "Border #77",
        }
    end,
    saveTable = function() end,
    formatClock = function() return "12:00" end,
    ingameDay = function() return 42 end,
    truncate = function(value, maximum)
        return tostring(value or ""):sub(1, maximum)
    end,
    page = function(items)
        return items, 1, 1
    end,
}

local client = {
    discover = function() return true end,
    request = function(_, action, payload)
        requests[#requests + 1] = action
        if action == "BORDER_STATUS" then
            assert(payload.controller_id == "BORDER000001")
            assert(payload.controller_token == "BORDER_TOKEN")
            return {
                controller_id = "BORDER000001",
                territory_id = "TER000001",
                territory_name = "Foxy Republic",
                label = "Border #77",
                day = 42,
                time = "12:00",
            }
        elseif action == "BORDER_CHECK" then
            assert(payload.code == "ABCD2345")
            return {
                approved = true,
                traveler_name = "VisitingFriend",
                territory_name = "Foxy Republic",
                authorization = "visa",
                permanent = false,
                stay_days = 6,
                due_day = 47,
                entered_day = 42,
                visiting = true,
            }
        end
        error("Unexpected request: " .. tostring(action))
    end,
}

package.loaded["lib.net"] = {
    client = function() return client end,
    autoUpdate = function() end,
}

local ui = {
    theme = {
        background = colors.black,
        panel = colors.gray,
        ink = colors.white,
        muted = colors.lightGray,
        accent = colors.cyan,
        accentDark = colors.blue,
        success = colors.lime,
        warning = colors.orange,
        danger = colors.red,
        shadow = colors.gray,
    },
}

local function assertBox(label, x, y, width, height)
    assert(x >= 1 and y >= 1, label .. " starts outside the screen")
    assert(width >= 1 and height >= 1, label .. " is empty")
    assert(x + width - 1 <= WIDTH, label .. " exceeds screen width")
    assert(y + height - 1 <= HEIGHT, label .. " exceeds screen height")
end

function ui.clear() end
function ui.boot(_, product, subtitle)
    assert(#product <= WIDTH and #subtitle <= WIDTH)
end
function ui.header(_, title, subtitle)
    assert(#tostring(title or "") <= WIDTH - 3)
    assert(#tostring(subtitle or "") <= WIDTH - 3)
end
function ui.center(_, y, value)
    assert(y >= 1 and y <= HEIGHT)
    assert(#tostring(value or "") <= WIDTH)
    drawnText[#drawnText + 1] = tostring(value or "")
end
function ui.text(_, x, y, value)
    assert(x >= 1 and x <= WIDTH and y >= 1 and y <= HEIGHT)
    assert(#tostring(value or "") <= WIDTH - x + 1)
    drawnText[#drawnText + 1] = tostring(value or "")
end
function ui.truncate(value, maximum)
    return tostring(value or ""):sub(1, maximum)
end
function ui.card(_, x, y, width, height)
    assertBox("card", x, y, width, height)
end
function ui.progress(_, x, y, width)
    assertBox("progress", x, y, width, 1)
end
function ui.input(_, title)
    assert(title == "VISA CODE")
    return "ABCD2345"
end
function ui.pin() return "1234" end
function ui.confirm() return true end
function ui.message(_, _, title, body)
    drawnText[#drawnText + 1] = title
    drawnText[#drawnText + 1] = body
end
function ui.networkError(_, err) error(err) end

function ui.scene()
    local scene = {}
    function scene:button(_, x, y, width, height)
        assertBox("button", x, y, width, height)
    end
    function scene:wait()
        local action = table.remove(actions, 1)
        assert(action, "Border Controller requested an unexpected action")
        return action
    end
    return scene
end

package.loaded["lib.ui"] = ui

assert(loadfile("../border_controller.lua"))()
assert(#actions == 0)
assert(oneSecondSleeps == 5)
assert(redstoneStates[1] == false)
assert(redstoneStates[2] == true)
assert(redstoneStates[3] == false)
assert(redstoneStates[#redstoneStates] == false)

local function contains(items, expected)
    for _, item in ipairs(items) do
        if item == expected then return true end
    end
    return false
end

assert(contains(requests, "BORDER_STATUS"))
assert(contains(requests, "BORDER_CHECK"))
assert(contains(drawnText, "LEAVE BY DAY  47"))

print("host_border_controller_test: OK")
