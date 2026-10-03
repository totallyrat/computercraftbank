-- Selling tickets the real way, FoxyOS 13, against a real Bank Core and Vault.
--
-- An event goes on sale at its release, with a presale before it for the
-- people its organizer invited -- by FoxMail, from the organizer's own
-- address. Buying happens on your turn in a queue: the waiting room is put in
-- a random order when a sale opens, later arrivals join at the back, a few
-- people choose at a time, and a turn that is not used runs out.

package.path = "../?.lua;../?/init.lua;" .. package.path

-- Two people choose at once, so a queue forms with six fans.
require("config").ticket_queue_shoppers = 2
local harness = require("bank_pair_harness")
local rejected = harness.rejected
local bank = harness.pair()
-- The host's os.time is the real clock; the game's is what a sale opens on.
os.time = function() return harness.time end


local organizer = bank.register("Venue Owner", "1111")
local fans = {}
for index = 1, 6 do
    fans[index] = bank.register("Fan " .. index, "2222")
    bank.fund(fans[index], 500)
end
local stranger = bank.register("Late Comer", "3333")
bank.fund(stranger, 500)

local function at(hour) harness.time = hour end
local today = harness.day
at(12)

-- Making the event ---------------------------------------------------------------------

rejected(bank.request, "PRESALE_AFTER_RELEASE", "CREATE_EVENT", bank.as(organizer, {
    title = "Fox Fest", event_day = today + 2, event_time = "20:00",
    location = "The Den", release_day = today, release_time = "18:00",
    presale_day = today, presale_time = "19:00" }))
rejected(bank.request, "RELEASE_AFTER_EVENT", "CREATE_EVENT", bank.as(organizer, {
    title = "Fox Fest", event_day = today, event_time = "20:00",
    release_day = today + 1, release_time = "10:00" }))
local made = bank.request("CREATE_EVENT", bank.as(organizer, {
    title = "Fox Fest", description = "Loud", event_day = today + 2,
    event_time = "20:00", location = "The Den",
    release_day = today, release_time = "18:00",
    presale_day = today, presale_time = "16:00", limit = 2 })).event
local eventId = made.event_id
local general = bank.request("ADD_TICKET_TYPE", bank.as(organizer, {
    event_id = eventId, name = "General", price = 10, quantity = 6 })).ticket_type
local function ask(who, action, extra)
    extra = extra or {}
    extra.event_id = eventId
    return bank.request(action, bank.as(who, extra))
end
local function queueOf(who) return ask(who, "QUEUE_STATUS").queue end
local function buy(who, quantity)
    return ask(who, "BUY_TICKETS", { ticket_type_id = general.ticket_type_id,
        quantity = quantity or 1, pin = who.pin })
end

-- What anybody sees, and nothing more.
local listed = bank.request("LIST_EVENTS", bank.as(fans[1])).events[1]
assert(listed.phase == "soon" and listed.release_time == "18:00"
    and listed.presale_time == "16:00" and listed.limit == 2, "on sale later")
assert(listed.invited == false)
rejected(buy, "NOT_YOUR_TURN", fans[1])

-- Presale invitations, by FoxMail ------------------------------------------------------

rejected(ask, "NOT_OWNER", fans[1], "EVENT_INVITE", { who = "Fan 2" })
rejected(ask, "NO_ADDRESS", organizer, "EVENT_INVITE", { who = "Fan 1" })
bank.request("MAIL_CLAIM", bank.as(organizer, { name = "venue" }))
bank.request("MAIL_CLAIM", bank.as(fans[1], { name = "fan1" }))
bank.request("MAIL_CLAIM", bank.as(fans[2], { name = "fan2" }))
rejected(ask, "NO_SUCH_ADDRESS", organizer, "EVENT_INVITE", { who = "nobody@foxy.com" })
rejected(ask, "ACCOUNT_NOT_FOUND", organizer, "EVENT_INVITE", { who = "Nobody At All" })
rejected(ask, "SELF_INVITE", organizer, "EVENT_INVITE", { who = "venue@foxy.com" })
local first = ask(organizer, "EVENT_INVITE", { who = "FAN1@foxy.com" }).invite
assert(first.name == "Fan 1" and first.mailed, "by address, and mailed")
local second = ask(organizer, "EVENT_INVITE", { who = "Fan 2" }).invite
assert(second.address == "fan2@foxy.com" and second.mailed,
    "by name, mailed to their address")
