-- Company Money and Radio+ at the Bank, FoxyOS 18.2. A real Core and Vault,
-- through the routes a client uses.
--
-- A company's sales go into its Company Money, not its owner's account. The
-- owner pays anybody out of it with a PIN, or puts money in. Radio+ is the
-- company's: 100 every 15 days out of Company Money, renewed or stopped on
-- its day. A company's radio station earns 25 a listener for an ad break --
-- rationed, since that money comes from nowhere -- and its giveaways are paid
-- out of Company Money, which holds the prize until the draw.

package.path = "../?.lua;../?/init.lua;" .. package.path
local harness = require("bank_pair_harness")
local rejected = harness.rejected
local bank = harness.pair()
local config = require("config")
local util = require("lib.util")
local state = bank.state

local ana = bank.register("Ana Fox", "1234")
local kit = bank.register("Kit Wolf", "5678")
local noa = bank.register("Noa Hare", "4321")
bank.fund(ana, 2000)
bank.fund(kit, 2000)
bank.fund(noa, 500)

local made = bank.request("COMPANY_CREATE", bank.as(ana, { company_name = "Fox FM" }))
local company = state.companies[made.company_id or made.company.company_id]
assert(company, "a company")
local id = company.company_id
local function money() return bank.request("COMPANY_MONEY", bank.as(ana, { company_id = id })) end

-- Sales ------------------------------------------------------------------------------------------

