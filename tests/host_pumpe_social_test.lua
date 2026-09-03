-- Friends, Messages, and Urgent Contact on the PUMPE's native 26x20 screen.

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

-- Four friends means the group picker needs a second page.
local friends = {
    { account_id = "ACC000002", name = "Bob Wolf" },
    { account_id = "ACC000003", name = "Cara Lynx" },
    { account_id = "ACC000006", name = "Finn Otter" },
    { account_id = "ACC000007", name = "Gus Stoat" },
}
local groupMembers
local chatMessages = {
    { seq = 1, sender_id = "ACC000002", sender_name = "Bob Wolf",
        kind = "text", body = "Are you at the market?" },
}
urgentStatus = "ringing"

local client = {
    discover = function() return true end,
    request = function(_, action, payload)
        requests[#requests + 1] = action
        if action == "LOGIN" then
            return { account = account, session_token = "SESSION" }
        elseif action == "ACCOUNT_SUMMARY" then
            return { account = account, unread_notifications = 0,
                unread_messages = 2, friend_requests = 1, friend_count = 2 }
        elseif action == "FRIEND_OVERVIEW" then
            return { friends = friends,
                incoming = { { account_id = "ACC000004", name = "Dave Elk" } },
                outgoing = {} }
        elseif action == "FRIEND_SEARCH" then
            assert(#payload.query >= 2)
            return { results = { { account_id = "ACC000005",
                name = "Erin Hare", friend = false, requested = false } } }
        elseif action == "FRIEND_REQUEST" then
            return { status = "requested", name = "Erin Hare" }
        elseif action == "CHAT_START" then
            groupMembers = payload.account_ids
            return { conversation = { conversation_id = "CHAT0002",
                kind = "group", title = payload.title or "Group",
                unread = 0, member_count = 3,
                member_names = { "FoxyUser", "Bob Wolf", "Gus Stoat" },
                last_preview = "", last_at = 20 } }
        elseif action == "CHAT_LIST" then
            return { conversations = { {
                conversation_id = "CHAT0001", kind = "direct",
                title = "Bob Wolf", unread = 2, member_count = 2,
                member_names = { "FoxyUser", "Bob Wolf" },
                last_preview = "Are you at the market?", last_at = 10,
            } } }
        elseif action == "CHAT_OPEN" then
            local after = payload.after_seq or 0
            local out = {}
            for _, item in ipairs(chatMessages) do
                if item.seq > after then out[#out + 1] = item end
            end
            return {
                conversation = { conversation_id = "CHAT0001",
                    kind = "direct", title = "Bob Wolf", member_count = 2,
                    member_names = { "FoxyUser", "Bob Wolf" }, unread = 0 },
                messages = out, next_seq = #chatMessages + 1,
            }
        elseif action == "CHAT_SEND" then
            assert(payload.body == "On my way now")
            chatMessages[#chatMessages + 1] = {
                seq = #chatMessages + 1, sender_id = account.account_id,
                sender_name = "FoxyUser", kind = "text", body = payload.body }
            return { message = chatMessages[#chatMessages] }
        elseif action == "CHAT_REQUEST_MONEY" then
            assert(payload.amount == 25)
            chatMessages[#chatMessages + 1] = {
                seq = #chatMessages + 1, sender_id = account.account_id,
                sender_name = "FoxyUser", kind = "money_request",
                body = "", amount = 25, status = "pending" }
            return { message = chatMessages[#chatMessages] }
        elseif action == "NOTIFICATIONS" then
            return { notifications = {} }
        elseif action == "MARK_NOTIFICATIONS_READ" then
            return { ok = true }
        elseif action == "PUMPE_POLL" then
            local poll = {
                balance = account.balance, unread_notifications = 0,
                unread_messages = 2, friend_requests = 1,
            }
            if urgentStatus == "incoming" then
                poll.call = { call_id = "CALL1", other_name = "Bob Wolf",
                    status = "ringing", outgoing = false, save_votes = 0 }
            end
            return poll
        elseif action == "URGENT_ANSWER" then
            assert(payload.accept == true)
            urgentStatus = "active"
            return { call = { call_id = "CALL1", other_name = "Bob Wolf",
                status = "active", save_votes = 0, i_saved = false } }
        elseif action == "URGENT_STATE" then
            return { call = { call_id = "CALL1", other_name = "Bob Wolf",
                status = urgentStatus == "active" and "active" or "ended",
                save_votes = 0, i_saved = false, saved = false }, messages = {} }
        elseif action == "URGENT_SEND" then
            assert(payload.body == "Two minutes")
            return { message = { seq = 1, sender_name = "FoxyUser",
                kind = "text", body = payload.body } }
        elseif action == "URGENT_SAVE" then
            return { call = { call_id = "CALL1", other_name = "Bob Wolf",
                status = "active", save_votes = 1, i_saved = true } }
        elseif action == "URGENT_END" then
            urgentStatus = "ended"
            return { call = { call_id = "CALL1", other_name = "Bob Wolf",
                status = "ended", saved = false, save_votes = 1 } }
        end
        error("Unexpected PUMPE request: " .. tostring(action))
    end,
}
package.loaded["lib.net"] = {
    client = function() return client end,
    autoUpdate = function() end,
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

-- login() asks for the account name first, then each screen's own input, in
-- the order the scripted actions below reach them.
inputs = {
    "FoxyUser",         -- sign in
    "On my way now",    -- chat message
    "25",               -- money request amount
    "Market Run",       -- group name
    "Two minutes",      -- urgent contact message
    "hare",             -- friend search
}
function ui.input() return table.remove(inputs, 1) end
function ui.pin() return "1234" end
function ui.confirm() return false end

actions = {
    "login",                    -- account landing
    "next",                     -- Favourites is page one; apps are page two
    "open:friends",             -- the one social app
    "messages",                 -- its Messages entry
    "open:CHAT0001",            -- chat list
    "type",                     -- send a message
    "money", "ask",             -- ask for money
    "back",                     -- leave the chat
    "group",                    -- build a group
    "pick:ACC000002",           -- first page
    "next",                     -- second page of friends
    "pick:ACC000007",           -- only reachable once paging works
    "create",
    "back",                     -- leave the new group chat
    "back",                     -- leave Messages
    "__ring",                   -- a friend reaches us from inside the app
    "accept",                   -- answer the Urgent Contact
    "type",                     -- talk
    "save",                     -- vote to save
    "hang",                     -- hang up
    "people",                   -- the Friends list inside the same app
    "add",                      -- search
    "add:ACC000005",            -- send a request
    "back",                     -- leave search
    "back",                     -- leave the Friends list
    "back",                     -- leave the social app
    "next", "next",             -- every home page renders
    "__terminate",
}
index = 0
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
        if not action:match("^__") then
            assert(live[action],
                "tapped '" .. action .. "' but no such button is on screen")
        end
        return action
    end
    return scene
end
package.loaded["lib.ui"] = ui

local ok, err = pcall(assert(loadfile("../pumpe.lua")))
assert(ok or tostring(err):find("more actions", 1, true), tostring(err))

-- The transcript wraps to the 26-column screen, so match a fragment.
local function drewContaining(text)
    for _, item in ipairs(drawnText) do
        if item:find(text, 1, true) then return true end
    end
    return false
end
local function pressed(label)
    for _, item in ipairs(buttonLabels) do
        if item == label then return true end
    end
    return false
end
local function asked(action)
    for _, item in ipairs(requests) do
        if item == action then return true end
    end
    return false
end

-- Home screen badges surface waiting messages and friend requests.
-- One social app, badged with everything waiting inside it.
assert(pressed("3\nFriends"),
    "unread messages and friend requests badge the one social app")
assert(pressed("Messages (2)"), "the hub shows what is waiting in Messages")
assert(pressed("Friends (+1)"), "and the requests waiting in Friends")
assert(pressed("Urgent Contact"), "Urgent Contact lives in the same app")

-- Messages
assert(asked("CHAT_LIST") and asked("CHAT_OPEN") and asked("CHAT_SEND"))
assert(asked("CHAT_REQUEST_MONEY"), "money can be asked for inside a chat")
assert(drewContaining("Bob Wolf:"), "the transcript names the sender")
assert(drewContaining("market"), "the transcript renders the message body")

-- Group chats can reach every friend, not just the first screenful.
assert(groupMembers and #groupMembers == 2, "both picks must reach the Bank")
local picked = {}
for _, id in ipairs(groupMembers) do picked[id] = true end
assert(picked["ACC000002"] and picked["ACC000007"],
    "a friend on the second page of the picker must be selectable")

-- Urgent Contact reached the user from the home screen, not from its own app.
assert(asked("PUMPE_POLL") and asked("URGENT_ANSWER"))
assert(pressed("Accept") and pressed("Decline"),
    "an incoming call shows Accept and Decline")
assert(asked("URGENT_SEND") and asked("URGENT_SAVE") and asked("URGENT_END"))
assert(pressed("Hang up"), "a live call can always be hung up")

-- Friends
assert(asked("FRIEND_OVERVIEW") and asked("FRIEND_SEARCH")
    and asked("FRIEND_REQUEST"))
assert(pressed("Erin Hare\nTap to add"), "search results are tappable")

-- A PUMPE left holding a newer pumpe.lua than lib/ui.lua must still launch.
-- Before v6.2.2 this crashed at startup on ui.setBackgroundTask.
ui.setBackgroundTask = nil
ringHandler = nil
buttonLabels, drawnText, requests = {}, {}, {}
urgentStatus = "ringing"
index = 0
inputs = { "FoxyUser" }
actions = {
    "login",
    "__tick", "__tick", "__tick", "__tick", "__tick", "__tick",
    "__terminate",
}
local launched, launchError = pcall(assert(loadfile("../pumpe.lua")))
assert(launched, "an older lib/ui.lua must not stop the PUMPE launching: "
    .. tostring(launchError))
assert(asked("PUMPE_POLL"),
    "without the shared hook, the Home Screen must still check for calls")

print("host_pumpe_social_test: OK")