local third = ask(organizer, "EVENT_INVITE", { who = "Fan 3" }).invite
assert(not third.mailed, "somebody with no address is still invited")
rejected(ask, "ALREADY_INVITED", organizer, "EVENT_INVITE", { who = "Fan 3" })
assert(#ask(organizer, "EVENT_INVITES").invites == 3)
local inbox = bank.request("MAIL_LIST", bank.as(fans[1], { address = "fan1@foxy.com" }))
assert(inbox.messages[1].from == "venue@foxy.com"
    and inbox.messages[1].subject == "Presale invite: Fox Fest",
    "the invitation is in their inbox, from the organizer")
local found = false
for _, note in ipairs(bank.notifications(fans[3])) do
    if note.title == "Presale invite" then found = true end
end
assert(found, "and everybody invited is told")
assert(bank.request("LIST_EVENTS", bank.as(fans[1])).events[1].invited)
-- Taking an invite back.
ask(organizer, "EVENT_INVITE", { who = "Late Comer" })
local kept = ask(organizer, "EVENT_UNINVITE", { account_id = stranger.id }).invites
assert(#kept == 3, "uninvited")

-- The waiting room ---------------------------------------------------------------------

local room = ask(fans[1], "QUEUE_JOIN").queue
assert(room.status == "waiting" and room.waiting_room and room.queue_phase == "presale",
    "an invited fan waits for the presale")
ask(fans[2], "QUEUE_JOIN")
ask(fans[3], "QUEUE_JOIN")
local outside = ask(fans[4], "QUEUE_JOIN").queue
assert(outside.queue_phase == "general" and outside.waiting_room,
    "somebody not invited waits for the general sale")
assert(outside.ahead == nil, "nobody has a place before the sale opens")

-- Nobody leaks: not the queue, not the guest list.
local details = ask(fans[5], "EVENT_DETAILS")
assert(details.event.queue == nil and details.event.invites == nil
    and details.event.bought == nil, "a public view of the event")
assert(details.mine.status == "none")

-- The presale opens --------------------------------------------------------------------

at(16.5)
for index = 1, 4 do queueOf(fans[index]) end
-- Two choose at once here; the lottery decided which two.
local turns, waiter = {}, nil
for index = 1, 3 do
    local mine = queueOf(fans[index])
    if mine.status == "shopping" then turns[#turns + 1] = fans[index]
    elseif mine.status == "waiting" then waiter = fans[index] end
end
assert(#turns == 2 and waiter, "two invited fans choose at once")
local next = queueOf(waiter)
assert(next.ahead == 0 and not next.waiting_room and next.in_line == 1,
    "the third has a place now: first in line")
assert(queueOf(fans[4]).waiting_room, "the general sale has not opened yet")
-- Fan 5 is not invited: in the presale they wait for the general sale.
assert(ask(fans[5], "QUEUE_JOIN").queue.queue_phase == "general")

local a, b = turns[1], turns[2]
local bought = buy(a, 2)
assert(#bought.tickets == 2 and bought.queue.status == "done",
    "the limit bought, the turn is over")
rejected(ask, "LIMIT_REACHED", a, "QUEUE_JOIN")
rejected(buy, "BAD_QUANTITY", b, 3)
buy(b, 1)
rejected(buy, "LIMIT_REACHED", b, 2)
assert(queueOf(b).status == "shopping", "one more is allowed on the same turn")
ask(b, "QUEUE_LEAVE")
assert(queueOf(b).status == "done")
assert(queueOf(waiter).status == "shopping", "and the next in line gets a turn")

-- A turn that is not used runs out. Everybody keeps their screen open; the
-- third fan just never buys.
for _ = 1, 7 do
    bank.advanceMs(20 * 1000)
    queueOf(waiter)
    queueOf(fans[4])
    queueOf(fans[5])
end
assert(queueOf(waiter).status == "expired", "the turn ran out")
assert(queueOf(fans[4]).waiting_room, "and nobody else gets a presale turn")

-- The general sale ---------------------------------------------------------------------

at(18.25)
local late = ask(stranger, "QUEUE_JOIN").queue
local four, five = queueOf(fans[4]), queueOf(fans[5])
assert(four.status == "shopping" and five.status == "shopping",
    "the waiting room goes first")
late = queueOf(stranger)
assert(late.status == "waiting" and late.ahead == 0 and not late.waiting_room,
    "and whoever arrived after the sale opened joins behind it")
-- Somebody who stops checking in loses their place.
for _ = 1, 4 do
    bank.advanceMs(8 * 1000)
    queueOf(fans[4])
    queueOf(fans[5])
end
assert(queueOf(stranger).status == "left", "the stranger walked away")
local rejoin = ask(stranger, "QUEUE_JOIN").queue
assert(rejoin.status == "waiting",
    "and joins again at the back")

-- Selling out closes the queue.
buy(fans[4], 2)
assert(queueOf(stranger).status == "shopping", "a turn freed up")
buy(fans[5], 1)
rejected(buy, "SOLD_OUT", stranger, 2)
local organizerView = bank.request("MY_EVENTS", bank.as(organizer)).events[1]
assert(organizerView.sold == 6 and organizerView.invited_count == 3)
rejected(ask, "SOLD_OUT", fans[6], "QUEUE_JOIN")
assert(bank.request("LIST_EVENTS", bank.as(fans[6])).events[1].sold_out)

-- Money went where it should, and the stored event carries no copies.
-- Everybody starts with 500, and the fans were given 500 more.
assert(bank.balanceOf(a) == 980 and bank.balanceOf(organizer) == 560)
for _, event in pairs(bank.vault_state.events) do
    assert(event.ticket_types == nil, "MY_EVENTS no longer writes onto the event")
end

-- Changing the sale afterwards ---------------------------------------------------------

rejected(ask, "NOT_OWNER", fans[1], "EVENT_SALE", { limit = 4 })
rejected(ask, "INVALID_LIMIT", organizer, "EVENT_SALE", { limit = 11 })
local changed = ask(organizer, "EVENT_SALE", { limit = 4, presale = false }).event
assert(changed.limit == 4 and changed.presale_day == nil)

-- An event from before 13 has no release: on sale, through the same queue.
local old = bank.request("CREATE_EVENT", bank.as(organizer, {
    title = "Old Show", event_day = today + 3, event_time = "12:00",
    location = "Hall" })).event
local oldType = bank.request("ADD_TICKET_TYPE", bank.as(organizer, {
    event_id = old.event_id, name = "Seat", price = 5, quantity = 10 })).ticket_type
local direct = bank.request("QUEUE_JOIN", bank.as(fans[6], { event_id = old.event_id }))
assert(direct.queue.status == "shopping", "nobody ahead, straight in")
bank.request("BUY_TICKETS", bank.as(fans[6], { event_id = old.event_id,
    ticket_type_id = oldType.ticket_type_id, quantity = 1, pin = "2222" }))

print("host_ticket_queue_test: OK")
