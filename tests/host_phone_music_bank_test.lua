-- FoxyOS 17 at the Bank: FoxyCloud+ tiers, phone numbers and what a plan
-- allows a day, calling a number, and the Music Server's side of it --
-- songs played and uploaded, songs kept on the Cloud Servers, and radio
-- giveaways. A real Core and Vault, through the routes a client uses.

package.path = "../?.lua;../?/init.lua;" .. package.path
local harness = require("bank_pair_harness")
local rejected = harness.rejected
local bank = harness.pair()
local config = require("config")
local util = require("lib.util")
local state = bank.state

local ana = bank.register("Ana Fox", "1234")
local kit = bank.register("Kit Wolf", "5678")
local noa = bank.register("Noa Hare", "4321", { no_phone = true })
bank.fund(ana, 5000)
bank.fund(kit, 2000)

-- Tiers ------------------------------------------------------------------------------------

local free = bank.request("CLOUD_PLAN", bank.as(ana))
assert(free.tier == 0 and free.plan == "free" and #free.tiers == 2)
assert(free.tiers[1].price == 500 and free.tiers[1].bytes == 25 * 1024 * 1024)
assert(free.tiers[2].price == 1000 and free.tiers[2].bytes == 50 * 1024 * 1024)
assert(free.limits.messages == 40 and free.limits.calls == 10
    and free.limits.plays == 10 and free.limits.uploads == 2, "the free day")
rejected(bank.request, "BAD_TIER", "CLOUD_PLUS_JOIN", bank.as(ana, { pin = "1234", tier = 3 }))

local balance = bank.balanceOf(ana)
local one = bank.request("CLOUD_PLUS_JOIN", bank.as(ana, { pin = "1234", tier = 1 }))
assert(one.tier == 1 and one.quota == 25 * 1024 * 1024 and one.tier_name == "FoxyCloud+ Tier 1")
assert(one.limits.messages == 500 and one.limits.calls == 100)
assert(one.limits.plays == nil and one.limits.uploads == nil, "songs are unlimited on any tier")
assert(bank.balanceOf(ana) == balance - 500)
local renewDay = one.next_charge_day

-- Two days in, up to Tier 2: the difference now, and the same renewal day.
bank.advanceDays(2)
balance = bank.balanceOf(ana)
local two = bank.request("CLOUD_PLUS_JOIN", bank.as(ana, { pin = "1234", tier = 2 }))
assert(two.tier == 2 and two.quota == 50 * 1024 * 1024)
assert(bank.balanceOf(ana) == balance - 500, "Tier 2 is 500 more than Tier 1, not 1000 again")
assert(two.next_charge_day == renewDay, "what was paid for still counts")
assert(two.limits.messages == nil and two.limits.calls == nil, "Tier 2 is unlimited")
rejected(bank.request, "ALREADY_PLUS", "CLOUD_PLUS_JOIN", bank.as(ana, { pin = "1234", tier = 2 }))

-- Down to Tier 1 waits for the next charge: nobody pays for room they lose.
balance = bank.balanceOf(ana)
local down = bank.request("CLOUD_PLUS_JOIN", bank.as(ana, { pin = "1234", tier = 1 }))
assert(down.tier == 2 and down.next_tier == 1 and bank.balanceOf(ana) == balance)
bank.advanceDays(renewDay - util.ingameDay())
bank.process_subscriptions()
local stepped = bank.request("CLOUD_PLAN", bank.as(ana))
assert(stepped.tier == 1 and stepped.next_tier == nil)
assert(bank.balanceOf(ana) == balance - 500, "renewed at the Tier 1 price")

-- Phone numbers --------------------------------------------------------------------------

assert(ana.phone:match("^%d%d%d%-%d%d%d%d$"), tostring(ana.phone))
assert(bank.request("PHONE_GET", bank.as(ana)).number == ana.phone, "one number, kept")
local noaPhone = bank.request("PHONE_ME", bank.as(noa))
assert(noaPhone.number == nil and noaPhone.messages_limit == 40 and noaPhone.calls_limit == 10)

-- Messages and Urgent Contact need one.
bank.request("FRIEND_REQUEST", bank.as(noa, { account_id = kit.id }))
bank.request("FRIEND_RESPOND", bank.as(kit, { account_id = noa.id, accept = true }))
rejected(bank.request, "NO_NUMBER", "CHAT_START", bank.as(noa, { account_ids = { kit.id } }))
rejected(bank.request, "NO_NUMBER", "URGENT_CALL", bank.as(noa, { account_id = kit.id }))
-- Reading what has arrived does not: a government message still reaches you.
assert(bank.request("CHAT_LIST", bank.as(noa)).conversations)
noa.phone = bank.request("PHONE_GET", bank.as(noa)).number
assert(noa.phone ~= ana.phone and noa.phone ~= kit.phone)

-- Who has a number, for a Pocket about to call it. Dashes and spaces are fine.
local found = bank.request("PHONE_LOOKUP", bank.as(kit,
    { number = " " .. ana.phone:gsub("%-", " ") }))
assert(found.kind == "person" and found.name == "Ana Fox" and found.number == ana.phone)
rejected(bank.request, "NO_SUCH_NUMBER", "PHONE_LOOKUP", bank.as(kit, { number = "12" }))

-- Forty messages a day on the free plan, counted once they have gone.
local chat = bank.request("CHAT_START", bank.as(noa, { account_ids = { kit.id } })).conversation
for index = 1, 40 do
    bank.request("CHAT_SEND", bank.as(noa, { conversation_id = chat.conversation_id,
        body = "Message " .. index }))
end
local used = bank.request("PHONE_ME", bank.as(noa))
assert(used.messages == 40, used.messages)
rejected(bank.request, "MESSAGE_LIMIT", "CHAT_SEND", bank.as(noa,
    { conversation_id = chat.conversation_id, body = "One more" }))
rejected(bank.request, "MESSAGE_LIMIT", "CHAT_REQUEST_MONEY", bank.as(noa,
    { conversation_id = chat.conversation_id, amount = 5 }))
-- A message that is refused for another reason is not counted.
rejected(bank.request, "EMPTY_MESSAGE", "CHAT_SEND", bank.as(kit,
    { conversation_id = chat.conversation_id, body = "  " }))
assert(bank.request("PHONE_ME", bank.as(kit)).messages == 0)
-- A new in-game day is a new forty.
bank.advanceDays(1)
assert(bank.request("CHAT_SEND", bank.as(noa, { conversation_id = chat.conversation_id,
    body = "Morning" })))
assert(bank.request("PHONE_ME", bank.as(noa)).messages == 1)

-- Ten calls a day free.
for _ = 1, 10 do
    local call = bank.request("URGENT_CALL", bank.as(noa, { account_id = kit.id })).call
    bank.request("URGENT_END", bank.as(noa, { call_id = call.call_id }))
end
rejected(bank.request, "CALL_LIMIT", "URGENT_CALL", bank.as(noa, { account_id = kit.id }))

-- Ana is on Tier 1: five hundred.
assert(bank.request("PHONE_ME", bank.as(ana)).messages_limit == 500)

-- Calling a number ------------------------------------------------------------------------
-- From the Pocket itself, or Foxy's Music app; never another installed app,
-- since a call to a radio costs money without a PIN.
rejected(bank.request, "WRONG_APP", "PHONE_CALL", bank.as(ana, { number = kit.phone,
    app_id = "YAP" }))
rejected(bank.request, "WRONG_APP", "PHONE_GET", bank.as(ana, { app_id = "MUSIC" }))
-- A person's number rings them through Urgent Contact, friend or not.
assert(not state.accounts[ana.id].friends, "the Core keeps no friends list")
local rang = bank.request("PHONE_CALL", bank.as(ana, { number = kit.phone }))
assert(rang.kind == "person" and rang.name == "Kit Wolf" and rang.call.status == "ringing")
bank.request("URGENT_END", bank.as(ana, { call_id = rang.call.call_id }))
rejected(bank.request, "OWN_NUMBER", "PHONE_CALL", bank.as(ana, { number = ana.phone }))
rejected(bank.request, "CALL_LIMIT", "PHONE_CALL", bank.as(noa, { number = ana.phone }))
-- Texting a number starts a chat with somebody who is not a friend.
local texted = bank.request("CHAT_START", bank.as(ana, { number = kit.phone })).conversation
assert(texted and texted.kind == "direct")
rejected(bank.request, "NOT_FRIENDS", "CHAT_START", bank.as(ana, { account_ids = { noa.id } }))
rejected(bank.request, "NO_SUCH_NUMBER", "CHAT_START", bank.as(ana, { number = "999-0000" }))

-- A company's number tells its owner who called, and their number.
local company = bank.request("COMPANY_CREATE", bank.as(kit, { company_name = "Kit Cafe" })).company
local companyPhone = bank.request("COMPANY_PHONE", bank.as(kit,
    { company_id = company.company_id })).phone
assert(companyPhone:match("^%d%d%d%-%d%d%d%d$"))
assert(bank.request("COMPANY_PHONE", bank.as(kit, { company_id = company.company_id })).phone
    == companyPhone)
rejected(bank.request, "NOT_OWNER", "COMPANY_PHONE", bank.as(ana, { company_id = company.company_id }))
local called = bank.request("PHONE_CALL", bank.as(ana, { number = companyPhone }))
assert(called.kind == "company" and called.name == "Kit Cafe")
local note = bank.notifications(kit)[1]
assert(note and note.title == "Call for Kit Cafe" and note.body:find(ana.phone, 1, true),
    "the owner can call back")

-- The Music Server ---------------------------------------------------------------------------

rejected(bank.request, "BAD_CODE", "MUSIC_SERVER_REGISTER", { code = "1111" })
rejected(bank.request, "MUSIC_OFFLINE", "MUSIC_WHERE", {})
local server = bank.core.actions.MUSIC_SERVER_REGISTER({ code = "4040", name = "Music 9" }, 77)
assert(server.server_token and server.server_id == "MS1")
-- Where it is, for a Pocket about to hand it a session: the computer that
-- registered, not whichever answers to the name.
assert(bank.request("MUSIC_WHERE", {}).computer_id == 77)
bank.core.actions.MUSIC_WHO({ server_token = server.server_token,
    session_token = kit.token }, 78)
assert(bank.request("MUSIC_WHERE", {}).computer_id == 78, "it moved to another computer")
local function musicAsk(action, payload)
    payload = payload or {}
    payload.server_token = server.server_token
    return bank.request(action, payload)
end
rejected(bank.request, "MUSIC_AUTH", "MUSIC_PLAY", { server_token = "nope", account_id = kit.id })

-- Who is listening, from their session, and what their plan allows.
local who = musicAsk("MUSIC_WHO", { session_token = kit.token })
assert(who.account_id == kit.id and who.tier == 0 and who.plays_limit == 10)

-- Ten songs a day free; radios are free and never ask.
for _ = 1, 10 do musicAsk("MUSIC_PLAY", { account_id = kit.id }) end
local stopped = rejected(musicAsk, "MUSIC_LIMIT", "MUSIC_PLAY", { account_id = kit.id })
assert(stopped.message:find("Radios are free", 1, true))
local anaWho = musicAsk("MUSIC_PLAY", { account_id = ana.id })
assert(anaWho.plays_limit == nil and anaWho.plays == 1, "unlimited with FoxyCloud+")

-- Two uploads a day free: checked before, counted after.
for _ = 1, 2 do
    musicAsk("MUSIC_UPLOAD_CHECK", { account_id = kit.id })
    musicAsk("MUSIC_UPLOADED", { account_id = kit.id })
end
rejected(musicAsk, "UPLOAD_LIMIT", "MUSIC_UPLOAD_CHECK", { account_id = kit.id })
bank.advanceDays(1)
assert(musicAsk("MUSIC_UPLOAD_CHECK", { account_id = kit.id }).uploads == 0, "a new day")

-- Songs on the Cloud Servers, under the library's name. Only a Music Server.
rejected(bank.request, "MUSIC_AUTH", "CLOUD_MUSIC_PUT", bank.as(kit, { size = 100 }))
rejected(musicAsk, "TOO_BIG", "CLOUD_MUSIC_PUT", { size = config.music_max_bytes + 1 })
rejected(musicAsk, "CLOUD_OFFLINE", "CLOUD_MUSIC_PUT", { size = 60000, name = "T1.dfpwm" })
for _ in pairs(bank.vault.cloud.store().files) do error("no Cloud Server: nothing kept") end

-- Radios and giveaways -----------------------------------------------------------------------

local radio = musicAsk("MUSIC_RADIO_NUMBER", { radio_id = "R1", name = "Foxy FM" })
assert(radio.number:match("^%d%d%d%-%d%d%d%d$") and radio.name == "Foxy FM")
local renamed = musicAsk("MUSIC_RADIO_NUMBER", { radio_id = "R1", name = "Foxy FM 99" })
assert(renamed.number == radio.number and renamed.name == "Foxy FM 99", "same number, new name")
assert(bank.request("PHONE_LOOKUP", bank.as(kit, { number = radio.number })).kind == "radio")

-- Outside a giveaway the lines are closed, and nothing is charged.
balance = bank.balanceOf(kit)
rejected(bank.request, "LINES_CLOSED", "PHONE_CALL", bank.as(kit, { number = radio.number }))
assert(bank.balanceOf(kit) == balance)

local giveaway = musicAsk("MUSIC_GIVEAWAY_OPEN", { radio_id = "R1", seconds = 120 })
assert(giveaway.status == "open" and giveaway.number == radio.number
    and giveaway.radio_name == "Foxy FM 99" and giveaway.closes_in_ms == 120000)
rejected(musicAsk, "NO_NUMBER", "MUSIC_GIVEAWAY_OPEN", { radio_id = "R2" })

-- Fifty a call, and every call is another entry.
balance = bank.balanceOf(kit)
local entry
for _ = 1, 3 do entry = bank.request("PHONE_CALL", bank.as(kit, { number = radio.number })) end
assert(entry.kind == "radio" and entry.price == 50 and entry.entries == 3)
assert(bank.balanceOf(kit) == balance - 150)
local anaEntry = bank.request("PHONE_CALL", bank.as(ana, { number = radio.number }))
assert(anaEntry.entries == 1 and anaEntry.all_entries == 4)
assert(state.phone_revenue == 200)
-- Calls to a radio count against the day's calls too.
bank.state.accounts[noa.id].phone_usage = { day = util.ingameDay(), messages = 0, calls = 10 }
rejected(bank.request, "CALL_LIMIT", "PHONE_CALL", bank.as(noa, { number = radio.number }))
bank.state.accounts[noa.id].balance = 20
bank.state.accounts[noa.id].phone_usage = nil
rejected(bank.request, "INSUFFICIENT_FUNDS", "PHONE_CALL", bank.as(noa, { number = radio.number }))

-- The draw is weighted by calls: four entries in the accounts' fixed order,
-- so the fourth is whoever is last -- Kit's third call, or Ana's one.
local expected = ana.id < kit.id and kit or ana
local realRandom = math.random
local picks = { 4, 321 }
math.random = function(low, high)
    local value = table.remove(picks, 1)
    assert(value and value >= low and value <= high, "draw out of range")
    return value
end
bank.advanceMs(120000)
local winnerBefore = bank.balanceOf(expected)
local done = musicAsk("MUSIC_GIVEAWAY_STATE", { giveaway_id = giveaway.giveaway_id })
math.random = realRandom
assert(done.status == "drawn" and done.winner_name == expected.name
    and done.prize == 321, tostring(done.winner_name) .. " " .. tostring(done.prize))
assert(state.giveaway_paid == 321)
assert(bank.balanceOf(expected) == winnerBefore + 321, "the prize is in their account")
local won = bank.notifications(expected)[1]
assert(won.title == "You won on Foxy FM 99" and won.kind == "money")

-- Closed: no more calls. A giveaway nobody called draws nobody.
rejected(bank.request, "LINES_CLOSED", "PHONE_CALL", bank.as(kit, { number = radio.number }))
local quiet = musicAsk("MUSIC_GIVEAWAY_OPEN", { radio_id = "R1", seconds = 30 })
bank.advanceMs(31000)
bank.music.sweepGiveaways()
assert(bank.state.giveaways[quiet.giveaway_id].status == "drawn",
    "the Bank closes it on time, asked or not")
local nobody = musicAsk("MUSIC_GIVEAWAY_STATE", { giveaway_id = quiet.giveaway_id })
assert(nobody.status == "drawn" and nobody.winner_name == nil and state.giveaway_paid == 321)
-- A day later they are forgotten.
bank.advanceMs(25 * 60 * 60 * 1000)
bank.music.sweepGiveaways()
rejected(musicAsk, "NOT_FOUND", "MUSIC_GIVEAWAY_STATE", { giveaway_id = quiet.giveaway_id })

io.write("host_phone_music_bank_test: OK\n")
