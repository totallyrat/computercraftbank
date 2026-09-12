-- The App Browser and an installed app, on the PUMPE's native 26x20 screen.
-- Foxy is loaded here exactly as the phone loads it: one file returning one
-- function, handed an api table and nothing else.

local WIDTH, HEIGHT = 26, 20
buttonLabels, drawnText, requests, storeCalls = {}, {}, {}, {}

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

term = { current = function()
    return { getSize = function() return WIDTH, HEIGHT end }
end }
local written = {}
fs = {
    getDir = function() return "/pumpe" end,
    combine = function(left, right)
        return tostring(left):gsub("/+$", "") .. "/"
            .. tostring(right):gsub("^/+", "")
    end,
    exists = function(path) return written[path] ~= nil end,
    isDir = function() return false end,
    makeDir = function() end,
    delete = function(path) written[path] = nil end,
}
shell = { getRunningProgram = function() return "/pumpe/pumpe.lua" end }
sleep = function() end

-- The phone loads an app off its own disk; here that disk is the repository.
local realLoadfile = loadfile
loadfile = function(path)
    if tostring(path):find("FOXY", 1, true) then
        return realLoadfile("../foxy.lua")
    end
    return realLoadfile(path)
end

local account = {
    account_id = "ACC000001", name = "FoxyUser",
    balance = 500, personal_number = "12345", daily_sent = 0,
}

