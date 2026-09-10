-- Yap, the first real app, driven through the phone exactly as it runs: the
-- FoxyLogin consent sheet, the feed with friends on top, the scroll buttons
-- down the right edge, posting, liking and replying. Every draw is bounds
-- checked at 26x20.

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
    if tostring(path):find("YAP", 1, true) then
        return realLoadfile("../apps/yap.lua")
    end
    return realLoadfile(path)
end

local account = {
    account_id = "ACC000001", name = "Ana Fox",
    balance = 500, personal_number = "12345", daily_sent = 0,
}

package.loaded.config = {
    version = "8.4.0", currency = "$",
    send_money_daily_limit = 2000, send_money_fee_rate = 0.10,
    pumpe_lock_seconds = 60, pumpe_pin_seconds = 120,
    urgent_ring_poll_seconds = 3, bet_maximum = 10000,
    app_protocol = "PUMPE_APPS_V1", app_hostname = "APP_SERVER",
    app_chunk_size = 6000, max_apps_installed = 12,
}
package.loaded["lib.util"] = {
    loadTable = function(path, fallback)
        if tostring(path):find("apps", 1, true) then
            return { list = { { app_id = "YAP", name = "Yap Social", version = 1,
                author = "Ana Fox", description = "Say something" } } }
        end
        return fallback
    end,
    saveTable = function() end,
    writeFile = function(path, body) written[path] = body end,
    readFile = function(path) return written[path] end,
    checksum = function() return "0" end,
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

-- Two friends' posts and two strangers', deliberately interleaved so the
-- feed has to do the sorting rather than the fixture.
local POSTS = {
    { id = "YAP000004", data = { body = "stranger says hello" },
      author_id = "ACC000009", author_name = "Zed Stone",
      created_day = 42, created_time = "12:04", reactions = 0,
      reacted = false, mine = false },
    { id = "YAP000003", data = { body = "friend posted third" },
      author_id = "ACC000002", author_name = "Bo Wolf",
      created_day = 42, created_time = "12:03", reactions = 2,
      reacted = false, mine = false },
    { id = "YAP000002", data = { body = "another stranger" },
      author_id = "ACC000008", author_name = "Yan Reed",
      created_day = 42, created_time = "12:02", reactions = 0,
      reacted = false, mine = false },
    { id = "YAP000001", data = { body = "my own first yap" },
      author_id = "ACC000001", author_name = "Ana Fox",
      created_day = 42, created_time = "12:01", reactions = 1,
      reacted = true, mine = true },
}
local approved, posted, liked, replied, purchased
-- What the Bank already says this player has paid for, before the app even
-- opens. One boost on a yap of their own, and one on a stranger's -- which
-- must do nothing, or anybody could lift anybody's post by buying it.
-- A boost already paid for on somebody else's yap. It must lift nothing --
-- otherwise anybody could push anybody's post to the top for ten dollars.
local entitlements = {
    { product_id = "boost_post", name = "Yap Boost", amount = 10,
      active = true, target = "YAP000004" },
    -- A daily boost that was cancelled. The Bank still remembers it, so the
    -- app has to read `active` rather than the product being present.
    { product_id = "boost_all", name = "Yap Boost Daily", amount = 20,
      active = false, period = "day" },
}
local client = {
    discover = function() return true end,
    request = function(_, action, payload)
        requests[#requests + 1] = action
        -- The real Bank rejects any app request that does not carry the id
        -- the app was installed under. Yap shipped in 8.4.0 unable to post
        -- because the runtime never stamped it; the stub said yes and the
        -- server said "That app has no id". A stub more permissive than the
        -- server is a test that cannot fail.
        -- The two account-wide lists are the PUMPE's own screens asking
        -- about every app at once, so they carry no id.
        if (action:find("^APP_") or action:find("^FOXY_LOGIN_")
            or action == "PIN_CHECK")
            and action ~= "FOXY_LOGIN_LIST"
            and action ~= "APP_PERMISSION_LIST" then
            assert(payload.app_id == "YAP", action
                .. " reached the Bank without the app id")
        end
        if action == "LOGIN" then
            return { account = account, session_token = "S" }
        elseif action == "ACCOUNT_SUMMARY" then
            return { account = account }
        elseif action == "PUMPE_POLL" then
            return { balance = account.balance }
        elseif action == "FOXY_LOGIN_STATUS" then
            return { approved = false }
        elseif action == "FOXY_LOGIN_APPROVE" then
            approved = payload
            return { approved = true, profile = {
                account_id = account.account_id, name = account.name,
                scopes = payload.scopes,
                friends = { { account_id = "ACC000002", name = "Bo Wolf" } },
            } }
        elseif action == "APP_DATA_LIST" then
            if payload.collection == "comments" then
                return { records = { { id = "YAC000001",
                    data = { body = "nice one" }, author_id = "ACC000002",
                    author_name = "Bo Wolf", created_time = "12:05",
                    reactions = 0, reacted = false, mine = false } } }
            end
            return { records = POSTS }
        elseif action == "APP_DATA_PUT" then
            if payload.parent then replied = payload else posted = payload end
            return { record = POSTS[1] }
        elseif action == "APP_ENTITLEMENTS" then
            return { entitlements = entitlements }
        elseif action == "APP_PURCHASE_QUOTE" then
            return { product_id = payload.product_id, name = payload.name,
                amount = payload.amount, tax = payload.amount * 0.3,
                to_seller = payload.amount * 0.7, seller = "Cy Hare",
                period = payload.period, balance = 500 }
        elseif action == "APP_PURCHASE" then
            purchased = payload
            entitlements[#entitlements + 1] = {
                product_id = payload.product_id, name = payload.name,
                amount = payload.amount, active = true,
                period = payload.period, target = payload.target,
                subscription = payload.period ~= nil,
            }
            return { bought = entitlements[#entitlements],
                paid = payload.amount, tax = payload.amount * 0.3 }
        elseif action == "APP_DATA_REACT" then
            liked = payload
            local record = {}
            for key, value in pairs(POSTS[2]) do record[key] = value end
            record.reactions, record.reacted = 3, true
            return { record = record }
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

actions = {
    "login",
    "open:ext:YAP",                    -- the app
    "yes",                             -- the FoxyLogin sheet
    "down", "up",                      -- the scroll buttons on the right
    "post:YAP000003",                  -- open a friend's post
    "like", "reply", "back",           -- like it, reply to it, come back
    "post:YAP000001",                  -- open one of my own
    "boost", "all", "buy",             -- Yap Boost, every yap, twenty a day
                                       -- buying returns straight to the feed
    "new",                             -- write one
    "back",                            -- leave Yap
    "next",                            -- Settings moved to page two
    "open:settings", "connected", "back", "back",
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
local function drewAt(needle)
    return table.concat(drawnText, " "):find(needle, 1, true) ~= nil
end

assert(not drew("stopped") and not drew("will not start"),
    "the app must have loaded and run to the end")

-- FoxyLogin asked before the app saw anything.
assert(drew("Sign in") and drew("with Foxy"))
assert(drewAt("Yap Social wants to use your Foxy Accou"),
    "the sheet names the app and what it is for")
assert(drewAt("Who your friends are"),
    "and lists exactly what will be shared")
assert(not drewAt("Your balance"), "not what it never asked for")
assert(pressed("Continue as Ana Fox"))
assert(approved and approved.app_id == "YAP",
    "the app id comes from the install, not from the app")
assert(#approved.scopes == 2 and approved.scopes[1] == "name"
    and approved.scopes[2] == "friends")

-- The feed: friends first, then everybody else, however the Bank hands them
-- over. The fixture deliberately interleaves them so the app has to sort.
local firstAt = {}
for position, item in ipairs(drawnText) do
    for _, who in ipairs({ "Bo Wolf", "Zed Stone", "Yan Reed" }) do
        if item == who and not firstAt[who] then firstAt[who] = position end
    end
end
assert(firstAt["Bo Wolf"] and firstAt["Zed Stone"] and firstAt["Yan Reed"],
    "every post reaches the screen")
assert(firstAt["Bo Wolf"] < firstAt["Zed Stone"]
    and firstAt["Bo Wolf"] < firstAt["Yan Reed"],
    "a friend is shown above everybody else, even when posted after them")
assert(firstAt["Yan Reed"] > firstAt["Zed Stone"],
    "and strangers keep their own order behind them")

-- Posting, liking and replying all reached the Bank.
assert(liked and liked.id == "YAP000003" and liked.on == true)
assert(replied and replied.parent == "YAP000003"
    and replied.data.body == "nice one back")
assert(posted and posted.data.body == "hello world this is my yap"
    and posted.parent == nil)
assert(pressed("+"), "the + is on the bottom of the feed")
assert(drew("nice one"), "replies are listed under the post")

-- And Settings can take the grant back.
assert(drew("Connected Apps"))

-- Yap Boost ---------------------------------------------------------------------
-- The app does not decide that somebody has paid. It asks what the Bank
-- recorded, and orders the feed by that.

assert(pressed("Boost this yap"),
    "a yap you wrote can be boosted from its own screen, and a cancelled"
        .. " subscription does not count as boosting it")
assert(drewAt("Yap Boost"), "and the sheet says what it is")
assert(pressed("This yap\n$10 once"), "ten for one yap")
assert(pressed("Every yap\n$20 a day"), "twenty a day for all of them")

assert(purchased, "the purchase reached the phone's API")
assert(purchased.product_id == "boost_all" and purchased.amount == 20,
    "boosting everything is twenty")
assert(purchased.period == "day",
    "and it is a subscription, not a one-off charge")

-- The purchase sheet is the phone's, not the app's: it prices it and shows
-- what the government takes.
assert(drew("Yap Boost"), "the phone names what is being bought")
assert(drew("Tax "), "and shows the tax")

-- A boosted yap rises above a friend's, which is the whole product. The
-- last feed drawn is the one after the subscription was bought, so this
-- reads the final positions rather than the first.
-- The feed header says how many posts there are, so the last one of those
-- marks where the final feed render begins. Names drawn on a post screen or
-- a purchase sheet before it are not the feed.
local feedStart = 0
for position, item in ipairs(drawnText) do
    if item:match("^%d+ posts$") then feedStart = position end
end
assert(feedStart > 0, "the feed was drawn")
local at = {}
for position = feedStart, #drawnText do
    for _, who in ipairs({ "Ana Fox", "Bo Wolf", "Zed Stone" }) do
        if drawnText[position] == who and not at[who] then
            at[who] = position
        end
    end
end
assert(at["Ana Fox"] and at["Bo Wolf"] and at["Zed Stone"],
    "every yap reached the screen")
assert(at["Ana Fox"] < at["Bo Wolf"],
    "a boosted yap of your own sits above a friend's")
assert(at["Zed Stone"] > at["Bo Wolf"],
    "but a boost bought on somebody else's yap lifts nothing -- otherwise"
        .. " anybody could push anybody's post to the top for ten dollars")

print("host_yap_app_test: OK")
