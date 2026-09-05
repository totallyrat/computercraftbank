-- Full host-side 26x20 layout flow for the PUMPE 8.0 experience.

-- Walks the home screen rebuilt for 8.0: sign-up, the guide, the icon grid
-- with its dock, every app hub, and the notification centre as the last
-- page, with every screen bounds-checked at 26x20.
local actions = {
    "create",                                        -- new account
    "next", "next", "next", "next", "next", "next",  -- the six guide steps
    "edit", "pick:buck", "pick:friends", "back",     -- fill the dock
    "open:buck",                                     -- BuckApp from the dock
    "pay", "code", "send", "back", "back",           -- payments behind Continue
    "activity", "back",                              -- activity inside BuckApp
    "wallet", "holding", "back", "activity", "back",
    "add", "withdraw", "back",                       -- Bet Wallet inside BuckApp
    "back",                                          -- leave BuckApp
    "open:tickets", "browse", "event:EVT000001", "back", "back",
    "mine", "back", "back",                          -- Tickets hub
    "open:customs",
    "visas", "documents", "back", "applications", "back", "back",
    "territories", "territory:TER000001", "citizens", "back",
    "applications", "back", "roam", "back", "back", "back",
    "back",                                          -- leave the Customs hub
    "open:bet", "pick:heads", "__tick", "done",
    "open:tax",                                      -- returns on its own
    "open:subs", "back",
    "next",                                          -- the notification centre
    "note:1", "back",                                -- read one in full
    "markread",
    "prev",                                          -- back to the apps
    "open:settings", "guide", "next", "done",        -- the guide from Settings
    "dock", "back", "close",
}
local buttonLabels, drawnText, requests = {}, {}, {}
local savedDevice
local lockSeconds
local betStatusCalls = 0
local WIDTH, HEIGHT = 26, 20
local LONG_CCG_CODE = "CCG2026LONGSCREENCODE987654321"

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
    version = "6.0.0",
    currency = "$",
    send_money_daily_limit = 2000,
    send_money_fee_rate = 0.10,
    pumpe_lock_seconds = 60,
    pumpe_pin_seconds = 120,
    max_ticket_quantity = 5,
    max_territories_per_account = 3,
    visa_min_days = 1,
    visa_max_days = 30,
    bet_maximum = 10000,
}

