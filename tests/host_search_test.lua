-- 10.0 Simple, driven through the phone.
--
-- The release is one idea: everything a PUMPE can do is a labelled action,
-- and anything that can find an action can do anything. Search finds them, a
-- QuickAction strings them together, and Settings and the App Browser search
-- the same way. So the tests worth having are that an action opens the app
-- *at that action* rather than at its front door, and that the things which
-- fire on their own actually fire.
--
-- Every draw is bounds checked at 26x20.

package.path = "../?.lua;../?/init.lua;" .. package.path

local WIDTH, HEIGHT = 26, 20
local drawn, buttonLabels = {}, {}
local actions, actionIndex = {}, 0
local inputs, confirms = {}, {}
local savedDevice = {}
-- Global so the test app, which is loaded as its own chunk, can reach it.
openedWith = {}

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}
os.day = function() return 400 end
os.time = function() return 12 end
os.epoch = function() return 5000000 end
os.getComputerID = function() return 9 end
sleep = function() end
term = { current = function()
    return { getSize = function() return WIDTH, HEIGHT end }
end }
fs = {
    getDir = function() return "/pumpe" end,
    combine = function(left, right)
        return tostring(left):gsub("/+$", "") .. "/"
            .. tostring(right):gsub("^/+", "")
    end,
    exists = function() return true end,
    isDir = function() return false end,
    makeDir = function() end,
    delete = function() end,
    getFreeSpace = function() return 500000 end,
    getSize = function() return 100 end,
}
shell = { getRunningProgram = function() return "/pumpe/pumpe.lua" end }

-- An installed app that declares two actions in its own header, which is the
-- whole of how an app tells the phone what it can be asked to do.
local APP_BODY = table.concat({
    "-- PUMPE APP: Test App",
    "-- PUMPE APP ACTION: cash | Send cash | Pay a friend",
    "-- PUMPE APP ACTION: ledger | Activity | What you have spent",
    "return function(api) openedWith[#openedWith + 1] = api.action() end",
}, "\n")

package.loaded.config = {
    version = "10.0.1", currency = "$", pumpe_lock_seconds = 60,
    pumpe_pin_seconds = 120, urgent_ring_poll_seconds = 3,
    bet_maximum = 10000, app_protocol = "PUMPE_APPS_V1",
    app_hostname = "APP_SERVER", app_chunk_size = 6000,
    max_apps_installed = 12, web_protocol = "PUMPE_WEB_V1",
    web_hostname = "INTERNET_SERVER",
}
local util = require("lib.util")
util.loadTable = function(path, fallback)
    if tostring(path):find("apps", 1, true) then
        return { list = { { app_id = "TESTAPP", name = "Test App",
            version = 1, author = "Ana", description = "For testing" } } }
    end
    if tostring(path):find("device", 1, true) then
        return {
            last_name = "Ana Fox", onboarding_complete = true,
            modem_on = true, update_mode = "ask",
            -- Seeded rather than typed in: what is under test here is that
            -- these fire, not the four input boxes that create them.
            reminders = { { text = "Feed the foxes", day = 400, hour = 0,
                style = "banner" } },
            shortcuts = {
                { name = "Morning", trigger = "demand", on_home = true,
                  steps = { { kind = "notify", text = "Good morning" } } },
                { name = "Eight", trigger = "auto", hour = 8,
                  steps = { { kind = "notify", text = "It is eight" },
                            { kind = "repeat", times = 3 } } },
            },
        }
    end
    return util.copy(fallback)
end
util.saveTable = function(path, value)
    if tostring(path):find("device", 1, true) then
        for key, item in pairs(value) do savedDevice[key] = item end
    end
end
util.readFile = function(path)
    if tostring(path):find("TESTAPP", 1, true) then return APP_BODY end
    return nil
end
util.writeFile = function() end
package.loaded["lib.util"] = util

local realLoadfile = loadfile
loadfile = function(path)
    if tostring(path):find("TESTAPP", 1, true) then
        return load(APP_BODY, "TESTAPP")
    end
    return realLoadfile(path)
end

