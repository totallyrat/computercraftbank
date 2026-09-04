-- A full CCG Heads or Tails round, rendered on a 1x1 Advanced Monitor
-- (29x19 at text scale 0.5) and again on a large wall.

local WIDTH, HEIGHT = 29, 19
local actions = {}
local requests, labels = {}, {}

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

local monitor = {
    getSize = function() return WIDTH, HEIGHT end,
    setTextScale = function(scale) assert(scale == 0.5) end,
    isColor = function() return true end,
}
term = {
    current = function() return monitor end,
    setBackgroundColor = function() end,
    setTextColor = function() end,
    clear = function() end,
    setCursorPos = function() end,
}
peripheral = {
    getNames = function() return { "left_monitor" } end,
    getType = function(name)
        assert(name == "left_monitor")
        return "monitor"
    end,
    wrap = function(name)
        assert(name == "left_monitor")
        return monitor
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
    getRunningProgram = function() return "/pumpe/ccg.lua" end,
}
sleep = function() end

package.loaded.config = {
    version = "6.0.0",
    currency = "$",
    auto_update = true,
    update_check_seconds = 5,
}
package.loaded["lib.util"] = {
    loadTable = function(_, fallback) return fallback end,
    saveTable = function() end,
    truncate = function(value, maximum)
        return tostring(value or ""):sub(1, maximum)
    end,
    money = function(value, symbol)
        return (symbol or "$") .. tostring(value)
    end,
    formatClock = function() return "12:00" end,
    clamp = function(value, low, high)
        return math.max(low, math.min(high, value))
    end,
}

local baseLobby = {
    lobby_id = "GAME00000001",
    code = "ABC234",
    game = "heads_tails",
    game_name = "Heads or Tails",
    multiplier = 2,
    status = "lobby",
    player_count = 1,
    players = {
        {
            seat = 1,
            display_name = "FoxyPlayer",
            wager = 10,
            selection = "heads",
            ready = true,
        },
    },
}
local client = {
    discover = function() return true end,
    request = function(_, action, payload)
        requests[#requests + 1] = action
        if action == "CCG_REGISTER" then
            return {
                console_id = "CCG000001",
                console_token = "CCG_TOKEN",
                name = "Neon Arena",
            }
        elseif action == "CCG_CONSOLE_STATUS" then
            return nil, "No active lobby"
        elseif action == "CCG_CREATE_LOBBY" then
            assert(payload.game == "heads_tails")
            return { lobby = baseLobby }
        elseif action == "CCG_START" then
            local lobby = {}
            for key, value in pairs(baseLobby) do lobby[key] = value end
            lobby.status = "running"
            lobby.outcome = "heads"
            return { lobby = lobby }
        elseif action == "CCG_TICK" then
            local lobby = {}
            for key, value in pairs(baseLobby) do lobby[key] = value end
            lobby.status = "finished"
            lobby.outcome = "heads"
            return { lobby = lobby }
        end
        error("Unexpected CCG request: " .. tostring(action))
    end,
}
package.loaded["lib.net"] = {
    client = function() return client end,
    autoUpdate = function() end,
    locate = function() return nil end,
}

local function assertBox(label, x, y, width, height)
    assert(x >= 1 and y >= 1, label .. " starts outside the monitor")
    assert(width >= 1 and height >= 1, label .. " has no size")
    assert(x + width - 1 <= WIDTH, label .. " exceeds monitor width")
    assert(y + height - 1 <= HEIGHT, label .. " exceeds monitor height")
end

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
function ui.usePhoneStyle() end
function ui.clear() end
function ui.fill(_, x, y, width, height)
    assertBox("fill", x, y, width, height)
end
function ui.text(_, x, y, value)
    assert(x >= 1 and x <= WIDTH and y >= 1 and y <= HEIGHT)
    assert(#tostring(value or "") <= WIDTH - x + 1)
end
function ui.center(_, y, value)
    assert(y >= 1 and y <= HEIGHT)
    assert(#tostring(value or "") <= WIDTH)
end
function ui.card(_, x, y, width, height)
    assertBox("card", x, y, width, height)
end
function ui.truncate(value, maximum)
    return tostring(value or ""):sub(1, maximum)
end
function ui.input() error("Saved CCG registration should not ask for input") end
function ui.message() end
function ui.networkError(_, err) error(err) end
function ui.scene()
    local scene = {}
    function scene:button(_, x, y, width, height, label)
        assertBox("button", x, y, width, height)
        labels[#labels + 1] = tostring(label or "")
    end
    function scene:wait()
        local action = table.remove(actions, 1)
        assert(action, "CCG requested an unexpected scene action")
        return action
    end
    return scene
end
package.loaded["lib.ui"] = ui

local function contains(items, expected)
    for _, item in ipairs(items) do
        if item == expected then return true end
    end
    return false
end

local console = assert(loadfile("../ccg.lua"))
local function playOneRound(width, height)
    WIDTH, HEIGHT = width, height
    requests, labels = {}, {}
    for _, action in ipairs({ "heads_tails", "start", "again", "close" }) do
        actions[#actions + 1] = action
    end
    console()
    assert(#actions == 0, "the scripted round did not finish")
    assert(contains(requests, "CCG_REGISTER"))
    assert(contains(requests, "CCG_CREATE_LOBBY"))
    assert(contains(requests, "CCG_START"))
    assert(contains(requests, "CCG_TICK"))
    assert(contains(labels, "NEXT GAME"))
end

-- The smallest supported display: every element must stay on screen.
playOneRound(29, 19)
assert(contains(labels, "HEADS OR TAILS // 2X"),
    "a narrow monitor stacks the games in one column")

-- A large wall uses the roomier three-card game picker.
playOneRound(82, 38)
assert(contains(labels, "HEADS OR TAILS\n2X"),
    "a wide monitor shows the games as cards")

print("host_ccg_console_test: OK")
