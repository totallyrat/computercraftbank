-- The Account ID and the transfer that crosses banks.
--
-- The thing worth testing here is not the happy path. It is that money is
-- never created and never destroyed: a bank that refuses, a bank that never
-- answers, and a reply that goes missing all have to leave exactly as much
-- money in the world as there was before.

package.path = "../?.lua;../?/init.lua;" .. package.path

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}
local currentDay, clock = 500, 20000000
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

-- The far bank. Every call the Bank makes over the ledger protocol comes
-- through here, so a test can make it refuse, vanish, or lose a reply.
local far = { accounts = {}, credits = {}, mode = "ok", calls = {} }
package.loaded["lib.net"] = {
    openModems = function() return { "modem" } end,
    host = function() end,
    reply = function() end,
    locate = function() return nil end,
    autoUpdate = function() end,
    client = function(spec)
        return {
            discover = function() return 7 end,
            request = function(_, action, payload)
                far.calls[#far.calls + 1] = { action = action,
                    payload = payload, hostname = spec.hostname }
                if far.mode == "offline" then
                    return nil, "Bank server is offline"
                end
                if action == "LEDGER_LOOKUP" then
                    local who = far.accounts[payload.bank_account_id]
                    if not who then
                        return nil, "No account has that Account ID",
                            "NO_SUCH_ACCOUNT"
                    end
                    return { bank_account_id = payload.bank_account_id,
                        name = who.name, bank_name = "BuckApp",
                        bank_code = "0042", accepting = true }
                elseif action == "LEDGER_CREDIT" then
                    if far.mode == "refuse" then
                        return nil, "That bank would not take it", "REFUSED"
                    end
                    -- The credit is applied whether or not the answer gets
                    -- home, which is exactly the case a lost reply creates.
                    local already = far.credits[payload.transfer_id]
                    if not already then
                        far.credits[payload.transfer_id] = payload.amount
                        local who = far.accounts[payload.bank_account_id]
                        who.balance = who.balance + payload.amount
                    end
                    if far.mode == "lost_reply" then
                        return nil, "Bank server timed out"
                    end
                    return { credited = payload.amount,
                        balance = far.accounts[payload.bank_account_id].balance,
                        repeated = already ~= nil }
                end
                if action == "LEDGER_STATUS" then
                    local amount = far.credits[payload.transfer_id]
                    return { applied = amount ~= nil, amount = amount }
                end
                return { ok = true }
            end,
        }
    end,
}

local config = require("config")
PUMPE_TEST_MODE = true
local bank = assert(loadfile("../bank_server.lua"))()
PUMPE_TEST_MODE = nil
local actions, ledger = bank.actions, bank.ledger

local function rejected(action, expectedCode, payload)
    local ok, result = pcall(action, payload)
    assert(not ok, "request should have been rejected")
    assert(type(result) == "table" and result.code == expectedCode,
        "expected " .. expectedCode .. ", got " .. tostring(
            type(result) == "table" and result.code or result))
end
local function register(name)
    return actions.REGISTER({ name = name, pin = "1234", gender = "Not set" })
end
local function as(who, extra)
    local payload = { session_token = who.session_token }
    for key, value in pairs(extra or {}) do payload[key] = value end
    return payload
end

local ana = register("Ana Fox")
local bo = register("Bo Wolf")

-- The Account ID -------------------------------------------------------------

local anaId = ana.account.bank_account_id
assert(anaId and #anaId == 16 and anaId:match("^%d+$"),
    "sixteen digits and nothing else: " .. tostring(anaId))
assert(anaId:sub(1, 4) == config.foxy_bank_code,
    "the first four name the bank holding it")
assert(bo.account.bank_account_id ~= anaId, "and the rest are unique")
assert(ledger.format(anaId):find(" ", 1, true),
    "it is shown in groups so it can be read off a screen")
assert(ledger.clean(ledger.format(anaId)) == anaId,
    "and typed back with or without the spaces")

