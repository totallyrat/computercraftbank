-- Friends, Messages, and Urgent Contact on the Bank Server.

package.path = "../?.lua;../?/init.lua;" .. package.path

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

local currentDay, currentTime, currentEpoch = 300, 12, 1000000
os.day = function() return currentDay end
os.time = function() return currentTime end
os.epoch = function() return currentEpoch end
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

PUMPE_TEST_MODE = true
local bank = assert(loadfile("../bank_server.lua"))()
PUMPE_TEST_MODE = nil
local actions, state = bank.actions, bank.state

local function rejected(action, expectedCode, payload)
    local ok, result = pcall(action, payload)
    assert(not ok, "request should have been rejected")
    assert(type(result) == "table" and result.code == expectedCode,
        "expected " .. expectedCode .. ", got " .. tostring(result.code))
end

local function register(name, pin)
    local created = actions.REGISTER({ name = name, pin = pin, gender = "Not set" })
    return { token = created.session_token, id = created.account.account_id,
        name = name, pin = pin }
end

local function as(who, extra)
    local payload = { session_token = who.token }
    for key, value in pairs(extra or {}) do payload[key] = value end
    return payload
end

local function alerts(who)
    return actions.NOTIFICATIONS(as(who)).notifications
end

local function alertCount(who, title)
    local total = 0
    for _, item in ipairs(alerts(who)) do
        if item.title == title then total = total + 1 end
    end
    return total
end

local alice = register("Alice Fox", "1111")
local bob = register("Bob Wolf", "2222")
local cara = register("Cara Lynx", "3333")
local dave = register("Dave Elk", "4444")   -- a stranger to everyone

-- Friends -------------------------------------------------------------------

rejected(actions.FRIEND_SEARCH, "QUERY_TOO_SHORT", as(alice, { query = "b" }))

