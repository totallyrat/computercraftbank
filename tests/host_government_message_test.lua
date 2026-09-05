-- Government messages: a two-way thread between the state and one account,
-- targeted announcements, and the payment lockout that stops a tax demand
-- being dodged by spending the balance first.

package.path = "../?.lua;../?/init.lua;" .. package.path

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

local currentDay, clock = 200, 5000000
os.day = function() return currentDay end
os.time = function() return 12 end
os.epoch = function() return clock end
os.getComputerID = function() return 1 end

fs = {
    getDir = function() return "/pumpe" end,
    combine = function(left, right)
        return tostring(left):gsub("/+$", "") .. "/"
            .. tostring(right):gsub("^/+", "")
    end,
    exists = function() return false end,
    isDir = function() return false end,
}
shell = { getRunningProgram = function() return "/pumpe/bank_server.lua" end }

local util = require("lib.util")
util.loadTable = function(_, fallback) return util.copy(fallback) end
util.saveTable = function() end
package.loaded["lib.util"] = util

local config = require("config")
PUMPE_TEST_MODE = true
local bank = assert(loadfile("../bank_server.lua"))()
PUMPE_TEST_MODE = nil
local actions = bank.actions

local function rejected(action, expectedCode, payload)
    local ok, result = pcall(action, payload)
    assert(not ok, "request should have been rejected")
    assert(type(result) == "table" and result.code == expectedCode,
        "expected " .. expectedCode .. ", got " .. tostring(result.code))
end

local function register(name)
    return actions.REGISTER({ name = name, pin = "1234", gender = "Not set" })
end

local driver = register("Fast Driver")
local friend = register("Old Friend")
local gov = actions.GOVERNMENT_LOGIN({ key = config.government_key })
local function admin(extra)
    local payload = { government_token = gov.government_token }
    for key, value in pairs(extra or {}) do payload[key] = value end
    return payload
end
local function as(who, extra)
    local payload = { session_token = who.session_token }
    for key, value in pairs(extra or {}) do payload[key] = value end
    return payload
end

-- A message from the government opens a thread -------------------------------

local opened = actions.ADMIN_MESSAGE(admin({
    account_id = driver.account.account_id,
    body = "You were doing 40 in the market square.",
}))
assert(opened.conversation_id)
assert(opened.message.sender_name == "Government",
    "the state signs its own messages")

-- It shows up in the holder's ordinary chat list, titled Government.
local threads = actions.CHAT_LIST(as(driver)).conversations
local official
for _, item in ipairs(threads) do
    if item.kind == "government" then official = item end
end
assert(official, "the thread reaches the PUMPE like any other chat")
assert(official.title == "Government")
assert(official.unread == 1, "an unanswered message is unread")

-- They can answer it.
actions.CHAT_SEND(as(driver, {
    conversation_id = official.conversation_id,
    body = "It was 30, I promise.",
}))
local history = actions.ADMIN_MESSAGE_HISTORY(admin({
    account_id = driver.account.account_id,
}))
assert(#history.messages == 2)
assert(history.messages[2].body:find("30", 1, true),
    "the terminal sees the reply")

-- Only the government moves money in this thread ------------------------------

rejected(actions.CHAT_REQUEST_MONEY, "GOVERNMENT_THREAD", as(driver, {
    conversation_id = official.conversation_id, amount = 50,
}))
rejected(actions.CHAT_SEND_MONEY, "GOVERNMENT_THREAD", as(driver, {
    conversation_id = official.conversation_id, amount = 50, pin = "1234",
}))

local demand = actions.ADMIN_MESSAGE_DEMAND(admin({
    account_id = driver.account.account_id,
    amount = 75,
    note = "Speeding fine",
}))
assert(demand.message.kind == "money_request" and demand.message.amount == 75)
assert(demand.conversation_id == opened.conversation_id,
    "every government message lands in the one thread")
assert(#actions.CHAT_LIST(as(driver)).conversations == 1,
    "and the holder never collects a pile of Government chats")

local before = actions.ACCOUNT_SUMMARY(as(driver)).account.balance
local revenueBefore = bank.state.tax_revenue or 0
actions.CHAT_PAY_REQUEST(as(driver, {
    conversation_id = official.conversation_id,
    seq = demand.message.seq,
    pin = "1234",
}))
assert(actions.ACCOUNT_SUMMARY(as(driver)).account.balance == before - 75)
assert((bank.state.tax_revenue or 0) == revenueBefore + 75,
    "a fine paid in a message reaches the treasury")

-- The government can also send money the other way.
local paid = actions.ADMIN_MESSAGE_PAY(admin({
    account_id = driver.account.account_id,
    amount = 25,
    note = "Overpayment refund",
}))
assert(paid.balance == before - 75 + 25)

-- The inbox shows who is waiting on a reply.
local inbox = actions.ADMIN_MESSAGE_THREADS(admin()).threads
assert(#inbox == 1 and inbox[1].name == "Fast Driver")
assert(inbox[1].waiting == false, "the state spoke last")

-- Announcements can be aimed at one account ----------------------------------

actions.ADMIN_ANNOUNCE(admin({
    account_id = driver.account.account_id,
    title = "Court date",
    body = "Day 210, the market square",
    mode = "modal",
}))
local mine = actions.PUMPE_POLL(as(driver)).announcement
assert(mine and mine.title == "Court date")
assert(actions.PUMPE_POLL(as(friend)).announcement == nil,
    "a targeted announcement reaches nobody else")

-- A broadcast still reaches everyone.
actions.ADMIN_ANNOUNCE(admin({
    title = "Market closes early", body = "Day 205", mode = "banner",
}))
local heard = actions.PUMPE_POLL(as(friend)).announcement
assert(heard and heard.title == "Market closes early")

-- Payment lockout under a tax demand -----------------------------------------

local kiosk = actions.KIOSK_REGISTER({ name = "Corner Shop" })
local code = actions.CREATE_PAY_CODE({
    terminal_id = kiosk.terminal_id, terminal_token = kiosk.terminal_token,
    amount = 5,
})
actions.ADMIN_TAX_DEMAND(admin({
    account_id = driver.account.account_id,
    amount = 40,
    reason = "Unpaid road tax",
}))

-- Everything that moves money out is refused, with a reason that says why.
for _, blocked in ipairs({
    { actions.PAY_CODE_PREVIEW, { code = code.code } },
    { actions.PAY_CODE_CONFIRM, { code = code.code, pin = "1234" } },
    { actions.SEND_MONEY_QUOTE, { recipient = "Old Friend", amount = 5 } },
    { actions.BET_WALLET_DEPOSIT, { amount = 5, pin = "1234" } },
    { actions.BET_UNLOCK, { pin = "1234" } },
}) do
    rejected(blocked[1], "TAX_DEMAND_DUE", as(driver, blocked[2]))
end

-- Being paid still works; only spending is shut off.
actions.SEND_MONEY(as(friend, {
    recipient = "Fast Driver", amount = 10, pin = "1234",
}))

-- And the demand itself can always be settled.
local owing = actions.ACCOUNT_SUMMARY(as(driver)).account.balance
actions.PAY_TAX_DEMAND(as(driver, { pin = "1234" }))
assert(actions.ACCOUNT_SUMMARY(as(driver)).account.balance == owing - 40)

-- With it settled, paying works again.
assert(actions.PAY_CODE_PREVIEW(as(driver, { code = code.code })).amount == 5,
    "the lockout lifts the moment the demand is paid")

print("host_government_message_test: OK")