package.loaded.config = {
    version = "8.3.0", currency = "$",
    send_money_daily_limit = 2000, send_money_fee_rate = 0.10,
    pumpe_lock_seconds = 60, pumpe_pin_seconds = 120,
    urgent_ring_poll_seconds = 3, bet_maximum = 10000,
    app_protocol = "PUMPE_APPS_V1", app_hostname = "APP_SERVER",
    app_chunk_size = 6000, max_apps_installed = 12,
    foxy_cash_fee_rate = 0.02,
}
package.loaded["lib.util"] = {
    loadTable = function(path, fallback)
        -- Foxy is already installed, so the Home Screen carries it.
        if tostring(path):find("apps", 1, true) then
            return { list = { { app_id = "FOXY", name = "Foxy", version = 1,
                author = "PUMPE", description = "Your Foxy Account" } } }
        end
        return fallback
    end,
    saveTable = function() end,
    writeFile = function(path, body) written[path] = body end,
    readFile = function(path) return written[path] end,
    checksum = function(body)
        local hash = 5381
        for index = 1, #body do
            hash = (hash * 33 + body:byte(index)) % 4294967296
        end
        return string.format("%08x", hash)
    end,
    cooperativeYield = function() end,
    trim = function(v) return tostring(v or ""):match("^%s*(.-)%s*$") end,
    money = function(v, symbol) return (symbol or "$") .. tostring(v) end,
    formatClock = function() return "12:00" end,
    ingameDay = function() return 42 end,
    eventCountdown = function() return "1d" end,
    page = function(items, page, size)
        local pages = math.max(1, math.ceil(#items / size))
        page = math.max(1, math.min(page or 1, pages))
        local out = {}
        for index = (page - 1) * size + 1, math.min(#items, page * size) do
            out[#out + 1] = items[index]
        end
        return out, page, pages
    end,
}

local POTS = { { pot_id = "POT00000001", name = "Savings", balance = 120 } }
local bankClient = {
    discover = function() return true end,
    request = function(_, action, payload)
        requests[#requests + 1] = action
        if action == "LOGIN" then
            return { account = account, session_token = "S" }
        elseif action == "ACCOUNT_SUMMARY" then
            return { account = account }
        elseif action == "PUMPE_POLL" then
            return { balance = account.balance }
        elseif action == "DEV_MINE" then
            return { developer_id = nil }
        elseif action == "FOXY_OVERVIEW" then
            return { name = account.name, card_id = "PUMPE_ACC000001",
                personal_number = "12345", balance = account.balance,
                saved = 120, pots = POTS, max_pots = 8, fee_rate = 0.02 }
        elseif action == "FOXY_POT_CREATE" then
            POTS[#POTS + 1] = { pot_id = "POT00000002",
                name = payload.name, balance = 0 }
            return { pots = POTS, balance = account.balance }
        elseif action == "FOXY_POT_MOVE" then
            return { pots = POTS, balance = account.balance, saved = 120 }
        elseif action == "FRIEND_OVERVIEW" then
            return { friends = { { account_id = "ACC000002",
                name = "Best Mate" } } }
        elseif action == "FOXY_CASH_QUOTE" then
            return { recipient = "Best Mate", amount = 100, fee = 2,
                total = 102, fee_rate = 0.02, balance = account.balance }
        elseif action == "FOXY_CASH_SEND" then
            return { amount = 100, fee = 2, total = 102,
                recipient = "Best Mate", balance = 398 }
        end
        return { ok = true }
    end,
}
local APP = { app_id = "NOTES", name = "Notes", version = 1,
    author = "Shop Owner", description = "Jot things down",
    size = 20, checksum = nil }
local BODY = "return function() end\n"
APP.size = #BODY
-- Advertised one way, served another: a download the PUMPE must refuse.
local ROTTEN = { app_id = "ROTTEN", name = "Rotten", version = 1,
    author = "Shop Owner", description = "Arrives damaged",
    size = #BODY, checksum = "deadbeef" }
local storeClient = {
    discover = function() return true end,
    request = function(_, action, payload)
        storeCalls[#storeCalls + 1] = action
        if action == "APP_LIST" then
            return { apps = {
                { app_id = "FOXY", name = "Foxy", version = 1,
                  author = "PUMPE", description = "Your Foxy Account",
                  size = 10, checksum = "0" },
                APP, ROTTEN,
            } }
        elseif action == "APP_CHUNK" then
            local body = payload.app_id == "ROTTEN" and BODY or BODY
            return { app_id = payload.app_id, offset = 0, data = body,
                next_offset = #body, total_size = #body, done = true }
        end
        return { ok = true }
    end,
}
APP.checksum = package.loaded["lib.util"].checksum(BODY)
package.loaded["lib.net"] = {
    client = function(config)
        if config.protocol == "PUMPE_APPS_V1" then return storeClient end
        return bankClient
    end,
    autoUpdate = function() end,
    locate = function() return nil end,
}

local function assertBox(label, x, y, width, height)
    assert(x >= 1 and y >= 1, label .. " starts outside the screen")
    assert(width >= 1 and height >= 1, label .. " has an empty size")
    assert(x + width - 1 <= WIDTH, label .. " exceeds screen width")
    assert(y + height - 1 <= HEIGHT, label .. " exceeds screen height")
end

local ui = { theme = {} }
for _, name in ipairs({
    "background", "panel", "panelAlt", "ink", "muted", "accent", "accentDark",
    "success", "warning", "danger", "shadow",
}) do ui.theme[name] = colors.white end
function ui.usePhoneStyle() end
function ui.noteActivity() end
function ui.idleForMs() return 0 end
function ui.setIdleLock() end
function ui.setBackgroundTask() end
function ui.clear() end
function ui.boot() end
function ui.splash() end
function ui.wipe() end
function ui.progress() end
function ui.fill(_, x, y, width, height) assertBox("fill", x, y, width, height) end
function ui.card(_, x, y, width, height) assertBox("card", x, y, width, height) end
function ui.truncate(value, length)
    value = tostring(value or "")
    if #value <= length then return value end
    return value:sub(1, math.max(0, length - 2)) .. ".."
end
function ui.wrap(value, width)
    local lines, current = {}, ""
    for word in tostring(value or ""):gmatch("%S+") do
        if #current == 0 then current = word:sub(1, width)
        elseif #current + 1 + #word <= width then current = current .. " " .. word
        else lines[#lines + 1] = current current = word:sub(1, width) end
    end
    if #current > 0 then lines[#lines + 1] = current end
    if #lines == 0 then lines[1] = "" end
    return lines
end
function ui.text(_, x, y, value, _, _, maximum)
    assert(x >= 1 and y >= 1 and y <= HEIGHT,
        "text outside the screen: " .. tostring(value))
    local available = math.min(maximum or WIDTH, WIDTH - x + 1)
    assert(#tostring(value or "") <= available,
        "text overflows: " .. tostring(value))
    drawnText[#drawnText + 1] = tostring(value or "")
end
function ui.center(_, y, value)
    assert(y >= 1 and y <= HEIGHT, "centered text outside the screen")
    assert(#tostring(value or "") <= WIDTH, "centered text is clipped")
    drawnText[#drawnText + 1] = tostring(value or "")
end
function ui.wrappedText(_, x, y, value, width, maxLines)
    local lines = ui.wrap(value, width)
    assert(#lines <= maxLines, "wrapped text loses lines: " .. tostring(value))
    for index, line in ipairs(lines) do ui.text(nil, x, y + index - 1, line) end
end
function ui.header(_, title, subtitle)
    assert(#tostring(title or "") <= WIDTH - 3, "header title is clipped")
    assert(not subtitle or #tostring(subtitle) <= WIDTH - 3,
        "header subtitle is clipped")
    drawnText[#drawnText + 1] = tostring(title or "")
    drawnText[#drawnText + 1] = tostring(subtitle or "")
end
function ui.message(_, _, title, body)
    drawnText[#drawnText + 1] = tostring(title)
    drawnText[#drawnText + 1] = tostring(body)
end
function ui.confirm() return true end
function ui.pin() return "1234" end
inputs = { "FoxyUser", "Holiday", "60", "100" }
function ui.input() return table.remove(inputs, 1) end
function ui.networkError(_, err) error("network error: " .. tostring(err)) end

actions = {
    "login",
    "open:browser",                      -- the App Browser
    "open:NOTES", "get",                 -- install one; that closes it
    "open:ROTTEN", "get", "back",        -- one that arrives damaged
    "back",                              -- leave the browser
    "open:ext:FOXY",                     -- the installed app
    "bank",                              -- the card, balance and accounts
    "new",                               -- open another account
    "down", "up",                        -- scroll the account column
    "pot:POT00000001", "move", "pick:main",
    "down", "down",                      -- Foxy Cash sits under the accounts
    "cash", "pick:ACC000002", "send",
    -- 9.4: the bet wallet, activity, cash out and the Account ID all moved
    -- into this list from the PUMPE's Bank tab, so scrolling to the bottom
    -- is what proves they are reachable from inside Foxy.
    "down", "down", "down", "down",
    "back",                              -- leave the bank
    "account", "back",                   -- the account section
    "back",                              -- leave Foxy
    -- 9.4: there is no Bank tab to open. Foxy is the bank, and the Home
    -- Screen has one fewer built-in app than it had.
    "__terminate",
}
local index = 0
function ui.scene()
    local scene = { width = WIDTH, height = HEIGHT }
    local live = {}
    function scene:button(id, x, y, width, height, label, options)
        assertBox("button '" .. tostring(label) .. "'", x, y, width, height)
        local lines = ui.wrap(label, math.max(1, width - 2))
        assert(#lines <= height, "button label is clipped: "
            .. tostring(label or ""))
        buttonLabels[#buttonLabels + 1] = tostring(label or "")
        if not (options and options.disabled) then live[id] = true end
    end
    function scene:hotspot(id, x, y, width, height)
        assertBox("hotspot", x, y, width, height)
        live[id] = true
    end
    function scene:wait()
        index = index + 1
        local action = actions[index]
        assert(action, "PUMPE asked for more actions than the script has")
        if not action:match("^__") then
            assert(live[action], "tapped '" .. action
                .. "' but no such button is on screen")
        end
        return action
    end
    return scene
end
package.loaded["lib.ui"] = ui

local ok, err = pcall(assert(loadfile("../pumpe.lua")))
assert(ok or tostring(err):find("more actions", 1, true), tostring(err))

local function drew(text)
    for _, item in ipairs(drawnText) do
        if item:find(text, 1, true) then return true end
    end
    return false
end
local function pressed(text)
    for _, item in ipairs(buttonLabels) do
        if item:find(text, 1, true) then return true end
    end
    return false
end
local function asked(list, action)
    for _, item in ipairs(list) do
        if item == action then return true end
    end
    return false
end

-- The App Browser talks to the App Server, never to the Bank.
assert(drew("App Browser"))
assert(asked(storeCalls, "APP_LIST") and asked(storeCalls, "APP_CHUNK"))
assert(not asked(requests, "APP_LIST") and not asked(requests, "APP_CHUNK"),
    "app downloads must not touch the Bank")
assert(written["/pumpe/apps/NOTES.lua"] == BODY,
    "the downloaded app lands on disk verified")
-- A download whose checksum does not match what was advertised is thrown
-- away rather than run.
assert(drew("Download was damaged"), "a bad download is refused")
assert(written["/pumpe/apps/ROTTEN.lua"] == nil,
    "and nothing of it is kept")

-- An installed app sits on the Home Screen beside the built-in ones.
assert(pressed("F"), "Foxy has an icon of its own")
assert(drew("Foxy"))

-- Foxy: the card, the balance, the accounts, and Foxy Cash under them.
assert(drew("Foxy Bank"))
local grouped = false
for _, item in ipairs(drawnText) do
    if item:match("^%d%d%d%d %d%d%d%d %d%d%d%d$") then grouped = true end
end
assert(grouped, "the card shows a grouped number")
assert(drew("FOXYUSER"), "and the holder's name across the front")
assert(drew("BALANCE") and drew("$500"))
assert(pressed("Savings"), "your accounts are listed under the balance")
assert(pressed("New account"))
assert(pressed("Foxy Cash"))
assert(asked(requests, "FOXY_POT_CREATE") and asked(requests, "FOXY_POT_MOVE"))
assert(asked(requests, "FOXY_CASH_QUOTE") and asked(requests, "FOXY_CASH_SEND"))
assert(drew("2%") or pressed("2%"), "the fee is shown before sending")

-- And the account section it shares the home page with.
assert(drew("Your Account"))
assert(pressed("Change your name") and pressed("Change your PIN"))

-- The app ran to the end. runInstalledApp catches a crash so a bad app
-- cannot take the phone down with it, which would otherwise hide a failure
-- in here as a quiet error message.
assert(not drew("stopped"), "the app must not have crashed")
assert(not drew("will not start"), "the app must have loaded")

-- 9.0: BuckApp left the home screen to become a bank of its own, and what
-- is built in is simply the Foxy bank account.
assert(not drew("BuckApp"), "BuckApp is no longer preinstalled")
assert(not pressed("Move to Foxy"),
    "and the migration banner that pointed at Foxy has gone with it")
assert(pressed("Account ID + Transfer"),
    "what is there instead is the Account ID every bank understands")

-- 9.4: everything that used to be a Bank tab on the Home Screen is in here.
assert(pressed("Bet Wallet"), "the bet wallet moved into Foxy")
assert(pressed("Activity"), "and so did the transaction list")
assert(pressed("Cash out with a code"),
    "and the one code a Foxy account still uses -- a kiosk handing it money")
assert(not pressed("Code Pay"),
    "but not Code Pay: paying a kiosk is Foxy Pay, or a third-party bank")

print("host_pumpe_apps_test: OK")
