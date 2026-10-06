-- VerCode and Yap Map on the Bank, FoxyOS 15.2 -- ahead of the FoxyOS 16
-- Pockets and Yap! that use them -- against a real Bank Core and Vault.
--
-- VerCode: an app somebody signed in to asks the Bank to send them a code,
-- and checks the one they type back. The code arrives as a message from the
-- app's publisher -- its developer's company, or Foxy for the apps FoxyOS
-- ships -- in a chat nobody can answer, and as a notification carrying the
-- code, which a Pocket offers to paste. Five minutes, five tries, one at a
-- time.
--
-- Yap Map: where your friends are, if they are in a Coordinate Zone (their
-- Pocket has coordinates from the GPS Anchors). Only friends who use Yap!,
-- and never anybody who chose Hide me.

package.path = "../?.lua;../?/init.lua;" .. package.path
sleep = function() end
local harness = require("bank_pair_harness")
local rejected = harness.rejected
local bank = harness.pair()

local ana = bank.register("Ana Fox", "1234")
local kit = bank.register("Kit Wolf", "5678")
local sam = bank.register("Sam Hare", "4321")
local lee = bank.register("Lee Owl", "1111")

local function signIn(who, appId, name)
    bank.request("FOXY_LOGIN_APPROVE", bank.as(who, { app_id = appId,
        app_name = name or appId, scopes = { "name" } }))
end
local function app(who, appId, action, extra)
    extra = extra or {}
    extra.app_id = appId
    return bank.request(action, bank.as(who, extra))
end

-- Only an app, only signed in -------------------------------------------------------------

rejected(app, "NOT_SIGNED_IN", ana, "YAP", "VERCODE_SEND")
rejected(bank.request, "APP_REQUIRED", "VERCODE_SEND", bank.as(ana, {}))
signIn(ana, "YAP", "Yap!")

-- From Foxy, for an app FoxyOS ships --------------------------------------------------------

local sent = app(ana, "YAP", "VERCODE_SEND")
assert(sent.sent and sent.publisher == "Foxy" and sent.expires_in == 300)
-- The notification carries the code; the poll hands it to the Pocket.
local poll = bank.request("PUMPE_POLL", bank.as(ana))
local latest = poll.latest
assert(latest and latest.kind == "vercode" and latest.publisher == "Foxy",
    "a VerCode notification, from the publisher")
local code = latest.code
assert(code and code:match("^%d%d%d%d%d%d$"), "six digits: " .. tostring(code))
assert(latest.body:find(code, 1, true), "and says it")
-- The message: a chat from Foxy, that cannot be answered.
local chats = bank.request("CHAT_LIST", bank.as(ana)).conversations
local thread
for _, chat in ipairs(chats) do if chat.title == "Foxy" then thread = chat end end
assert(thread and thread.kind == "publisher" and thread.unread == 1,
    "a chat from Foxy, unread")
local opened = bank.request("CHAT_OPEN", bank.as(ana, { conversation_id = thread.conversation_id }))
assert(opened.messages[1].body:find(code, 1, true) and opened.messages[1].sender_name == "Foxy")
rejected(bank.request, "READ_ONLY", "CHAT_SEND", bank.as(ana, {
    conversation_id = thread.conversation_id, body = "thanks" }))
rejected(bank.request, "READ_ONLY", "CHAT_REQUEST_MONEY", bank.as(ana, {
    conversation_id = thread.conversation_id, amount = 5 }))

-- One at a time.
rejected(app, "VERCODE_WAIT", ana, "YAP", "VERCODE_SEND")

-- A code is for its app: INVT cannot use Yap!'s.
signIn(ana, "INVT")
rejected(app, "NO_VERCODE", ana, "INVT", "VERCODE_CHECK", { code = code })
-- Checking it: wrong, then right, and only once.
rejected(app, "BAD_VERCODE", ana, "YAP", "VERCODE_CHECK", { code = "000000" == code and "111111" or "000000" })
local checked = app(ana, "YAP", "VERCODE_CHECK", { code = code })
assert(checked.verified, "the code they were sent")
rejected(app, "NO_VERCODE", ana, "YAP", "VERCODE_CHECK", { code = code })

