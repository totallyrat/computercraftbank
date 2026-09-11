-- Foxy on the Bank: sub-accounts you name yourself, moving money between
-- them, Foxy Cash to a friend, and the developer accounts the App Server
-- checks before it lets anybody publish.

package.path = "../?.lua;../?/init.lua;" .. package.path

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

local currentDay, clock = 300, 9000000
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
-- Since 9.3 these routes are answered by the Vault, so the test stands up
-- both halves and lets the Core decide which one answers -- the same way the
-- server does. A stub Vault would be more forgiving than the real one.
local harness = require("bank_pair_harness")
local bank = harness.pair()
local actions = bank.actions
local state = bank.state
local vaultState = bank.vault_state

local function rejected(action, expectedCode, payload)
    local ok, result = pcall(action, payload)
    assert(not ok, "request should have been rejected")
    assert(type(result) == "table" and result.code == expectedCode,
        "expected " .. expectedCode .. ", got " .. tostring(result.code))
end

local function register(name)
    return actions.REGISTER({ name = name, pin = "1234", gender = "Not set" })
end
local function as(who, extra)
    local payload = { session_token = who.session_token }
    for key, value in pairs(extra or {}) do payload[key] = value end
    return payload
end

local holder = register("Foxy Holder")
local mate = register("Best Mate")
local stranger = register("Total Stranger")

-- Sub-accounts ---------------------------------------------------------------

