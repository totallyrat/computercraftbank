-- Yap Chat, driven through the phone exactly as it runs. It is the app that
-- uses all three new APIs, so this is where they are checked end to end:
--
--   * notifications are asked for before anything else, and before the app
--     has been told a single thing about the account
--   * the PIN gate stands between the app and any message
--   * a message is written with an audience of exactly two and a one-day
--     life, and opening the thread is what starts that clock
--   * the call button raises the PUMPE's own Urgent Contact ring, labelled
--
-- Every draw is bounds checked at 26x20.

local WIDTH, HEIGHT = 26, 20
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
    saveTable = function() end,
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

-- One message each way, already in the thread. Bo's is unread, which is what
-- the app has to notice.
local MESSAGES = {
    { id = "DM000002", data = { body = "are you around" },
      author_id = "ACC000002", author_name = "Bo Wolf",
      created_day = 42, created_time = "12:02", reactions = 0,
      reacted = false, mine = false, read = false, private = true },
    { id = "DM000001", data = { body = "hello you" },
      author_id = "ACC000001", author_name = "Ana Fox",
      created_day = 42, created_time = "12:01", reactions = 0,
      reacted = false, mine = true, read = false, private = true },
}

local FRIENDS = {
    { account_id = "ACC000002", name = "Bo Wolf" },
    { account_id = "ACC000003", name = "Cy Hare" },
}