-- Five tries, then a new code.
bank.advanceMs(21000)
app(ana, "YAP", "VERCODE_SEND")
local second = bank.request("PUMPE_POLL", bank.as(ana)).latest.code
for _ = 1, 5 do
    rejected(app, "BAD_VERCODE", ana, "YAP", "VERCODE_CHECK",
        { code = second == "000000" and "111111" or "000000" })
end
rejected(app, "VERCODE_LOCKED", ana, "YAP", "VERCODE_CHECK", { code = second })
-- And five minutes.
bank.advanceMs(21000)
app(ana, "YAP", "VERCODE_SEND")
local third = bank.request("PUMPE_POLL", bank.as(ana)).latest.code
bank.advanceMs(5 * 60 * 1000 + 1)
rejected(app, "VERCODE_EXPIRED", ana, "YAP", "VERCODE_CHECK", { code = third })
-- The same thread every time.
local foxyThreads = 0
for _, chat in ipairs(bank.request("CHAT_LIST", bank.as(ana)).conversations) do
    if chat.title == "Foxy" then foxyThreads = foxyThreads + 1 end
end
assert(foxyThreads == 1, "one chat from Foxy, not one per code")

-- From a company, for an app somebody published -------------------------------------------

local company = bank.request("COMPANY_CREATE", bank.as(kit, { app_id = "COMPANY",
    company_name = "Wolf Games" })).company
assert(company)
local developer = bank.request("DEV_REGISTER", bank.as(kit, { pin = "5678" }))
bank.request("APP_OWNER_SET", { app_id = "APP00007", app_name = "Howl",
    developer_id = developer.developer_id, developer_token = developer.developer_token })
signIn(sam, "APP00007", "Howl")
assert(app(sam, "APP00007", "VERCODE_SEND").publisher == "Wolf Games",
    "from the company the developer runs")
assert(bank.request("PUMPE_POLL", bank.as(sam)).latest.title == "Wolf Games")

-- Yap Map ------------------------------------------------------------------------------------

for _, pair in ipairs({ { ana, "Kit Wolf" }, { ana, "Sam Hare" }, { ana, "Lee Owl" } }) do
    bank.request("FRIEND_REQUEST", bank.as(pair[1], { name = pair[2] }))
end
for _, who in ipairs({ kit, sam, lee }) do
    bank.request("FRIEND_REQUEST", bank.as(who, { name = "Ana Fox" }))
end
signIn(kit, "YAP", "Yap!")
signIn(sam, "YAP", "Yap!")
-- Lee is a friend but does not use Yap!.
local at = function(x, z) return { x = x, y = 64, z = z } end
bank.request("REPORT_POSITION", bank.as(kit, { position = at(120.6, -30.2) }))
bank.request("REPORT_POSITION", bank.as(lee, { position = at(5, 5) }))
bank.request("REPORT_POSITION", bank.as(ana, { position = at(1, 2) }))

rejected(app, "WRONG_APP", ana, "INVT", "YAP_MAP")
local map = app(ana, "YAP", "YAP_MAP")
assert(#map.friends == 2, "friends who use Yap!, and nobody else: " .. #map.friends)
assert(map.friends[1].name == "Kit Wolf" and map.friends[1].in_zone
    and map.friends[1].x == 120 and map.friends[1].z == -31,
    "Kit, in a Coordinate Zone, with coordinates")
assert(map.friends[2].name == "Sam Hare" and not map.friends[2].in_zone
    and map.friends[2].x == nil, "Sam has no coordinates: not in a zone")
assert(map.me and map.me.x == 1 and not map.hidden, "and where you are")

-- Kit hides: gone from Ana's.
assert(app(kit, "YAP", "YAP_MAP_HIDE", { hidden = true }).hidden)
map = app(ana, "YAP", "YAP_MAP")
assert(#map.friends == 1 and map.friends[1].name == "Sam Hare", "Hide me hides")
assert(app(kit, "YAP", "YAP_MAP").hidden, "and Kit sees that they are hidden")
app(kit, "YAP", "YAP_MAP_HIDE", { hidden = false })
-- Old coordinates are not a zone.
bank.advanceMs(10 * 60 * 1000)
map = app(ana, "YAP", "YAP_MAP")
assert(map.friends[1].name == "Kit Wolf" and not map.friends[1].in_zone,
    "a position nobody has reported for a while is not a zone")

print("host_vercode_test: OK")