assert(money().balance == 0 and #money().log == 0, "empty to start with")
rejected(bank.request, "NOT_OWNER", "COMPANY_MONEY", bank.as(kit, { company_id = id }))
rejected(bank.request, "WRONG_APP", "COMPANY_MONEY", bank.as(ana, { company_id = id,
    app_id = "FOXY" }))
local anaBefore = bank.balanceOf(ana)
company.money = nil
-- A company with a casino balance from before 18.2 starts Company Money with it.
company.casino = { balance = 120, earned = 300, paid = 180, borrowed = 0, cashed_out = 0,
    added = 0, rounds = 4 }
assert(money().balance == 120 and company.casino.balance == nil, "the casino's balance moved in")

-- Paying out ---------------------------------------------------------------------------------------

rejected(bank.request, "BAD_PIN", "COMPANY_MONEY_PAY", bank.as(ana, { company_id = id,
    to = "Kit Wolf", amount = 20, pin = "0000" }))
rejected(bank.request, "ACCOUNT_NOT_FOUND", "COMPANY_MONEY_PAY", bank.as(ana, {
    company_id = id, to = "Nobody At All", amount = 20, pin = "1234" }))
rejected(bank.request, "INSUFFICIENT_FUNDS", "COMPANY_MONEY_PAY", bank.as(ana, {
    company_id = id, to = "Kit Wolf", amount = 121, pin = "1234" }))
local kitBefore = bank.balanceOf(kit)
local paid = bank.request("COMPANY_MONEY_PAY", bank.as(ana, { company_id = id, to = "kit wolf",
    amount = 20, pin = "1234", note = "Wages" }))
assert(paid.to == "Kit Wolf" and paid.money.balance == 100 and paid.money.paid_out == 20)
assert(bank.balanceOf(kit) == kitBefore + 20, "to anybody")
assert(paid.money.log[1].kind == "pay" and paid.money.log[1].amount == -20)
-- And to the owner, the same way.
bank.request("COMPANY_MONEY_PAY", bank.as(ana, { company_id = id, amount = 10, pin = "1234" }))
assert(bank.balanceOf(ana) == anaBefore + 10 and money().balance == 90)
local added = bank.request("COMPANY_MONEY_ADD", bank.as(ana, { company_id = id, amount = 210,
    pin = "1234" }))
assert(added.money.balance == 300 and bank.balanceOf(ana) == anaBefore + 10 - 210)

-- Radio+ ---------------------------------------------------------------------------------------------

local plus = bank.request("RADIO_PLUS_START", bank.as(ana, { company_id = id }))
assert(plus.money.balance == 200 and plus.money.radio_plus.active, "100 out of Company Money")
assert(plus.money.radio_plus.next_charge_day == util.ingameDay() + 15)
rejected(bank.request, "ALREADY", "RADIO_PLUS_START", bank.as(ana, { company_id = id }))
rejected(bank.request, "NOT_OWNER", "RADIO_PLUS_START", bank.as(kit, { company_id = id }))

-- MUSIC_RADIO_PLUS tells the Music Server, for its stations.
local server = bank.core.actions.MUSIC_SERVER_REGISTER({ code = "4040", name = "Music" }, 77)
local function musicAsk(action, payload)
    payload = payload or {}
    payload.server_token = server.server_token
    return bank.request(action, payload)
end
local status = musicAsk("MUSIC_RADIO_PLUS", { company_ids = { id, "NOPE" } }).companies
assert(status[id].radio_plus and status[id].free == 200 and not status.NOPE)
local mine = musicAsk("MUSIC_COMPANY", { session_token = ana.token })
assert(mine.name == "Ana Fox" and mine.companies[1].company_id == id and mine.companies[1].radio_plus)
rejected(bank.request, "MUSIC_AUTH", "MUSIC_COMPANY", { session_token = ana.token })

-- Ad breaks ----------------------------------------------------------------------------------------

local ad = musicAsk("MUSIC_AD_BREAK", { company_id = id, radio_id = "B1", name = "Fox FM",
    listeners = { kit.id, kit.id, noa.id, ana.id, "AC-NOBODY" } })
assert(ad.paid == 50 and ad.listeners == 2, "Kit once, Noa, never the owner: " .. ad.paid)
assert(money().balance == 250 and money().log[1].kind == "ads")
local again = musicAsk("MUSIC_AD_BREAK", { company_id = id, radio_id = "B1",
    listeners = { kit.id, noa.id } })
assert(again.paid == 0 and again.too_soon, "one paid break every ten minutes")
bank.advanceMs(10 * 60 * 1000 + 1000)
again = musicAsk("MUSIC_AD_BREAK", { company_id = id, radio_id = "B1", name = "Fox FM",
    listeners = { kit.id } })
assert(again.paid == 25 and money().balance == 275)
assert(money().log[1].amount == 75 and money().log[1].count == 2, "one line a day")

-- A company's giveaway -------------------------------------------------------------------------------

local number = musicAsk("MUSIC_RADIO_NUMBER", { radio_id = "B1", name = "Fox FM" }).number
rejected(musicAsk, "INSUFFICIENT_FUNDS", "MUSIC_GIVEAWAY_OPEN", { radio_id = "B1",
    company_id = id, prize = 276, seconds = 60 })
local give = musicAsk("MUSIC_GIVEAWAY_OPEN", { radio_id = "B1", company_id = id, prize = 200,
    seconds = 60 })
assert(money().free == 75 and money().reserved == 200, "the prize is held")
rejected(bank.request, "INSUFFICIENT_FUNDS", "COMPANY_MONEY_PAY", bank.as(ana, {
    company_id = id, to = "Kit Wolf", amount = 100, pin = "1234" }))
bank.request("PHONE_CALL", bank.as(kit, { number = number }))
kitBefore = bank.balanceOf(kit)
bank.advanceMs(61000)
local drawn = musicAsk("MUSIC_GIVEAWAY_STATE", { giveaway_id = give.giveaway_id })
assert(drawn.winner_name == "Kit Wolf" and drawn.prize == 200)
assert(bank.balanceOf(kit) == kitBefore + 200, "Kit won 200")
assert(money().balance == 75 and money().reserved == 0, "out of Company Money")
-- Nobody calls: the prize is free again.
give = musicAsk("MUSIC_GIVEAWAY_OPEN", { radio_id = "B1", company_id = id, prize = 50,
    seconds = 30 })
assert(money().free == 25)
bank.advanceMs(31000)
musicAsk("MUSIC_GIVEAWAY_STATE", { giveaway_id = give.giveaway_id })
assert(money().free == 75 and money().balance == 75, "nobody called, nothing paid")

-- Radio+ renews on its day, or stops ------------------------------------------------------------------

local function newDay()
    bank.advanceDays(1)
    company.radio_plus.next_charge_day = util.ingameDay()
    bank.core.process_subscriptions()
end
bank.request("COMPANY_MONEY_ADD", bank.as(ana, { company_id = id, amount = 100, pin = "1234" }))
newDay()
assert(company.radio_plus and company.radio_plus.next_charge_day == util.ingameDay() + 15
    and money().balance == 75, "renewed: 100 more out of Company Money")
newDay()
assert(company.radio_plus == nil, "75 cannot pay for it: stopped")
local told = false
for _, note in ipairs(bank.notifications(ana)) do
    if note.title == "Radio+ stopped" then told = true end
end
assert(told, "and the owner is told")
-- Cancelled, it lasts to its day and then ends.
bank.request("COMPANY_MONEY_ADD", bank.as(ana, { company_id = id, amount = 100, pin = "1234" }))
bank.request("RADIO_PLUS_START", bank.as(ana, { company_id = id }))
bank.request("RADIO_PLUS_CANCEL", bank.as(ana, { company_id = id }))
assert(money().radio_plus.cancelled and money().balance == 75)
newDay()
assert(company.radio_plus == nil and money().balance == 75, "ended, not charged")

io.write("host_company_money_test: OK\n")
