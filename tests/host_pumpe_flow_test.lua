-- Full host-side 26x20 layout flow for the PUMPE 5.2.1 experience.

local actions = {
    "next",
    "next",
    "create",
    "gender:They / them",
    "pay",
    "code",
    "proximity",
    "back",
    "send",
    "back",
    "back",
    "balance",
    "back",
    "history",
    "back",
    "events",
    "event:EVT000001",
    "back",
    "back",
    "next",
    "tickets",
    "back",
    "notifications",
    "back",
    "tax",
    "subscriptions",
    "back",
    "next",
    "settings",
    "back",
    "exit",
}
local buttonLabels, drawnText, requests = {}, {}, {}
local savedDevice
local lockSeconds
local WIDTH, HEIGHT = 26, 20

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

term = {
    current = function()
        return {
            getSize = function() return WIDTH, HEIGHT end,
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
    version = "5.2.1",
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
    eventCountdown = function() return "8d 06:30" end,
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
        elseif action == "HISTORY" then
            return {
                transactions = {
                    {
                        description = "Service kiosk purchase with several products"
                            .. " and a clearly visible description",
                        amount = -42.50,
                        day = 42,
                        time = "12:00",
                    },
                },
            }
        elseif action == "LIST_EVENTS" then
            return {
                events = {
                    {
                        event_id = "EVT000001",
                        title = "Summer Festival at the Riverside",
                        location = "Riverside Arena, Gate Two",
                        event_day = 50,
                        event_time = "18:30",
                        from_price = 25,
                    },
                },
            }
        elseif action == "EVENT_DETAILS" then
            return {
                event = {
                    event_id = "EVT000001",
                    title = "Summer Festival at the Riverside",
                    location = "Riverside Arena, Gate Two",
                    event_day = 50,
                    event_time = "18:30",
                },
                ticket_types = {
                    {
                        ticket_type_id = "TT000001",
                        name = "Premium Balcony Admission",
                        price = 25,
                        total_quantity = 100,
                        sold_quantity = 20,
                    },
                },
            }
        elseif action == "MY_TICKETS" then
            return {
                tickets = {
                    {
                        ticket_type_name = "Premium Balcony Admission",
                        event_title = "Summer Festival at the Riverside",
                        event_day = 50,
                        event_time = "18:30",
                        qr_code = "ABCD1234",
                        used = false,
                        location = "Riverside Arena, Gate Two",
                    },
                },
            }
        elseif action == "NOTIFICATIONS" then
            return {
                notifications = {
                    {
                        title = "Welcome to your Foxy Account",
                        body = "Your new PUMPE is ready for code payments,"
                            .. " nearby requests and money transfers.",
                        kind = "info",
                        created_day = 42,
                        created_time = "12:00",
                    },
                },
            }
        elseif action == "TAX_STATUS" then
            return {}
        elseif action == "LIST_SUBSCRIPTIONS" then
            return {
                subscriptions = {
                    {
                        subscription_id = "SUB000001",
                        description = "Daily commuter pass with station access",
                        amount = 12,
                        next_charge_day = 43,
                        active = true,
                    },
                },
            }
        elseif action == "PAY_CODE_PREVIEW" then
            return {
                kind = "purchase",
                amount = 12,
                merchant = "Corner Service Kiosk",
                pin_required = true,
            }
        elseif action == "PAY_CODE_CONFIRM" then
            return {
                balance = 488,
                kind = "purchase",
                amount = 12,
                merchant = "Corner Service Kiosk",
            }
        elseif action == "SEND_MONEY_QUOTE" then
            return {
                recipient = "FoxyFriend",
                amount = 100,
                fee = 10,
                total = 110,
                daily_remaining = 1900,
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
local function assertBox(label, x, y, width, height)
    assert(type(x) == "number" and type(y) == "number"
        and type(width) == "number" and type(height) == "number",
        label .. " has non-numeric bounds")
    assert(x >= 1 and y >= 1, label .. " starts outside the screen")
    assert(width >= 1 and height >= 1, label .. " has an empty size")
    assert(x + width - 1 <= WIDTH, label .. " exceeds screen width")
    assert(y + height - 1 <= HEIGHT, label .. " exceeds screen height")
end

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

function ui.wrap(value, width)
    width = math.max(1, math.floor(tonumber(width) or 1))
    value = tostring(value or "")
    local lines = {}
    for paragraph in (value .. "\n"):gmatch("(.-)\n") do
        paragraph = trim(paragraph)
        if paragraph == "" then
            lines[#lines + 1] = ""
        else
            while #paragraph > width do
                local breakAt
                for index = width, 1, -1 do
                    if paragraph:sub(index, index) == " " then
                        breakAt = index
                        break
                    end
                end
                if not breakAt or breakAt < math.floor(width / 2) then
                    breakAt = width
                end
                lines[#lines + 1] = trim(paragraph:sub(1, breakAt))
                paragraph = trim(paragraph:sub(breakAt + 1))
            end
            if paragraph ~= "" then lines[#lines + 1] = paragraph end
        end
    end
    if #lines == 0 then lines[1] = "" end
    return lines
end

function ui.clear() end
function ui.fill(_, x, y, width, height)
    assertBox("fill", x, y, width, height)
end
function ui.card(_, x, y, width, height)
    assertBox("card", x, y, width, height)
end
function ui.progress(_, x, y, width)
    assertBox("progress", x, y, width, 1)
end
function ui.wipe() end
function ui.boot(_, product, subtitle)
    assert(#tostring(product or "") <= WIDTH, "boot product is clipped")
    assert(#tostring(subtitle or "") <= WIDTH, "boot subtitle is clipped")
end
function ui.networkError(_, err) error(err) end
function ui.header(_, title, subtitle)
    assert(#tostring(title or "") <= WIDTH - 3, "header title is clipped")
    assert(not subtitle or #tostring(subtitle) <= WIDTH - 3,
        "header subtitle is clipped")
    remember(title)
    remember(subtitle)
end
function ui.center(_, y, value)
    assert(y >= 1 and y <= HEIGHT, "centered text is outside the screen")
    assert(#tostring(value or "") <= WIDTH, "centered text is clipped")
    remember(value)
end
function ui.text(_, x, y, value, _, _, maximum)
    assert(x >= 1 and x <= WIDTH, "text starts outside the screen")
    assert(y >= 1 and y <= HEIGHT, "text is outside the screen")
    local available = math.min(maximum or WIDTH, WIDTH - x + 1)
    assert(#tostring(value or "") <= available, "text is clipped")
    remember(value)
end
function ui.wrappedText(_, x, y, value, width, maxLines)
    assertBox("wrapped text", x, y, width, 1)
    local lines = ui.wrap(value, width)
    assert(#lines <= maxLines, "wrapped text loses one or more lines")
    assert(y + #lines - 1 <= HEIGHT, "wrapped text exceeds screen height")
    for _, line in ipairs(lines) do
        assert(#line <= width, "wrapped line exceeds its width")
        remember(line)
    end
    return #lines
end
function ui.truncate(value, maximum)
    value = tostring(value or "")
    return value:sub(1, maximum)
end
function ui.input(_, title)
    if title == "Create Foxy Account" then return "FoxyUser" end
    if title == "PAY A CODE" then return "ABC123" end
    if title == "Send Money" then return "FoxyFriend" end
    if title == "They Receive" then return "100" end
    error("Unexpected input screen: " .. tostring(title))
end
function ui.pin() return "1234" end
function ui.confirm() return true end
function ui.message(_, _, title, body)
    remember(title)
    remember(body)
end

function ui.scene()
    local scene = { width = WIDTH, height = HEIGHT }
    function scene:button(_, x, y, width, height, label)
        assertBox("button", x, y, width, height)
        local lines = ui.wrap(label, math.max(1, width - 2))
        assert(#lines <= height, "button label is clipped: "
            .. tostring(label or ""))
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
    "Code Pay\nEnter a six-character\nkiosk code"))
local proximityIndex = assert(find(buttonLabels,
    "Proximity Pay\nOn and broadcasting\nnearby"))
local sendIndex = assert(find(buttonLabels,
    "Send Money\n10% processing fee\n$2000 daily limit"))
assert(codeIndex < proximityIndex and proximityIndex < sendIndex)
assert(find(buttonLabels, "=\nActivity"))
assert(find(buttonLabels, "o\nSettings"))
assert(find(requests, "REGISTER"))
assert(find(requests, "ACCOUNT_SUMMARY"))

print("host_pumpe_flow_test: OK")