package.loaded["lib.util"] = {
    loadTable = function(_, fallback) return fallback end,
    trim = function(value)
        return tostring(value or ""):match("^%s*(.-)%s*$")
    end,
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
            return { account = account, unread_notifications = 0 }
        elseif action == "PUMPE_POLL" then
            return {
                balance = account.balance,
                unread_notifications = 1,
                unread_messages = 0,
                friend_requests = 0,
                latest = {
                    notification_id = "NOT00000001",
                    title = "Welcome",
                    body = "Your PUMPE is ready",
                    kind = "info",
                },
            }
        elseif action == "MARK_NOTIFICATIONS_READ" then
            return { ok = true }
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
        elseif action == "VISA_OVERVIEW" then
            return {
                documents = {
                    {
                        visa_id = "VISA00000001",
                        code = "ABCD2345",
                        kind = "citizenship",
                        territory_id = "TER000001",
                        territory_name = "Foxy Republic",
                        permanent = true,
                        status = "active",
                        issued_day = 42,
                        free_roam = {
                            {
                                territory_id = "TER000002",
                                territory_name = "River State",
                            },
                        },
                        visits = {},
                    },
                },
                applications = {
                    {
                        application_id = "VAPP00000001",
                        territory_id = "TER000002",
                        territory_name = "River State",
                        applicant_name = "FoxyUser",
                        requested_days = 7,
                        status = "pending",
                        created_day = 42,
                    },
                },
                territories = {
                    {
                        territory_id = "TER000001",
                        name = "Foxy Republic",
                        access = "citizenship",
                        can_apply = false,
                    },
                    {
                        territory_id = "TER000002",
                        name = "River State",
                        pending = true,
                        can_apply = false,
                    },
                },
                visa_min_days = 1,
                visa_max_days = 30,
            }
        elseif action == "CUSTOMS_OVERVIEW" then
            return {
                territories = {
                    {
                        territory_id = "TER000001",
                        name = "Foxy Republic",
                        citizen_count = 1,
                        free_roam_count = 1,
                        pending_count = 1,
                        created_day = 42,
                    },
                },
                maximum_territories = 3,
            }
        elseif action == "CUSTOMS_DETAIL" then
            return {
                territory = {
                    territory_id = "TER000001",
                    name = "Foxy Republic",
                    citizen_count = 1,
                    free_roam_count = 1,
                },
                citizens = {
                    {
                        account_id = "ACC000001",
                        name = "FoxyUser",
                        code = "ABCD2345",
                        issued_day = 42,
                    },
                },
                applications = {
                    {
                        application_id = "VAPP00000002",
                        territory_id = "TER000001",
                        territory_name = "Foxy Republic",
                        applicant_name = "VisitingFriend",
                        requested_days = 5,
                        status = "pending",
                        created_day = 42,
                    },
                },
                other_territories = {
                    {
                        territory_id = "TER000002",
                        name = "River State",
                        free_roam = true,
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
                kind = "subscription",
                amount = 12,
                merchant = "Corner Service Kiosk",
                pin_required = true,
            }
        elseif action == "PAY_CODE_CONFIRM" then
            return {
                balance = 488,
                kind = "subscription",
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
        elseif action == "BET_UNLOCK" then
            assert(payload.pin == "1234")
            return {
                bet_token = "BET_TOKEN",
                wallet = {
                    available = 100,
                    held = 20,
                    hold_count = 1,
                    holds = {
                        {
                            hold_id = "HOLD0000000001",
                            amount = 20,
                            status = "holding",
                            game_name = "Heads or Tails",
                            release_day = 43,
                            release_time = "12:00",
                        },
                    },
                    activity = {
                        {
                            description = "Heads or Tails winnings - holding",
                            amount = 20,
                            day = 42,
                        },
                    },
                },
            }
        elseif action == "BET_JOIN" then
            assert(payload.bet_token == "BET_TOKEN")
            assert(payload.code == LONG_CCG_CODE)
            assert(payload.display_name == "FoxyPlayer")
            return {
                lobby = {
                    code = LONG_CCG_CODE,
                    game = "heads_tails",
                    game_name = "Heads or Tails",
                    multiplier = 2,
                    status = "lobby",
                },
            }
        elseif action == "BET_PLACE_WAGER" then
            assert(payload.code == LONG_CCG_CODE)
            assert(payload.selection == "heads")
            assert(payload.amount == 10)
            return {
                lobby = {
                    code = LONG_CCG_CODE,
                    game = "heads_tails",
                    game_name = "Heads or Tails",
                    multiplier = 2,
                    status = "lobby",
                },
                player = {
                    display_name = "FoxyPlayer",
                    selection = "heads",
                    wager = 10,
                },
                wallet = { available = 90, held = 0, holds = {} },
            }
        elseif action == "BET_LOBBY_STATUS" then
            assert(payload.code == LONG_CCG_CODE)
            betStatusCalls = betStatusCalls + 1
            local finished = betStatusCalls >= 2
            return {
                lobby = {
                    code = LONG_CCG_CODE,
                    game = "heads_tails",
                    game_name = "Heads or Tails",
                    multiplier = 2,
                    status = finished and "finished" or "running",
                    outcome = finished and "heads" or nil,
                },
                player = {
                    display_name = "FoxyPlayer",
                    selection = "heads",
                    wager = 10,
                    won = finished,
                    payout = finished and 20 or nil,
                    hold_id = finished and "HOLD0000000001" or nil,
                },
                wallet = {
                    available = 90,
                    held = finished and 20 or 0,
                    hold_count = finished and 1 or 0,
                    holds = finished and {
                        {
                            hold_id = "HOLD0000000001",
                            amount = 20,
                            status = "holding",
                            release_day = 43,
                            release_time = "12:00",
                        },
                    } or {},
                },
            }
        elseif action == "BET_WALLET_SUMMARY" then
            return {
                wallet = {
                    available = 90,
                    held = 20,
                    hold_count = 1,
                    holds = {
                        {
                            hold_id = "HOLD0000000001",
                            amount = 20,
                            status = "holding",
                            game_name = "Heads or Tails",
                            release_day = 43,
                            release_time = "12:00",
                        },
                    },
                    activity = {
                        {
                            description = "Heads or Tails winnings - holding",
                            amount = 20,
                            day = 42,
                        },
                    },
                },
            }
        elseif action == "BET_WALLET_DEPOSIT" then
            assert(payload.amount == 25 and payload.pin == "1234")
            return {
                account_balance = 463,
                wallet = {
                    available = 115, held = 20, hold_count = 1,
                    holds = {}, activity = {},
                },
            }
        elseif action == "BET_WALLET_WITHDRAW" then
            assert(payload.amount == 10 and payload.pin == "1234")
            return {
                account_balance = 473,
                wallet = {
                    available = 105, held = 20, hold_count = 1,
                    holds = {}, activity = {},
                },
            }
        end
        return { ok = true }
    end,
}

package.loaded["lib.net"] = {
    client = function() return client end,
    autoUpdate = function() end,
    locate = function() return nil end,
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
local ringSeconds
function ui.setBackgroundTask(seconds)
    ringSeconds = seconds
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
function ui.input(_, title, options)
    if title == "Create Foxy Account" then return "FoxyUser" end
    if title == "PAY A CODE" then return "ABC123" end
    if title == "Send Money" then return "FoxyFriend" end
    if title == "They Receive" then return "100" end
    if title == "Join CCG" then
        assert(options.mode == "code")
        assert(options.maxLength == math.huge)
        assert(options.scrollToEnd == true)
        assert(options.minLength == nil)
        return "cCg2026LongScreenCode987654321"
    end
    if title == "Player Name" then return "FoxyPlayer" end
    if title == "Set Wager" then return "10" end
    if title == "Add to Bet Wallet" then return "25" end
    if title == "Send to Foxy Account" then return "10" end
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
    local live = {}
    function scene:button(id, x, y, width, height, label, options)
        assertBox("button", x, y, width, height)
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
        local action = table.remove(actions, 1)
        assert(action, "PUMPE requested an unexpected scene action")
        -- A scripted tap must land on a button that is really on screen,
        -- otherwise a drifting sequence silently skips whole screens.
        if not tostring(action):match("^__") then
            assert(live[action], "tapped '" .. action
                .. "' but no such button is on screen")
        end
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
-- Sign-up ends in the guide, and Settings can re-open the same screens.
assert(find(drawnText, "How PUMPE Works"))
assert(find(drawnText, "Step 1 of 6"))
assert(find(buttonLabels, "Finish"))
assert(find(buttonLabels, "How PUMPE Works"))
assert(find(buttonLabels, "Edit Your Dock"))

local codeIndex = assert(find(buttonLabels,
    "Code Pay\nEnter a six-character\nkiosk code"))
local sendIndex = assert(find(buttonLabels,
    "Send Money\n10% processing fee\n$2000 daily limit"))
assert(codeIndex < sendIndex)
assert(not find(buttonLabels, "Proximity Pay"))
assert(find(drawnText, "SUBSCRIPTION ACTIVE"))
-- The 8.0 home screen: small glyph icons with the app name drawn beneath
-- them, so every app fits on one page instead of two-per-row tiles.
for _, glyph in ipairs({ "$", "@", "#", "=", "?", "%", "~", "*" }) do
    assert(find(buttonLabels, glyph), "missing app icon " .. glyph)
end
for _, name in ipairs({ "BuckApp", "Friends", "Tickets", "Customs",
    "Bet", "Tax", "Subs", "Settings" }) do
    assert(find(drawnText, name), "missing app caption " .. name)
end
assert(not find(buttonLabels, "$\nBuckApp"), "old two-line tiles are gone")
-- Payments, the Bet Wallet and activity all live inside BuckApp now.
assert(find(buttonLabels, "Continue"))
assert(find(buttonLabels, "Bet\nWallet"))
assert(not find(buttonLabels, "$\nBet Wallet"),
    "Bet Wallet is no longer a separate home screen app")
assert(not find(buttonLabels, "!\nAlerts"),
    "Alerts became an OS page rather than an app")
-- Favourites became the dock, so they sit under every app page instead of
-- taking a page of their own; the notification centre is still the last one.
assert(find(drawnText, "Your Dock"), "the dock picker is reachable")
assert(find(drawnText, "Notifications"), "the notification centre is a page")
assert(find(buttonLabels, "Mark all read"))
assert(find(drawnText, "Welcome to your"),
    "an alert title is drawn in the centre")
assert(find(requests, "NOTIFICATIONS"))
assert(find(requests, "MARK_NOTIFICATIONS_READ"))
-- A ticket or travel document on screen is advertised to the Bank, which is
-- what lets a door or a border find this PUMPE without anybody reading a
-- code out loud.
assert(find(requests, "PRESENT"),
    "an open ticket and visa tell the Bank what is being held up")
assert(find(requests, "REGISTER"))
assert(find(requests, "ACCOUNT_SUMMARY"))
assert(find(requests, "VISA_OVERVIEW"))
assert(find(requests, "CUSTOMS_DETAIL"))
assert(find(requests, "BET_UNLOCK"))
assert(find(requests, "BET_JOIN"))
assert(find(requests, "BET_PLACE_WAGER"))
assert(find(requests, "BET_WALLET_DEPOSIT"))
assert(find(requests, "BET_WALLET_WITHDRAW"))

-- A signed-in PUMPE arms the Urgent Contact ring watcher, so a call reaches
-- the user from whatever app is open.
assert(ringSeconds == nil or type(ringSeconds) == "number",
    "the ring watcher must be armed with an interval")

print("host_pumpe_flow_test: OK")
