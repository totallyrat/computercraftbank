-- The 9.0 Settings app, driven through the phone exactly as it runs:
--
--   * the modem switch that takes the phone off the network
--   * what the phone is holding
--   * whether it updates itself
--
-- Every draw is bounds checked at 26x20.

local WIDTH, HEIGHT = 26, 20
savedDevice, deviceSaves, requestsAtModemOff = {}, {}, 0
drawsAtModemOff, requestsAtModemOn, leakedOpens = 0, 0, 0
radioOff = false
appLiveRuns = 0
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
    if tostring(path):find("TESTBANK", 1, true) then
        return function()
            return function(api)
                -- An app asks the phone whether it is still live before it
                -- draws anything; one that is told no closes immediately.
                if api.running() then appLiveRuns = appLiveRuns + 1 end
                api.bank("TPB_INFO", {})
            end
        end
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
        if bootOffline and tostring(path):find("device", 1, true) then
            return { last_name = "Ana Fox", onboarding_complete = true,
                modem_on = false, update_mode = "ask" }
        end
        if tostring(path):find("apps", 1, true) then
            -- One installed app, so the built-in apps still fit on the
            -- first Home Screen page. It reaches a bank of its own, because
            -- api.bank builds a client on every call and building any
            -- client opens every modem on the device.
            return { list = { { app_id = "TESTBANK", name = "Test Bank",
                version = 1, author = "Ana Fox",
                description = "Its own bank" } } }
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
local updateOptions = {}
local updateAsked, updateAnswer = false, nil
package.loaded["lib.net"] = {
    client = function()
        -- The real net.client opens every modem it can find before it
        -- returns anything. A stub that skips that is more forgiving than
        -- the thing it stands for, and what it hides is the modem switch
        -- turning itself back on the moment an app or the App Browser
        -- builds a client of its own.
        package.loaded["lib.net"].openModems()
        return client
    end,
    autoUpdate = function(_, _, _, _, options)
        updateOptions[#updateOptions + 1] = options or {}
        -- The updater's half of the bargain. A stub that takes the callback
        -- and never calls it would let the alert screen ship undrawn and
        -- unmeasured, which on a 26x20 pocket screen is where the bugs are.
        if options and options.confirm and not updateAsked then
            updateAsked = true
            updateAnswer = options.confirm({
                version = "9.9.9",
                label = "10.0 Pre",
                changes = {
                    "Updates ask first.",
                    "The modem switch no longer bricks the phone.",
                },
            })
        end
        return false
    end,
    locate = function() return nil end,
    openModems = function()
        openedModems = openedModems + 1
        if savedDevice.modem_on == false then
            -- Opening the radio back up while the phone says it is off.
            -- Start-up is the one time this is allowed: a client is built
            -- before the device file has been read, and the phone closes
            -- them again straight after.
            if radioOff then leakedOpens = leakedOpens + 1 end
        else
            radioOff = false
            requestsAtModemOn = #requests
        end
        return { "m" }
    end,
    closeModems = function()
        closedModems = closedModems + 1
        radioOff = true
        requestsAtModemOff = #requests
        drawsAtModemOff = #drawnText
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
    "later",                           -- the update alert, before anything
    "login",
    -- 9.4: the Bank app left the Home Screen, so the built-in apps fit on
    -- one page and Settings no longer needs a page turn to reach.
    "open:settings",
    "storage", "back",                 -- what the phone is holding
    "updates", "mode", "back",         -- switch updates to automatic
    -- 9.5: turning the modem off leaves you signed in. It used to drop the
    -- session, which parked the phone on a sign-in screen that needed the
    -- radio it had just switched off.
    "network", "toggle",               -- turn the modem off
    "back",                            -- Settings still answers offline
    "open:tax",                        -- something that needs a server
    "open:browser", "back",            -- and something that builds a client
    "open:ext:TESTBANK",               -- including an app reaching its bank
    "open:settings", "network", "toggle", "back",  -- and back on again
    "back",
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
-- Only what the phone drew after the radio went off. The welcome screen at
-- the very start of the run would otherwise answer for the one it must not
-- go back to.
local function drewOffline(text)
    for index = drawsAtModemOff + 1, #drawnText do
        if drawnText[index]:find(text, 1, true) then return true end
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
for _, label in ipairs({ "Network", "Storage", "Updates",
    "App Settings", "Connected Apps", "How PUMPE Works", "Edit Your Dock",
    "Sign Out", "Close PUMPE" }) do
    assert(pressed(label), "Settings is missing " .. label)
end
-- The Account ID moves money, so in 9.4 it left Settings for the bank
-- section of the Foxy app, where the rest of the banking is.
assert(not pressed("Account ID"),
    "the Account ID belongs with the money, not beside the modem switch")

-- Storage ------------------------------------------------------------------------

assert(drew("FREE SPACE"), "storage says what is free")
assert(drew("WHAT IS ON THIS PUMPE"), "and what the phone is holding")

-- Updates ------------------------------------------------------------------------

-- 9.5: a phone asks before it replaces itself. Automatic is still a setting,
-- it is just no longer what a phone does without being told.
assert(drew("WHEN A RELEASE LANDS"))
assert(drew("Ask me first"),
    "asking is what a PUMPE does unless somebody chose otherwise")
assert(pressed("Install automatically"),
    "and automatic is still there for anybody who wants it")
-- Saved when the switch was flipped, not incidentally by a later save.
local savedOnItsOwn = false
for _, snapshot in ipairs(deviceSaves) do
    if snapshot.update_mode == "auto" and snapshot.modem_on ~= false then
        savedOnItsOwn = true
    end
end
assert(savedOnItsOwn,
    "the update setting is remembered on the device the moment it is"
        .. " changed, and on the device rather than in config.lua, which"
        .. " an update rewrites")
assert(pressed("Ask me instead"),
    "and the switch reads the other way once it is on")

-- The setting is only a label unless the updater actually asks. A PUMPE that
-- says "Ask me first" on screen and hands net.autoUpdate no way to ask would
-- install the next release out from under its owner.
assert(#updateOptions > 0, "the PUMPE never looked for a release at all")
assert(type(updateOptions[1].confirm) == "function",
    "a PUMPE in ask mode must hand the updater something to ask with")
assert(updateAsked, "and the question has to actually be put")
assert(drew("10.0 Pre"), "the alert names the release")
assert(drew("- Updates ask first."),
    "and lists what changed, in the release's own words")
assert(pressed("Update now") and pressed("Later"),
    "with both answers on screen")
assert(updateAnswer == false,
    "Later means no: the updater is told not to install, rather than the"
        .. " phone installing and telling the owner afterwards")

-- The modem --------------------------------------------------------------------
-- Turning the radio off is the one setting that changes what the rest of the
-- phone can do, so it is the one worth checking end to end.

assert(drew("MODEM"))
assert(closedModems == 1, "the radio was actually closed, not just recorded")
local rememberedOff = false
for _, snapshot in ipairs(deviceSaves) do
    if snapshot.modem_on == false then rememberedOff = true end
end
assert(rememberedOff, "and the choice was remembered")

-- With the radio off a request must not go out at all. Letting it through
-- would mean every screen waiting out a five second timeout to discover
-- what the phone already knows.
local afterOff = 0
for index = requestsAtModemOff + 1, requestsAtModemOn do afterOff = afterOff + 1 end
assert(afterOff == 0,
    "nothing reached the network after the modem was turned off, but "
        .. afterOff .. " request(s) did")
assert(drew("Modem is off"), "and the phone says why rather than hanging")

-- Offline is a state the phone stays usable in ----------------------------------
-- The switch used to sign you out, and signing back in needed the radio it
-- had just turned off, so the only way out was the Settings screen you could
-- no longer reach. Three things have to survive it: the Home Screen, the way
-- back on, and your account.
assert(savedDevice.session_token == nil,
    "a session token is never written to disk; the phone would resume as you"
        .. " after a reboot without ever asking for a PIN")
assert(drewOffline("Offline"),
    "the Home Screen says Offline rather than a balance nobody checked")
assert(not drewOffline("Let us get you started"),
    "turning the modem off must not dump the phone back at the welcome"
        .. " screen, which is a screen it cannot get past while offline")
assert(pressed("Turn the modem on"),
    "and Settings still reaches the switch that puts the radio back")
-- Still signed in, not merely still running. The phone knows this account's
-- personal number, which it only has from the session it was handed at
-- sign-in; a phone that dropped the session falls back to a cached name and
-- has nothing else to show.
assert(leakedOpens == 0,
    "the radio was reopened " .. leakedOpens .. " time(s) while the modem"
        .. " was switched off; building any client opens every modem, so the"
        .. " switch has to be checked before one is built, not after")
assert(drewOffline("NO 12345"),
    "the account survives the switch: dropping the session offline is what"
        .. " made the phone unrecoverable, because signing back in needs the"
        .. " radio that was just turned off")
local logins = 0
for _, action in ipairs(requests) do
    if action == "LOGIN" then logins = logins + 1 end
end
assert(logins == 1,
    "and turning the radio back on does not cost a second sign-in")

-- Starting up with the modem already off ---------------------------------------
-- The dangerous half of the switch. A phone that restarts while offline has
-- no session to keep, so it used to open on the welcome screen -- whose only
-- two buttons both need the radio, and from which Settings cannot be
-- reached. That is a phone you have to wipe to get back.

local requestsBeforeBoot, drawsBeforeBoot = #requests, #drawnText
local closesBeforeBoot, appRunsBeforeBoot = closedModems, appLiveRuns
bootOffline = true
savedDevice.modem_on = false
index, actions = 0, {
    "open:settings",                   -- reachable with no session at all
    "network", "back",                 -- and the switch is right there
    "back",
    "open:browser", "back",            -- nothing builds a client behind it
    "open:ext:TESTBANK",               -- and what is downloaded still opens
    "__terminate",
}
local bootOk, bootErr = pcall(assert(loadfile("../pumpe.lua")))
assert(bootOk or tostring(bootErr):find("more actions", 1, true),
    tostring(bootErr))

local function drewAtBoot(text)
    for index = drawsBeforeBoot + 1, #drawnText do
        if drawnText[index]:find(text, 1, true) then return true end
    end
    return false
end
assert(closedModems > closesBeforeBoot,
    "building a client opens every modem on the device, so a phone that"
        .. " starts up switched off has to close them again or the radio is"
        .. " on regardless of the setting")
assert(#requests == requestsBeforeBoot,
    "a phone that starts up offline must not put anything on the network")
assert(not drewAtBoot("Let us get you started"),
    "it opens as itself rather than at a sign-in screen it cannot finish")
assert(drewAtBoot("Offline"), "and says so")
assert(pressed("Turn the modem on"),
    "with the way back onto the network reachable from where it opened")
assert(leakedOpens == 0,
    "and nothing it opened put the radio back on by building a client")
assert(appLiveRuns > appRunsBeforeBoot,
    "an app that is already downloaded still runs with no session and no"
        .. " network; browsing what is on the phone is the whole of what is"
        .. " left when the radio is off")

print("host_settings_test: OK")