local client = {
    discover = function() return true end,
    isOnline = function() return true end,
    request = function(_, action)
        if action == "LOGIN" then
            return { session_token = "SESSION-1", account = {
                account_id = "ACC000001", name = "Ana Fox", balance = 500,
                personal_number = "12345", bank_account_id = "0001000000000001",
                bank_name = "Foxy" } }
        elseif action == "ACCOUNT_SUMMARY" then
            return { account = { account_id = "ACC000001", name = "Ana Fox",
                balance = 500, personal_number = "12345" } }
        elseif action == "APP_LIST" then
            return { apps = {} }
        end
        return { ok = true }
    end,
}
package.loaded["lib.net"] = {
    client = function() return client end,
    autoUpdate = function() end,
    locate = function() return nil end,
    openModems = function() return { "m" } end,
    closeModems = function() return { "m" } end,
    modemsOpen = function() return true end,
}

local function assertBox(label, x, y, width, height)
    assert(x >= 1 and y >= 1, label .. " starts outside the screen")
    assert(width >= 1 and height >= 1, label .. " has an empty size")
    assert(x + width - 1 <= WIDTH, label .. " exceeds screen width")
    assert(y + height - 1 <= HEIGHT, label .. " exceeds screen height: " .. y)
end

local ui = { theme = setmetatable({}, { __index = function() return 1 end }) }
function ui.clear() end
function ui.fill(_, x, y, w, h) assertBox("fill", x, y, w, h) end
function ui.card(_, x, y, w, h) assertBox("card", x, y, w, h) end
function ui.text(_, x, y, value)
    assert(y >= 1 and y <= HEIGHT, "text outside the screen: " .. tostring(value))
    assert(#tostring(value or "") <= WIDTH - x + 1,
        "text overflows: " .. tostring(value))
    drawn[#drawn + 1] = tostring(value or "")
end
function ui.center(_, y, value)
    assert(y >= 1 and y <= HEIGHT, "centered text outside the screen")
    assert(#tostring(value or "") <= WIDTH, "centered text is clipped")
    drawn[#drawn + 1] = tostring(value or "")
end
function ui.wrap(value, width)
    local out, line = {}, ""
    for word in tostring(value or ""):gmatch("%S+") do
        if #line + #word + 1 > width and line ~= "" then
            out[#out + 1] = line
            line = word
        else
            line = line == "" and word or (line .. " " .. word)
        end
    end
    if line ~= "" then out[#out + 1] = line end
    return out
end
function ui.wrappedText(_, x, y, value, width, maxLines)
    local out = ui.wrap(value, width)
    assert(#out <= maxLines, "wrapped text loses lines: " .. tostring(value))
    for index, line in ipairs(out) do ui.text(nil, x, y + index - 1, line) end
end
function ui.header(_, title, subtitle)
    assert(#tostring(title or "") <= WIDTH - 3, "header title is clipped")
    assert(not subtitle or #tostring(subtitle) <= WIDTH - 3,
        "header subtitle is clipped: " .. tostring(subtitle))
    drawn[#drawn + 1] = tostring(title or "")
    drawn[#drawn + 1] = tostring(subtitle or "")
end
function ui.truncate(value, width)
    value = tostring(value or "")
    if #value <= width then return value end
    return value:sub(1, math.max(0, width - 1)) .. "."
end
function ui.message(_, _, title, body)
    drawn[#drawn + 1] = tostring(title)
    drawn[#drawn + 1] = tostring(body or "")
    assert(not tostring(title):find("stopped"),
        "an app crashed: " .. tostring(title) .. " -- " .. tostring(body))
end
function ui.confirm()
    local answer = table.remove(confirms, 1)
    if answer == nil then return true end
    return answer
end
filterAt = 0
suggested = {}
function ui.input(_, _, spec)
    local value = table.remove(inputs, 1)
    -- 11.0: an entry can name a suggestion to tap. The phone's own suggest
    -- function is asked, exactly as the real field asks it on every key.
    if type(value) == "table" then
        local items = spec.suggest(value.typed)
        suggested = items
        for _, item in ipairs(items) do
            if item.label == value.choose then return value.typed, item end
        end
        error("nothing called " .. value.choose .. " was suggested for "
            .. value.typed)
    end
    -- The moment Settings is handed a search term. Everything drawn before
    -- it is the unfiltered list, which would answer for the filtered one.
    if value == "modem" then filterAt = #buttonLabels end
    return value
end
function ui.pin() return "1234" end
function ui.wordmark() return true end
function ui.splash() end
function ui.boot() end
function ui.progress() end
function ui.idleForMs() return 0 end
function ui.noteActivity() end
function ui.setIdleLock() end
function ui.setBackgroundTask() end
function ui.usePhoneStyle() end
function ui.networkError(_, err) error("network error: " .. tostring(err)) end
function ui.scene()
    local scene = { width = WIDTH, height = HEIGHT }
    local live = {}
    function scene:button(id, x, y, width, height, label, options)
        assertBox("button '" .. tostring(label) .. "'", x, y, width, height)
        local lines = ui.wrap(label, math.max(1, width - 2))
        assert(#lines <= height, "button label is clipped: " .. tostring(label))
        buttonLabels[#buttonLabels + 1] = tostring(label or "")
        if not (options and options.disabled) then live[id] = true end
    end
    function scene:hotspot(id, x, y, width, height)
        assertBox("hotspot", x, y, width, height)
        live[id] = true
    end
    function scene:wait()
        actionIndex = actionIndex + 1
        local action = actions[actionIndex]
        assert(action, "the phone asked for more actions than the test has")
        if action ~= "__terminate" and action ~= "__tick" then
            assert(live[action],
                "tapped '" .. action .. "' but no such button is on screen")
        end
        return action
    end
    return scene
end
package.loaded["lib.ui"] = ui

actions = {
    "login",
    "__tick",                          -- the reminder and the daily action
    "search", "hit:1",                 -- find an app action and run it
    "back",
    "search",                          -- 11.0: tap a suggestion instead
    "open:quick:1",                    -- a QuickAction living on the grid
    "open:settings", "find", "back",   -- searching Settings
    "__terminate",
}
inputs = { "Ana Fox", "cash", { typed = "activ", choose = "Activity" },
    "modem" }

-- showBanner draws straight onto the screen rather than through ui.message,
-- so the banner text lands in `drawn` like anything else.
local ok, err = pcall(assert(realLoadfile("../pumpe.lua")))
assert(ok or tostring(err):find("more actions", 1, true), tostring(err))

local page = table.concat(drawn, " ")
local function drew(text) return page:find(text, 1, true) ~= nil end
local function pressed(text)
    for _, item in ipairs(buttonLabels) do
        if item:find(text, 1, true) then return true end
    end
    return false
end
local function pressedAfterFilter(text)
    for index = filterAt + 1, #buttonLabels do
        if buttonLabels[index]:find(text, 1, true) then return true end
    end
    return false
end

-- Search ---------------------------------------------------------------------

assert(drew("Send cash"),
    "search found the action an app declared in its own header, which is how"
        .. " it knows what an app does without running it")
assert(#openedWith > 0, "and opening it actually opened the app")
assert(openedWith[1] == "cash",
    "at the action that was asked for, not at the app's front door -- the"
        .. " app was handed " .. tostring(openedWith[1]))

-- 11.0: the search bar sits above the dock, and suggests as you type.
assert(drew("Q  Search everything"), "the Home Screen has a search bar")
local offered
for _, item in ipairs(suggested) do
    if item.label == "Activity" then offered = item end
end
assert(offered and offered.detail == "Test App",
    "typing offered the app's action, saying whose it is")
assert(openedWith[2] == "ledger",
    "and tapping the suggestion opened the app at that action")

-- Everything on the phone is searchable ------------------------------------------

assert(pressed("Look in the App Browser"),
    "and what is not installed is one tap further on")

-- Settings search ------------------------------------------------------------------

assert(pressed("Q  modem") or drew("Q  modem"),
    "Settings keeps the search it was given")
assert(pressedAfterFilter("Network"),
    "and Network survives a search for 'modem'")
assert(not pressedAfterFilter("How PUMPE Works"),
    "while everything that does not match is gone, which is the point of"
        .. " searching a list rather than paging through it")

-- Things that fire on their own -------------------------------------------------

assert(drew("Feed the foxes"),
    "a reminder that has come due arrives without being asked for")
assert(drew("It is eight"),
    "and so does a QuickAction set to run every day")
assert(savedDevice.reminders and savedDevice.reminders[1].done,
    "a reminder that has fired is marked done, so it does not fire again on"
        .. " every tick for the rest of the day")
assert(savedDevice.shortcuts and savedDevice.shortcuts[2].last_day == 400,
    "and a daily QuickAction records the day it ran")

-- A QuickAction on the Home Screen ------------------------------------------------

assert(drew("Good morning"),
    "an icon that runs a QuickAction runs it rather than opening an app")

print("host_search_test: OK")
