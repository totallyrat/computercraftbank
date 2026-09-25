-- History and notifications live on the Vault, 11.2.
--
-- The Core used to keep every transaction and every notification in the
-- file that holds the money, and it filled the Core's disk. Now it keeps
-- balances, an unread summary and an income tally, and sends the rest down
-- the cable through an outbox it saves. What matters: nothing is lost while
-- the Vault is away, nothing is stored twice when a batch is sent twice, the
-- phone reads the same shapes it always did, and a Core coming from 11.1
-- moves what it had.

package.path = "../?.lua;../?/init.lua;" .. package.path

local harness = require("bank_pair_harness")
local bank = harness.pair()
local core, vault = bank.core, bank.vault

local ana = bank.register("Ana Fox", "1234")
local kit = bank.register("Kit Wolf", "5678")
bank.fund(ana, 1000)

local function pay(amount, note)
    return bank.request("SEND_MONEY", bank.as(ana, { recipient = "Kit Wolf",
        amount = amount, pin = "1234", description = note }))
end

-- Down the cable ---------------------------------------------------------------------

pay(10, "Lunch")
assert(#core.state.outbox > 0, "records wait in the outbox")
assert(core.state.transactions == nil, "and the Core keeps no history list")
assert(core.state.accounts[kit.id].notifications == nil)
assert(core.records.flush(), "the Vault takes them")
assert(#core.state.outbox == 0, "and the outbox empties")
local history = bank.request("HISTORY", bank.as(kit)).transactions
assert(history[1].description == "Lunch" and history[1].amount == 10
    and history[1].type and history[1].tx_id and history[1].day
    and history[1].time and history[1].counterparty == "Ana Fox",
    "History reads as it always did, from the Vault")
local notes = bank.notifications(kit)
assert(notes[1].title and notes[1].read == false and notes[1].notification_id,
    "and so do notifications")

-- The Vault away ---------------------------------------------------------------------

bank.unplug()
local unreadBefore = bank.request("PUMPE_POLL", bank.as(kit)).unread_notifications
pay(20, "Dinner")
assert(not core.records.flush(), "nothing moves without the Vault")
-- And once the Vault has failed to answer, a phone is not kept waiting on
-- it again for a while: what is waiting is shown at once.
local asks, realPairAsk = 0, core.pair.ask
core.pair.ask = function(...) asks = asks + 1 return realPairAsk(...) end
assert(bank.request("HISTORY", bank.as(kit)).transactions[1].description
    == "Dinner" and asks == 0, "no second wait on a Vault that is away")
core.pair.ask = realPairAsk
local waiting = #core.state.outbox
assert(waiting > 0)
history = bank.request("HISTORY", bank.as(kit)).transactions
assert(history[1].description == "Dinner",
    "what has not gone down the cable is still shown")
assert(bank.request("PUMPE_POLL", bank.as(kit)).unread_notifications
    == unreadBefore + 1, "the unread count never needed the Vault")
bank.replug()
assert(not core.records.flush(), "still inside the pause")
bank.advanceMs(21 * 1000)
assert(core.records.flush() and #core.state.outbox == 0)
history = bank.request("HISTORY", bank.as(kit)).transactions
assert(history[1].description == "Dinner" and history[2].description == "Lunch",
    "newest first, once each")

-- A batch sent twice, because an answer was lost, is kept once.
pay(5, "Coffee")
local batch = {}
for index, entry in ipairs(core.state.outbox) do
    batch[index] = { k = entry.k, a = entry.a, i = entry.i }
end
vault.vault.VAULT_RECORDS({ items = batch }, bank.core_id)
vault.vault.VAULT_RECORDS({ items = batch }, bank.core_id)
core.records.flush()
local coffees = 0
for _, item in ipairs(bank.request("HISTORY", bank.as(kit)).transactions) do
    if item.description == "Coffee" then coffees = coffees + 1 end
end
assert(coffees == 1, "a repeated batch is not stored twice")
-- And only the Core may send one.
harness.rejected(vault.vault.VAULT_RECORDS, "NOT_MY_CORE", { items = batch }, 77)
harness.rejected(vault.vault.VAULT_RECORDS_READ, "NOT_MY_CORE",
    { account_id = kit.id, kind = "t" }, 77)

-- A record made while a batch is on the cable -- another request, served
-- while this one waited -- goes in the next batch, not nowhere.
local realAsk, madeDuring = core.pair.ask, false
core.pair.ask = function(action, payload, timeout)
    if action == "VAULT_RECORDS" and not madeDuring then
        madeDuring = true
        core.records.push("t", kit.id, { tx_id = "DURING", type = "test",
            amount = 1, counterparty = "x", description = "Made meanwhile",
            day = 1, time = "00:00" })
    end
    return realAsk(action, payload, timeout)
end
pay(3, "Before")
assert(core.records.flush() and madeDuring)
core.pair.ask = realAsk
local during = false
for _, item in ipairs(bank.request("HISTORY", bank.as(kit)).transactions) do
    if item.tx_id == "DURING" then during = true end
end
assert(during, "the record made meanwhile reached the Vault")

-- Read ----------------------------------------------------------------------------------

bank.request("MARK_NOTIFICATIONS_READ", bank.as(kit))
local poll = bank.request("PUMPE_POLL", bank.as(kit))
assert(poll.unread_notifications == 0 and poll.latest == nil)
for _, note in ipairs(bank.notifications(kit)) do
    assert(note.read, "all read, before and after the Vault hears of it")
end
core.records.flush()
for _, row in ipairs(vault.vault.VAULT_RECORDS_READ({ account_id = kit.id,
    kind = "n" }, bank.core_id).items) do
    assert(row.read, "the Vault marks them read too")
end
-- Read while the Vault is away: the phone still shows them read, because
-- read or not is the Core's to say.
bank.unplug()
pay(1, "Offline")
pay(1, "Offline again")
bank.request("MARK_NOTIFICATIONS_READ", bank.as(kit))
for _, note in ipairs(bank.notifications(kit)) do
    assert(note.read, "read, though the Vault has not heard yet")
end
bank.replug()
bank.advanceMs(21 * 1000)
core.records.flush()
pay(1, "Tip")
poll = bank.request("PUMPE_POLL", bank.as(kit))
assert(poll.unread_notifications == 1 and poll.latest.title,
    "a new one is the latest again")

-- Capped ----------------------------------------------------------------------------------

for index = 1, 40 do pay(1, "Small " .. index) end
core.records.flush()
history = bank.request("HISTORY", bank.as(kit)).transactions
assert(#history == 30 and history[1].description == "Small 40",
    "the Vault keeps an account's newest thirty")
assert(#bank.notifications(kit) == 20, "and twenty notifications")

-- An outbox that cannot drain forever is bounded: history is what goes.
bank.unplug()
local ceiling = core.records.cap
for index = 1, ceiling + 10 do
    core.records.push("t", kit.id, { tx_id = "X" .. index, type = "test",
        amount = 1, description = "x", day = 1, time = "00:00" })
end
assert(#core.state.outbox == ceiling, "the outbox never grows past its cap")
assert(core.state.outbox[#core.state.outbox].i.tx_id == "X" .. (ceiling + 10),
    "and keeps the newest")
bank.replug()
bank.advanceMs(21 * 1000)
core.records.flush()

-- Tax, without the history ------------------------------------------------------------------
-- A tax period adds up income by day from a tally on the account.

local gov = bank.fund(kit, 1)
local period = bank.request("OPEN_TAX_PERIOD", { government_token = gov,
    end_day = 99999, personal_rate = 10, commercial_rate = 10,
    threshold = 0 }).period
bank.request("SEND_MONEY", bank.as(ana, { recipient = "Kit Wolf", amount = 100,
    pin = "1234" }))
local income = 0
for day, amount in pairs(core.state.accounts[kit.id].income) do
    if day >= period.start_day then income = income + amount end
end
assert(income >= 100, "income arriving in a period is counted for it")

-- Saving when the disk is full ---------------------------------------------------------------
-- History waiting for the Vault is given up before the money is.

local util = require("lib.util")
bank.unplug()
pay(2, "Before the disk filled")
assert(#core.state.outbox > 0)
local realSave, attempts = util.saveTable, 0
util.saveTable = function(_, value)
    attempts = attempts + 1
    if #(value.outbox or {}) > 0 then error("Out of space", 0) end
end
bank.request("SEND_MONEY", bank.as(ana, { recipient = "Kit Wolf", amount = 1,
    pin = "1234" }))
assert(attempts == 2 and #core.state.outbox == 0,
    "the outbox went, and the save went through")
util.saveTable = function() error("Out of space", 0) end
local ok, err = pcall(bank.request, "SEND_MONEY", bank.as(ana, {
    recipient = "Kit Wolf", amount = 1, pin = "1234" }))
assert(not ok and tostring(err):find("cannot save", 1, true),
    "with nothing left to give up, it says so rather than pretending")
util.saveTable = realSave
bank.replug()
bank.advanceMs(21 * 1000)

-- Coming from 11.1 -------------------------------------------------------------------------
-- A Bank that kept everything: fifty transactions and thirty notifications
-- for one account, one of them unread. The newest thirty and twenty go to
-- the outbox, the lists go, and nothing about the money changes.

local old = util.copy(core.state)
old.tx_count = nil
-- Something was still waiting for the Vault when it stopped.
old.outbox = { { s = 500, k = "t", a = kit.id, i = { tx_id = "PENDING",
    type = "x", amount = 1, description = "waiting", day = 1,
    time = "00:00" } } }
old.outbox_seq = 500
old.transactions = {}
local today = util.ingameDay()
for index = 1, 50 do
    old.transactions[index] = { tx_id = "TXOLD" .. index, account_id = kit.id,
        type = "transfer_in", amount = 2, counterparty = "Ana Fox",
        description = "Old " .. index, day = today, time = "12:00",
        timestamp = 1, company_id = "CO1", tax_amount = 0 }
end
local oldAccount = old.accounts[kit.id]
oldAccount.inbox, oldAccount.income = nil, nil
oldAccount.notifications = {}
for index = 1, 30 do
    oldAccount.notifications[index] = { notification_id = "NOLD" .. index,
        title = "Old note " .. index, body = "b", kind = "info",
        created_day = today, created_time = "12:00", read = index ~= 1 }
end
local balance = oldAccount.balance
local realLoad = util.loadTable
util.loadTable = function(path, fallback)
    if tostring(path):find("bank_data", 1, true) then return util.copy(old) end
    return util.copy(fallback)
end
PUMPE_TEST_MODE = true
local restarted = assert(loadfile("../bank_server.lua"))()
PUMPE_TEST_MODE = nil
util.loadTable = realLoad
local moved = restarted.state
assert(moved.transactions == nil and moved.accounts[kit.id].notifications == nil,
    "the lists are gone from the Core")
assert(moved.outbox[1].i.tx_id == "PENDING", "what was waiting still waits")
local kinds = { t = 0, n = 0 }
for index = 2, #moved.outbox do
    local entry = moved.outbox[index]
    kinds[entry.k] = kinds[entry.k] + 1
    assert(entry.s > 500, "numbered after what was already waiting")
end
assert(kinds.t == 30 and kinds.n == 20, "the newest thirty and twenty move")
assert(moved.outbox[31].i.description == "Old 50",
    "oldest first, so the Vault ends with the newest on top")
assert(moved.outbox[2].i.company_id == nil and moved.outbox[2].i.timestamp == nil,
    "carrying only what History shows")
assert(moved.accounts[kit.id].inbox.unread == 1
    and moved.accounts[kit.id].inbox.latest.notification_id == "NOLD1",
    "the unread one is still unread")
assert(moved.tx_count == 50)
assert(moved.accounts[kit.id].income[today] == 100,
    "and the tax tally is built from what was there")
assert(moved.accounts[kit.id].balance == balance, "money untouched")
-- Items pushed after the move carry on the saved sequence.
local last = moved.outbox[#moved.outbox].s
restarted.records.push("t", kit.id, { tx_id = "NEW", type = "x", amount = 1,
    description = "n", day = today, time = "12:00" })
assert(moved.outbox[#moved.outbox].s == last + 1)

print("host_bank_records_test: OK")
