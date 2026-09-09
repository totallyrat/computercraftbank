-- The 9.0 Settings app, driven through the phone exactly as it runs:
--
--   * the modem switch that takes the phone off the network
--   * what the phone is holding
--   * whether it updates itself
--
-- Every draw is bounds checked at 26x20.

local WIDTH, HEIGHT = 26, 20
savedDevice, deviceSaves, requestsAtModemOff = {}, {}, 0
buttonLabels, drawnText, requests = {}, {}, {}

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

-- The phone loads an app off its own disk; here that disk is apps/.
local realLoadfile = loadfile
loadfile = function(path)
    if tostring(path):find("YAPCHAT", 1, true) then
        return realLoadfile("../apps/yapchat.lua")
    end
    return realLoadfile(path)
end

local account = {
    account_id = "ACC000001", name = "Ana Fox",
    balance = 500, personal_number = "12345", daily_sent = 0,
}

package.loaded.config = {
    version = "8.5.0", currency = "$",
    send_money_daily_limit = 2000, send_money_fee_rate = 0.10,
    pumpe_lock_seconds = 60, pumpe_pin_seconds = 120,
    urgent_ring_poll_seconds = 3, bet_maximum = 10000,
    app_protocol = "PUMPE_APPS_V1", app_hostname = "APP_SERVER",
    app_chunk_size = 6000, max_apps_installed = 12,
}
package.loaded["lib.util"] = {
    loadTable = function(path, fallback)
        if tostring(path):find("apps", 1, true) then
            return { list = { { app_id = "YAPCHAT", name = "Yap Chat",
                version = 1, author = "Ana Fox",
                description = "Private messages" } } }
        end
        return fallback
    end,
    saveTable = function(path, value)
        -- Settings live on the device file, and that is the point: an
        -- update rewrites config.lua and would take the choice with it.
        -- Every save is snapshotted, not merged, so a later save cannot
        -- cover for an earlier one that never happened.
        if tostring(path):find("device", 1, true) then
            local snapshot = {}
            for key, item in pairs(value) do
                savedDevice[key] = item
                snapshot[key] = item
            end
            deviceSaves[#deviceSaves + 1] = snapshot
        end
    end,
    writeFile = function(path, body) written[path] = body end,
    readFile = function(path) return written[path] end,
    checksum = function(body)
        -- Enough of a hash for the test: the two sides of a
        -- conversation must land on the same collection name.
        local hash = 5381
        for index = 1, #tostring(body) do
            hash = (hash * 33 + tostring(body):byte(index)) % 4294967296
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

local closedModems, openedModems = 0, 0
package.loaded["lib.net"] = nil

local requests = requests or {}
local client = {
    discover = function() return true end,
    request = function(_, action, payload)
        requests[#requests + 1] = action
        if action == "LOGIN" then
            return { account = account, session_token = "S" }
        elseif action == "ACCOUNT_SUMMARY" then
            return { account = account }
        elseif action == "PUMPE_POLL" then
            return { balance = account.balance }
        elseif action == "BANK_IDENTITY" then
            return { bank_account_id = "0001222233334444",
                formatted = "0001 2222 3333 4444", bank_name = "Foxy",
                bank_closed = false, balance = account.balance }
        elseif action == "APP_PERMISSION_LIST" then
            return { apps = {} }
        elseif action == "FOXY_LOGIN_LIST" then
            return { apps = {} }
        end
        return { ok = true }
    end,
}
package.loaded["lib.net"] = {
    client = function() return client end,
    autoUpdate = function() end,
    locate = function() return nil end,
    openModems = function() openedModems = openedModems + 1 return { "m" } end,
    closeModems = function()
        closedModems = closedModems + 1
        requestsAtModemOff = #requests
        return { "m" }
    end,
    modemsOpen = function() return true end,
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
local ringHandler
function ui.setBackgroundTask(_, handler) ringHandler = handler end
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
    return #lines
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
-- In the order the script reaches them: sign in, the reply, then the post.
inputs = { "Ana Fox", "nice one back", "hello world this is my yap" }
function ui.input() return table.remove(inputs, 1) end
function ui.networkError(_, err) error("network error: " .. tostring(err)) end

-- In the order the script reaches them: the PUMPE login, then the message.
inputs = { "Ana Fox", "see you in a bit" }
function ui.input() return table.remove(inputs, 1) end
function ui.networkError(_, err) error("network error: " .. tostring(err)) end

local pinPrompts = {}
function ui.pin(_, prompt)
    pinPrompts[#pinPrompts + 1] = tostring(prompt or "")
    return "1234"
end

-- Two sign-ins: the one at the start, and the one attempted after the modem
-- has been turned off.
inputs = { "Ana Fox", "Ana Fox" }
function ui.input() return table.remove(inputs, 1) end
function ui.networkError(_, err) error("network error: " .. tostring(err)) end
function ui.pin() return "1234" end
function ui.confirm() return true end

actions = {
    "login",
    "next", "open:settings",           -- Settings is on page two
    "storage", "back",                 -- what the phone is holding
    "updates", "toggle", "back",       -- turn auto updates off
    "network", "toggle",               -- turn the modem off: signs out
    "login",                           -- and try to use the network anyway
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
        local wake = action and action:match("^__wake:(.+)$")
        if wake then
            pendingPoll = assert(ALERTS[wake], "unknown scripted alert")
            assert(ringHandler, "the OS watcher was never armed")
            wokeWith[#wokeWith + 1] = { name = wake, took = ringHandler() }
            return "__wake"
        end
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

assert(not drew("stopped"), "the PUMPE must not have crashed")

-- Everything reachable from one list -------------------------------------------
-- 9.0 added enough to Settings that the old fixed layout stopped fitting a
-- 20-row screen. The list pages instead, and every entry keeps its name on
-- its own button rather than being drawn over a blank one.
for _, label in ipairs({ "Network", "Storage", "Updates", "Account ID",
    "App Settings", "Connected Apps", "How PUMPE Works", "Edit Your Dock",
    "Sign Out", "Close PUMPE" }) do
    assert(pressed(label), "Settings is missing " .. label)
end

-- Storage ------------------------------------------------------------------------

assert(drew("FREE SPACE"), "storage says what is free")
assert(drew("WHAT IS ON THIS PUMPE"), "and what the phone is holding")

-- Updates ------------------------------------------------------------------------

assert(drew("AUTOMATIC UPDATES"))
-- Saved when the switch was flipped, not incidentally by a later save.
local savedOnItsOwn = false
for _, snapshot in ipairs(deviceSaves) do
    if snapshot.auto_update == false and snapshot.modem_on ~= false then
        savedOnItsOwn = true
    end
end
assert(savedOnItsOwn,
    "turning updates off is remembered on the device the moment it is"
        .. " turned off, and on the device rather than in config.lua, which"
        .. " an update rewrites")
assert(require("config").auto_update == false,
    "and it reaches the config table net.autoUpdate actually reads")
assert(pressed("Turn updates on"),
    "and the switch reads the other way once it is off")

-- The modem --------------------------------------------------------------------
-- Turning the radio off is the one setting that changes what the rest of the
-- phone can do, so it is the one worth checking end to end.

assert(drew("MODEM"))
assert(closedModems == 1, "the radio was actually closed, not just recorded")
assert(savedDevice.modem_on == false, "and the choice was remembered")

-- With the radio off a request must not go out at all. Letting it through
-- would mean every screen waiting out a five second timeout to discover
-- what the phone already knows.
local afterOff = 0
for index = requestsAtModemOff + 1, #requests do afterOff = afterOff + 1 end
assert(afterOff == 0,
    "nothing reached the network after the modem was turned off, but "
        .. afterOff .. " request(s) did")
assert(drew("Modem is off"), "and the phone says why rather than hanging")

print("host_settings_test: OK")
