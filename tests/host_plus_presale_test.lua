-- The FoxyCloud+ pre-presale, FoxyOS 16.3, on a real Bank Core and Vault. An
-- event can let FoxyCloud+ members into its queue before the presale, the way
-- a real ticket seller lets its members in first. They stay in for the
-- presale too. Whether somebody has FoxyCloud+ is the Core's to say -- it goes
-- down the cable with the request -- and nothing a Pocket sends can claim it.

package.path = "../?.lua;../?/init.lua;" .. package.path
require("config").ticket_queue_shoppers = 2
local harness = require("bank_pair_harness")
local rejected = harness.rejected
local bank = harness.pair()
os.time = function() return harness.time end

local organizer = bank.register("Venue Owner", "1111")
local plusA = bank.register("Plus Ana", "2222")
local plusB = bank.register("Plus Bo", "2222")
local invited = bank.register("Invited Cy", "2222")
local everyone = bank.register("Dee Everyone", "2222")
for _, who in ipairs({ plusA, plusB, invited, everyone }) do bank.fund(who, 1000) end
bank.request("CLOUD_PLUS_JOIN", bank.as(plusA, { pin = "2222" }))
bank.request("CLOUD_PLUS_JOIN", bank.as(plusB, { pin = "2222" }))

local function at(hour) harness.time = hour end
local today = harness.day
at(12)

-- Setting it up ------------------------------------------------------------------------------

rejected(bank.request, "PLUS_AFTER_PRESALE", "CREATE_EVENT", bank.as(organizer, {
    title = "Fox Fest", event_day = today + 2, event_time = "20:00",
    release_day = today, release_time = "18:00",
    presale_day = today, presale_time = "16:00",
    plus_day = today, plus_time = "17:00" }))
rejected(bank.request, "PLUS_AFTER_PRESALE", "CREATE_EVENT", bank.as(organizer, {
    title = "No Presale", event_day = today + 2, event_time = "20:00",
    release_day = today, release_time = "18:00",
    plus_day = today, plus_time = "19:00" }))
local made = bank.request("CREATE_EVENT", bank.as(organizer, {
    title = "Fox Fest", event_day = today + 2, event_time = "20:00",
    location = "The Den", release_day = today, release_time = "18:00",
    presale_day = today, presale_time = "16:00",
    plus_day = today, plus_time = "14:00", limit = 2 })).event
assert(made.plus_day == today and made.plus_time == "14:00")
local eventId = made.event_id
local general = bank.request("ADD_TICKET_TYPE", bank.as(organizer, {
    event_id = eventId, name = "General", price = 10, quantity = 10 })).ticket_type
bank.request("MAIL_CLAIM", bank.as(organizer, { name = "venue" }))
bank.request("EVENT_INVITE", bank.as(organizer, { event_id = eventId, who = "Invited Cy" }))

local function ask(who, action, extra)
    extra = extra or {}
    extra.event_id = eventId
    return bank.request(action, bank.as(who, extra))
end
local function queueOf(who) return ask(who, "QUEUE_STATUS").queue end

-- Who sees what.
local seen = bank.request("LIST_EVENTS", bank.as(plusA))
assert(seen.plus_member == true and seen.events[1].plus_time == "14:00")
assert(bank.request("LIST_EVENTS", bank.as(everyone)).plus_member == false)
assert(ask(plusA, "EVENT_DETAILS").plus_member == true)
assert(ask(everyone, "EVENT_DETAILS").mine.plus_early, "everybody sees there is one")

-- The waiting rooms ---------------------------------------------------------------------------

assert(ask(plusA, "QUEUE_JOIN").queue.queue_phase == "plus")
assert(ask(plusB, "QUEUE_JOIN").queue.queue_phase == "plus")
assert(ask(invited, "QUEUE_JOIN").queue.queue_phase == "presale")
-- Saying so is not having it: only the Core's word counts.
assert(ask(everyone, "QUEUE_JOIN", { plus = true }).queue.queue_phase == "general",
    "a Pocket cannot claim FoxyCloud+")

-- 14:30: FoxyCloud+ only.
at(14.5)
assert(bank.request("LIST_EVENTS", bank.as(everyone)).events[1].phase == "plus")
assert(queueOf(plusA).status == "shopping" and queueOf(plusB).status == "shopping",
    "both members are choosing before the presale")
assert(queueOf(invited).waiting_room, "the presale has not opened")
assert(queueOf(everyone).waiting_room, "nor the general sale")
rejected(ask, "NOT_YOUR_TURN", invited, "BUY_TICKETS",
    { ticket_type_id = general.ticket_type_id, quantity = 1, pin = "2222" })
assert(ask(plusA, "BUY_TICKETS", { ticket_type_id = general.ticket_type_id,
    quantity = 2, pin = "2222" }))
ask(plusB, "QUEUE_LEAVE")

-- 16:30: the presale. The invited are in; members who arrive now still are.
at(16.5)
assert(queueOf(invited).status == "shopping", "the invited fan's turn")
assert(queueOf(everyone).waiting_room, "the general sale is still to come")

-- Ending the pre-presale, and starting it again.
local ended = ask(organizer, "EVENT_SALE", { plus = false }).event
assert(ended.plus_day == nil)
rejected(ask, "NOT_OWNER", everyone, "EVENT_SALE", { plus = false })

print("host_plus_presale_test: OK")
