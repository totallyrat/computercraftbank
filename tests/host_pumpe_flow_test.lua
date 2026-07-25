-- Host-side flow smoke test for the focused PUMPE 5.2 experience.

local actions = {
    "next",
    "next",
    "create",
    "gender:They / them",
    "pay",
    "back",
    "exit",
}
local buttonLabels, drawnText, requests = {}, {}, {}
local savedDevice
local lockSeconds

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

term = {
    current = function()
        return {
            getSize = function() return 26, 20 end,
        }
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
    getRunningProgram = function() return "/pumpe/pumpe.lua" end,
}
sleep = function() end

local account = {
    account_id = "ACC000001",
    name = "FoxyUser",
    balance = 500,
    personal_number = "12345",
    daily_sent = 0,
}

package.loaded.config = {
    version = "5.2.0",
    currency = "$",
    send_money_daily_limit = 2000,
    send_money_fee_rate = 0.10,
    pumpe_lock_seconds = 60,
    pumpe_pin_seconds = 120,
    proximity_update_seconds = 2,
    max_ticket_quantity = 5,
}

package.loaded["lib.util"] = {
    loadTable = function(_, fallback) return fallback end,
    saveTable = function(_, value)
        savedDevice = {}
        for key, item in pairs(value) do savedDevice[key] = item end
    end,
    money = function(value, symbol)
        return (symbol or "$") .. tostring(value)
    end,
    formatClock = function() return "12:00" end,
    ingameDay = function() return 42 end,
}

local client = {
    discover = function() return true end,
    request = function(_, action, payload)
        requests[#requests + 1] = action
        if action == "REGISTER" then
            assert(payload.name == "FoxyUser")
            assert(payload.pin == "1234")
            return { account = account, session_token = "SESSION" }
        elseif action == "ACCOUNT_SUMMARY" then
            return {
                account = account,
                unread_notifications = 0,
                pending_requests = 0,
            }
        end
        return { ok = true }
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
        panelAlt = colors.lightGray,
        ink = colors.white,
        muted = colors.lightGray,
        accent = colors.cyan,
        accentDark = colors.blue,
        success = colors.lime,
        danger = colors.red,
        warning = colors.orange,
        shadow = colors.gray,
    },
}

local function remember(value)
    drawnText[#drawnText + 1] = tostring(value or "")
end

function ui.usePhoneStyle() end
function ui.noteActivity() end
function ui.idleForMs() return 0 end
function ui.setIdleLock(seconds)
    lockSeconds = seconds
end
function ui.clear() end
function ui.fill() end
function ui.card() end
function ui.progress() end
function ui.wipe() end
function ui.boot() end
function ui.networkError(_, err) error(err) end
function ui.header(_, title, subtitle)
    remember(title)
    remember(subtitle)
end
function ui.center(_, _, value) remember(value) end
function ui.text(_, _, _, value) remember(value) end
function ui.truncate(value, maximum)
    value = tostring(value or "")
    return value:sub(1, maximum)
end
function ui.input(_, title)
    if title == "Create Foxy Account" then return "FoxyUser" end
    error("Unexpected input screen: " .. tostring(title))
end
function ui.pin() return "1234" end
function ui.confirm() return true end
function ui.message(_, _, title, body)
    remember(title)
    remember(body)
end

function ui.scene()
    local scene = { width = 26, height = 20 }
    function scene:button(_, _, _, _, _, label)
        buttonLabels[#buttonLabels + 1] = tostring(label or "")
    end
    function scene:wait()
        local action = table.remove(actions, 1)
        assert(action, "PUMPE requested an unexpected scene action")
        return action
    end
    return scene
end

package.loaded["lib.ui"] = ui

assert(loadfile("../pumpe.lua"))()

assert(#actions == 0)
assert(savedDevice and savedDevice.onboarding_complete == true)
assert(savedDevice.last_name == "FoxyUser")
assert(lockSeconds == 60)

local function find(items, expected)
    for index, value in ipairs(items) do
        if value == expected then return index end
    end
end

assert(find(drawnText, "Setting up your"))
assert(find(drawnText, "Foxy Account"))
assert(find(drawnText, "Preparing your PUMPE"))

local codeIndex = assert(find(buttonLabels,
    "Code Pay\nEnter a 6-character code"))
local proximityIndex = assert(find(buttonLabels,
    "Proximity Pay\nOn - broadcasting nearby"))
local sendIndex = assert(find(buttonLabels,
    "Send Money\n10% fee - $2000 daily limit"))
assert(codeIndex < proximityIndex and proximityIndex < sendIndex)
assert(find(requests, "REGISTER"))
assert(find(requests, "ACCOUNT_SUMMARY"))

print("host_pumpe_flow_test: OK")
