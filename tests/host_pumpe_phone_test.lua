-- Phone numbers on the PUMPE, FoxyOS 17, on its native 26x20 screen: the
-- Phone tab in Messages getting a number, then calling a radio in a giveaway
-- (which costs money, so it asks), a person (who rings, through Urgent
-- Contact) and texting a number. And a chat cannot be started without a
-- number: it offers to get one instead.

local WIDTH, HEIGHT = 26, 20
buttonLabels, drawnText, requests = {}, {}, {}
ringHandler = nil

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
shell = { getRunningProgram = function() return "/pumpe/pumpe.lua" end }
sleep = function() end

local account = {
    account_id = "ACC000001", name = "FoxyUser",
    balance = 500, personal_number = "12345", daily_sent = 0,
}

package.loaded.config = {
    version = "6.2.0", currency = "$",
    send_money_daily_limit = 2000, send_money_fee_rate = 0.10,
    pumpe_lock_seconds = 60, pumpe_pin_seconds = 120,
    urgent_ring_poll_seconds = 3, bet_maximum = 10000,
}

package.loaded["lib.util"] = {
    loadTable = function(_, fallback)
        fallback.onboarding_complete = true
        fallback.last_name = "FoxyUser"
        return fallback
    end,
    saveTable = function() end,
    trim = function(value) return tostring(value or ""):match("^%s*(.-)%s*$") end,
    money = function(value, symbol) return (symbol or "$") .. tostring(value) end,
    formatClock = function() return "12:00" end,
    ingameDay = function() return 42 end,
    page = function(items, requestedPage, pageSize)
        local pages = math.max(1, math.ceil(#items / pageSize))
        local page = math.max(1, math.min(requestedPage or 1, pages))
        local output = {}
        local first = (page - 1) * pageSize + 1
        for index = first, math.min(#items, first + pageSize - 1) do
            output[#output + 1] = items[index]
        end
        return output, page, pages
    end,
}

local myNumber = nil
local lookups, calls, chats = {}, {}, {}
local client = {
    discover = function() return true end,
    request = function(_, action, payload)
        requests[#requests + 1] = action
        if action == "LOGIN" then
            return { account = account, session_token = "SESSION" }
        elseif action == "ACCOUNT_SUMMARY" then
            return { account = account, unread_notifications = 0,
                unread_messages = 0, friend_requests = 0, friend_count = 1 }
        elseif action == "PHONE_ME" then
            return { number = myNumber, messages = 0, calls = #calls,
                messages_limit = 40, calls_limit = 10, tier = 0 }
        elseif action == "PHONE_GET" then
            myNumber = "345-6789"
            return { number = myNumber, messages = 0, calls = 0, messages_limit = 40,
                calls_limit = 10 }
        elseif action == "PHONE_LOOKUP" then
            lookups[#lookups + 1] = payload.number
            if payload.number == "666-1234" then
                return { number = payload.number, kind = "radio", name = "Foxy FM" }
            end
            return { number = payload.number, kind = "person", name = "Bob Wolf" }
        elseif action == "PHONE_CALL" then
            calls[#calls + 1] = payload.number
            if payload.number == "666-1234" then
                return { kind = "radio", name = "Foxy FM", price = 50, entries = 1,
                    all_entries = 3 }
            end
            return { kind = "person", name = "Bob Wolf", call = { call_id = "CALL9",
                other_name = "Bob Wolf", status = "ringing" } }
        elseif action == "URGENT_STATE" then
            return { call = { call_id = "CALL9", other_name = "Bob Wolf",
                status = "ringing" }, messages = {} }
        elseif action == "URGENT_END" then
            return { call = { call_id = "CALL9", status = "ended" } }
        elseif action == "CHAT_LIST" then
            return { conversations = {} }
        elseif action == "CHAT_START" then
            chats[#chats + 1] = payload.number
            return { conversation = { conversation_id = "CHAT7", kind = "direct",
                title = "Bob Wolf", unread = 0, member_count = 2,
                member_names = { "FoxyUser", "Bob Wolf" }, last_preview = "" } }
        elseif action == "CHAT_OPEN" then
            return { conversation = { conversation_id = "CHAT7", kind = "direct",
                title = "Bob Wolf", member_count = 2, member_names = { "FoxyUser",
                "Bob Wolf" }, unread = 0 }, messages = {}, next_seq = 1 }
        elseif action == "PUMPE_POLL" then
            return { balance = account.balance, unread_notifications = 0,
                unread_messages = 0, friend_requests = 0 }
        elseif action == "NOTIFICATIONS" then
            return { notifications = {} }
        elseif action == "MARK_NOTIFICATIONS_READ" then
            return { ok = true }
        end
        error("Unexpected PUMPE request: " .. tostring(action))
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
function ui.setBackgroundTask(seconds, handler) ringHandler = handler end
function ui.clear() end
function ui.boot() end
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
function ui.text(_, x, y, value)
    assert(x >= 1 and y >= 1 and y <= HEIGHT, "text outside the screen")
    assert(x + #tostring(value or "") - 1 <= WIDTH,
        "text overflows the screen: " .. tostring(value))
    drawnText[#drawnText + 1] = tostring(value or "")
end
function ui.center(_, y, value)
    assert(y >= 1 and y <= HEIGHT, "centered text outside the screen")
    assert(#tostring(value or "") <= WIDTH)
    drawnText[#drawnText + 1] = tostring(value or "")
end
function ui.wrappedText(_, x, y, value, width, maxLines)
    for index, line in ipairs(ui.wrap(value, width)) do
        if index <= maxLines then ui.text(nil, x, y + index - 1, line) end
    end
end
function ui.header(_, title, subtitle)
    drawnText[#drawnText + 1] = tostring(title or "")
    drawnText[#drawnText + 1] = tostring(subtitle or "")
end
function ui.message(_, kind, title) drawnText[#drawnText + 1] = tostring(title) end
function ui.networkError(_, err) error("unexpected network error: " .. tostring(err)) end


inputs = {
    "666 1234",   -- a radio's number, typed with a space
    "2345679",    -- a person's
    "2345679",    -- texted
}
function ui.input() return table.remove(inputs, 1) end
function ui.pin() return "1234" end
local confirms = {
    false,        -- + New chat without a number: not now
    true,         -- calling the radio costs $50: call
}
local confirmed = {}
function ui.confirm(_, title, body)
    confirmed[#confirmed + 1] = title .. ": " .. tostring(body)
    return table.remove(confirms, 1)
end

actions = {
    "open:messages",
    "new",              -- a new chat, but no number yet: it offers one
    "tab:phone",
    "get",              -- Get a number
    "call",             -- the radio
    "call",             -- a person: it rings through Urgent Contact
    "cancel",           -- and is hung up while it rings
    "text",             -- texting a number opens the chat
    "back",
    "home",
    "__terminate",
}
index = 0
-- FoxyOS 16: a call is a banner drawn over whatever is open, with buttons of
-- its own. A tap on one is the banner's to answer, exactly as in lib/ui.
local overlay
function ui.setOverlay(spec) overlay = spec end
function ui.topBanner(_, spec)
    drawnText[#drawnText + 1] = tostring(spec.title or "")
    drawnText[#drawnText + 1] = tostring(spec.body or "")
    local buttons = {}
    for slot, button in ipairs(spec.buttons or {}) do
        buttonLabels[#buttonLabels + 1] = button.label
        buttons[slot] = { id = button.id, x1 = slot, x2 = slot, y1 = 2, y2 = 2 }
    end
    return { top = 1, bottom = 4, buttons = buttons }
end
function ui.scene()
    local scene = { width = WIDTH, height = HEIGHT }
    local live = {}
    function scene:button(id, x, y, width, height, label, options)
        assertBox("button '" .. tostring(label) .. "'", x, y, width, height)
        buttonLabels[#buttonLabels + 1] = tostring(label or "")
        -- A disabled button is drawn but cannot be tapped, exactly as in the
        -- real scene, so the script cannot reach through one.
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
        if action == "__ring" then
            -- Exactly what the shared wait loop does when a call arrives.
            urgentStatus = "incoming"
            assert(ringHandler, "the ring watcher was never armed")
            assert(ringHandler() == true, "an incoming call must take over")
            return "__wake"
        end
        local bannerId = action:match("^banner:(.+)$")
        if bannerId then
            local onBanner = false
            for _, button in ipairs(overlay and overlay.buttons or {}) do
                if button.id == bannerId then onBanner = true end
            end
            assert(onBanner, "tapped the banner's " .. bannerId .. " but it is not up")
            overlay.tap(bannerId)
            return "__wake"
        end
        if not action:match("^__") then
            assert(live[action],
                "tapped '" .. action .. "' but no such button is on screen")
        end
        return action
    end
    return scene
end
-- 11.0: the tab bar and tab host every app shares, run for real against
-- this stub's scenes.
do
    local realUi = dofile("real_ui.lua")
    ui.tabBar, ui.runTabs = realUi.tabBar, realUi.runTabs
    -- 12.0: the bar paints its labels rather than putting them on buttons,
    -- so what the app asked it to show is read here instead.
    local paint = ui.tabBar
    ui.tabBar = function(scene, target, tabs, ...)
        for _, tab in ipairs(tabs) do buttonLabels[#buttonLabels + 1] = tab.label end
        return paint(scene, target, tabs, ...)
    end
end
dofile("ui_stub_fill.lua")(ui)
-- 12.0: a phone with an account starts on its lock screen, which waits for
-- a tap before asking for the PIN.
os.startTimer = os.startTimer or function() return 0 end
os.pullEvent = os.pullEvent or function() return "mouse_click", 1, 1, 1 end
package.loaded["lib.ui"] = ui

local ok, err = pcall(assert(loadfile("../pumpe.lua")))
assert(ok or tostring(err):find("more actions", 1, true), tostring(err))

local function drew(text)
    for _, item in ipairs(drawnText) do
        if item:find(text, 1, true) then return true end
    end
    return false
end

assert(confirmed[1]:find("Get a number", 1, true), "no number: it offers one, "
    .. tostring(confirmed[1]))
local function button(label)
    for _, item in ipairs(buttonLabels) do if item == label then return true end end
    return false
end
assert(drew("No number yet") and button("Get a number"), "the Phone tab, before a number")
assert(button("Call a number") and button("Text a number"))
assert(drew("345-6789"), "the number, once got")
assert(drew("Today") and drew("0 / 40"), "and what today has left")
assert(lookups[1] == "666-1234", "dashes and spaces are fine")
assert(confirmed[2]:find("Call Foxy FM", 1, true) and confirmed[2]:find("$50", 1, true),
    "a radio call says what it costs first")
assert(calls[1] == "666-1234" and drew("You're in!"))
assert(calls[2] == "234-5679" and drew("Reaching"), "a person rings")
local ended = false
for _, item in ipairs(requests) do if item == "URGENT_END" then ended = true end end
assert(ended, "hung up while it rang")
assert(chats[1] == "234-5679", "texting starts a chat with the number")
assert(#inputs == 0 and #confirms == 0, "everything scripted was asked")

print("host_pumpe_phone_test: OK")