local found = actions.FRIEND_SEARCH(as(alice, { query = "wolf" })).results
assert(#found == 1 and found[1].name == "Bob Wolf", "search must find Bob")
assert(not found[1].friend and not found[1].requested)
for _, item in ipairs(actions.FRIEND_SEARCH(as(alice, { query = "fox" })).results) do
    assert(item.account_id ~= alice.id, "search must never return yourself")
end

assert(actions.FRIEND_REQUEST(as(alice, { account_id = bob.id })).status
    == "requested")
assert(alertCount(bob, "Friend request") == 1)
-- Asking twice must not queue a second request or a second alert.
actions.FRIEND_REQUEST(as(alice, { account_id = bob.id }))
assert(alertCount(bob, "Friend request") == 1, "a repeat request must be quiet")
assert(#actions.FRIEND_OVERVIEW(as(bob)).incoming == 1)
assert(#actions.FRIEND_OVERVIEW(as(alice)).outgoing == 1)

-- Bob asking back accepts immediately rather than crossing requests.
assert(actions.FRIEND_REQUEST(as(bob, { account_id = alice.id })).status
    == "friends")
assert(#actions.FRIEND_OVERVIEW(as(alice)).friends == 1)
assert(#actions.FRIEND_OVERVIEW(as(bob)).friends == 1)
assert(#actions.FRIEND_OVERVIEW(as(bob)).incoming == 0)

actions.FRIEND_REQUEST(as(cara, { account_id = alice.id }))
assert(actions.FRIEND_RESPOND(as(alice, { account_id = cara.id, accept = false })).status
    == "declined")
assert(#actions.FRIEND_OVERVIEW(as(alice)).friends == 1, "declining adds nobody")
actions.FRIEND_REQUEST(as(cara, { account_id = alice.id }))
assert(actions.FRIEND_RESPOND(as(alice, { account_id = cara.id, accept = true })).status
    == "friends")
assert(actions.ACCOUNT_SUMMARY(as(alice)).friend_count == 2)

-- Messages ------------------------------------------------------------------

rejected(actions.CHAT_START, "NOT_FRIENDS", as(bob, { account_ids = { cara.id } }))

local chat = actions.CHAT_START(as(alice, { account_ids = { bob.id } })).conversation
assert(chat.kind == "direct")
local again = actions.CHAT_START(as(bob, { account_ids = { alice.id } })).conversation
assert(again.conversation_id == chat.conversation_id,
    "a direct chat must never be duplicated")

actions.CHAT_SEND(as(alice, { conversation_id = chat.conversation_id,
    body = "Are you at the market?" }))
assert(actions.ACCOUNT_SUMMARY(as(bob)).unread_messages == 1)
assert(actions.ACCOUNT_SUMMARY(as(alice)).unread_messages == 0,
    "your own message is not unread for you")
assert(alertCount(bob, "Message from Alice Fox") == 1)

-- A second unread message must not raise a second alert.
actions.CHAT_SEND(as(alice, { conversation_id = chat.conversation_id,
    body = "I have your tools" }))
assert(actions.ACCOUNT_SUMMARY(as(bob)).unread_messages == 2)
assert(alertCount(bob, "Message from Alice Fox") == 1,
    "a busy chat must not flood the alerts list")

local opened = actions.CHAT_OPEN(as(bob, { conversation_id = chat.conversation_id }))
assert(#opened.messages == 2)
assert(actions.ACCOUNT_SUMMARY(as(bob)).unread_messages == 0,
    "opening a chat clears its unread count")

-- Money inside a chat uses the same fee and PIN rules as PUMPE Pay.
local aliceStart = actions.ACCOUNT_SUMMARY(as(alice)).account.balance
local bobStart = actions.ACCOUNT_SUMMARY(as(bob)).account.balance
local askSeq = actions.CHAT_REQUEST_MONEY(as(alice, {
    conversation_id = chat.conversation_id, amount = 100,
    note = "for the tools",
})).message.seq

rejected(actions.CHAT_PAY_REQUEST, "OWN_REQUEST", as(alice, {
    conversation_id = chat.conversation_id, seq = askSeq, pin = "1111" }))
rejected(actions.CHAT_PAY_REQUEST, "BAD_PIN", as(bob, {
    conversation_id = chat.conversation_id, seq = askSeq, pin = "0000" }))

local paid = actions.CHAT_PAY_REQUEST(as(bob, {
    conversation_id = chat.conversation_id, seq = askSeq, pin = "2222" })).quote
assert(paid.amount == 100 and paid.fee == 10 and paid.total == 110,
    "chat payments keep the 10% processing fee")
assert(actions.ACCOUNT_SUMMARY(as(bob)).account.balance == bobStart - 110)
assert(actions.ACCOUNT_SUMMARY(as(alice)).account.balance == aliceStart + 100)
rejected(actions.CHAT_PAY_REQUEST, "ALREADY_HANDLED", as(bob, {
    conversation_id = chat.conversation_id, seq = askSeq, pin = "2222" }))

local declineSeq = actions.CHAT_REQUEST_MONEY(as(alice, {
    conversation_id = chat.conversation_id, amount = 5 })).message.seq
assert(actions.CHAT_DECLINE_REQUEST(as(bob, {
    conversation_id = chat.conversation_id, seq = declineSeq })).status == "declined")

-- Group chats.
actions.FRIEND_REQUEST(as(bob, { account_id = cara.id }))
actions.FRIEND_RESPOND(as(cara, { account_id = bob.id, accept = true }))
local group = actions.CHAT_START(as(alice, {
    account_ids = { bob.id, cara.id }, title = "Market Run" })).conversation
assert(group.kind == "group" and group.member_count == 3)
assert(group.title == "Market Run")
-- Unread counts span every conversation, so measure the change this one
-- message makes rather than assuming the earlier chat was left clean.
local aliceUnread = actions.ACCOUNT_SUMMARY(as(alice)).unread_messages
local bobUnread = actions.ACCOUNT_SUMMARY(as(bob)).unread_messages
actions.CHAT_SEND(as(cara, { conversation_id = group.conversation_id,
    body = "On my way" }))
assert(actions.ACCOUNT_SUMMARY(as(alice)).unread_messages == aliceUnread + 1)
assert(actions.ACCOUNT_SUMMARY(as(bob)).unread_messages == bobUnread + 1)
assert(actions.ACCOUNT_SUMMARY(as(cara)).unread_messages == 0,
    "the sender never sees their own group message as unread")
rejected(actions.CHAT_SEND_MONEY, "CHOOSE_MEMBER", as(alice, {
    conversation_id = group.conversation_id, amount = 5, pin = "1111" }))
assert(actions.CHAT_SEND_MONEY(as(alice, {
    conversation_id = group.conversation_id, to_account_id = cara.id,
    amount = 20, pin = "1111" })).quote.amount == 20)

-- Urgent Contact ------------------------------------------------------------

rejected(actions.URGENT_CALL, "ACCOUNT_NOT_FOUND",
    as(cara, { account_id = "ACC999999" }))
rejected(actions.URGENT_CALL, "NOT_FRIENDS", as(cara, { account_id = dave.id }))
rejected(actions.CHAT_START, "NOT_FRIENDS", as(cara, { account_ids = { dave.id } }))

local call = actions.URGENT_CALL(as(alice, { account_id = bob.id })).call
assert(call.status == "ringing" and call.outgoing)
assert(actions.URGENT_RING(as(bob)).call.call_id == call.call_id,
    "the person being reached must see it ringing")
assert(actions.URGENT_RING(as(cara)).call == nil,
    "nobody else may see the call")
rejected(actions.URGENT_CALL, "CALL_BUSY", as(alice, { account_id = bob.id }))

rejected(actions.URGENT_ANSWER, "NOT_CALLEE",
    as(alice, { call_id = call.call_id, accept = true }))
assert(actions.URGENT_ANSWER(as(bob, { call_id = call.call_id, accept = true })).call.status
    == "active")

actions.URGENT_SEND(as(alice, { call_id = call.call_id, body = "Where are you?" }))
actions.URGENT_SEND(as(bob, { call_id = call.call_id, body = "Behind the bank" }))
local live = actions.URGENT_STATE(as(alice, { call_id = call.call_id }))
assert(#live.messages == 2, "both sides see the live transcript")
local delta = actions.URGENT_STATE(as(alice, {
    call_id = call.call_id, after_seq = 1 }))
assert(#delta.messages == 1, "polling only returns what is new")

-- Money works inside a call too.
local urgentSeq = actions.URGENT_REQUEST_MONEY(as(bob, {
    call_id = call.call_id, amount = 50 })).message.seq
rejected(actions.URGENT_PAY_REQUEST, "BAD_PIN", as(alice, {
    call_id = call.call_id, seq = urgentSeq, pin = "0000" }))
local before = actions.ACCOUNT_SUMMARY(as(alice)).account.balance
actions.URGENT_PAY_REQUEST(as(alice, {
    call_id = call.call_id, seq = urgentSeq, pin = "1111" }))
assert(actions.ACCOUNT_SUMMARY(as(alice)).account.balance == before - 55)

-- Saving needs both people.
assert(actions.URGENT_SAVE(as(alice, { call_id = call.call_id })).call.save_votes == 1)
local chatsBefore = #actions.CHAT_OPEN(as(alice, {
    conversation_id = chat.conversation_id })).messages
assert(actions.URGENT_SAVE(as(bob, { call_id = call.call_id })).call.save_votes == 2)
local ended = actions.URGENT_END(as(bob, { call_id = call.call_id })).call
assert(ended.status == "ended" and ended.saved,
    "two votes save the transcript")
local chatsAfter = #actions.CHAT_OPEN(as(alice, {
    conversation_id = chat.conversation_id })).messages
assert(chatsAfter > chatsBefore,
    "a saved call is written into the direct chat")

-- One vote alone saves nothing.
local second = actions.URGENT_CALL(as(alice, { account_id = bob.id })).call
actions.URGENT_ANSWER(as(bob, { call_id = second.call_id, accept = true }))
actions.URGENT_SEND(as(alice, { call_id = second.call_id, body = "Private" }))
actions.URGENT_SAVE(as(alice, { call_id = second.call_id }))
local lonely = actions.URGENT_END(as(alice, { call_id = second.call_id })).call
assert(not lonely.saved, "one vote must not save the conversation")
assert(#actions.CHAT_OPEN(as(alice, {
    conversation_id = chat.conversation_id })).messages == chatsAfter,
    "an unsaved call leaves no trace in the chat")

-- Declining.
local declined = actions.URGENT_CALL(as(alice, { account_id = bob.id })).call
assert(actions.URGENT_ANSWER(as(bob, {
    call_id = declined.call_id, accept = false })).call.status == "declined")
assert(alertCount(alice, "Urgent Contact declined") == 1)
rejected(actions.URGENT_SEND, "CALL_CLOSED",
    as(alice, { call_id = declined.call_id, body = "hello" }))

-- An unanswered call becomes a missed call for both sides.
local missed = actions.URGENT_CALL(as(alice, { account_id = bob.id })).call
currentEpoch = currentEpoch + 31 * 1000
assert(actions.URGENT_RING(as(bob)).call == nil, "a stale ring stops ringing")
assert(alertCount(bob, "Missed Urgent Contact") == 1)
assert(alertCount(alice, "No answer") == 1)
assert(bank.urgent_calls[missed.call_id].status == "missed")

-- Calls are never written to the database, so a Bank restart drops them.
assert(state.conversations ~= nil and state.urgent_calls == nil,
    "urgent calls must stay out of the saved state")

-- Proximity Pay ---------------------------------------------------------------

local kiosk = actions.KIOSK_REGISTER({ name = "Corner Shop" })
local kioskAuth = {
    terminal_id = kiosk.terminal_id, terminal_token = kiosk.terminal_token,
}
local function atKiosk(extra)
    local payload = {}
    for key, value in pairs(kioskAuth) do payload[key] = value end
    for key, value in pairs(extra or {}) do payload[key] = value end
    return payload
end

-- Without any GPS fix the kiosk cannot offer to anyone.
rejected(actions.PROXIMITY_OFFER, "NO_POSITION",
    atKiosk({ amount = 25, description = "Bread" }))

local shop = { x = 100, y = 64, z = 100 }
actions.PUMPE_POLL(as(alice, { position = { x = 103, y = 64, z = 100 } }))
actions.PUMPE_POLL(as(bob, { position = { x = 112, y = 64, z = 100 } }))
actions.PUMPE_POLL(as(dave, { position = { x = 400, y = 64, z = 400 } }))

local offered = actions.PROXIMITY_OFFER(atKiosk({
    amount = 25, description = "Bread", position = shop })).offer
assert(offered.target_name == "Alice Fox",
    "the nearest PUMPE is offered the bill, got " .. tostring(offered.target_name))
assert(offered.distance and offered.distance < 4)

-- The offer reaches that phone through the same OS poll everything else uses.
local waiting = actions.PUMPE_POLL(as(alice)).offer
assert(waiting and waiting.offer_id == offered.offer_id)
assert(actions.PUMPE_POLL(as(bob)).offer == nil,
    "only the targeted phone sees the offer")

-- Declining hands it to the next nearest rather than cancelling the sale.
local passed = actions.PROXIMITY_DECLINE(
    as(alice, { offer_id = offered.offer_id })).offer
assert(passed.target_name == "Bob Wolf",
    "a decline passes the bill along, got " .. tostring(passed.target_name))
assert(actions.PUMPE_POLL(as(alice)).offer == nil,
    "the phone that declined stops being asked")

-- Someone far outside the radius is never offered anything.
actions.PROXIMITY_DECLINE(as(bob, { offer_id = offered.offer_id }))
local exhausted = actions.PROXIMITY_STATUS(
    atKiosk({ offer_id = offered.offer_id })).offer
assert(exhausted.status == "nobody_nearby",
    "a distant PUMPE is out of range, got " .. tostring(exhausted.status))
assert(actions.PUMPE_POLL(as(dave)).offer == nil)

-- Accepting settles through the ordinary payment code, fee rules included.
actions.PUMPE_POLL(as(alice, { position = { x = 101, y = 64, z = 100 } }))
local second = actions.PROXIMITY_OFFER(atKiosk({
    amount = 30, description = "Milk", position = shop })).offer
local preview = actions.PAY_CODE_PREVIEW(as(alice, { code = second.code }))
assert(preview.amount == 30)
local before = actions.ACCOUNT_SUMMARY(as(alice)).account.balance
actions.PAY_CODE_CONFIRM(as(alice, { code = second.code, pin = "1111" }))
assert(actions.ACCOUNT_SUMMARY(as(alice)).account.balance == before - 30)
assert(actions.PROXIMITY_STATUS(
    atKiosk({ offer_id = second.offer_id })).offer.status == "paid")

-- A stale fix does not make someone a payment target forever.
currentEpoch = currentEpoch + 10 * 60 * 1000
rejected(actions.PROXIMITY_OFFER, "NO_POSITION",
    atKiosk({ amount = 5, description = "Stale", position = nil }))

print("host_social_server_test: OK")
