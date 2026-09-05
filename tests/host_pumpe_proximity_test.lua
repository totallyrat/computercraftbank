-- The PUMPE side of Proximity ticket scanning, Proximity Visa and Portable
-- Mode: three full-screen asks that arrive from the OS poll while any app is
-- open, and are answered without leaving the screen you were on.

local WIDTH, HEIGHT = 26, 20
buttonLabels, drawnText, requests = {}, {}, {}
ringHandler = nil

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

term = { current = function()
    return { getSize = function() return WIDTH, HEIGHT end }
end }
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
    version = "8.2.0", currency = "$",
    send_money_daily_limit = 2000, send_money_fee_rate = 0.10,
    pumpe_lock_seconds = 60, pumpe_pin_seconds = 120,
    urgent_ring_poll_seconds = 3, bet_maximum = 10000,
}
package.loaded["lib.util"] = {
    loadTable = function(_, fallback) return fallback end,
    saveTable = function() end,
    trim = function(v) return tostring(v or ""):match("^%s*(.-)%s*$") end,
    money = function(v, symbol) return (symbol or "$") .. tostring(v) end,
    formatClock = function() return "12:00" end,
    ingameDay = function() return 42 end,
    eventCountdown = function() return "1d 00:00" end,
    page = function(items, page, size)
        local pages = math.max(1, math.ceil(#items / size))
        page = math.max(1, math.min(page or 1, pages))
        local out = {}
        for index = (page - 1) * size + 1,
            math.min(#items, page * size) do
            out[#out + 1] = items[index]
        end
        return out, page, pages
    end,
}

-- What the OS poll hands back next. Each scenario sets this, then fires the
-- background handler exactly as the shared wait loop does.
local pending = {}
local scanAccepted, scanDeclined, claimed, paid
local client = {
    discover = function() return true end,
    request = function(_, action, payload)
        requests[#requests + 1] = action
        if action == "LOGIN" then
            return { account = account, session_token = "S" }
        elseif action == "ACCOUNT_SUMMARY" then
            return { account = account }
        elseif action == "PUMPE_POLL" then
            return pending
        elseif action == "SCAN_ACCEPT" then
            scanAccepted = payload.request_id
            return { scan = { status = "accepted" } }
        elseif action == "SCAN_DECLINE" then
            scanDeclined = payload.request_id
            return { scan = { status = "offered" } }
        elseif action == "PROXIMITY_ACCEPT" then
            claimed = payload.offer_id
            return { offer = { offer_id = payload.offer_id,
                status = "claimed" } }
        elseif action == "PAY_CODE_PREVIEW" then
            return { amount = 12, pin_required = true }
        elseif action == "PAY_CODE_CONFIRM" then
            paid = payload.code
            return { balance = 488 }
        end
        return { ok = true }
    end,
}
package.loaded["lib.net"] = {
    client = function() return client end,
    autoUpdate = function() end,
    locate = function() return { x = 1, y = 64, z = 1 } end,
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
function ui.text(_, x, y, value)
    assert(x >= 1 and y >= 1 and y <= HEIGHT, "text outside the screen")
    assert(x + #tostring(value or "") - 1 <= WIDTH,
        "text overflows the screen: " .. tostring(value))
    drawnText[#drawnText + 1] = tostring(value or "")
end
function ui.center(_, y, value)
    assert(y >= 1 and y <= HEIGHT, "centered text outside the screen")
    assert(#tostring(value or "") <= WIDTH, "centered text is clipped")
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
function ui.message(_, _, title) drawnText[#drawnText + 1] = tostring(title) end
function ui.confirm() return true end
function ui.pin() return "1234" end
function ui.input() return "FoxyUser" end
function ui.networkError(_, err) error("unexpected network error: " .. tostring(err)) end

-- A tap, or one of two scripted arrivals:
--   __wake:<name>  hands the OS poll a new answer and runs the background
--                  handler, exactly as the shared wait loop does
--   __poll:<name>  hands the poll a new answer and ticks, for a screen that
--                  is already open and polling for itself
local polls = {}
actions = {
    "login",
    -- A ticket check while the home screen is open.
    "__wake:ticket", "yes",
    -- A border check, which warns to stand close before the gate opens.
    "__wake:visa", "no",
    -- Portable Mode: take the sale, then the basket lands on the same screen.
    "__wake:claim", "yes", "__poll:basket", "pay",
    "__terminate",
}
local index = 0
function ui.scene()
    local scene = { width = WIDTH, height = HEIGHT }
    local live = {}
    function scene:button(id, x, y, width, height, label, options)
        assertBox("button '" .. tostring(label) .. "'", x, y, width, height)
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
        local wake = action:match("^__wake:(.+)$")
        local poll = action:match("^__poll:(.+)$")
        if wake or poll then
            pending = assert(polls[wake or poll], "unknown scripted poll")
            if poll then return "__tick" end
            assert(ringHandler, "the OS watcher was never armed")
            local took = ringHandler()
            assert(took == true, "an arrival must take over: got "
                .. tostring(took) .. " for " .. action)
            return "__wake"
        end
        if not action:match("^__") then
            assert(live[action], "tapped '" .. action
                .. "' but no such button is on screen")
        end
        return action
    end
    return scene
end
package.loaded["lib.ui"] = ui

local TICKET_SCAN = { scan = { request_id = "SCAN01", kind = "ticket",
    status = "offered", title = "Ticket check",
    detail = "Scan your ticket for Riverside", distance = 3 } }
local VISA_SCAN = { scan = { request_id = "SCAN02", kind = "visa",
    status = "offered", title = "Border check",
    detail = "Stand at the Fox Republic border to cross" } }
local CLAIM = { offer = { offer_id = "NEAR01", portable = true,
    status = "claiming", merchant = "Market Cart", distance = 2 } }
local BASKET = { offer = { offer_id = "NEAR01", portable = true,
    status = "offered", code = "ABC123", amount = 12,
    merchant = "Market Cart",
    items = { { name = "Apple", price = 4, quantity = 3 } } } }

polls.ticket, polls.visa = TICKET_SCAN, VISA_SCAN
polls.claim, polls.basket = CLAIM, BASKET

local ok, err = pcall(assert(loadfile("../pumpe.lua")))
assert(ok or tostring(err):find("more actions", 1, true), tostring(err))

local function drew(text)
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

-- The ticket check took the whole screen and was accepted.
assert(drew("TICKET CHECK"), "a ticket check takes over the screen")
assert(pressed("Scan my ticket"))
assert(scanAccepted == "SCAN01", "accepting reaches the Bank")

-- The border check warns to stand close, because the gate opens for two
-- seconds and then closes again.
assert(drew("BORDER CHECK"))
assert(pressed("Open the gate"))
-- The warning wraps across lines, so match it on the rejoined screen.
assert(table.concat(drawnText, " "):find("two seconds", 1, true),
    "the border popup says the gate only opens briefly")
assert(table.concat(drawnText, " "):find("stand close", 1, true),
    "and tells them to be close before accepting")
assert(scanDeclined == "SCAN02", "declining passes it to the next person")

-- Portable Mode: claim first, basket second, pay last.
assert(drew("PAYING HERE?"), "the sale finds the customer before the basket")
assert(pressed("That is me"))
assert(claimed == "NEAR01")
assert(drew("Your Basket"), "the itemised basket arrives on the PUMPE")
assert(drew("3x Apple"), "with the lines the operator rang up")
assert(pressed("Continue  $12"))
assert(paid == "ABC123", "and confirming again is what actually pays")

print("host_pumpe_proximity_test: OK")