local askedPermission, approved, pinChecked, sentMessage, marked
local notified, called, permissionAllowed, permissionFull
local permissionSets = {}
local pendingPoll
local wokeWith = {}
-- Alerts the OS watcher will find on its next poll.
local ALERTS = {
    FULLSCREEN = { latest = { notification_id = "N2",
        title = "Bo Wolf", kind = "app", app_name = "Yap Chat",
        style = "fullscreen",
        -- Exactly the 120 characters the Bank will store, in words long
        -- enough that every line wastes room. This is the worst a body can
        -- be, not a convenient one.
        body = "wordwordword wordwordword wordwordword wordwordword wordwordword wordwordword wordwordword wordwordword wordwordword xxx" } },
    BANNER = { latest = { notification_id = "N3",
        title = "Bo Wolf", kind = "app", app_name = "Yap Chat",
        style = "banner", body = "never mind" } },
}
local client = {
    discover = function() return true end,
    request = function(_, action, payload)
        requests[#requests + 1] = action
        -- The real Bank refuses an app request with no id. A stub that is
        -- more permissive than the server is a test that cannot fail: that
        -- is exactly how Yap shipped in 8.4.0 unable to post.
        if (action:find("^APP_") or action:find("^FOXY_LOGIN_")
            or action == "PIN_CHECK")
            and action ~= "FOXY_LOGIN_LIST"
            and action ~= "APP_PERMISSION_LIST" then
            assert(payload.app_id == "YAPCHAT", action
                .. " reached the Bank without the app id")
        end
        if action == "LOGIN" then
            return { account = account, session_token = "S" }
        elseif action == "ACCOUNT_SUMMARY" then
            return { account = account }
        elseif action == "PUMPE_POLL" then
            local queued = pendingPoll
            pendingPoll = nil
            local poll = { balance = account.balance }
            for key, value in pairs(queued or {}) do poll[key] = value end
            return poll
        elseif action == "APP_PERMISSION_ASK" then
            askedPermission = askedPermission or payload
            if payload.allow ~= nil then permissionAllowed = payload.allow end
            return { permission = {
                app_id = payload.app_id, app_name = payload.app_name,
                notifications = permissionAllowed == nil and "unset"
                    or (permissionAllowed and "granted" or "denied"),
                fullscreen = false,
            } }
        elseif action == "FOXY_LOGIN_STATUS" then
            return { approved = false }
        elseif action == "FOXY_LOGIN_APPROVE" then
            approved = payload
            return { approved = true, profile = {
                account_id = account.account_id, name = account.name,
                scopes = payload.scopes, friends = FRIENDS,
            } }
        elseif action == "PIN_CHECK" then
            pinChecked = payload
            return { ok = true }
        elseif action == "APP_DATA_LIST" then
            return { records = MESSAGES }
        elseif action == "APP_DATA_READ" then
            marked = payload
            return { read = payload.ids or {} }
        elseif action == "APP_DATA_PUT" then
            sentMessage = payload
            return { record = MESSAGES[1] }
        elseif action == "APP_PERMISSION_LIST" then
            return { apps = { {
                app_id = "YAPCHAT", app_name = "Yap Chat",
                notifications = permissionAllowed and "granted" or "denied",
                fullscreen = permissionFull == true, asked_day = 42,
            } } }
        elseif action == "APP_PERMISSION_SET" then
            if payload.notifications ~= nil then
                permissionAllowed = payload.notifications
            end
            if payload.fullscreen ~= nil then
                permissionFull = payload.fullscreen
            end
            -- The Bank drops fullscreen with the permission it hangs off.
            if not permissionAllowed then permissionFull = false end
            permissionSets[#permissionSets + 1] = payload
            return { permission = {
                app_id = "YAPCHAT", app_name = "Yap Chat",
                notifications = permissionAllowed and "granted" or "denied",
                fullscreen = permissionFull == true,
            } }
        elseif action == "APP_NOTIFY" then
            notified = payload
            return { sent = true, style = "banner" }
        elseif action == "URGENT_CALL" then
            called = payload
            return { call = { call_id = "CALL1", status = "declined",
                other_name = "Bo Wolf" } }
        elseif action == "URGENT_STATE" then
            return { call = { call_id = "CALL1", status = "declined",
                other_name = "Bo Wolf" } }
        end
        return { ok = true }
    end,
}
package.loaded["lib.net"] = {
    client = function() return client end,
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

actions = {
    "login",
    "open:ext:YAPCHAT",                -- launch it
    "yes",                             -- allow notifications, asked first
    "yes",                             -- the FoxyLogin sheet
    "open:ACC000002",                  -- open the conversation with Bo
    "send",                            -- write one
    "call",                            -- and ring them
    "cancel",                          -- Bo does not pick up
    "back",                            -- back to the chat list
    "back",                            -- leave the app
    "next",                            -- Settings is on page two
    "open:settings", "apps",           -- App Settings
    "open:YAPCHAT",                    -- the app's own permissions
    "full",                            -- turn fullscreen on
    "notify",                          -- block: fullscreen goes with it
    "notify",                          -- allow again, fullscreen stays off
    "back", "back", "back",
    "__wake:FULLSCREEN", "ok",         -- the loud one, and dismissing it
    "__wake:BANNER",                   -- and the quiet one
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
local function drewAt(needle)
    return table.concat(drawnText, " "):find(needle, 1, true) ~= nil
end

assert(not drew("stopped") and not drew("will not start"),
    "the app must have loaded and run to the end")

-- Notifications, before anything else ------------------------------------------

-- The permission question comes up before the app is told a single thing
-- about the account, which is the order the app asks in.
local askedAt, signedInAt
for position, action in ipairs(requests) do
    if action == "APP_PERMISSION_ASK" and not askedAt then askedAt = position end
    if action == "FOXY_LOGIN_APPROVE" and not signedInAt then
        signedInAt = position
    end
end
assert(askedAt and signedInAt and askedAt < signedInAt,
    "Yap Chat asks about notifications before it asks about you")
assert(askedPermission and askedPermission.app_id == "YAPCHAT"
    and askedPermission.app_name == "Yap Chat",
    "the id and the name both come from the install")
assert(permissionAllowed == true, "the answer reached the Bank")
assert(drewAt("wants to send you notifications"),
    "the sheet says what is being asked")
assert(drewAt("Fullscreen is off"),
    "and that fullscreen is not part of the deal")
assert(pressed("Allow") and pressed("Not now"))

-- FoxyLogin --------------------------------------------------------------------

assert(approved and approved.app_id == "YAPCHAT",
    "the app id comes from the install, not from the app")
assert(#approved.scopes == 2 and approved.scopes[2] == "friends")
assert(not drewAt("Your balance"), "it never asked for the balance")

-- The PIN gate -----------------------------------------------------------------

assert(pinChecked and pinChecked.pin == "1234"
    and pinChecked.app_id == "YAPCHAT",
    "the PIN went to the Bank to be checked, stamped with the app")
local askedToUnlock = false
for _, prompt in ipairs(pinPrompts) do
    if prompt:find("Unlock Yap Chat", 1, true) then askedToUnlock = true end
end
assert(askedToUnlock,
    "and the owner was told which app they were unlocking, in its words")

-- The conversation --------------------------------------------------------------

assert(drew("Bo Wolf"), "friends are the chat list")
assert(drew("are you around") and drew("hello you"),
    "both sides of the thread are on screen")

-- Opening the thread marks the other person's message read, and only theirs.
assert(marked and marked.ids and #marked.ids == 1
    and marked.ids[1] == "DM000002",
    "the unread message from Bo is what gets marked, not Ana's own")

-- A message is written so that only two people can ever read it, and so
-- that it goes a day after it has been read.
assert(sentMessage and sentMessage.data.body == "see you in a bit")
assert(sentMessage.expire_after_days == 1, "one day, as the app promises")
assert(sentMessage.audience and #sentMessage.audience == 2,
    "exactly two people, never a broadcast")
local audience = {}
for _, id in ipairs(sentMessage.audience) do audience[id] = true end
assert(audience["ACC000001"] and audience["ACC000002"],
    "and they are the two in the conversation")
assert(sentMessage.collection == marked.collection,
    "reading and writing use the same thread")

-- Both sides derive the same collection name from the same pair of ids.
assert(sentMessage.collection:find("^dm%x+$"),
    "the thread is named from the pair, not from who opened it: "
        .. tostring(sentMessage.collection))

-- The friend hears about it, through the API rather than by the app writing
-- to their notifications directly.
assert(notified and notified.account_id == "ACC000002"
    and notified.title == "Ana Fox",
    "the alert says who it is from")
assert(notified.body:find("see you in a bit", 1, true))

-- The call button ----------------------------------------------------------------

assert(called and called.account_id == "ACC000002"
    and called.app_id == "YAPCHAT",
    "the ring is placed through the Urgent Contact API, labelled")
assert(pressed("Call"), "and there is a call button in the conversation")

-- App Settings ---------------------------------------------------------------------

assert(drew("App Settings"), "Settings has an App Settings entry")
assert(pressed("App Settings"))
assert(drewAt("NOTIFICATIONS"), "an app's own permissions screen")
assert(pressed("Fullscreen"),
    "fullscreen lives here and nowhere else -- an app cannot ask for it")
assert(#permissionSets == 3, "three changes were made from App Settings")
assert(permissionSets[1].fullscreen == true, "fullscreen turned on")
assert(permissionSets[2].notifications == false, "then notifications blocked")
assert(permissionFull == false,
    "blocking notifications takes fullscreen with it, and allowing them"
        .. " again does not quietly bring it back")
assert(permissionAllowed == true, "notifications are back on")
assert(drewAt("Blocked"), "the screen says so while it is blocked")

-- Notifications actually arriving -----------------------------------------------

assert(#wokeWith == 2, "both alerts reached the OS watcher")
assert(wokeWith[1].name == "FULLSCREEN" and wokeWith[1].took == true,
    "a fullscreen alert takes the screen over")
assert(wokeWith[2].name == "BANNER" and wokeWith[2].took ~= true,
    "a banner does not -- it drops over whatever is open and goes")

assert(drewAt("YAP CHAT"),
    "the fullscreen alert says which app it is from")
assert(drewAt("wordwordword"),
    "and shows the message, all 120 characters of it, without the layout"
        .. " assertions in this harness catching an overflow")
assert(pressed("Got it"))

-- The banner names the app beside the title, so it is not mistaken for the
-- Bank's own.
local bannerLine
for _, item in ipairs(drawnText) do
    if item:find("Yap Chat", 1, true) and item:find("Bo Wolf", 1, true) then
        bannerLine = item
    end
end
assert(bannerLine, "the banner carries the app name and the title together")

print("host_yapchat_app_test: OK")