-- An account made before 9.0 has none, and gets one the first time it is
-- asked for rather than in a migration that walks the whole ledger at boot.
local old = bank.state.accounts[bo.account.account_id]
old.bank_account_id = nil
local minted = actions.BANK_IDENTITY(as(bo)).bank_account_id
assert(#minted == 16, "an older account gets one on demand")
assert(actions.BANK_IDENTITY(as(bo)).bank_account_id == minted,
    "and keeps it")
assert(ledger.byBankId(minted).account_id == bo.account.account_id,
    "and is findable by it")

-- Transferring out -------------------------------------------------------------

far.accounts["0042000000000001"] = { name = "Ana Fox", balance = 0 }
local startingBalance = bank.state.accounts[ana.account.account_id].balance
assert(startingBalance > 0)

local quote = actions.BANK_TRANSFER_QUOTE(as(ana, {
    bank_account_id = "0042 0000 0000 0001",
}))
assert(quote.bank_name == "BuckApp" and quote.amount == startingBalance,
    "the quote says where it is going and how much goes")
assert(far.calls[#far.calls].hostname == "LEDGER_0042",
    "the first four digits are what found the bank")

rejected(actions.BANK_TRANSFER_QUOTE, "BAD_ACCOUNT_ID",
    as(ana, { bank_account_id = "12345" }))
rejected(actions.BANK_TRANSFER_QUOTE, "SAME_ACCOUNT",
    as(ana, { bank_account_id = anaId }))
rejected(actions.BANK_TRANSFER_QUOTE, "NO_SUCH_ACCOUNT",
    as(ana, { bank_account_id = "0042000000009999" }))

-- Money is never created or destroyed --------------------------------------------

-- Money in the world is what is spendable: balances, here and there. A
-- parked transfer is deliberately NOT counted -- it is money in flight, in
-- exactly one of those two places and not yet known which. So the invariant
-- is that the total never goes UP (money is never created), and that it is
-- whole again once a parked transfer has been reconciled.
local function worldTotal()
    return bank.state.accounts[ana.account.account_id].balance
        + far.accounts["0042000000000001"].balance
end
local function parked()
    local count = 0
    for _ in pairs(bank.state.accounts[ana.account.account_id]
        .pending_transfers or {}) do count = count + 1 end
    return count
end
local before = worldTotal()

-- The far bank refuses. The money comes straight back.
far.mode = "refuse"
rejected(actions.BANK_TRANSFER_CONFIRM, "REFUSED", as(ana, {
    bank_account_id = "0042000000000001", pin = "1234",
}))
assert(bank.state.accounts[ana.account.account_id].balance == startingBalance,
    "a refused transfer leaves the balance exactly as it was")
assert(worldTotal() == before, "and the world still holds the same money")

-- The far bank is not there at all. The lookup fails before anything is
-- debited, so this one never even reaches the parked state.
far.mode = "offline"
rejected(actions.BANK_TRANSFER_CONFIRM, "BANK_UNREACHABLE", as(ana, {
    bank_account_id = "0042000000000001", pin = "1234",
}))
assert(bank.state.accounts[ana.account.account_id].balance == startingBalance)
assert(worldTotal() == before)

-- The wrong PIN never gets as far as the radio.
far.mode = "ok"
local callsBefore = #far.calls
rejected(actions.BANK_TRANSFER_CONFIRM, "BAD_PIN", as(ana, {
    bank_account_id = "0042000000000001", pin = "9999",
}))
assert(#far.calls == callsBefore, "a wrong PIN sends nothing anywhere")

-- The credit lands but the answer is lost. This is the case that decides
-- whether the design is sound. An earlier version of this code refunded on
-- any failure, which meant the far bank had the money and so did this one:
-- the transfer created money out of nothing. It has to be parked instead.
far.mode = "lost_reply"
rejected(actions.BANK_TRANSFER_CONFIRM, "TRANSFER_PENDING", as(ana, {
    bank_account_id = "0042000000000001", pin = "1234",
}))
assert(worldTotal() <= before,
    "an unanswered transfer never creates money: here=" 
        .. bank.state.accounts[ana.account.account_id].balance .. " there="
        .. far.accounts["0042000000000001"].balance)
assert(bank.state.accounts[ana.account.account_id].balance == 0,
    "the balance is not quietly given back on a guess")
assert(parked() == 1, "it is held as one pending transfer")

-- Resolved by asking the far bank, not by assuming either way.
far.mode = "ok"
ledger.reconcile()
assert(parked() == 0, "the pending transfer is settled")
assert(worldTotal() == before,
    "and the world is whole again: nothing created, nothing lost")
assert(far.accounts["0042000000000001"].balance == startingBalance,
    "the money ended up where it was sent, exactly once")
assert(bank.state.accounts[ana.account.account_id].balance == 0,
    "and is no longer here")

-- The other way round: a parked transfer the far bank never applied. It
-- comes back, because now we know which way it went.
bank.state.accounts[ana.account.account_id].pending_transfers = {
    XFER_NEVER_LANDED = { transfer_id = "XFER_NEVER_LANDED", amount = 500,
        to = "0042000000000001", at = 1 },
}
ledger.reconcile()
assert(bank.state.accounts[ana.account.account_id].balance == 500,
    "a transfer the far bank never saw comes back")
assert(parked() == 0, "and stops being pending")

-- The real thing, from a clean slate.
far.mode = "ok"
far.credits = {}
far.accounts["0042000000000001"].balance = 0
bank.state.accounts[ana.account.account_id].balance = startingBalance
bank.state.accounts[ana.account.account_id].pending_transfers = {}

local moved = actions.BANK_TRANSFER_CONFIRM(as(ana, {
    bank_account_id = "0042 0000 0000 0001", pin = "1234",
}))
assert(moved.moved == startingBalance and moved.bank_name == "BuckApp")
assert(far.accounts["0042000000000001"].balance == startingBalance,
    "the money is at the other bank")
assert(bank.state.accounts[ana.account.account_id].balance == 0,
    "and not at this one")

-- The account closes behind it ----------------------------------------------------

local closed = actions.BANK_IDENTITY(as(ana))
assert(closed.bank_closed and closed.moved_to == "0042000000000001",
    "the Foxy bank account is closed, and says where the money went")
assert(actions.ACCOUNT_SUMMARY(as(ana)).account.bank_closed,
    "which is what hides the Bank tab in the Foxy app")

-- Nothing that spends can work while the money is elsewhere.
rejected(actions.SEND_MONEY, "BANK_CLOSED", as(ana, {
    recipient = "Bo Wolf", amount = 1, pin = "1234",
}))
rejected(actions.BANK_TRANSFER_CONFIRM, "BANK_CLOSED", as(ana, {
    bank_account_id = "0042000000000001", pin = "1234",
}))

-- And nobody can push money into a closed account either.
rejected(actions.SEND_MONEY, "RECIPIENT_CLOSED", as(bo, {
    recipient = "Ana Fox", amount = 1, pin = "1234",
}))

-- Coming back ---------------------------------------------------------------------
-- The far bank sends it home over the same protocol, which is the path the
-- third-party bank's own transfer feature uses.

local home = ledger.actions.LEDGER_CREDIT({
    bank_account_id = anaId, amount = startingBalance,
    transfer_id = "XFER_COMING_HOME", from_name = "Ana Fox",
    from_bank_name = "BuckApp",
})
assert(home.credited == startingBalance)

-- Applied once, however many times it arrives.
local again = ledger.actions.LEDGER_CREDIT({
    bank_account_id = anaId, amount = startingBalance,
    transfer_id = "XFER_COMING_HOME", from_name = "Ana Fox",
    from_bank_name = "BuckApp",
})
assert(again.repeated, "a repeated credit says so")
assert(bank.state.accounts[ana.account.account_id].balance == startingBalance,
    "and does not credit it twice")

-- Money coming home is what reopens the account, which is the whole of the
-- "move back" path the player uses from the third-party bank.
local reopened = actions.BANK_IDENTITY(as(ana))
assert(not reopened.bank_closed and reopened.moved_to == nil,
    "the bank account opens again with the money in it")
assert(actions.ACCOUNT_SUMMARY(as(ana)).account.bank_closed == false,
    "so the Bank tab comes back in the Foxy app")
-- And it can be spent again.
assert(actions.SEND_MONEY(as(ana, {
    recipient = "Bo Wolf", amount = 10, pin = "1234",
})), "spending works again once the money is home")

print("host_ledger_test: OK")
