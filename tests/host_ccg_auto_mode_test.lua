-- CCG Auto Mode: start with a code, run rounds hands-free, and refuse to stop
-- without that code. Screen size is a 1x1 Advanced Monitor at text scale 0.5.

local WIDTH, HEIGHT = 29, 19
local requests, labels, messages, saved = {}, {}, {}, {}

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
    getType = function() return "monitor" end,
    wrap = function() return monitor end,
}
fs = {
    getDir = function() return "/pumpe" end,
    combine = function(left, right)
        return tostring(left):gsub("/+$", "") .. "/"
            .. tostring(right):gsub("^/+", "")
    end,
}
shell = { getRunningProgram = function() return "/pumpe/ccg.lua" end }
sleep = function() end

package.loaded.config = {
    version = "6.1.0",
    currency = "$",
    auto_update = true,
    update_check_seconds = 30,
    ccg_auto_start_seconds = 1,
    ccg_auto_next_seconds = 1,
}

local device
package.loaded["lib.util"] = {
    loadTable = function(_, fallback)
        device = fallback
        return fallback
    end,
    saveTable = function(_, value)
        saved[#saved + 1] = value.auto and value.auto.hash or false
    end,
    truncate = function(value, maximum)
        return tostring(value or ""):sub(1, maximum)
    end,
    trim = function(value) return (tostring(value or ""):gsub("^%s*(.-)%s*$", "%1")) end,
    checksum = function(value)
        local hash = 5381
        for index = 1, #tostring(value) do
            hash = (hash * 33 + string.byte(value, index)) % 4294967296
        end
        return string.format("%08x", hash)
    end,
    money = function(value, symbol) return (symbol or "$") .. tostring(value) end,
    formatClock = function() return "12:00" end,
    clamp = function(value, low, high)
        return math.max(low, math.min(high, value))
    end,
}

local lobbyCounter = 0
local function lobbyTemplate(status)
    lobbyCounter = status == "lobby" and lobbyCounter + 1 or lobbyCounter
    return {
        lobby_id = "GAME0000000" .. lobbyCounter,
        code = "AUTO0" .. lobbyCounter,
        game = "heads_tails",
        game_name = "Heads or Tails",
        multiplier = 2,
        status = status,
        outcome = "heads",
        player_count = 1,
        players = {
            {
                seat = 1, display_name = "FoxyPlayer",
                wager = 10, selection = "heads", ready = true,
            },
        },
    }
end

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
            if not payload.code then return nil, "No active lobby" end
            return { lobby = lobbyTemplate("lobby") }
        elseif action == "CCG_CREATE_LOBBY" then
            return { lobby = lobbyTemplate("lobby") }
        elseif action == "CCG_START" then
            return { lobby = lobbyTemplate("running") }
        elseif action == "CCG_TICK" then
            return { lobby = lobbyTemplate("finished") }
        elseif action == "CCG_CANCEL_LOBBY" then
            return { lobby = lobbyTemplate("cancelled") }
        end
        error("Unexpected CCG request: " .. tostring(action))
    end,
}
package.loaded["lib.net"] = {
    client = function() return client end,
    autoUpdate = function() end,
}

-- Scripted operator: start Auto Mode on Heads or Tails, let two rounds run
-- untouched, try to stop with the wrong code, then stop with the right one.
local actions = {
    "auto",                     -- game menu
    "game:heads_tails",         -- Auto Mode setup
    "__tick", "__tick",         -- lobby ticks reach the auto-start countdown
    "__tick",                   -- result screen advances on its own
    "cancel",                   -- STOP AUTO with the wrong code
    "cancel",                   -- STOP AUTO with the right code
    "close",                    -- manual game menu again
}
local codes = { "ARCADE1", "ARCADE1", "NOPE1", "ARCADE1" }

local ui = { theme = {} }
for _, name in ipairs({
    "background", "panel", "panelAlt", "ink", "muted", "accent", "accentDark",
    "success", "warning", "danger", "shadow",
}) do ui.theme[name] = colors.white end
function ui.usePhoneStyle() end
function ui.clear() end
function ui.fill(_, x, y, width, height)
    assert(x >= 1 and y >= 1 and width >= 1 and height >= 1, "fill outside")
    assert(x + width - 1 <= WIDTH and y + height - 1 <= HEIGHT, "fill overflow")