local start = actions.FOXY_OVERVIEW(as(holder))
assert(start.name == "Foxy Holder" and start.card_id)
assert(#start.pots == 0 and start.saved == 0)
assert(start.fee_rate == config.foxy_cash_fee_rate)

local savings = actions.FOXY_POT_CREATE(as(holder, { name = "Savings" }))
assert(#savings.pots == 1 and savings.pots[1].name == "Savings")
assert(savings.pots[1].balance == 0)
local potId = savings.pots[1].pot_id

local opening = actions.ACCOUNT_SUMMARY(as(holder)).account.balance
local moved = actions.FOXY_POT_MOVE(as(holder, {
    from_pot = "main", to_pot = potId, amount = 120,
}))
assert(moved.balance == opening - 120, "money leaves the main balance")
assert(moved.pots[1].balance == 120, "and lands in the pot")
assert(moved.saved == 120)

-- It is still the same money: nothing was created or destroyed.
assert(actions.ACCOUNT_SUMMARY(as(holder)).account.balance
    + actions.FOXY_OVERVIEW(as(holder)).saved == opening,
    "moving between your own accounts never changes the total")

rejected(actions.FOXY_POT_MOVE, "INSUFFICIENT_FUNDS", as(holder, {
    from_pot = potId, to_pot = "main", amount = 500,
}))
rejected(actions.FOXY_POT_MOVE, "SAME_ACCOUNT", as(holder, {
    from_pot = "main", to_pot = "main", amount = 5,
}))

-- Closing a pot hands its money back rather than losing it.
local rent = actions.FOXY_POT_CREATE(as(holder, { name = "Rent" }))
local rentId
for _, pot in ipairs(rent.pots) do
    if pot.name == "Rent" then rentId = pot.pot_id end
end
actions.FOXY_POT_MOVE(as(holder, {
    from_pot = "main", to_pot = rentId, amount = 30,
}))
local afterClose = actions.FOXY_POT_CLOSE(as(holder, { pot_id = rentId }))
assert(#afterClose.pots == 1, "the pot is gone")
assert(afterClose.balance == opening - 120,
    "and its money came back to the main balance")

-- Foxy Cash ------------------------------------------------------------------

rejected(actions.FOXY_CASH_QUOTE, "NOT_FRIENDS", as(holder, {
    account_id = stranger.account.account_id, amount = 10,
}))

actions.FRIEND_REQUEST(as(holder, { account_id = mate.account.account_id }))
assert(actions.FRIEND_RESPOND(as(mate, {
    account_id = holder.account.account_id, accept = true,
})).status == "friends")

local quote = actions.FOXY_CASH_QUOTE(as(holder, {
    account_id = mate.account.account_id, amount = 100,
}))
assert(quote.fee == 2 and quote.total == 102,
    "Foxy Cash takes two percent, not the old ten")
assert(quote.recipient == "Best Mate")

-- No daily ceiling: the old Send Money limit does not apply here.
local before = actions.ACCOUNT_SUMMARY(as(holder)).account.balance
local mateBefore = actions.ACCOUNT_SUMMARY(as(mate)).account.balance
rejected(actions.FOXY_CASH_SEND, "BAD_PIN", as(holder, {
    account_id = mate.account.account_id, amount = 100, pin = "9999",
}))
-- Friends only, and that is checked when it matters, not just on the quote.
rejected(actions.FOXY_CASH_SEND, "NOT_FRIENDS", as(holder, {
    account_id = stranger.account.account_id, amount = 10, pin = "1234",
}))
local sent = actions.FOXY_CASH_SEND(as(holder, {
    account_id = mate.account.account_id, amount = 100, pin = "1234",
}))
assert(sent.amount == 100 and sent.fee == 2)
assert(actions.ACCOUNT_SUMMARY(as(holder)).account.balance == before - 102)
assert(actions.ACCOUNT_SUMMARY(as(mate)).account.balance == mateBefore + 100,
    "the friend gets the whole amount; the fee is the sender's")

-- Account details ------------------------------------------------------------

rejected(actions.FOXY_SET_ACCOUNT, "BAD_PIN", as(holder, {
    name = "Renamed", pin = "0000",
}))
actions.FOXY_SET_ACCOUNT(as(holder, { name = "Foxy Renamed", pin = "1234" }))
assert(actions.ACCOUNT_SUMMARY(as(holder)).account.name == "Foxy Renamed")
-- The old name is free again and the new one resolves.
assert(actions.SEND_MONEY_QUOTE(as(mate, {
    recipient = "Foxy Renamed", amount = 1,
})).recipient == "Foxy Renamed")
rejected(actions.FOXY_SET_ACCOUNT, "NAME_TAKEN", as(holder, {
    name = "Best Mate", pin = "1234",
}))

actions.FOXY_SET_ACCOUNT(as(holder, { pin = "1234", new_pin = "4321" }))
rejected(actions.FOXY_CASH_SEND, "BAD_PIN", as(holder, {
    account_id = mate.account.account_id, amount = 1, pin = "1234",
}))
assert(actions.FOXY_CASH_SEND(as(holder, {
    account_id = mate.account.account_id, amount = 1, pin = "4321",
})).amount == 1, "the new PIN is the one that works")

-- A tax demand still shuts everything down, savings included ------------------

local gov = actions.GOVERNMENT_LOGIN({ key = config.government_key })
actions.ADMIN_TAX_DEMAND({
    government_token = gov.government_token,
    account_id = holder.account.account_id,
    amount = 20, reason = "Unpaid road tax",
})
rejected(actions.FOXY_CASH_SEND, "TAX_DEMAND_DUE", as(holder, {
    account_id = mate.account.account_id, amount = 1, pin = "4321",
}))
rejected(actions.FOXY_POT_MOVE, "TAX_DEMAND_DUE", as(holder, {
    from_pot = "main", to_pot = potId, amount = 1,
}))
-- Moving savings back to where a demand can reach them is always allowed.
assert(actions.FOXY_POT_MOVE(as(holder, {
    from_pot = potId, to_pot = "main", amount = 1,
})), "money can always come back out of savings")

-- Developer accounts ---------------------------------------------------------

local shopOwner = register("Shop Owner")
local kiosk = actions.KIOSK_REGISTER({ name = "Corner Shop" })
local terminal = {
    terminal_id = kiosk.terminal_id, terminal_token = kiosk.terminal_token,
}

-- A kiosk with no company behind it has no owner to become a developer.
rejected(actions.DEV_REGISTER, "NO_COMPANY", {
    terminal_id = terminal.terminal_id,
    terminal_token = terminal.terminal_token, pin = "1234",
})

local company = actions.CREATE_COMPANY({
    owner_session = shopOwner.session_token,
    company_name = "Corner Holdings",
})
actions.LINK_TERMINAL({
    terminal_id = terminal.terminal_id,
    terminal_token = terminal.terminal_token,
    owner_session = shopOwner.session_token,
    company_id = company.company.company_id,
})

rejected(actions.DEV_REGISTER, "BAD_PIN", {
    terminal_id = terminal.terminal_id,
    terminal_token = terminal.terminal_token, pin = "0000",
})
local developer = actions.DEV_REGISTER({
    terminal_id = terminal.terminal_id,
    terminal_token = terminal.terminal_token, pin = "1234",
})
assert(developer.developer_id and developer.developer_token)
assert(developer.existing == false and developer.name == "Shop Owner")

-- Registering again returns the same credentials rather than a second one.
local again = actions.DEV_REGISTER({
    terminal_id = terminal.terminal_id,
    terminal_token = terminal.terminal_token, pin = "1234",
})
assert(again.existing and again.developer_id == developer.developer_id)

-- The App Server checks these, and nothing else does.
assert(actions.DEV_VERIFY({
    developer_id = developer.developer_id,
    developer_token = developer.developer_token,
}).name == "Shop Owner")
rejected(actions.DEV_VERIFY, "DEV_UNKNOWN", {
    developer_id = developer.developer_id, developer_token = "WRONG",
})

-- A PUMPE asks whether it is a developer, so the App Browser can offer to
-- delete only the apps this account published.
assert(actions.DEV_MINE(as(shopOwner)).developer_id == developer.developer_id)
assert(actions.DEV_MINE(as(mate)).developer_id == nil)

print("host_foxy_server_test: OK")