end
function ui.text(_, x, y, value)
    assert(x >= 1 and x <= WIDTH and y >= 1 and y <= HEIGHT, "text outside")
    assert(#tostring(value or "") <= WIDTH - x + 1, "text overflow")
end
function ui.center(_, y, value)
    assert(y >= 1 and y <= HEIGHT, "centered text outside the monitor")
    assert(#tostring(value or "") <= WIDTH)
end
function ui.card(_, x, y, width, height)
    assert(x + width - 1 <= WIDTH and y + height - 1 <= HEIGHT, "card overflow")
end
function ui.truncate(value, maximum)
    return tostring(value or ""):sub(1, maximum)
end
function ui.input()
    local code = table.remove(codes, 1)
    assert(code, "CCG asked for an unexpected code")
    return code
end
function ui.message(_, kind, title) messages[#messages + 1] = title end
function ui.networkError(_, err) error(err) end
function ui.scene()
    local scene = {}
    function scene:button(_, x, y, width, height, label)
        assert(x >= 1 and y >= 1 and width >= 1 and height >= 1,
            "button outside the monitor: " .. tostring(label))
        assert(x + width - 1 <= WIDTH and y + height - 1 <= HEIGHT,
            "button overflows the monitor: " .. tostring(label))
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

assert(loadfile("../ccg.lua"))()
assert(#actions == 0, "the scripted Auto Mode run did not finish")
assert(#codes == 0, "not every scripted code was used")

local function count(items, expected)
    local total = 0
    for _, item in ipairs(items) do
        if item == expected then total = total + 1 end
    end
    return total
end

-- Auto Mode started the round itself: no operator pressed START.
assert(count(requests, "CCG_START") == 1, "Auto Mode must start the game")
assert(count(requests, "CCG_CREATE_LOBBY") == 2,
    "Auto Mode must open the next lobby after a result")
assert(count(requests, "CCG_CANCEL_LOBBY") == 1,
    "stopping Auto Mode closes the open lobby")

-- The wrong code leaves Auto Mode running; the right one turns it off.
assert(count(messages, "WRONG CODE") == 1, "a wrong stop code must be refused")
assert(count(messages, "AUTO MODE OFF") == 1, "the right code must stop it")
local savedHash = false
for _, entry in ipairs(saved) do savedHash = savedHash or entry end
assert(savedHash and savedHash ~= false,
    "Auto Mode must be saved so a reboot resumes it")
assert(saved[#saved] == false, "stopping Auto Mode must clear the saved state")
assert(device.auto == nil, "the device file must not keep a stopped Auto Mode")

local function contains(items, expected)
    for _, item in ipairs(items) do
        if item == expected then return true end
    end
    return false
end
assert(contains(labels, "AUTO MODE // NON-STOP"))
assert(contains(labels, "STOP AUTO"))
assert(contains(labels, "ROTATE ALL GAMES"))

-- A console that reboots (an automatic update, a chunk reload, a server
-- restart) must come back straight into Auto Mode instead of the game menu.
local resumeHash = package.loaded["lib.util"].checksum("ARCADE1")
local resumed = {
    console_id = "CCG000001",
    console_token = "CCG_TOKEN",
    name = "Neon Arena",
    auto = { game = "rotate", hash = resumeHash, index = 0 },
}
package.loaded["lib.util"].loadTable = function() return resumed end
requests, labels, messages = {}, {}, {}
for _, item in ipairs({
    "__tick", "__tick",     -- first rotated game starts itself
    "__tick",               -- result rolls straight into the next lobby
    "__tick", "__tick",     -- second rotated game starts itself
    "__tick",
    "cancel",               -- stop Auto Mode with the saved code
    "close",
}) do actions[#actions + 1] = item end
codes[#codes + 1] = "ARCADE1"

assert(loadfile("../ccg.lua"))()
assert(#actions == 0, "the resumed Auto Mode run did not finish")
assert(requests[3] == "CCG_CREATE_LOBBY",
    "a resumed console opens a lobby without showing the game menu first")
assert(count(requests, "CCG_START") == 2, "both rotated rounds must start")
assert(count(requests, "CCG_CREATE_LOBBY") == 3,
    "Auto Mode keeps opening lobbies until it is stopped")
assert(count(labels, "AUTO MODE // NON-STOP") == 1,
    "the game menu only returns once Auto Mode has been stopped")
assert(resumed.auto == nil, "stopping clears the resumed Auto Mode")

-- A Bank outage must park Auto Mode on a visible standby screen that still
-- offers STOP AUTO, rather than spinning on a failing request.
local failCreates = 1
local baseRequest = client.request
client.request = function(self, action, payload)
    if action == "CCG_CREATE_LOBBY" and failCreates > 0 then
        failCreates = failCreates - 1
        requests[#requests + 1] = action
        return nil, "Bank server is offline"
    end
    return baseRequest(self, action, payload)
end
package.loaded["lib.util"].loadTable = function()
    return {
        console_id = "CCG000001",
        console_token = "CCG_TOKEN",
        name = "Neon Arena",
        auto = { game = "heads_tails", hash = resumeHash },
    }
end
requests, labels, messages = {}, {}, {}
for _, item in ipairs({
    "__tick",               -- standby screen retries
    "__tick", "__tick",     -- the retried lobby starts itself
    "__tick",               -- result rolls on
    "cancel",               -- stop Auto Mode
    "close",
}) do actions[#actions + 1] = item end
codes[#codes + 1] = "ARCADE1"

assert(loadfile("../ccg.lua"))()
assert(#actions == 0, "the standby run did not finish")
assert(contains(labels, "STOP AUTO"),
    "the standby screen must still offer a way out of Auto Mode")
assert(count(requests, "CCG_CREATE_LOBBY") == 3,
    "Auto Mode retries the lobby after the Bank comes back")
assert(count(requests, "CCG_START") == 1,
    "the retried lobby still starts on its own")

print("host_ccg_auto_mode_test: OK")
