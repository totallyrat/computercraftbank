local ROOT = fs.getDir(shell.getRunningProgram())
package.path = package.path .. ";" .. fs.combine(ROOT, "?.lua")
































local PROGRAM_VERSION = "11.2.0"
local config = require("config")
local util = require("lib.util")
local net = require("lib.net")
local ui = require("lib.ui")

local TEST_MODE = rawget(_G, "PUMPE_TEST_MODE") == true
local PROTOCOL = config.pair_protocol or "PUMPE_PAIR_V1"

local running = true
local DATA_FILE = fs.combine(ROOT, "bank_vault_v1.dat")
local PAIR_FILE = fs.combine(ROOT, "bank_pair_v1.dat")
local activity = {}
local dash = { core = "NO CORE", core_color = colors.orange,
update_status = "IDLE", update_color = colors.lightGray }

local function logActivity(text, color)
table.insert(activity, 1, {
time = util.formatClock(), text = tostring(text),
color = color or colors.white,
})
while #activity > 40 do table.remove(activity) end
end

local function blankState()
return {
schema = 1,
created_at = util.nowMs(),
sequence = {
territory = 0, visa = 0, visa_application = 0, visit = 0,
border = 0, conversation = 0, scan = 0, event = 0,
ticket_type = 0, ticket = 0, web = 0, order = 0,
},

holders = {},


names = {},
conversations = {},
direct_conversations = {},
territories = {},
territory_names = {},
visas = {},
visa_codes = {},
visa_applications = {},
visits = {},
border_controllers = {},
events = {},
ticket_types = {},
tickets = {},


app_data = {},




domains = {},



orders = {},
pickup_points = {},
pickup_misses = {},

waiting = {},
migrated = {},
}
end

local state = util.loadTable(DATA_FILE, blankState())
for key, value in pairs(blankState()) do
if state[key] == nil then state[key] = value end
end

local function save() pcall(util.saveTable, DATA_FILE, state) end

local function reject(code, message)
error({ pumpe = true, code = code, message = message }, 0)
end

local function need(condition, code, message)
if not condition then reject(code, message) end
end

local prefixes = {
territory = { "TER", 6 },
visa = { "VISA", 8 },
visa_application = { "VAPP", 8 },
visit = { "VISIT", 8 },
border = { "BORDER", 6 },
conversation = { "CHAT", 8 },
scan = { "SCAN", 8 },
event = { "EVT", 6 },
ticket_type = { "TT", 6 },
ticket = { "TICK", 10 },




web = { "SITE", 8 },
order = { "ORD", 8 },
}

local function nextId(kind)
state.sequence[kind] = (state.sequence[kind] or 0) + 1
local format = prefixes[kind]
return format[1]
.. string.format("%0" .. format[2] .. "d", state.sequence[kind])
end




local core = { id = nil, online = nil }




local dirty = {}

function core.load()
local saved = util.loadTable(PAIR_FILE, {})
if saved.role == "vault" then core.id = saved.partner end
return core.id
end

function core.ask(action, payload, timeout)
if not core.id then return nil, "This Vault has no Core", "NO_CORE" end
local client = net.client({ protocol = PROTOCOL,
hostname = "BANKPAIR_" .. tostring(core.id) })
client.serverId = core.id
local data, err, code = client:request(action, payload, timeout or 6)
core.online = data ~= nil
return data, err, code
end







function core.move(fromId, toId, amount, kind, description, priced)
local data, err, code = core.ask("CORE_MOVE", {
move_id = util.token("VMOVE"),
from = fromId, to = toId, amount = amount,
kind = kind, description = description, priced = priced,
}, 8)
if not data then reject(code or "CORE_OFFLINE",
err or "The Bank did not answer") end
return data
end

function core.notify(accountId, title, body, kind, extra)
if accountId and accountId ~= "GOVERNMENT" then dirty[accountId] = true end
return core.ask("CORE_NOTIFY", { account_id = accountId, title = title,
body = body, kind = kind, extra = extra }, 4)
end

function core.account(accountId)
if not accountId then return nil end
local data = core.ask("CORE_ACCOUNT", { account_id = accountId }, 4)
if data and data.found then
state.names[data.account_id] = data.name
return data
end
return nil
end

function core.byName(name)
local data = core.ask("CORE_ACCOUNT", { name = name }, 4)
if data and data.found then
state.names[data.account_id] = data.name
return data
end
return nil
end



local function nameOf(accountId)
if not accountId then return "Someone" end
if accountId == "GOVERNMENT" then return "Government" end
local known = state.names[accountId]
if known then return known end
local account = core.account(accountId)
return account and account.name or "Unknown"
end





local function holder(accountId)
local record = state.holders[accountId]
if not record then
record = {
account_id = accountId,
friends = {},
friend_requests_in = {},
friend_requests_out = {},
conversation_ids = {},
documents = {},
presenting = nil,
}
state.holders[accountId] = record
end
record.friends = record.friends or {}
record.friend_requests_in = record.friend_requests_in or {}
record.friend_requests_out = record.friend_requests_out or {}
record.conversation_ids = record.conversation_ids or {}
return record
end



local function whoIsAsking(caller)
need(type(caller) == "table" and type(caller.account_id) == "string"
and #caller.account_id > 0, "NO_CALLER",
"The Bank did not say who is asking")
local record = holder(caller.account_id)
if type(caller.name) == "string" and #caller.name > 0 then
record.name = caller.name
state.names[caller.account_id] = caller.name
end
record.name = record.name or nameOf(caller.account_id)
record.position = caller.position
return record
end

local actions = {}



local function validateAmount(value, maximum)
local amount = util.roundMoney(value)
need(amount and amount > 0, "INVALID_AMOUNT", "Enter an amount above zero")
need(not maximum or amount <= maximum, "INVALID_AMOUNT",
"Amount is above the allowed maximum")
return amount
end



local function activeAccount(accountId, receiving)
local account = accountId and core.account(accountId)



need(account, "ACCOUNT_NOT_FOUND", "Account not found")
if receiving then
need(not account.bank_closed, "RECIPIENT_CLOSED",
account.name .. " has moved to another bank")
end
need(not account.banned, "ACCOUNT_BANNED", "This account is banned")
need(account.approved ~= false, "ACCOUNT_PENDING",
"This account is waiting for government approval")
need(not account.frozen, "ACCOUNT_FROZEN", "This account is frozen")
return account
end






local SOCIAL = { max_group = 8, max_message = 160 }



SOCIAL.max_conversation = 60
SOCIAL.ring_ms = 30 * 1000
SOCIAL.idle_ms = 10 * 60 * 1000

local function areFriends(account, otherId)
return account.friends[otherId] == true
end

local function requireFriend(account, accountId)
activeAccount(accountId)
need(areFriends(account, accountId), "NOT_FRIENDS",
"You can only do that with a friend")
return holder(accountId)
end

local function linkFriends(first, second)
first.friends[second.account_id] = true
second.friends[first.account_id] = true
first.friend_requests_in[second.account_id] = nil
first.friend_requests_out[second.account_id] = nil
second.friend_requests_in[first.account_id] = nil
second.friend_requests_out[first.account_id] = nil
end

local function friendCard(accountId)
return { account_id = accountId, name = nameOf(accountId) }
end

function actions.FRIEND_OVERVIEW(payload, caller)
local account = whoIsAsking(caller)
local friends, incoming, outgoing = {}, {}, {}
for friendId in pairs(account.friends) do
friends[#friends + 1] = friendCard(friendId)
end
for requesterId in pairs(account.friend_requests_in) do
incoming[#incoming + 1] = friendCard(requesterId)
end
for targetId in pairs(account.friend_requests_out) do
outgoing[#outgoing + 1] = friendCard(targetId)
end
local byName = function(a, b) return a.name < b.name end
table.sort(friends, byName)
table.sort(incoming, byName)
table.sort(outgoing, byName)
return { friends = friends, incoming = incoming, outgoing = outgoing }
end



function actions.FRIEND_SEARCH(payload, caller)
local account = whoIsAsking(caller)
local found, err, code = core.ask("CORE_SEARCH", {
query = payload.query, exclude = account.account_id,
}, 5)
if not found then reject(code or "CORE_OFFLINE",
err or "The Bank did not answer") end
local results = {}
for _, entry in ipairs(found.results or {}) do
state.names[entry.account_id] = entry.name
results[#results + 1] = {
account_id = entry.account_id,
name = entry.name,
friend = account.friends[entry.account_id] == true,
requested = account.friend_requests_out[entry.account_id] == true,
incoming = account.friend_requests_in[entry.account_id] ~= nil,
}
end
return { results = results }
end

function actions.FRIEND_REQUEST(payload, caller)
local account = whoIsAsking(caller)
local target = payload.account_id and core.account(payload.account_id)
or core.byName(payload.name or "")
need(target, "NOT_FOUND", "Account not found")
need(not target.banned, "ACCOUNT_BANNED", "That account is banned")
need(target.account_id ~= account.account_id,
"INVALID_FRIEND", "That is your own account")
local other = holder(target.account_id)
need(not account.friends[other.account_id], "ALREADY_FRIENDS",
target.name .. " is already a friend")
if account.friend_requests_in[other.account_id] then
linkFriends(account, other)
core.notify(other.account_id, "Friend added",
account.name .. " accepted your friend request", "social")
save()
return { status = "friends", name = target.name }
end
if not account.friend_requests_out[other.account_id] then
account.friend_requests_out[other.account_id] = true
other.friend_requests_in[account.account_id] = {
created_day = util.ingameDay(),
created_time = util.formatClock(),
}
core.notify(other.account_id, "Friend request",
account.name .. " wants to be your friend", "social")
save()
end
return { status = "requested", name = target.name }
end

function actions.FRIEND_RESPOND(payload, caller)
local account = whoIsAsking(caller)
local otherId = tostring(payload.account_id or "")
need(account.friend_requests_in[otherId],
"NOT_FOUND", "That friend request is no longer waiting")
local other = holder(otherId)
if payload.accept == true then
linkFriends(account, other)
core.notify(otherId, "Friend added",
account.name .. " accepted your friend request", "social")
save()
return { status = "friends", name = nameOf(otherId) }
end
account.friend_requests_in[otherId] = nil
other.friend_requests_out[account.account_id] = nil
dirty[otherId] = true
save()
return { status = "declined", name = nameOf(otherId) }
end

function actions.FRIEND_REMOVE(payload, caller)
local account = whoIsAsking(caller)
local otherId = tostring(payload.account_id or "")
local other = holder(otherId)
account.friends[otherId] = nil
other.friends[account.account_id] = nil
dirty[otherId] = true
save()
return { status = "removed", name = nameOf(otherId) }
end


function actions.VAULT_FRIEND(payload, caller)
local account = whoIsAsking(caller)
local otherId = tostring(payload.account_id or "")
need(areFriends(account, otherId), "NOT_FRIENDS",
"You can only do that with a friend")
return { account_id = otherId, name = nameOf(otherId), friend = true }
end

function actions.VAULT_FRIEND_LIST(payload, caller)
local account = whoIsAsking(caller)
local friends = {}
for friendId in pairs(account.friends) do
friends[#friends + 1] = friendCard(friendId)
end
table.sort(friends, function(a, b) return a.name < b.name end)
return { friends = friends }
end



local function directKey(firstId, secondId)
if firstId < secondId then return firstId .. "|" .. secondId end
return secondId .. "|" .. firstId
end

local function unreadFor(conversation, accountId)
local member = conversation.members[accountId]
if not member then return 0 end
local unread = 0
for _, item in ipairs(conversation.messages) do
if item.seq > (member.last_read_seq or 0)
and item.sender_id ~= accountId then
unread = unread + 1
end
end
return unread
end

local function conversationTitle(conversation, accountId)
if conversation.kind == "government" then return "Government" end
if conversation.kind == "group" then return conversation.title end
for _, memberId in ipairs(conversation.member_ids) do
if memberId ~= accountId then return nameOf(memberId) end
end
return "Empty chat"
end

local function conversationSummary(conversation, account)
local last = conversation.messages[#conversation.messages]
local names = {}
for _, memberId in ipairs(conversation.member_ids) do
names[#names + 1] = nameOf(memberId)
end
return {
conversation_id = conversation.conversation_id,
kind = conversation.kind,
title = conversationTitle(conversation, account.account_id),
member_names = names,
member_count = #conversation.member_ids,
unread = unreadFor(conversation, account.account_id),
last_at = conversation.last_at,
last_preview = last and (last.kind == "text" and last.body
or last.kind == "money_request"
and ("asked for " .. util.money(last.amount, config.currency))
or last.kind == "money_sent"
and ("sent " .. util.money(last.amount, config.currency))
or last.body) or "No messages yet",
last_sender = last and last.sender_name or nil,
}
end

local function appendMessage(conversation, senderId, kind, body, extra)
local item = {
seq = conversation.next_seq,
sender_id = senderId,
sender_name = senderId and nameOf(senderId) or "PUMPE",
kind = kind,
body = util.safeText(body, SOCIAL.max_message),
day = util.ingameDay(),
time = util.formatClock(),
at = util.nowMs(),
}
for key, value in pairs(extra or {}) do item[key] = value end
conversation.next_seq = conversation.next_seq + 1
conversation.messages[#conversation.messages + 1] = item
while #conversation.messages > SOCIAL.max_conversation do
table.remove(conversation.messages, 1)
end
conversation.last_at = item.at
if senderId and conversation.members[senderId] then
conversation.members[senderId].last_read_seq = item.seq
end




for _, memberId in ipairs(conversation.member_ids) do
if memberId ~= senderId then dirty[memberId] = true end
end
return item
end



local function notifyNewMessage(conversation, senderId, preview)
for _, memberId in ipairs(conversation.member_ids) do
if memberId ~= senderId and unreadFor(conversation, memberId) <= 1 then
core.notify(memberId, "Message from "
.. conversationTitle(conversation, memberId),
preview, "message")
end
end
end

local function newConversation(kind, memberIds, title, ownerId)
local conversationId = nextId("conversation")
local conversation = {
conversation_id = conversationId,
kind = kind,
title = title,
owner_id = ownerId,
member_ids = memberIds,
members = {},
messages = {},
next_seq = 1,
created_at = util.nowMs(),
last_at = util.nowMs(),
}
for _, memberId in ipairs(memberIds) do
conversation.members[memberId] = { last_read_seq = 0 }
holder(memberId).conversation_ids[conversationId] = true
end
state.conversations[conversationId] = conversation
if kind == "direct" then
state.direct_conversations[directKey(memberIds[1], memberIds[2])] =
conversationId
end
return conversation
end

local function directConversation(firstId, secondId)
local existing = state.direct_conversations[directKey(firstId, secondId)]
local conversation = existing and state.conversations[existing]
if conversation then return conversation end
return newConversation("direct", { firstId, secondId }, nil, firstId)
end

local function requireConversation(account, conversationId)
local conversation = state.conversations[conversationId]
need(conversation and conversation.members[account.account_id],
"NOT_FOUND", "That chat is not available")
return conversation
end

function actions.CHAT_LIST(payload, caller)
local account = whoIsAsking(caller)
local list = {}
for conversationId in pairs(account.conversation_ids) do
local conversation = state.conversations[conversationId]
if conversation then
list[#list + 1] = conversationSummary(conversation, account)
else
account.conversation_ids[conversationId] = nil
end
end
table.sort(list, function(a, b)
return (a.last_at or 0) > (b.last_at or 0)
end)
return { conversations = list }
end

function actions.CHAT_START(payload, caller)
local account = whoIsAsking(caller)
local requested = type(payload.account_ids) == "table"
and payload.account_ids or {}
need(#requested >= 1, "NO_MEMBERS", "Choose at least one friend")
need(#requested + 1 <= SOCIAL.max_group, "TOO_MANY_MEMBERS",
"A group holds at most " .. SOCIAL.max_group .. " people")
local memberIds, seen = { account.account_id }, {
[account.account_id] = true,
}
for _, accountId in ipairs(requested) do
if not seen[accountId] then
requireFriend(account, accountId)
seen[accountId] = true
memberIds[#memberIds + 1] = accountId
end
end
if #memberIds == 2 then
local conversation = directConversation(memberIds[1], memberIds[2])
save()
return { conversation = conversationSummary(conversation, account) }
end
local title = util.safeText(util.trim(payload.title or ""), 24)
if title == "" then title = account.name .. "'s group" end
local conversation = newConversation("group", memberIds, title,
account.account_id)
appendMessage(conversation, nil, "system",
account.name .. " created " .. title)
for _, memberId in ipairs(memberIds) do
if memberId ~= account.account_id then
core.notify(memberId, "Added to a group",
account.name .. " added you to " .. title, "message")
end
end
save()
return { conversation = conversationSummary(conversation, account) }
end

function actions.CHAT_OPEN(payload, caller)
local account = whoIsAsking(caller)
local conversation = requireConversation(account, payload.conversation_id)
local afterSeq = math.max(0, math.floor(tonumber(payload.after_seq) or 0))
local messages = {}
for _, item in ipairs(conversation.messages) do
if item.seq > afterSeq then messages[#messages + 1] = util.copy(item) end
end


local member = conversation.members[account.account_id]
if payload.mark_read ~= false
and member.last_read_seq ~= conversation.next_seq - 1 then
member.last_read_seq = conversation.next_seq - 1
dirty[account.account_id] = true
save()
end
return {
conversation = conversationSummary(conversation, account),
messages = messages,
next_seq = conversation.next_seq,
}
end

function actions.CHAT_SEND(payload, caller)
local account = whoIsAsking(caller)
local conversation = requireConversation(account, payload.conversation_id)
local body = util.safeText(util.trim(payload.body or ""),
SOCIAL.max_message)
need(#body > 0, "EMPTY_MESSAGE", "Type a message first")
local item = appendMessage(conversation, account.account_id, "text", body)
notifyNewMessage(conversation, account.account_id, body)
save()
return { message = util.copy(item) }
end

function actions.CHAT_REQUEST_MONEY(payload, caller)
local account = whoIsAsking(caller)
local conversation = requireConversation(account, payload.conversation_id)
need(conversation.kind ~= "government", "GOVERNMENT_THREAD",
"Only the government can move money in this chat")
local amount = validateAmount(payload.amount)
local item = appendMessage(conversation, account.account_id,
"money_request", util.safeText(payload.note or "", 60), {
amount = amount,
status = "pending",
})
notifyNewMessage(conversation, account.account_id,
account.name .. " asked for " .. util.money(amount, config.currency))
save()
return { message = util.copy(item) }
end

local function conversationCounterpart(conversation, account, accountId)
if accountId then
need(conversation.members[accountId], "NOT_FOUND",
"That person is not in this chat")
return accountId
end
need(conversation.kind == "direct", "CHOOSE_MEMBER",
"Choose who to pay in a group chat")
for _, memberId in ipairs(conversation.member_ids) do
if memberId ~= account.account_id then return memberId end
end
end



function actions.CHAT_SEND_MONEY(payload, caller)
local account = whoIsAsking(caller)
local conversation = requireConversation(account, payload.conversation_id)
need(conversation.kind ~= "government", "GOVERNMENT_THREAD",
"Only the government can move money in this chat")
local recipientId = conversationCounterpart(conversation, account,
payload.to_account_id)
local recipient = activeAccount(recipientId)
local amount = validateAmount(payload.amount)
local moved = core.move(account.account_id, recipientId, amount,
"message", "Sent in Messages", true)
appendMessage(conversation, account.account_id, "money_sent",
"sent " .. util.money(amount, config.currency)
.. " to " .. recipient.name,
{ amount = amount, to_account_id = recipientId })
save()
return { quote = { amount = moved.amount, total = moved.total,
fee = moved.fee, recipient = recipient.name,
balance = moved.from_balance } }
end

function actions.CHAT_PAY_REQUEST(payload, caller)
local account = whoIsAsking(caller)
local conversation = requireConversation(account, payload.conversation_id)
local requestSeq = math.floor(tonumber(payload.seq) or 0)
local target
for _, item in ipairs(conversation.messages) do
if item.seq == requestSeq and item.kind == "money_request" then
target = item
end
end
need(target, "NOT_FOUND", "That money request is no longer here")
need(target.status == "pending", "ALREADY_HANDLED",
"That request was already handled")
need(target.sender_id ~= account.account_id, "OWN_REQUEST",
"That is your own request")
local amount = validateAmount(target.amount)


if conversation.kind == "government" then
local paid, err, code = core.ask("CORE_GOV_PAY", {
move_id = util.token("VGOV"),
account_id = account.account_id, amount = amount,
description = util.safeText(target.body or "Government demand", 60),
}, 8)
if not paid then reject(code or "CORE_OFFLINE",
err or "The Bank did not answer") end
target.status = "paid"
target.paid_by = account.account_id
appendMessage(conversation, account.account_id, "money_sent",
"paid " .. util.money(amount, config.currency) .. " to Government",
{ amount = amount })
logActivity(account.name .. " paid a government demand", colors.lime)
save()
return { quote = { amount = amount, total = amount, fee = 0,
recipient = "Government" } }
end
local recipient = activeAccount(target.sender_id)
local moved = core.move(account.account_id, target.sender_id, amount,
"message", "Money request in Messages", true)
target.status = "paid"
target.paid_by = account.account_id
appendMessage(conversation, account.account_id, "money_sent",
"paid " .. util.money(amount, config.currency)
.. " to " .. recipient.name,
{ amount = amount, to_account_id = target.sender_id })
save()
return { quote = { amount = moved.amount, total = moved.total,
fee = moved.fee, recipient = recipient.name,
balance = moved.from_balance } }
end

function actions.CHAT_DECLINE_REQUEST(payload, caller)
local account = whoIsAsking(caller)
local conversation = requireConversation(account, payload.conversation_id)
local requestSeq = math.floor(tonumber(payload.seq) or 0)
for _, item in ipairs(conversation.messages) do
if item.seq == requestSeq and item.kind == "money_request"
and item.status == "pending"
and item.sender_id ~= account.account_id then
item.status = "declined"
appendMessage(conversation, account.account_id, "system",
account.name .. " declined the request")
save()
return { status = "declined" }
end
end
need(false, "NOT_FOUND", "That money request is no longer here")
end



function actions.VAULT_GOV_SAY(payload, caller)
local accountId = tostring(payload.account_id or "")
need(#accountId > 0, "NO_ACCOUNT", "No account was named")
local record = holder(accountId)
if type(payload.name) == "string" and #payload.name > 0 then
record.name = payload.name
state.names[accountId] = payload.name
end
local conversationId = record.government_conversation_id
local conversation = conversationId and state.conversations[conversationId]
if not conversation then
conversation = newConversation("government", { accountId },
"Government", nil)
record.government_conversation_id = conversation.conversation_id
end
local item = appendMessage(conversation, "GOVERNMENT",
tostring(payload.kind or "text"), payload.body,
type(payload.extra) == "table" and payload.extra or nil)
save()
return { conversation_id = conversation.conversation_id,
message = util.copy(item) }
end




function actions.VAULT_GOV_HISTORY(payload, caller)
need(caller and caller.kind == "government", "GOVERNMENT_AUTH",
"Government session expired")
local accountId = tostring(payload.account_id or "")
local record = state.holders[accountId]
local conversation = record and record.government_conversation_id
and state.conversations[record.government_conversation_id]
if not conversation then return { messages = {} } end
local afterSeq = math.max(0, math.floor(tonumber(payload.after_seq) or 0))
local messages = {}
for _, item in ipairs(conversation.messages) do
if item.seq > afterSeq then messages[#messages + 1] = util.copy(item) end
end
return {
conversation_id = conversation.conversation_id,
messages = messages,
next_seq = conversation.next_seq,
}
end



function actions.VAULT_GOV_THREADS(payload, caller)
need(caller and caller.kind == "government", "GOVERNMENT_AUTH",
"Government session expired")
local threads = {}
for accountId, record in pairs(state.holders) do
local conversation = record.government_conversation_id
and state.conversations[record.government_conversation_id]
if conversation then
local last = conversation.messages[#conversation.messages]
threads[#threads + 1] = {
account_id = accountId,
name = nameOf(accountId),
last_at = conversation.last_at,
last_body = last and util.safeText(last.body or "", 40) or "",
waiting = last ~= nil and last.sender_id ~= "GOVERNMENT",
}
end
end
table.sort(threads, function(a, b)
return (a.last_at or 0) > (b.last_at or 0)
end)
return { threads = threads }
end

local function socialBadges(account)
local messages, requests, friends = 0, 0, 0
for conversationId in pairs(account.conversation_ids) do
local conversation = state.conversations[conversationId]
if conversation then
messages = messages + unreadFor(conversation, account.account_id)
end
end
for _ in pairs(account.friend_requests_in) do requests = requests + 1 end
for _ in pairs(account.friends) do friends = friends + 1 end
return { messages = messages, friend_requests = requests, friends = friends }
end





local urgentCalls = {}

local function endCall(call, reason, endedById)
if call.status == "ended" then return call end
call.status = "ended"
call.ended_at = util.nowMs()
call.ended_reason = reason
call.ended_by = endedById
if call.save_votes[call.from_id] and call.save_votes[call.to_id] then
local conversation = directConversation(call.from_id, call.to_id)
appendMessage(conversation, nil, "system",
"Urgent Contact transcript saved")
for _, item in ipairs(call.messages) do
if item.kind ~= "system" then
appendMessage(conversation, item.sender_id, item.kind,
item.body, { amount = item.amount })
end
end
call.saved = true
save()
end
return call
end

local function cleanupUrgentCalls()
local now = util.nowMs()
for callId, call in pairs(urgentCalls) do
if call.status == "ringing"
and now - call.created_at > SOCIAL.ring_ms then
call.status = "missed"
call.ended_at = now
core.notify(call.to_id, "Missed Urgent Contact",
call.from_name .. " tried to reach you", "warning")
core.notify(call.from_id, "No answer",
call.to_name .. " did not answer", "warning")
elseif call.status == "active"
and now - (call.last_at or now) > SOCIAL.idle_ms then
endCall(call, "Timed out")
elseif call.status ~= "ringing" and call.status ~= "active"
and (call.ended_at or now) + 120 * 1000 < now then
urgentCalls[callId] = nil
end
end
end

local function busyCall(accountId)
for _, call in pairs(urgentCalls) do
if (call.status == "ringing" or call.status == "active")
and (call.from_id == accountId or call.to_id == accountId) then
return call
end
end
return nil
end

local function requireCall(account, callId)
local call = urgentCalls[callId]
need(call and (call.from_id == account.account_id
or call.to_id == account.account_id),
"NOT_FOUND", "That Urgent Contact has ended")
return call
end

local function publicCall(call, accountId)
local mine = call.from_id == accountId
return {
call_id = call.call_id,
status = call.status,
other_name = mine and call.to_name or call.from_name,
other_id = mine and call.to_id or call.from_id,
outgoing = mine,
saved = call.saved == true,
save_votes = (call.save_votes[call.from_id] and 1 or 0)
+ (call.save_votes[call.to_id] and 1 or 0),
i_saved = call.save_votes[accountId] == true,
ended_reason = call.ended_reason,
next_seq = call.next_seq,
app_name = call.app_name,
}
end

function actions.URGENT_RING(payload, caller)
local account = whoIsAsking(caller)
cleanupUrgentCalls()
for _, call in pairs(urgentCalls) do
if call.to_id == account.account_id and call.status == "ringing" then
return { call = publicCall(call, account.account_id) }
end
end
return {}
end




function actions.URGENT_CALL(payload, caller)
local account = whoIsAsking(caller)
cleanupUrgentCalls()
requireFriend(account, payload.account_id)
local other = holder(payload.account_id)
local appName = caller.app_name
need(not busyCall(account.account_id), "CALL_BUSY",
"You already have an Urgent Contact open")
need(not busyCall(other.account_id), "CALL_BUSY",
nameOf(other.account_id) .. " is already on an Urgent Contact")
local call = {
call_id = util.token("CALL"),
from_id = account.account_id,
from_name = account.name,
to_id = other.account_id,
to_name = nameOf(other.account_id),
status = "ringing",
created_at = util.nowMs(),
last_at = util.nowMs(),
messages = {},
next_seq = 1,
save_votes = {},
app_name = appName,
}
urgentCalls[call.call_id] = call
core.notify(other.account_id,
appName and (appName .. " call") or "Urgent Contact",
account.name .. " is reaching you right now"
.. (appName and (" on " .. appName) or ""), "urgent")
logActivity("Urgent Contact " .. account.name .. " > " .. call.to_name
.. (appName and (" via " .. appName) or ""), colors.orange)
return { call = publicCall(call, account.account_id) }
end

function actions.URGENT_ANSWER(payload, caller)
local account = whoIsAsking(caller)
local call = requireCall(account, payload.call_id)
need(call.to_id == account.account_id, "NOT_CALLEE",
"Only the person being reached can answer")
need(call.status == "ringing", "CALL_CLOSED", "That Urgent Contact ended")
if payload.accept == true then
call.status = "active"
call.answered_at = util.nowMs()
call.last_at = call.answered_at
return { call = publicCall(call, account.account_id) }
end
call.status = "declined"
call.ended_at = util.nowMs()
core.notify(call.from_id, "Urgent Contact declined",
call.to_name .. " could not talk", "warning")
return { call = publicCall(call, account.account_id) }
end

local function appendCallMessage(call, senderId, kind, body, extra)
local item = {
seq = call.next_seq,
sender_id = senderId,
sender_name = senderId and nameOf(senderId) or "PUMPE",
kind = kind,
body = util.safeText(body, SOCIAL.max_message),
time = util.formatClock(),
at = util.nowMs(),
}
for key, value in pairs(extra or {}) do item[key] = value end
call.next_seq = call.next_seq + 1
call.messages[#call.messages + 1] = item
while #call.messages > SOCIAL.max_conversation do
table.remove(call.messages, 1)
end
call.last_at = item.at
return item
end

function actions.URGENT_STATE(payload, caller)
local account = whoIsAsking(caller)
cleanupUrgentCalls()
local call = requireCall(account, payload.call_id)
local afterSeq = math.max(0, math.floor(tonumber(payload.after_seq) or 0))
local messages = {}
for _, item in ipairs(call.messages) do
if item.seq > afterSeq then messages[#messages + 1] = util.copy(item) end
end
return { call = publicCall(call, account.account_id), messages = messages }
end

function actions.URGENT_SEND(payload, caller)
local account = whoIsAsking(caller)
local call = requireCall(account, payload.call_id)
need(call.status == "active", "CALL_CLOSED", "That Urgent Contact ended")
local body = util.safeText(util.trim(payload.body or ""),
SOCIAL.max_message)
need(#body > 0, "EMPTY_MESSAGE", "Type something first")
local item = appendCallMessage(call, account.account_id, "text", body)
return { message = util.copy(item) }
end

function actions.URGENT_SAVE(payload, caller)
local account = whoIsAsking(caller)
local call = requireCall(account, payload.call_id)
need(call.status == "active", "CALL_CLOSED", "That Urgent Contact ended")
if call.save_votes[account.account_id] then
call.save_votes[account.account_id] = nil
appendCallMessage(call, nil, "system",
account.name .. " no longer wants to save this")
else
call.save_votes[account.account_id] = true
appendCallMessage(call, nil, "system",
account.name .. " wants to save this conversation")
end
return { call = publicCall(call, account.account_id) }
end

function actions.URGENT_REQUEST_MONEY(payload, caller)
local account = whoIsAsking(caller)
local call = requireCall(account, payload.call_id)
need(call.status == "active", "CALL_CLOSED", "That Urgent Contact ended")
local amount = validateAmount(payload.amount)
local item = appendCallMessage(call, account.account_id, "money_request",
"asked for " .. util.money(amount, config.currency),
{ amount = amount, status = "pending" })
return { message = util.copy(item) }
end

function actions.URGENT_SEND_MONEY(payload, caller)
local account = whoIsAsking(caller)
local call = requireCall(account, payload.call_id)
need(call.status == "active", "CALL_CLOSED", "That Urgent Contact ended")
local otherId = call.from_id == account.account_id
and call.to_id or call.from_id
local recipient = activeAccount(otherId)
local amount = validateAmount(payload.amount)
local moved = core.move(account.account_id, otherId, amount,
"urgent", "Sent in Urgent Contact", true)
appendCallMessage(call, account.account_id, "money_sent",
"sent " .. util.money(amount, config.currency), { amount = amount })
return { quote = { amount = moved.amount, total = moved.total,
fee = moved.fee, recipient = recipient.name,
balance = moved.from_balance } }
end

function actions.URGENT_PAY_REQUEST(payload, caller)
local account = whoIsAsking(caller)
local call = requireCall(account, payload.call_id)
need(call.status == "active", "CALL_CLOSED", "That Urgent Contact ended")
local requestSeq = math.floor(tonumber(payload.seq) or 0)
local target
for _, item in ipairs(call.messages) do
if item.seq == requestSeq and item.kind == "money_request" then
target = item
end
end
need(target and target.status == "pending", "NOT_FOUND",
"That money request is no longer waiting")
need(target.sender_id ~= account.account_id, "OWN_REQUEST",
"That is your own request")
local recipient = activeAccount(target.sender_id)
local amount = validateAmount(target.amount)
local moved = core.move(account.account_id, target.sender_id, amount,
"urgent", "Urgent Contact request", true)
target.status = "paid"
appendCallMessage(call, account.account_id, "money_sent",
"paid " .. util.money(amount, config.currency), { amount = amount })
return { quote = { amount = moved.amount, total = moved.total,
fee = moved.fee, recipient = recipient.name,
balance = moved.from_balance } }
end

function actions.URGENT_END(payload, caller)
local account = whoIsAsking(caller)
local call = requireCall(account, payload.call_id)
endCall(call, "Hung up", account.account_id)
return { call = publicCall(call, account.account_id) }
end











local scans = { requests = {}, kinds = { ticket = true, visa = true } }

function scans.public(request)
return {
request_id = request.request_id,
kind = request.kind,
status = request.status,
title = request.title,
detail = request.detail,
target_name = request.target_name,
distance = request.distance,
reference = request.reference,
result = request.result,
}
end

function scans.expired(request)
return request.status ~= "offered" or request.expires_at <= util.nowMs()
end


function scans.retarget(request)
local found = core.ask("CORE_NEAREST", {
origin = request.origin,
kind = request.kind,
exclude = request.declined,
}, 5)
local candidates = found and found.candidates or {}
for _, candidate in ipairs(candidates) do
state.names[candidate.account_id] = candidate.name
local ok, matched = pcall(request.matches, candidate)
if ok and matched then
request.target_account_id = candidate.account_id
request.target_name = candidate.name
request.reference = candidate.ref
request.distance = math.floor((candidate.distance or 0) * 10) / 10
request.status = "offered"
request.expires_at = util.nowMs()
+ (tonumber(config.proximity_offer_ttl_ms) or 60000)
core.notify(candidate.account_id, request.title, request.detail,
"info")
return request
end
end
request.status = "nobody_nearby"
request.target_account_id, request.target_name = nil, nil
return request
end



function scans.cleanup()
local now = util.nowMs()
for requestId, request in pairs(scans.requests) do
local settled = request.settled_at or request.created_at
if (request.status ~= "offered" and now - settled > 60 * 1000)
or request.expires_at + 5 * 60 * 1000 < now then
scans.requests[requestId] = nil
end
end
end

function scans.new(kind, origin, title, detail, matches, extra)
scans.cleanup()
local request = {
request_id = nextId("scan"),
kind = kind,
origin = origin,
title = util.safeText(title, 40),
detail = util.safeText(detail, 90),
matches = matches,
declined = {},
status = "offered",
created_at = util.nowMs(),
expires_at = util.nowMs()
+ (tonumber(config.proximity_offer_ttl_ms) or 60000),
}
for key, value in pairs(extra or {}) do request[key] = value end
scans.requests[request.request_id] = request
scans.retarget(request)
return request
end

function scans.poll(request)
scans.cleanup()
if request.status == "offered" and request.expires_at <= util.nowMs() then
request.declined[request.target_account_id or ""] = true
scans.retarget(request)
end
return request
end


function scans.forAccount(accountId)
for _, request in pairs(scans.requests) do
if request.target_account_id == accountId
and not scans.expired(request) then
return scans.public(request), request.expires_at
end
end
return nil
end


function scans.requireOwn(ownerId, requestId, field)
local request = scans.requests[requestId]
need(request and request[field] == ownerId, "NOT_FOUND",
"That check has ended")
return request
end

function scans.require(account, requestId)
local request = scans.requests[requestId]
need(request and not scans.expired(request), "NOT_FOUND",
"That request has ended")
need(request.target_account_id == account.account_id, "NOT_YOURS",
"That request is not yours")
return request
end




function actions.SCAN_ACCEPT(payload, caller)
local account = whoIsAsking(caller)
local request = scans.require(account, payload.request_id)
local ok, result = pcall(request.settle, request, account)
if not ok then
request.declined[account.account_id] = true
request.status = "rejected"
request.settled_at = util.nowMs()
request.result = type(result) == "table" and result.message
or "Could not be accepted"
save()
error(result, 0)
end
request.status = "accepted"
request.settled_at = util.nowMs()
request.settled_account_id = account.account_id
request.result = result
save()
return { scan = scans.public(request) }
end

function actions.SCAN_DECLINE(payload, caller)
local account = whoIsAsking(caller)
local request = scans.require(account, payload.request_id)
request.declined[account.account_id] = true
scans.retarget(request)
save()
return { scan = scans.public(request) }
end










function scans.position(payload)
local position = type(payload) == "table" and payload.position or nil
local x = position and tonumber(position.x)
local y = position and tonumber(position.y)
local z = position and tonumber(position.z)
need(x and y and z, "NO_POSITION",
"This computer has no GPS fix. Add GPS anchors nearby.")
return { x = x, y = y, z = z }
end

local function mapCount(map)
local count = 0
for _ in pairs(map or {}) do count = count + 1 end
return count
end

local function requireBorderController(payload)
local controller =
state.border_controllers[payload and payload.controller_id]
need(controller and controller.auth_token == payload.controller_token,
"BORDER_AUTH", "Border Controller is not registered")
need(controller.status == "active",
"BORDER_INACTIVE", "Border Controller is inactive")
controller.last_seen = util.nowMs()
return controller
end



local function sweepTravel()
local today = util.ingameDay()
local changed = false
for _, visit in pairs(state.visits) do
if visit.status == "visiting" and visit.due_day
and visit.due_day < today then
visit.status = "overdue"
local document = state.visas[visit.visa_id]
if document and document.kind == "visa" then
document.status = "overdue"
end
changed = true
end
end
scans.cleanup()
if changed then save() end
end

local function territoryOwner(account, territoryId)
local territory = state.territories[territoryId]
need(territory and territory.status == "active",
"TERRITORY_NOT_FOUND", "Territory not found")
need(territory.owner_account_id == account.account_id,
"NOT_TERRITORY_OWNER", "You do not control that territory")
return territory
end

local function newVisaCode()
local code
repeat
code = util.randomString(8, "ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
until not state.visa_codes[code]
return code
end

local function matchingDocument(accountId, territoryId, kind)
for _, document in pairs(state.visas) do
if document.account_id == accountId
and document.territory_id == territoryId
and (not kind or document.kind == kind)
and document.status ~= "revoked"
and document.status ~= "expired"
and document.status ~= "used" then
return document
end
end
return nil
end

local function issueDocument(account, territory, kind, options)
options = options or {}
local existing = matchingDocument(
account.account_id, territory.territory_id, kind)
if existing then return nil, existing end
local visaId = nextId("visa")
local document = {
visa_id = visaId,
code = newVisaCode(),
account_id = account.account_id,
territory_id = territory.territory_id,
kind = kind,
duration_days = kind == "visa"
and math.floor(tonumber(options.duration_days) or 1) or nil,
status = kind == "citizenship" and "active" or "issued",
issued_day = util.ingameDay(),
issued_by_account_id = options.issued_by_account_id,
application_id = options.application_id,
}
state.visas[visaId] = document
state.visa_codes[document.code] = visaId
if kind == "citizenship" then
territory.citizen_account_ids[account.account_id] = true
end
return document
end

local function openVisit(accountId, territoryId, visaId)
local newest
for _, visit in pairs(state.visits) do
if visit.account_id == accountId
and visit.territory_id == territoryId
and (not visaId or visit.visa_id == visaId)
and (visit.status == "visiting" or visit.status == "overdue")
and (not newest
or (visit.entered_at or 0) > (newest.entered_at or 0)) then
newest = visit
end
end
return newest
end

local function publicVisit(visit)
if not visit then return nil end
local remaining
if visit.due_day then
remaining = math.max(0, visit.due_day - util.ingameDay() + 1)
end
return {
visit_id = visit.visit_id,
territory_id = visit.territory_id,
territory_name = state.territories[visit.territory_id]
and state.territories[visit.territory_id].name or "Unknown",
authorization = visit.authorization,
entered_day = visit.entered_day,
due_day = visit.due_day,
remaining_days = remaining,
permanent = visit.due_day == nil,
status = visit.status,
}
end

local function publicDocument(document)
local territory = state.territories[document.territory_id]
local freeRoam = {}
if document.kind == "citizenship" then
for _, destination in pairs(state.territories) do
if destination.status == "active"
and destination.territory_id ~= document.territory_id
and destination.free_roam_territory_ids[
document.territory_id] then
freeRoam[#freeRoam + 1] = {
territory_id = destination.territory_id,
territory_name = destination.name,
}
end
end
table.sort(freeRoam, function(a, b)
return a.territory_name < b.territory_name
end)
end
local visits = {}
for _, visit in pairs(state.visits) do
if visit.account_id == document.account_id
and visit.visa_id == document.visa_id
and (visit.status == "visiting" or visit.status == "overdue") then
visits[#visits + 1] = publicVisit(visit)
end
end
table.sort(visits, function(a, b)
return (a.entered_day or 0) > (b.entered_day or 0)
end)
return {
visa_id = document.visa_id,
code = document.code,
kind = document.kind,
territory_id = document.territory_id,
territory_name = territory and territory.name or "Unknown",
duration_days = document.duration_days,
permanent = document.kind == "citizenship",
status = document.status,
issued_day = document.issued_day,
free_roam = freeRoam,
visits = visits,
}
end

local function publicApplication(application)
local territory = state.territories[application.territory_id]
local applicantName = nameOf(application.account_id)
return {
application_id = application.application_id,
territory_id = application.territory_id,
territory_name = territory and territory.name or "Unknown",
applicant_name = applicantName,
requested_days = application.requested_days,
status = application.status,
created_day = application.created_day,
reviewed_day = application.reviewed_day,
visa_id = application.visa_id,
}
end

local function accessForAccount(accountId, destination)
local temporary
for _, document in pairs(state.visas) do
if document.account_id == accountId
and document.status ~= "revoked"
and document.status ~= "expired"
and document.status ~= "used" then
if document.kind == "citizenship"
and document.territory_id == destination.territory_id then
return "citizenship", document
elseif document.kind == "citizenship"
and destination.free_roam_territory_ids[
document.territory_id] then
return "free_roam", document
elseif document.kind == "visa"
and document.territory_id == destination.territory_id then
temporary = document
end
end
end
if temporary then return "visa", temporary end
return nil
end

local function pendingApplication(accountId, territoryId)
for _, application in pairs(state.visa_applications) do
if application.account_id == accountId
and application.territory_id == territoryId
and application.status == "pending" then
return application
end
end
return nil
end



function actions.CUSTOMS_OVERVIEW(payload, caller)
local account = whoIsAsking(caller)
sweepTravel()
local territories = util.sortedValues(state.territories, function(territory)
return territory.owner_account_id == account.account_id
and territory.status == "active"
end, function(a, b) return a.name < b.name end)
local output = {}
for _, territory in ipairs(territories) do
local pending = 0
for _, application in pairs(state.visa_applications) do
if application.territory_id == territory.territory_id
and application.status == "pending" then
pending = pending + 1
end
end
output[#output + 1] = {
territory_id = territory.territory_id,
name = territory.name,
citizen_count = mapCount(territory.citizen_account_ids),
free_roam_count = mapCount(territory.free_roam_territory_ids),
pending_count = pending,
created_day = territory.created_day,
}
end
return {
territories = output,
maximum_territories =
math.max(1, math.floor(tonumber(config.max_territories_per_account)
or 3)),
}
end

function actions.CUSTOMS_DETAIL(payload, caller)
local account = whoIsAsking(caller)
local territory = territoryOwner(account, payload.territory_id)
sweepTravel()
local citizens = {}
for accountId in pairs(territory.citizen_account_ids) do
local document = matchingDocument(
accountId, territory.territory_id, "citizenship")
if document then
citizens[#citizens + 1] = {
account_id = accountId,
name = nameOf(accountId),
code = document.code,
issued_day = document.issued_day,
}
end
end
table.sort(citizens, function(a, b) return a.name < b.name end)

local applications = {}
for _, application in pairs(state.visa_applications) do
if application.territory_id == territory.territory_id then
applications[#applications + 1] =
publicApplication(application)
end
end
table.sort(applications, function(a, b)
if a.status ~= b.status then return a.status == "pending" end
return (a.created_day or 0) > (b.created_day or 0)
end)

local otherTerritories = {}
for _, other in pairs(state.territories) do
if other.status == "active"
and other.territory_id ~= territory.territory_id then
otherTerritories[#otherTerritories + 1] = {
territory_id = other.territory_id,
name = other.name,
free_roam =
territory.free_roam_territory_ids[other.territory_id]
== true,
}
end
end
table.sort(otherTerritories, function(a, b) return a.name < b.name end)
return {
territory = {
territory_id = territory.territory_id,
name = territory.name,
citizen_count = #citizens,
free_roam_count = mapCount(territory.free_roam_territory_ids),
},
citizens = citizens,
applications = applications,
other_territories = otherTerritories,
}
end

function actions.CUSTOMS_CREATE_TERRITORY(payload, caller)
local account = whoIsAsking(caller)
local name = util.safeText(util.trim(payload.name), 24)
need(#name >= 3 and name:match("^[%w _%-]+$"),
"INVALID_TERRITORY",
"Use 3-24 letters, numbers, spaces, _ or -")
need(not state.territory_names[util.normalName(name)],
"TERRITORY_TAKEN", "That territory name is already registered")
local owned = 0
for _, territory in pairs(state.territories) do
if territory.owner_account_id == account.account_id
and territory.status == "active" then
owned = owned + 1
end
end
local maximum = math.max(1,
math.floor(tonumber(config.max_territories_per_account) or 3))
need(owned < maximum, "TERRITORY_LIMIT",
"A Foxy Account can control up to " .. maximum .. " territories")

local territoryId = nextId("territory")
local territory = {
territory_id = territoryId,
name = name,
owner_account_id = account.account_id,
citizen_account_ids = {},
free_roam_territory_ids = {},
status = "active",
created_day = util.ingameDay(),
}
state.territories[territoryId] = territory
state.territory_names[util.normalName(name)] = territoryId
local citizenship = assert(issueDocument(
account, territory, "citizenship", {
issued_by_account_id = account.account_id,
}))
core.notify(account.account_id, "Territory created",
name .. " citizenship code: " .. citizenship.code, "travel")
save()
logActivity("Territory created: " .. name, colors.lightBlue)
return {
territory = {
territory_id = territoryId,
name = name,
},
citizenship = publicDocument(citizenship),
}
end

function actions.CUSTOMS_ISSUE_CITIZENSHIP(payload, caller)
local owner = whoIsAsking(caller)
local territory = territoryOwner(owner, payload.territory_id)
local found = core.byName(payload.username)
need(found, "NOT_FOUND", "Account not found")
local citizen = activeAccount(found.account_id)
local document, existing = issueDocument(
citizen, territory, "citizenship", {
issued_by_account_id = owner.account_id,
})
need(document, "ALREADY_CITIZEN",
existing and "That Foxy Account is already a citizen"
or "Citizenship could not be created")
core.notify(citizen.account_id, "Citizenship granted",
territory.name .. " permanent code: " .. document.code, "travel")
save()
logActivity("Citizenship: " .. citizen.name .. " / " .. territory.name,
colors.cyan)
return {
citizen_name = citizen.name,
document = publicDocument(document),
}
end

function actions.CUSTOMS_SET_FREE_ROAM(payload, caller)
local owner = whoIsAsking(caller)
local territory = territoryOwner(owner, payload.territory_id)
local source = state.territories[payload.source_territory_id]
need(source and source.status == "active",
"TERRITORY_NOT_FOUND", "Partner territory not found")
need(source.territory_id ~= territory.territory_id,
"INVALID_TERRITORY", "A territory already accepts its own citizens")
local enabled = payload.enabled == true
territory.free_roam_territory_ids[source.territory_id] =
enabled and true or nil
save()
logActivity((enabled and "Free Roam enabled: " or "Free Roam ended: ")
.. source.name .. " > " .. territory.name,
enabled and colors.lime or colors.orange)
return {
territory_id = territory.territory_id,
source_territory_id = source.territory_id,
enabled = enabled,
}
end

function actions.CUSTOMS_REVIEW_APPLICATION(payload, caller)
local owner = whoIsAsking(caller)
local application = state.visa_applications[payload.application_id]
need(application and application.status == "pending",
"APPLICATION_NOT_FOUND", "Pending visa application not found")
local territory = territoryOwner(owner, application.territory_id)
local applicant = activeAccount(application.account_id)

local document
if payload.approved == true then
local access = accessForAccount(applicant.account_id, territory)
need(not access, "ACCESS_EXISTS",
"This traveler already has entry rights")
document = assert(issueDocument(
applicant, territory, "visa", {
duration_days = application.requested_days,
issued_by_account_id = owner.account_id,
application_id = application.application_id,
}))
application.status = "approved"
application.visa_id = document.visa_id
core.notify(applicant.account_id, "Visa approved",
territory.name .. " for " .. application.requested_days
.. " day(s). Code: " .. document.code, "travel")
else
application.status = "denied"
core.notify(applicant.account_id, "Visa declined",
territory.name .. " declined your application", "travel")
end
application.reviewed_day = util.ingameDay()
application.reviewed_by_account_id = owner.account_id
save()
logActivity("Visa " .. application.status .. ": "
.. applicant.name .. " / " .. territory.name,
document and colors.lime or colors.orange)
return {
application = publicApplication(application),
document = document and publicDocument(document) or nil,
}
end

function actions.VISA_OVERVIEW(payload, caller)
local account = whoIsAsking(caller)
sweepTravel()
local documents = {}
for _, document in pairs(state.visas) do
if document.account_id == account.account_id then
documents[#documents + 1] = publicDocument(document)
end
end
table.sort(documents, function(a, b)
if a.kind ~= b.kind then return a.kind == "citizenship" end
return a.territory_name < b.territory_name
end)

local applications = {}
for _, application in pairs(state.visa_applications) do
if application.account_id == account.account_id then
applications[#applications + 1] =
publicApplication(application)
end
end
table.sort(applications, function(a, b)
return (a.created_day or 0) > (b.created_day or 0)
end)

local territories = {}
for _, territory in pairs(state.territories) do
if territory.status == "active" then
local accessKind = accessForAccount(account.account_id, territory)
local pending = pendingApplication(
account.account_id, territory.territory_id) ~= nil
territories[#territories + 1] = {
territory_id = territory.territory_id,
name = territory.name,
access = accessKind,
pending = pending,
can_apply = not accessKind and not pending,
}
end
end
table.sort(territories, function(a, b) return a.name < b.name end)
return {
documents = documents,
applications = applications,
territories = territories,
visa_min_days =
math.max(1, math.floor(tonumber(config.visa_min_days) or 1)),
visa_max_days =
math.max(1, math.floor(tonumber(config.visa_max_days) or 30)),
}
end

function actions.VISA_APPLY(payload, caller)
local account = whoIsAsking(caller)
local territory = state.territories[payload.territory_id]
need(territory and territory.status == "active",
"TERRITORY_NOT_FOUND", "Territory not found")
local minimum =
math.max(1, math.floor(tonumber(config.visa_min_days) or 1))
local maximum =
math.max(minimum, math.floor(tonumber(config.visa_max_days) or 30))
local requestedDays = math.floor(tonumber(payload.requested_days) or 0)
need(requestedDays >= minimum and requestedDays <= maximum,
"INVALID_STAY", "Choose a stay from " .. minimum
.. " to " .. maximum .. " days")
local access = accessForAccount(account.account_id, territory)
need(not access, "ACCESS_EXISTS",
"You already have entry rights for this territory")
need(not pendingApplication(account.account_id, territory.territory_id),
"APPLICATION_PENDING", "You already have an application pending")

local applicationId = nextId("visa_application")
local application = {
application_id = applicationId,
account_id = account.account_id,
territory_id = territory.territory_id,
requested_days = requestedDays,
status = "pending",
created_day = util.ingameDay(),
}
state.visa_applications[applicationId] = application
local ownerId = territory.owner_account_id
if owner then
core.notify(ownerId, "New visa request",
account.name .. " requests " .. requestedDays
.. " day(s) in " .. territory.name, "travel")
end
save()
logActivity("Visa applied: " .. account.name .. " / " .. territory.name,
colors.lightBlue)
return { application = publicApplication(application) }
end



function actions.BORDER_REGISTER(payload, caller)
local owner = whoIsAsking(caller)
local territory = territoryOwner(owner, payload.territory_id)
local controllerId = nextId("border")
local controller = {
controller_id = controllerId,
auth_token = util.token("BORDER"),
territory_id = territory.territory_id,
owner_account_id = owner.account_id,
label = util.safeText(
util.trim(payload.label or ("Border " .. controllerId)), 24),
status = "active",
created_day = util.ingameDay(),
last_seen = util.nowMs(),
}
state.border_controllers[controllerId] = controller
save()
logActivity("Border online: " .. territory.name, colors.purple)
return {
controller_id = controller.controller_id,
controller_token = controller.auth_token,
territory_id = territory.territory_id,
territory_name = territory.name,
label = controller.label,
}
end

function actions.BORDER_STATUS(payload, caller)
local controller = requireBorderController(payload)
local territory = state.territories[controller.territory_id]
need(territory and territory.status == "active",
"TERRITORY_NOT_FOUND", "Configured territory is unavailable")
return {
controller_id = controller.controller_id,
territory_id = territory.territory_id,
territory_name = territory.name,
label = controller.label,
day = util.ingameDay(),
time = util.formatClock(),
}
end

function actions.BORDER_OWNER_PIN(payload, caller)
local controller = requireBorderController(payload)
local verified = core.ask("CORE_VERIFY_PIN", {
account_id = controller.owner_account_id, pin = payload.pin,
}, 5)
need(verified and verified.ok,
"BAD_PIN", "Owner PIN is incorrect")
return { authorized = true }
end

function actions.BORDER_CHECK(payload, caller)
local controller = requireBorderController(payload)
sweepTravel()
local territory = state.territories[controller.territory_id]
need(territory and territory.status == "active",
"TERRITORY_NOT_FOUND", "Configured territory is unavailable")
local code = string.upper(util.trim(payload.code))
local direction = string.lower(util.trim(payload.direction))
need(direction == "enter" or direction == "exit",
"BORDER_DIRECTION", "Choose Enter Territory or Exit Territory")
need(code:match("^[A-Z2-9]+$") and #code == 8,
"VISA_CODE_INVALID", "Enter the eight-character travel code")
local documentId = state.visa_codes[code]
local document = documentId and state.visas[documentId]
need(document and document.status ~= "revoked",
"VISA_NOT_FOUND", "Travel code was not found")
need(document.status ~= "expired",
"VISA_EXPIRED", "This visa has expired")
local traveler = activeAccount(document.account_id)

local authorization
if document.kind == "citizenship"
and document.territory_id == territory.territory_id then
authorization = "citizenship"
elseif document.kind == "citizenship"
and territory.free_roam_territory_ids[document.territory_id] then
authorization = "free_roam"
elseif document.kind == "visa"
and document.territory_id == territory.territory_id then
authorization = "visa"
end
need(authorization, "VISA_WRONG_TERRITORY",
"This document does not allow entry here")

local visit = openVisit(
traveler.account_id, territory.territory_id, document.visa_id)
local now = util.nowMs()
local today = util.ingameDay()
local permanent = authorization ~= "visa"
local actionLabel

if direction == "enter" then
need(not visit, "ALREADY_VISITING",
"This traveler is already inside; choose Exit Territory")
if not permanent then
need(document.status == "issued",
"VISA_ALREADY_USED", "This temporary visa has already been used")
else
local nextEntry = tonumber(document.next_border_entry_at) or 0
local remaining = math.ceil(math.max(0, nextEntry - now) / 1000)
need(remaining <= 0, "VISA_COOLDOWN",
"This permanent travel code is cooling down for "
.. remaining .. " second(s)")
end
local visitId = nextId("visit")
local dueDay
if authorization == "visa" then
dueDay = today
+ math.max(1, document.duration_days or 1) - 1
document.status = "visiting"
document.entered_day = today
document.due_day = dueDay
else
local cooldown = math.max(1,
math.floor(tonumber(config.permanent_visa_cooldown_seconds)
or 30))
document.next_border_entry_at = now + cooldown * 1000
end
visit = {
visit_id = visitId,
account_id = traveler.account_id,
territory_id = territory.territory_id,
visa_id = document.visa_id,
authorization = authorization,
entered_day = today,
entered_at = now,
due_day = dueDay,
status = "visiting",
controller_id = controller.controller_id,
}
state.visits[visitId] = visit
core.notify(traveler.account_id, "Border entry recorded",
territory.name .. (dueDay and
(" - leave by day " .. dueDay) or " - permanent stay"),
"travel")
logActivity("Border entry: " .. traveler.name .. " > "
.. territory.name, colors.lime)
actionLabel = "entered"
else
need(visit, "NOT_VISITING",
"No active visit was found for this travel code")
visit.status = "exited"
visit.exited_day = today
visit.exited_at = now
visit.exit_controller_id = controller.controller_id
if permanent then
local cooldown = math.max(1,
math.floor(tonumber(config.permanent_visa_cooldown_seconds)
or 30))
document.next_border_entry_at = now + cooldown * 1000
document.last_exit_day = today
else
document.status = "used"
document.exited_day = today
end
core.notify(traveler.account_id, "Border exit recorded",
"You left " .. territory.name
.. (permanent and "" or "; temporary visa locked"), "travel")
logActivity("Border exit: " .. traveler.name .. " < "
.. territory.name, colors.orange)
actionLabel = "exited"
end
save()
local remaining = visit.due_day
and math.max(0, visit.due_day - today + 1) or nil
return {
approved = true,
direction = direction,
action = actionLabel,
traveler_name = traveler.name,
territory_name = territory.name,
authorization = authorization,
permanent = permanent,
stay_days = remaining,
due_day = visit.due_day,
entered_day = visit.entered_day,
exited_day = visit.exited_day,
visiting = direction == "enter",
}
end






function actions.VISA_SCAN(payload, caller)
local controller = requireBorderController(payload)
local territory = state.territories[controller.territory_id]
need(territory and territory.status == "active",
"TERRITORY_NOT_FOUND", "Configured territory is unavailable")
local origin = scans.position(payload)
local request = scans.new("visa", origin, "Border check",
"Stand at the " .. territory.name .. " border to cross",
function(candidate)
local document = state.visas[candidate.ref]
return document ~= nil
and document.account_id == candidate.account_id
and document.status ~= "revoked"
and document.status ~= "expired"
end,
{
controller_id = controller.controller_id,
controller_token = controller.auth_token,
territory_id = territory.territory_id,
settle = function(request, account)
local document = state.visas[request.reference]
need(document and document.account_id == account.account_id,
"NOT_YOURS", "That travel document is not yours")


local inside = openVisit(account.account_id,
request.territory_id, document.visa_id)
local outcome = actions.BORDER_CHECK({
controller_id = request.controller_id,
controller_token = request.controller_token,
code = document.code,
direction = inside and "exit" or "enter",
})
core.ask("CORE_CLEAR_PRESENTING",
{ account_id = account.account_id }, 4)
request.direction = outcome.direction
return account.name .. "  -  " .. outcome.action
end,
})
save()
return { scan = scans.public(request) }
end

function actions.VISA_SCAN_STATUS(payload, caller)
local controller = requireBorderController(payload)
local request = scans.requireOwn(controller.controller_id,
payload.request_id, "controller_id")
scans.poll(request)
return { scan = scans.public(request) }
end

function actions.VISA_SCAN_CANCEL(payload, caller)
local controller = requireBorderController(payload)
local request = scans.requireOwn(controller.controller_id,
payload.request_id, "controller_id")
request.status = "cancelled"
request.settled_at = util.nowMs()
return { scan = scans.public(request) }
end


function actions.LIST_EVENTS(payload, caller)
whoIsAsking(caller)
local today = util.ingameDay()
local events = util.sortedValues(state.events, function(event)
return event.status == "active" and tonumber(event.event_day) >= today
end, function(a, b)
if a.event_day ~= b.event_day then return a.event_day < b.event_day end
return (util.parseEventTime(a.event_time) or 0)
< (util.parseEventTime(b.event_time) or 0)
end)
local output = {}
for _, event in ipairs(events) do
local sold, total, minimum = 0, 0, nil
for _, typeId in ipairs(event.ticket_type_ids or {}) do
local ticketType = state.ticket_types[typeId]
if ticketType then
sold = sold + ticketType.sold_quantity
total = total + ticketType.total_quantity
minimum = not minimum and ticketType.price or math.min(minimum, ticketType.price)
end
end
output[#output + 1] = {
event_id = event.event_id,
title = event.title,
description = event.description,
location = event.location,
event_day = event.event_day,
event_time = event.event_time,
sold = sold,
total = total,
from_price = minimum,
}
end
return { events = output }
end

function actions.EVENT_DETAILS(payload, caller)
whoIsAsking(caller)
local event = state.events[payload.event_id]
need(event and event.status == "active", "NOT_FOUND", "Event not found")
local types = {}
for _, id in ipairs(event.ticket_type_ids or {}) do
local ticketType = state.ticket_types[id]
if ticketType then
local item = util.copy(ticketType)
item.available_quantity = ticketType.total_quantity - ticketType.sold_quantity
types[#types + 1] = item
end
end
return { event = util.copy(event), ticket_types = types }
end

function actions.BUY_TICKETS(payload, caller)
local account = whoIsAsking(caller)
local event = state.events[payload.event_id]
local ticketType = state.ticket_types[payload.ticket_type_id]
need(event and event.status == "active" and ticketType
and ticketType.event_id == event.event_id,
"NOT_FOUND", "Ticket type not found")
local quantity = math.floor(tonumber(payload.quantity) or 0)
need(quantity >= 1 and quantity <= config.max_ticket_quantity,
"BAD_QUANTITY", "Choose 1-" .. config.max_ticket_quantity .. " tickets")
need(ticketType.sold_quantity + quantity <= ticketType.total_quantity,
"SOLD_OUT", "Not enough tickets are left")
local total = util.roundMoney(ticketType.price * quantity)
local organizer = activeAccount(event.organizer_account_id)
local moved = core.move(account.account_id, organizer.account_id, total,
"ticket", event.title .. " - " .. ticketType.name)
ticketType.sold_quantity = ticketType.sold_quantity + quantity
if ticketType.sold_quantity >= ticketType.total_quantity then
ticketType.status = "sold_out"
end

local tickets = {}
for _ = 1, quantity do
local ticket = {
ticket_id = nextId("ticket"),
event_id = event.event_id,
ticket_type_id = ticketType.ticket_type_id,
account_id = account.account_id,
qr_code = util.randomString(8),
used = false,
status = "valid",
purchased_day = util.ingameDay(),
}
state.tickets[ticket.ticket_id] = ticket
tickets[#tickets + 1] = util.copy(ticket)
end
core.notify(account.account_id, "Tickets purchased",
quantity .. "x " .. ticketType.name .. " for " .. event.title, "event")
core.notify(organizer.account_id, "Ticket sale",
account.name .. " bought " .. quantity .. "x " .. ticketType.name,
"money")
save()
logActivity("Tickets sold: " .. event.title .. " x" .. quantity, colors.magenta)
return {
tickets = tickets,
total = total,
balance = moved.from_balance,
event = util.copy(event),
ticket_type = util.copy(ticketType),
}
end

function actions.MY_TICKETS(payload, caller)
local account = whoIsAsking(caller)
local output = {}
for _, ticket in pairs(state.tickets) do
if ticket.account_id == account.account_id then
local event = state.events[ticket.event_id]
local ticketType = state.ticket_types[ticket.ticket_type_id]
if event and ticketType then
local item = util.copy(ticket)
item.event_title = event.title
item.location = event.location
item.event_day = event.event_day
item.event_time = event.event_time
item.ticket_type_name = ticketType.name
output[#output + 1] = item
end
end
end
table.sort(output, function(a, b)
if a.event_day ~= b.event_day then return a.event_day < b.event_day end
return a.event_time < b.event_time
end)
return { tickets = output }
end



function actions.EVENT_DASHBOARD(payload, caller)
local owner = whoIsAsking(caller)
local active, sold, revenue = 0, 0, 0
for _, event in pairs(state.events) do
if event.organizer_account_id == owner.account_id then
if event.status == "active" then active = active + 1 end
for _, typeId in ipairs(event.ticket_type_ids or {}) do
local ticketType = state.ticket_types[typeId]
if ticketType then
sold = sold + ticketType.sold_quantity
revenue = revenue + ticketType.sold_quantity * ticketType.price
end
end
end
end
return {
active_events = active,
tickets_sold = sold,
revenue = util.roundMoney(revenue),
}
end

function actions.CREATE_EVENT(payload, caller)
local owner = whoIsAsking(caller)
local title = util.safeText(util.trim(payload.title), 40)
need(#title >= 2, "INVALID_TITLE", "Event title is too short")
local day = math.floor(tonumber(payload.event_day) or -1)
need(day >= util.ingameDay(), "INVALID_DAY", "Event day is in the past")
need(util.parseEventTime(payload.event_time), "INVALID_TIME", "Use time HH:MM")
local id = nextId("event")
local event = {
event_id = id,
title = title,
description = util.safeText(payload.description, 120),
location = util.safeText(payload.location, 60),
event_day = day,
event_time = payload.event_time,
organizer_account_id = owner.account_id,
ticket_type_ids = {},
status = "active",
created_day = util.ingameDay(),
}
state.events[id] = event
save()
logActivity("Event created: " .. title, colors.magenta)
return { event = util.copy(event) }
end

function actions.MY_EVENTS(payload, caller)
local owner = whoIsAsking(caller)
local output = util.sortedValues(state.events, function(event)
return event.organizer_account_id == owner.account_id
end, function(a, b) return a.event_day < b.event_day end)
for _, event in ipairs(output) do
event.ticket_types = {}
for _, id in ipairs(event.ticket_type_ids or {}) do
event.ticket_types[#event.ticket_types + 1] = util.copy(state.ticket_types[id])
end
end
return { events = util.copy(output) }
end

local function ownedEvent(payload, caller)
local owner = whoIsAsking(caller)
local event = state.events[payload.event_id]
need(event and event.organizer_account_id == owner.account_id,
"NOT_OWNER", "Event not found or not yours")
return owner, event
end

function actions.ADD_TICKET_TYPE(payload, caller)
local _, event = ownedEvent(payload, caller)
local name = util.safeText(util.trim(payload.name), 28)
need(#name >= 1, "INVALID_NAME", "Ticket type needs a name")
local price = validateAmount(payload.price, 1000000)
local quantity = math.floor(tonumber(payload.quantity) or 0)
need(quantity >= 1 and quantity <= 100000,
"INVALID_QUANTITY", "Quantity must be 1-100000")
local id = nextId("ticket_type")
local ticketType = {
ticket_type_id = id,
event_id = event.event_id,
name = name,
description = util.safeText(payload.description, 80),
price = price,
total_quantity = quantity,
sold_quantity = 0,
perks = payload.perks or {},
status = "available",
}
state.ticket_types[id] = ticketType
event.ticket_type_ids[#event.ticket_type_ids + 1] = id
save()
return { ticket_type = util.copy(ticketType) }
end

function actions.VERIFY_TICKET(payload, caller)
local owner = whoIsAsking(caller)
local code = string.upper(util.trim(payload.code))
local found
for _, ticket in pairs(state.tickets) do
if ticket.qr_code == code then found = ticket break end
end
need(found, "NOT_FOUND", "Ticket code not found")
local event = state.events[found.event_id]
need(event and event.organizer_account_id == owner.account_id,
"NOT_OWNER", "Ticket is for another organizer")
local ticketType = state.ticket_types[found.ticket_type_id]
return {
ticket = util.copy(found),
event = util.copy(event),
ticket_type = util.copy(ticketType),
holder = nameOf(found.account_id),
valid = found.status == "valid" and not found.used
and event.status == "active",
}
end

function actions.MARK_TICKET_USED(payload, caller)
local owner = whoIsAsking(caller)
local ticket = state.tickets[payload.ticket_id]
need(ticket, "NOT_FOUND", "Ticket not found")
local event = state.events[ticket.event_id]
need(event and event.organizer_account_id == owner.account_id,
"NOT_OWNER", "Ticket is for another organizer")
need(ticket.status == "valid" and not ticket.used,
"ALREADY_USED", "Ticket has already been used")
ticket.used = true
ticket.status = "used"
ticket.used_day = util.ingameDay()
ticket.used_time = util.formatClock()
save()
logActivity("Ticket admitted: " .. ticket.qr_code, colors.lime)
return { ticket = util.copy(ticket) }
end




local function requireOrganizerEvent(owner, eventId)
local event = state.events[eventId]
need(event and event.organizer_account_id == owner.account_id,
"NOT_OWNER", "That event is not yours")
need(event.status == "active", "EVENT_CLOSED", "That event is closed")
return event
end

function actions.TICKET_SCAN(payload, caller)
local owner = whoIsAsking(caller)
local event = requireOrganizerEvent(owner, payload.event_id)
local origin = scans.position(payload)
local request = scans.new("ticket", origin, "Ticket check",
"Scan your ticket for " .. event.title,
function(candidate)
local ticket = state.tickets[candidate.ref]
return ticket ~= nil and ticket.event_id == event.event_id
and ticket.status == "valid" and not ticket.used
end,
{
event_id = event.event_id,
organizer_id = owner.account_id,
settle = function(request, account)
local ticket = state.tickets[request.reference]
need(ticket and ticket.account_id == account.account_id,
"NOT_YOURS", "That ticket is not yours")
need(ticket.event_id == request.event_id, "WRONG_EVENT",
"That ticket is for another event")
need(ticket.status == "valid" and not ticket.used,
"ALREADY_USED", "That ticket has already been used")
ticket.used = true
ticket.status = "used"
ticket.used_day = util.ingameDay()
ticket.used_time = util.formatClock()
core.ask("CORE_CLEAR_PRESENTING",
{ account_id = account.account_id }, 4)
local ticketType = state.ticket_types[ticket.ticket_type_id]
logActivity("Ticket admitted: " .. ticket.qr_code, colors.lime)
return account.name .. "  -  "
.. (ticketType and ticketType.name or "Ticket")
end,
})
save()
return { scan = scans.public(request) }
end

function actions.TICKET_SCAN_STATUS(payload, caller)
local owner = whoIsAsking(caller)
local request = scans.requireOwn(owner.account_id, payload.request_id,
"organizer_id")
scans.poll(request)
return { scan = scans.public(request) }
end

function actions.TICKET_SCAN_CANCEL(payload, caller)
local owner = whoIsAsking(caller)
local request = scans.requireOwn(owner.account_id, payload.request_id,
"organizer_id")
request.status = "cancelled"
request.settled_at = util.nowMs()
return { scan = scans.public(request) }
end








local records = {}

local function requireAppId(caller)
local appId = caller and caller.app_id
need(type(appId) == "string" and appId:match("^[%w_%-]+$"),
"APP_REQUIRED", "That app has no id")
return appId
end

function records.collection(appId, name)
state.app_data = state.app_data or {}
state.app_data[appId] = state.app_data[appId] or {}
local key = util.safeText(util.trim(tostring(name or "")), 20)
need(key:match("^[%w_%-]+$"), "BAD_COLLECTION", "That collection has no name")
local existing = state.app_data[appId][key]
if existing then return existing end






local limit = tonumber(config.max_app_collections) or 40
local count = 0
for _ in pairs(state.app_data[appId]) do count = count + 1 end
if count >= limit then
for otherKey, collection in pairs(state.app_data[appId]) do
if #collection.items == 0 then
state.app_data[appId][otherKey] = nil
count = count - 1
end
end
need(count < limit, "TOO_MANY",
"That app is holding as much as it is allowed to")
end
state.app_data[appId][key] = { items = {}, sequence = 0 }
return state.app_data[appId][key]
end

function records.dataSize(value, depth)
depth = (depth or 0) + 1
if depth > 4 then return math.huge end
local kind = type(value)
if kind == "string" then return #value + 2 end
if kind ~= "table" then return 8 end
local total = 2
for key, item in pairs(value) do
total = total + records.dataSize(key, depth)
+ records.dataSize(item, depth)
end
return total
end

function records.audience(payload)
local raw = payload.audience
if type(raw) ~= "table" or #raw == 0 then return nil end
local out, seen = {}, {}
for _, id in ipairs(raw) do
id = util.safeText(util.trim(tostring(id or "")), 24)
if id ~= "" and not seen[id] then
seen[id] = true
out[#out + 1] = id
end
if #out >= 8 then break end
end
if #out == 0 then return nil end
return out
end

function records.visible(record, accountId)
if not record.audience then return true end
if record.author_id == accountId then return true end
for _, id in ipairs(record.audience) do
if id == accountId then return true end
end
return false
end

function records.prune(collection)
local today, removed = util.ingameDay(), 0
for index = #collection.items, 1, -1 do
local record = collection.items[index]
if record.expires_day and today >= record.expires_day then
table.remove(collection.items, index)
removed = removed + 1
end
end
return removed
end

function records.publicRecord(record, accountId)
local reactions, mine = 0, false
for reactorId in pairs(record.reactions or {}) do
reactions = reactions + 1
if reactorId == accountId then mine = true end
end
return {
id = record.id,
parent = record.parent,
data = util.copy(record.data),
author_id = record.author_id,
author_name = record.author_name,
created_day = record.created_day,
created_time = record.created_time,
created_at = record.created_at,
reactions = reactions,
reacted = mine,
mine = record.author_id == accountId,
private = record.audience ~= nil,
read = record.read_by ~= nil and record.read_by[accountId] == true,
seen = record.read_by ~= nil and next(record.read_by) ~= nil,
expires_day = record.expires_day,
}
end

function actions.APP_DATA_PUT(payload, caller)
local account = whoIsAsking(caller)
local appId = requireAppId(caller)
local collection = records.collection(appId, payload.collection)
records.prune(collection)
need(records.dataSize(payload.data or {})
<= (tonumber(config.max_app_record_bytes) or 400),
"RECORD_TOO_BIG", "That is more than an app record can hold")
local record
if payload.id then
for _, item in ipairs(collection.items) do
if item.id == payload.id
and records.visible(item, account.account_id) then
record = item
end
end
need(record, "NOT_FOUND", "That record is gone")
need(record.author_id == account.account_id, "NOT_YOURS",
"That record belongs to somebody else")
record.data = util.copy(payload.data or {})
else
collection.sequence = collection.sequence + 1
record = {
id = string.format("%s%06d", appId:sub(1, 3):upper(),
collection.sequence),
parent = payload.parent and util.safeText(payload.parent, 24) or nil,
data = util.copy(payload.data or {}),
author_id = account.account_id,
author_name = account.name,
created_day = util.ingameDay(),
created_time = util.formatClock(),
created_at = util.nowMs(),
reactions = {},
audience = records.audience(payload),
expire_after_days = payload.expire_after_days
and math.max(1, math.min(30,
math.floor(tonumber(payload.expire_after_days) or 1)))
or nil,
}
table.insert(collection.items, 1, record)
local limit = tonumber(config.max_app_records) or 200
while #collection.items > limit do table.remove(collection.items) end
end
save()
return { record = records.publicRecord(record, account.account_id) }
end

function actions.APP_DATA_LIST(payload, caller)
local account = whoIsAsking(caller)
local appId = requireAppId(caller)
local collection = records.collection(appId, payload.collection)
if records.prune(collection) > 0 then save() end
local parent = payload.parent
local limit = math.max(1, math.min(60,
math.floor(tonumber(payload.limit) or 40)))
local out, visible = {}, 0
for _, record in ipairs(collection.items) do
if records.visible(record, account.account_id) then
visible = visible + 1
if (not parent or record.parent == parent) and #out < limit then
out[#out + 1] = records.publicRecord(record,
account.account_id)
end
end
end
return { records = out, total = visible }
end

function actions.APP_DATA_DELETE(payload, caller)
local account = whoIsAsking(caller)
local appId = requireAppId(caller)
local collection = records.collection(appId, payload.collection)
for index = #collection.items, 1, -1 do
local record = collection.items[index]
if record.id == payload.id
and records.visible(record, account.account_id) then
need(record.author_id == account.account_id, "NOT_YOURS",
"That record belongs to somebody else")
table.remove(collection.items, index)
save()
return { removed = payload.id }
end
end
need(false, "NOT_FOUND", "That record is gone")
end

function actions.APP_DATA_READ(payload, caller)
local account = whoIsAsking(caller)
local appId = requireAppId(caller)
local collection = records.collection(appId, payload.collection)
records.prune(collection)
local marked = {}
local wanted = {}
if type(payload.ids) == "table" then
for _, id in ipairs(payload.ids) do wanted[tostring(id)] = true end
end
if payload.id then wanted[tostring(payload.id)] = true end
for _, record in ipairs(collection.items) do
if wanted[record.id]
and records.visible(record, account.account_id)


and record.author_id ~= account.account_id then
record.read_by = record.read_by or {}
if not record.read_by[account.account_id] then
record.read_by[account.account_id] = true
if record.expire_after_days and not record.expires_day then
record.expires_day = util.ingameDay()
+ record.expire_after_days
end
end
marked[#marked + 1] = record.id
end
end
save()
return { read = marked }
end

function actions.APP_DATA_REACT(payload, caller)
local account = whoIsAsking(caller)
local appId = requireAppId(caller)
local collection = records.collection(appId, payload.collection)
for _, record in ipairs(collection.items) do
if record.id == payload.id
and records.visible(record, account.account_id) then
record.reactions = record.reactions or {}
if payload.on == false then
record.reactions[account.account_id] = nil
else
local count = 0
for _ in pairs(record.reactions) do count = count + 1 end
need(count < (tonumber(config.max_app_reactions) or 60)
or record.reactions[account.account_id],
"TOO_MANY", "That record cannot hold more reactions")
record.reactions[account.account_id] = true
end
save()
return { record = records.publicRecord(record,
account.account_id) }
end
end
need(false, "NOT_FOUND", "That record is gone")
end






local function touchBadges(accountId)
if accountId and accountId ~= "GOVERNMENT" then dirty[accountId] = true end
end

local function pushBadges()
local sent = 0
for accountId in pairs(dirty) do
dirty[accountId] = nil
local record = state.holders[accountId]
if record then
local badges = socialBadges(record)
core.ask("CORE_BADGES", {
account_id = accountId,
messages = badges.messages,
friend_requests = badges.friend_requests,
friends = badges.friends,
}, 4)
end
sent = sent + 1
if sent >= 12 then return end
end
end







local lastWaiting = false

local function syncWaiting()
local entries, any = {}, false
for _, call in pairs(urgentCalls) do
if call.status == "ringing" then
entries[call.to_id] = entries[call.to_id] or {}
entries[call.to_id].call = publicCall(call, call.to_id)
entries[call.to_id].call_expires_at =
call.created_at + SOCIAL.ring_ms
any = true
end
end
for _, request in pairs(scans.requests) do
local target = request.target_account_id
if target and not scans.expired(request) then
entries[target] = entries[target] or {}
entries[target].scan = scans.public(request)
entries[target].scan_expires_at = request.expires_at
any = true
end
end
if not any and not lastWaiting then return end
lastWaiting = any
core.ask("CORE_WAITING", { entries = entries }, 4)
end












local WEB = {
max_per_account = 2,


launch_hours = 2,
edit_hours = 0.5,
token_ms = 5 * 60 * 1000,
}

local function domainKey(value)
return string.lower(util.trim(tostring(value or "")))
end



local function validDomain(value)
local key = domainKey(value)
if #key < 3 or #key > 20 then return nil end
if not key:match("^[%a%d%-]+$") then return nil end
if key:sub(1, 1) == "-" or key:sub(-1) == "-" then return nil end
return key
end

local function domainLive(record)
return util.ingameMoment() >= (record.live_at or 0)
end

local function publicDomain(record)
local hoursLeft = math.max(0, (record.live_at or 0) - util.ingameMoment())
return {
domain = record.domain,
site_id = record.site_id,
owner_name = record.owner_name,
owner_account_id = record.owner_account_id,
live = domainLive(record),
live_at = record.live_at,
hours_left = hoursLeft,
revision = record.revision or 0,
reserved_day = record.reserved_day,
updated_day = record.updated_day,
}
end

local function myDomain(account, wanted)
local key = validDomain(wanted)
need(key, "BAD_DOMAIN", "A domain is 3-20 letters, numbers or dashes")
local record = state.domains[key]
need(record, "NO_SUCH_DOMAIN", "Nobody has reserved " .. key)
need(record.owner_account_id == account.account_id, "NOT_YOURS",
key .. " belongs to somebody else")
return key, record
end


function actions.WEB_MINE(payload, caller)
local account = whoIsAsking(caller)
local sites = {}
for _, record in pairs(state.domains) do
if record.owner_account_id == account.account_id then
sites[#sites + 1] = publicDomain(record)
end
end
table.sort(sites, function(a, b) return a.domain < b.domain end)
return { sites = sites, limit = WEB.max_per_account,
launch_hours = WEB.launch_hours, edit_hours = WEB.edit_hours }
end

function actions.WEB_RESERVE(payload, caller)
local account = whoIsAsking(caller)
local key = validDomain(payload.domain)
need(key, "BAD_DOMAIN", "A domain is 3-20 letters, numbers or dashes")
need(not state.domains[key], "DOMAIN_TAKEN",
key .. " is already somebody else's")
local mine = 0
for _, record in pairs(state.domains) do
if record.owner_account_id == account.account_id then
mine = mine + 1
end
end
need(mine < WEB.max_per_account, "TOO_MANY_SITES",
"Two websites is the limit for one account")
state.domains[key] = {
domain = key,
site_id = nextId("web"),
owner_account_id = account.account_id,
owner_name = account.name,
reserved_day = util.ingameDay(),
updated_day = util.ingameDay(),
live_at = util.ingameMoment() + WEB.launch_hours,
revision = 0,
}
save()
logActivity("Domain " .. key .. " to " .. tostring(account.name),
colors.cyan)
return publicDomain(state.domains[key])
end




function actions.WEB_RENAME(payload, caller)
local account = whoIsAsking(caller)
local key, record = myDomain(account, payload.domain)
local wanted = validDomain(payload.new_domain)
need(wanted, "BAD_DOMAIN", "A domain is 3-20 letters, numbers or dashes")
need(wanted ~= key, "SAME_DOMAIN", "That is the name it already has")
need(not state.domains[wanted], "DOMAIN_TAKEN",
wanted .. " is already somebody else's")
state.domains[key] = nil
record.domain = wanted
record.updated_day = util.ingameDay()
record.live_at = math.max(record.live_at or 0,
util.ingameMoment() + WEB.edit_hours)
record.revision = (record.revision or 0) + 1
state.domains[wanted] = record
save()
logActivity("Domain " .. key .. " is now " .. wanted, colors.cyan)
return publicDomain(record)
end

function actions.WEB_RELEASE(payload, caller)
local account = whoIsAsking(caller)
local key = myDomain(account, payload.domain)
state.domains[key] = nil
save()
logActivity("Domain " .. key .. " released", colors.orange)
return { domain = key, released = true }
end



function actions.WEB_EDITED(payload, caller)
local account = whoIsAsking(caller)
local key, record = myDomain(account, payload.domain)
record.updated_day = util.ingameDay()
record.revision = (record.revision or 0) + 1
record.live_at = math.max(record.live_at or 0,
util.ingameMoment() + WEB.edit_hours)
save()
return publicDomain(record)
end




function actions.WEB_TOKEN(payload, caller)
local account = whoIsAsking(caller)
local key, record = myDomain(account, payload.domain)
record.token = util.token("WEB")
record.token_expires_at = util.nowMs() + WEB.token_ms
save()
return { domain = key, token = record.token,
expires_at = record.token_expires_at,
max_pages = tonumber(config.max_web_pages) or 3 }
end




function actions.WEB_LOOKUP(payload)
local key = validDomain(payload.domain)
need(key, "BAD_DOMAIN", "A domain is 3-20 letters, numbers or dashes")
local record = state.domains[key]
need(record, "NO_SUCH_DOMAIN", "Nobody has reserved " .. key)
local public = publicDomain(record)
public.owner_account_id = nil
return public
end




function actions.WEB_CLAIM(payload)
local key = validDomain(payload.domain)
need(key, "BAD_DOMAIN", "A domain is 3-20 letters, numbers or dashes")
local record = state.domains[key]
need(record, "NO_SUCH_DOMAIN", "Nobody has reserved " .. key)
local token = tostring(payload.token or "")
need(token ~= "" and record.token == token, "BAD_WEB_TOKEN",
"That publish ticket is not for " .. key)
need(util.nowMs() < (record.token_expires_at or 0), "WEB_TOKEN_EXPIRED",
"That publish ticket has run out")
record.token, record.token_expires_at = nil, nil
save()
return { domain = key, site_id = record.site_id,
owner_name = record.owner_name,
owner_account_id = record.owner_account_id,
max_pages = tonumber(config.max_web_pages) or 3 }
end















local SHOP = {
unpaid_ms = 10 * 60 * 1000,
keep_days = 14,
max_open_per_company = 300,
code_tries = 5,
code_lock_ms = 60 * 1000,



return_days = 5,
keep_after_returns = 7,
stages = { "Order received", "Packing", "Packed", "Out for delivery",
"At the pickup point" },




ask_ms = 2 * 60 * 1000,
preconfirm_ms = 30 * 60 * 1000,

max_offers = 12,
}




local function shopTerminal(caller)
need(type(caller) == "table"
and (caller.kind == "terminal" or caller.kind == "owner")
and type(caller.company_id) == "string", "NOT_A_TERMINAL",
"Only a company's own terminal can do that")
return caller
end


local function pickupPoint(caller)
need(type(caller) == "table" and caller.kind == "terminal"
and type(caller.company_id) == "string"
and type(caller.terminal_id) == "string", "NOT_A_TERMINAL",
"Only the pickup point itself can do that")
return caller
end



local function securityState(order)
local check = order.security
local now = util.nowMs()
if not check then return nil end
if check.status == "asked" and now < (check.expires_at or 0) then
return { status = "asked", expires_in_ms = check.expires_at - now }
elseif check.status == "confirmed" and now < (check.until_at or 0) then
return { status = "confirmed", expires_in_ms = check.until_at - now }
end
return nil
end




local function returnDeadline(order)
local arrived = order.finished_at
or ((order.done_day or util.ingameDay()) + 1) * 24
return arrived + (order.return_days or SHOP.return_days) * 24
end

local function orderStamp(order, label)
order.stage = label
order.history = order.history or {}
table.insert(order.history, {
label = label, day = util.ingameDay(), time = util.formatClock(),
})
while #order.history > 12 do table.remove(order.history, 1) end
end





local function publicOrder(order, forBuyer)
local now = util.ingameMoment()
local arrived = order.status == "done" or order.status == "collected"
return {
order_id = order.order_id,
company_id = order.company_id,
company_name = order.company_name,
color = order.color,
buyer_name = order.buyer_name,
lines = util.copy(order.lines),
subtotal = order.subtotal,
fee = order.fee,
total = order.total,
delivery = util.copy(order.delivery),
code = forBuyer and order.code or nil,



delivery_code = not forBuyer and order.delivery.kind == "pickup"
and order.status == "open" and not order.locker
and order.delivery_code or nil,
security = forBuyer and order.locker and securityState(order) or nil,
status = order.status,
stage = order.stage,
history = util.copy(order.history or {}),

note = order.note,
stocked = order.locker ~= nil,


confirmed = not order.confirm_at or now >= order.confirm_at,
confirms_in = order.confirm_at
and math.max(0, order.confirm_at - now) or 0,
cancellable = order.status == "open" and order.cancellable == true
and order.confirm_at ~= nil and now < order.confirm_at,
return_days = order.return_days or SHOP.return_days,
returns_left = arrived and math.max(0, returnDeadline(order) - now)
or nil,
returnable = arrived and not order.return_request
and now <= returnDeadline(order) or false,
return_request = util.copy(order.return_request),
paid_with = order.paid_with,
created_day = order.created_day,
created_time = order.created_time,
}
end



local function freshCode(pointId, avoid)
for _ = 1, 20 do
local code = string.format("%06d", math.random(0, 999999))
local clash = code == avoid
for _, order in pairs(state.orders) do
if (order.code == code or order.delivery_code == code)
and (order.status == "open" or order.status == "unpaid")
and (not pointId or (order.delivery.point_id == pointId)) then
clash = true
break
end
end
if not clash then return code end
end
return string.format("%06d", math.random(0, 999999))
end



for _, order in pairs(state.orders) do
if (order.status == "open" or order.status == "unpaid")
and type(order.delivery) == "table" and order.delivery.kind == "pickup"
and not order.locker and not order.delivery_code then
order.delivery_code = freshCode(order.delivery.point_id, order.code)
end
end

local function sweepOrders()
local now, today = util.nowMs(), util.ingameDay()
local changed = false
for orderId, order in pairs(state.orders) do
if order.status == "unpaid"
and now - (order.created_at or 0) > SHOP.unpaid_ms then
state.orders[orderId] = nil
changed = true
elseif order.status == "done" or order.status == "collected"
or order.status == "cancelled" then
local keep = SHOP.keep_days
if order.status ~= "cancelled" then
keep = math.max(keep, (order.return_days or SHOP.return_days)
+ SHOP.keep_after_returns)
end
local waiting = order.return_request
and order.return_request.status == "requested"
if not waiting and today - (order.done_day or today) > keep then
state.orders[orderId] = nil
changed = true
end
end
end
if changed then save() end
return changed
end


function actions.VAULT_SHOP_OPEN(payload, caller)
local buyer = whoIsAsking(caller)
local companyId = util.safeText(tostring(payload.company_id or ""), 24)
need(#companyId > 0, "NO_STORE", "Which store is this for?")
local open = 0
for _, order in pairs(state.orders) do
if order.company_id == companyId and order.status == "open" then
open = open + 1
end
end
need(open < SHOP.max_open_per_company, "STORE_BUSY",
"That store has too many orders waiting. Try again later")

local raw = type(payload.delivery) == "table" and payload.delivery or {}
local delivery
if raw.kind == "pickup" then
local point = state.pickup_points[tostring(raw.point_id or "")]
need(point and point.company_id == companyId, "NO_SUCH_POINT",
"That pickup point is not one of this store's")
delivery = { kind = "pickup", point_id = point.point_id,
point_name = point.name, x = point.x, y = point.y, z = point.z }
else
local x, y, z = tonumber(raw.x), tonumber(raw.y), tonumber(raw.z)
need(x and y and z, "NO_ADDRESS", "Where should it be delivered?")
delivery = { kind = "home", x = math.floor(x), y = math.floor(y),
z = math.floor(z),
label = util.safeText(util.trim(tostring(raw.label or "Home")),
18) }
end

local lines = {}
for _, line in ipairs(type(payload.lines) == "table" and payload.lines
or {}) do
lines[#lines + 1] = {
item_id = util.safeText(tostring(line.item_id or ""), 16),
name = util.safeText(tostring(line.name or ""), 20),
price = tonumber(line.price) or 0,
quantity = math.max(1, math.floor(tonumber(line.quantity) or 1)),
}
end
need(#lines > 0, "EMPTY_CART", "There is nothing in the basket")

local orderId = nextId("order")
local code = freshCode(delivery.point_id)
state.orders[orderId] = {
order_id = orderId,
company_id = companyId,
company_name = util.safeText(tostring(payload.company_name or ""), 28),
color = util.safeText(tostring(payload.color or "orange"), 12),
buyer_account_id = buyer.account_id,
buyer_name = buyer.name,
lines = lines,
subtotal = tonumber(payload.subtotal) or 0,
fee = tonumber(payload.fee) or 0,
total = tonumber(payload.total) or 0,
delivery = delivery,
code = code,
delivery_code = delivery.kind == "pickup"
and freshCode(delivery.point_id, code) or nil,
status = "unpaid",



owner_account_id = payload.owner_account_id
and tostring(payload.owner_account_id) or nil,
payer_bank_account_id = payload.payer_bank_account_id
and tostring(payload.payer_bank_account_id) or nil,
confirm_at = tonumber(payload.confirm_at),
cancellable = payload.cancellable == true,
return_days = math.max(SHOP.return_days,
math.floor(tonumber(payload.return_days) or SHOP.return_days)),
history = {},
created_day = util.ingameDay(),
created_time = util.formatClock(),
created_at = util.nowMs(),
}
save()
return { order_id = orderId, code = state.orders[orderId].code,
delivery = util.copy(delivery) }
end


function actions.VAULT_SHOP_PAID(payload)
local order = state.orders[tostring(payload.order_id or "")]
need(order, "NO_SUCH_ORDER", "That order is gone")
if order.status ~= "unpaid" then return publicOrder(order, true) end
order.status = "open"
order.paid_with = util.safeText(tostring(payload.paid_with or "Foxy"), 20)
orderStamp(order, SHOP.stages[1])
save()
core.notify(order.buyer_account_id, "Order placed",
order.company_name .. " has your order. Follow it in Shop.", "money",
{ order_id = order.order_id })
return publicOrder(order, true)
end


function actions.VAULT_SHOP_CANCEL(payload)
local order = state.orders[tostring(payload.order_id or "")]
if order and order.status == "unpaid" then
state.orders[order.order_id] = nil
save()
end
return { cancelled = true }
end

function actions.SHOP_ORDERS(payload, caller)
local buyer = whoIsAsking(caller)
local mine = {}
for _, order in pairs(state.orders) do
if order.buyer_account_id == buyer.account_id
and order.status ~= "unpaid" then
mine[#mine + 1] = publicOrder(order, true)
end
end
table.sort(mine, function(a, b) return a.order_id > b.order_id end)
return { orders = mine }
end

function actions.SHOP_ORDER(payload, caller)
local buyer = whoIsAsking(caller)
local order = state.orders[tostring(payload.order_id or "")]
need(order and order.buyer_account_id == buyer.account_id
and order.status ~= "unpaid", "NO_SUCH_ORDER", "That order is gone")
return { order = publicOrder(order, true) }
end


function actions.VAULT_SHOP_POINTS(payload)
local companyId = tostring(payload.company_id or "")
local points = {}
for _, point in pairs(state.pickup_points) do
if point.company_id == companyId then
points[#points + 1] = { point_id = point.point_id,
name = point.name, x = point.x, y = point.y, z = point.z }
end
end
table.sort(points, function(a, b) return a.name < b.name end)
return { points = points, stages = util.copy(SHOP.stages) }
end


function actions.DELIVERY_ORDERS(payload, caller)
local terminal = shopTerminal(caller)
sweepOrders()
local list = {}
local wanted = payload.status
for _, order in pairs(state.orders) do
if order.company_id == terminal.company_id
and order.status ~= "unpaid"
and (not wanted or order.status == wanted) then
list[#list + 1] = publicOrder(order, false)
end
end
local function rank(order)
if order.status == "open" then return 1 end
if order.return_request and order.return_request.status == "requested"
then return 2 end
return 3
end
table.sort(list, function(a, b)
if rank(a) ~= rank(b) then return rank(a) < rank(b) end
return a.order_id < b.order_id
end)
return { orders = list, stages = util.copy(SHOP.stages) }
end

local function companyOrder(terminal, orderId)
local order = state.orders[tostring(orderId or "")]
need(order and order.company_id == terminal.company_id
and order.status ~= "unpaid", "NO_SUCH_ORDER",
"That order is not this company's")
return order
end



function actions.DELIVERY_STAGE(payload, caller)
local terminal = shopTerminal(caller)
local order = companyOrder(terminal, payload.order_id)
need(order.status == "open", "ORDER_CLOSED", "That order is finished")
local label = SHOP.stages[tonumber(payload.stage) or 0]
or util.safeText(util.trim(tostring(payload.label or "")), 28)
need(label and #label > 0, "NO_STAGE", "Say what is happening")
orderStamp(order, label)
save()
core.notify(order.buyer_account_id, order.company_name,
label .. " -- order " .. order.order_id, "info",
{ order_id = order.order_id })
return { order = publicOrder(order, false) }
end

function actions.DELIVERY_DONE(payload, caller)
local terminal = shopTerminal(caller)
local order = companyOrder(terminal, payload.order_id)
need(order.status == "open", "ORDER_CLOSED", "That order is finished")
order.status = "done"
order.done_day = util.ingameDay()
order.finished_at = util.ingameMoment()
local where = order.delivery.kind == "pickup"
and ("Handed over at " .. tostring(order.delivery.point_name))
or ("Delivered to " .. tostring(order.delivery.label) .. " at "
.. order.delivery.x .. " " .. order.delivery.y .. " "
.. order.delivery.z)
orderStamp(order, "Delivered")
local note = util.safeText(util.trim(tostring(payload.note or "")), 60)
if note ~= "" then order.note = note end
save()
core.notify(order.buyer_account_id, "Delivered",
where .. (note ~= "" and (". " .. note) or ""), "success",
{ order_id = order.order_id })
return { order = publicOrder(order, false) }
end



function actions.DELIVERY_OUT(payload, caller)
local company = shopTerminal(caller)
local list = {}
for _, order in pairs(state.orders) do
if order.company_id == company.company_id and order.status == "open"
and order.stage == SHOP.stages[4] and not order.locker then
list[#list + 1] = publicOrder(order, false)
end
end
table.sort(list, function(a, b) return a.order_id < b.order_id end)
return { orders = list }
end












local function refundable(order, why, caller)
need(order and order.status ~= "unpaid", "NO_SUCH_ORDER",
"That order is gone")
if why == "cancel" then
local buyer = whoIsAsking(caller)
need(order.buyer_account_id == buyer.account_id, "NO_SUCH_ORDER",
"That order is gone")
need(order.status == "open", "ORDER_CLOSED",
"That order is finished. Return it instead")
need(order.cancellable == true, "NOT_CANCELLABLE",
tostring(order.company_name) .. " does not take cancellations")
need(order.confirm_at and util.ingameMoment() < order.confirm_at,
"CONFIRMED", "That order is confirmed. Return it once it arrives")
else
local terminal = shopTerminal(caller)
need(order.company_id == terminal.company_id, "NO_SUCH_ORDER",
"That order is not this company's")
if why == "store" then
need(order.status == "open", "ORDER_CLOSED",
"That order is finished")
elseif why == "return" then
need(order.return_request
and order.return_request.status == "requested", "NO_RETURN",
"Nobody has asked to return that order")
else
reject("BAD_REFUND", "Refund why?")
end
end
return {
order_id = order.order_id,
total = order.total,
buyer_account_id = order.buyer_account_id,
buyer_name = order.buyer_name,
payer_bank_account_id = order.payer_bank_account_id,
owner_account_id = order.owner_account_id,
company_id = order.company_id,
company_name = order.company_name,
}
end

function actions.VAULT_SHOP_REFUND_CHECK(payload, caller)
return refundable(state.orders[tostring(payload.order_id or "")],
payload.why, caller)
end

function actions.VAULT_SHOP_REFUNDED(payload, caller)
local order = state.orders[tostring(payload.order_id or "")]
local info = refundable(order, payload.why, caller)
if payload.why == "return" then
order.return_request.status = "refunded"
orderStamp(order, "Return refunded")
else
order.status = "cancelled"
order.done_day = util.ingameDay()


order.locker = nil
orderStamp(order, payload.why == "store" and "Cancelled by the store"
or "Cancelled")
local note = util.safeText(util.trim(tostring(payload.note or "")), 60)
if note ~= "" then order.note = note end
end
save()
info.order = publicOrder(order, false)
return info
end



function actions.SHOP_RETURN(payload, caller)
local buyer = whoIsAsking(caller)
local order = state.orders[tostring(payload.order_id or "")]
need(order and order.buyer_account_id == buyer.account_id
and order.status ~= "unpaid", "NO_SUCH_ORDER", "That order is gone")
need(order.status == "done" or order.status == "collected", "NOT_ARRIVED",
"Returns open once the order has arrived")
need(not order.return_request, "ALREADY_ASKED",
"You have already asked to return this order")
need(util.ingameMoment() <= returnDeadline(order), "RETURNS_CLOSED",
"The " .. (order.return_days or SHOP.return_days)
.. " day return window has closed")
local reason = util.safeText(util.trim(tostring(payload.reason or "")), 60)
need(#reason >= 2, "NO_REASON", "Say why you are sending it back")
order.return_request = { status = "requested", reason = reason,
day = util.ingameDay(), time = util.formatClock() }
orderStamp(order, "Return requested")
save()
if order.owner_account_id then
core.notify(order.owner_account_id, "Return requested",
tostring(order.company_name) .. ", order " .. order.order_id
.. ": " .. reason, "info", { order_id = order.order_id })
end
return { order = publicOrder(order, true) }
end

function actions.DELIVERY_RETURN_DECLINE(payload, caller)
local order = state.orders[tostring(payload.order_id or "")]
refundable(order, "return", caller)
local reason = util.safeText(util.trim(tostring(payload.reason or "")), 60)
need(#reason >= 2, "NO_REASON", "Tell the buyer why")
order.return_request.status = "declined"
order.return_request.answer = reason
orderStamp(order, "Return declined")
save()
core.notify(order.buyer_account_id, "Return declined",
tostring(order.company_name) .. ": " .. reason, "warning",
{ order_id = order.order_id })
return { order = publicOrder(order, false) }
end



function actions.PICKUP_REGISTER(payload, caller)
local terminal = pickupPoint(caller)
local name = util.safeText(util.trim(tostring(payload.name or "")), 20)
need(#name >= 2, "BAD_NAME", "Give the pickup point a name")
local x, y, z = tonumber(payload.x), tonumber(payload.y),
tonumber(payload.z)
local before = state.pickup_points[terminal.terminal_id]
state.pickup_points[terminal.terminal_id] = {
point_id = terminal.terminal_id,
company_id = terminal.company_id,
name = name,
x = x and math.floor(x) or nil,
y = y and math.floor(y) or nil,
z = z and math.floor(z) or nil,
registered_day = util.ingameDay(),

store = before and before.company_id == terminal.company_id
and before.store or nil,
}
save()
return { point = util.copy(state.pickup_points[terminal.terminal_id]) }
end

function actions.PICKUP_REMOVE(payload, caller)
local terminal = pickupPoint(caller)
state.pickup_points[terminal.terminal_id] = nil
save()
return { removed = true }
end


function actions.PICKUP_ORDERS(payload, caller)
local terminal = pickupPoint(caller)
local list = {}
for _, order in pairs(state.orders) do
if order.status == "open" and order.delivery.kind == "pickup"
and order.delivery.point_id == terminal.terminal_id then
local shown = publicOrder(order, false)
shown.locker = order.locker
list[#list + 1] = shown
end
end
table.sort(list, function(a, b) return a.order_id < b.order_id end)
return { orders = list }
end




function actions.PICKUP_STOCK(payload, caller)
local terminal = pickupPoint(caller)
local order = companyOrder(terminal, payload.order_id)
need(order.status == "open" and order.delivery.kind == "pickup"
and order.delivery.point_id == terminal.terminal_id, "WRONG_POINT",
"That order is not coming to this pickup point")
local code = tostring(payload.code or ""):gsub("%D", "")
need(code ~= "", "UPDATE_TERMINAL", "Parcels go in with their delivery"
.. " code now. Leave Pickup mode so this point can update")
need(order.delivery_code and code == order.delivery_code, "BAD_CODE",
"That is not this parcel's delivery code")
need(not order.locker, "ALREADY_HERE", "That parcel is already here")
local locker = util.safeText(tostring(payload.locker or ""), 40)
need(#locker > 0, "NO_LOCKER", "Which locker is it in?")
for _, other in pairs(state.orders) do
need(not (other.status == "open" and other.locker == locker
and other.delivery.point_id == terminal.terminal_id
and other.order_id ~= order.order_id), "LOCKER_IN_USE",
"Somebody else's parcel is already in that locker")
end
order.locker = locker
orderStamp(order, "Ready for pickup")
save()
core.notify(order.buyer_account_id, "Ready to collect",
"At " .. tostring(order.delivery.point_name) .. ". Your code is "
.. order.code .. ".", "success", { order_id = order.order_id })
return { order = publicOrder(order, false) }
end




local function pointMisses(pointId)
local misses = state.pickup_misses[pointId] or { count = 0, until_at = 0 }
state.pickup_misses[pointId] = misses
need(util.nowMs() >= (misses.until_at or 0), "TRY_LATER",
"Too many wrong codes. Wait a minute and try again")
return misses
end




function actions.PICKUP_COLLECT(payload, caller)
pickupPoint(caller)
reject("UPDATE_TERMINAL", "This pickup point needs its update. Ask staff"
.. " to leave Pickup mode for a moment")
end









function actions.PICKUP_CODE(payload, caller)
local terminal = pickupPoint(caller)
local misses = pointMisses(terminal.terminal_id)
local code = tostring(payload.code or ""):gsub("%D", "")
local found
for _, order in pairs(state.orders) do
if order.status == "open" and order.delivery.kind == "pickup"
and order.delivery.point_id == terminal.terminal_id
and #code == 6 and (order.code == code
or order.delivery_code == code) then
found = order
end
end
if not found then
misses.count = (misses.count or 0) + 1
if misses.count >= SHOP.code_tries then
misses.count, misses.until_at = 0, util.nowMs() + SHOP.code_lock_ms
end
save()
reject("NO_SUCH_CODE", "That code is not for anything here")
end
misses.count = 0
local shown = { order_id = found.order_id, lines = util.copy(found.lines),
company_name = found.company_name }
if found.delivery_code == code then
need(not found.locker, "ALREADY_HERE", "That parcel is already here")
save()
shown.kind = "deliver"
shown.buyer_name = found.buyer_name
return shown
end
need(found.locker, "NOT_HERE_YET",
"That order is on its way but has not arrived yet")
shown.kind = "collect"
local held = securityState(found)
if held and held.status == "confirmed" then
save()
shown.confirmed = true
return shown
end
found.security = { status = "asked", point_id = terminal.terminal_id,
expires_at = util.nowMs() + SHOP.ask_ms }
save()

core.notify(found.buyer_account_id, "Is this you?",
"Somebody is collecting your " .. tostring(found.company_name)
.. " order at " .. tostring(found.delivery.point_name)
.. ". Confirm with your PIN.", "warning",
{ order_id = found.order_id, security_order = found.order_id,
style = "fullscreen", app_name = "Foxy Security" })
shown.waiting = true
shown.expires_in_ms = SHOP.ask_ms
return shown
end

local function askedHere(terminal, orderId)
local order = state.orders[tostring(orderId or "")]
need(order and order.status == "open" and order.locker
and order.delivery.kind == "pickup"
and order.delivery.point_id == terminal.terminal_id, "NO_SUCH_ORDER",
"That parcel is not waiting here")
return order
end


function actions.PICKUP_WAIT(payload, caller)
local order = askedHere(pickupPoint(caller), payload.order_id)
local check = order.security or {}
local held = securityState(order)
if held then
return { status = held.status, expires_in_ms = held.expires_in_ms }
end
if check.status == "denied" then
order.security = nil
save()
return { status = "denied" }
end
return { status = "expired" }
end


function actions.PICKUP_RELEASE(payload, caller)
local terminal = pickupPoint(caller)
local order = askedHere(terminal, payload.order_id)
local held = securityState(order)
need(held and held.status == "confirmed", "NOT_CONFIRMED",
"The buyer has not confirmed it is them")
local locker = order.locker
order.status = "collected"
order.done_day = util.ingameDay()
order.finished_at = util.ingameMoment()
order.locker, order.security = nil, nil
orderStamp(order, "Collected")
save()
core.notify(order.buyer_account_id, "Collected",
"You picked up your order from " .. order.company_name .. ".",
"success", { order_id = order.order_id })
return { order_id = order.order_id, locker = locker,
lines = util.copy(order.lines) }
end



local function buyersParcel(caller, orderId)
local buyer = whoIsAsking(caller)
local order = state.orders[tostring(orderId or "")]
need(order and order.buyer_account_id == buyer.account_id
and order.status == "open" and order.delivery.kind == "pickup",
"NO_SUCH_ORDER", "That order is not waiting at a pickup point")
need(order.locker, "NOT_HERE_YET", "It has not reached the pickup point")
return order
end


function actions.SECURITY_LIST(payload, caller)
local buyer = whoIsAsking(caller)
local list = {}
for _, order in pairs(state.orders) do
if order.buyer_account_id == buyer.account_id
and order.status == "open" and order.delivery.kind == "pickup"
and order.locker then
list[#list + 1] = { order_id = order.order_id,
company_name = order.company_name,
point_name = order.delivery.point_name,
lines = util.copy(order.lines),
security = securityState(order) }
end
end
local function rank(entry)
local status = entry.security and entry.security.status
return status == "asked" and 1 or status == "confirmed" and 2 or 3
end
table.sort(list, function(a, b)
if rank(a) ~= rank(b) then return rank(a) < rank(b) end
return a.order_id < b.order_id
end)
return { parcels = list, preconfirm_ms = SHOP.preconfirm_ms }
end



function actions.SECURITY_CONFIRM(payload, caller)
local order = buyersParcel(caller, payload.order_id)
local held = securityState(order)
local answering = held and held.status == "asked"
order.security = { status = "confirmed",
point_id = order.delivery.point_id,
until_at = util.nowMs() + (answering and SHOP.ask_ms
or SHOP.preconfirm_ms) }
save()
return { order_id = order.order_id, answered = answering,
security = securityState(order) }
end




function actions.SECURITY_DENY(payload, caller)
local order = buyersParcel(caller, payload.order_id)
local held = securityState(order)
if held and held.status == "asked" then
order.security = { status = "denied" }
order.code = freshCode(order.delivery.point_id, order.code)
save()
core.notify(order.buyer_account_id, "New pickup code",
"Nobody got your parcel. Your new code for "
.. tostring(order.delivery.point_name) .. " is "
.. order.code .. ".", "warning", { order_id = order.order_id })
return { order_id = order.order_id, denied = true, code = order.code }
end
order.security = nil
save()
return { order_id = order.order_id, denied = false }
end









local function storeOf(point)
point.store = point.store or { open = false, offers = {} }
point.store.offers = point.store.offers or {}
return point.store
end

local function companyPoint(caller, pointId)
local company = shopTerminal(caller)
local point = state.pickup_points[tostring(pointId or "")]
need(point and point.company_id == company.company_id, "NO_SUCH_POINT",
"That pickup point is not this company's")
return point
end

local function shownPoint(point)
local store = storeOf(point)
return { point_id = point.point_id, name = point.name, x = point.x,
y = point.y, z = point.z, open = store.open == true,
offers = util.copy(store.offers) }
end


function actions.STORE_POINTS(payload, caller)
local company = shopTerminal(caller)
local list = {}
for _, point in pairs(state.pickup_points) do
if point.company_id == company.company_id then
list[#list + 1] = shownPoint(point)
end
end
table.sort(list, function(a, b) return a.name < b.name end)
return { points = list, max_offers = SHOP.max_offers }
end


local function itemName(raw)
local name = string.lower(util.trim(tostring(raw or "")))
need(#name >= 2 and #name <= 48, "BAD_ITEM",
"Type the item's game name, like oak_log")
if not name:find(":", 1, true) then name = "minecraft:" .. name end
need(name:match("^[a-z0-9_%.%-]+:[a-z0-9_%./%-]+$"), "BAD_ITEM",
"Type the item's game name, like oak_log")
return name
end

function actions.STORE_OFFER_SET(payload, caller)
local point = companyPoint(caller, payload.point_id)
local store = storeOf(point)
local name = util.safeText(util.trim(tostring(payload.name or "")), 20)
need(#name >= 2, "BAD_NAME", "Give it a name")
local count = math.floor(tonumber(payload.count) or 0)
need(count >= 1 and count <= 64 * 9, "BAD_COUNT",
"Between 1 and 576 items a sale")
local price = validateAmount(payload.price, 1000000)
local offer
for _, existing in ipairs(store.offers) do
if existing.offer_id == payload.offer_id then offer = existing end
end
if not offer then
need(#store.offers < SHOP.max_offers, "TOO_MANY_OFFERS",
"A pickup point sells " .. SHOP.max_offers .. " things at most")
store.sequence = (store.sequence or 0) + 1
offer = { offer_id = "S" .. store.sequence }
store.offers[#store.offers + 1] = offer
end
offer.name, offer.item = name, itemName(payload.item)
offer.count, offer.price = count, price
save()
return { point = shownPoint(point), offer = util.copy(offer) }
end

function actions.STORE_OFFER_REMOVE(payload, caller)
local point = companyPoint(caller, payload.point_id)
local store = storeOf(point)
for index, offer in ipairs(store.offers) do
if offer.offer_id == payload.offer_id then
table.remove(store.offers, index)
if #store.offers == 0 then store.open = false end
save()
return { point = shownPoint(point) }
end
end
reject("NOT_FOUND", "That is not sold there")
end

function actions.STORE_OPEN(payload, caller)
local point = companyPoint(caller, payload.point_id)
local store = storeOf(point)
if payload.open == true then
need(#store.offers > 0, "NOTHING_TO_SELL",
"Add something to sell first")
end
store.open = payload.open == true
save()
return { point = shownPoint(point) }
end


function actions.PICKUP_STORE(payload, caller)
local terminal = pickupPoint(caller)
local point = state.pickup_points[terminal.terminal_id]
need(point, "NOT_A_POINT", "This terminal is not a pickup point")
return shownPoint(point)
end

















local MAIL = {
personal_domain = string.lower(tostring(config.mail_domain or "foxy.com")),
inbox = 30, sent = 15, subject = 40, body = 300, recipients = 5,
per_domain = 5, per_day = 40,
reserved = { ["foxy.com"] = true, ["pumpe.com"] = true },
}
local MAIL_FILE = fs.combine(ROOT, "bank_vault_mail_v1.dat")
local mail = util.loadTable(MAIL_FILE, {})
mail.addresses = mail.addresses or {}
mail.personal = mail.personal or {}
mail.domains = mail.domains or {}
mail.boxes = mail.boxes or {}
mail.messages = mail.messages or {}
mail.sent_today = mail.sent_today or {}
mail.sequence = mail.sequence or 0

local function saveMail() pcall(util.saveTable, MAIL_FILE, mail) end

local function mailAddress(value)
return string.lower(util.trim(tostring(value or "")))
end

local function mailLocal(value)
local wanted = mailAddress(value)
need(#wanted >= 2 and #wanted <= 16
and wanted:match("^[a-z0-9][a-z0-9%._%-]*$") ~= nil, "BAD_ADDRESS",
"2 to 16 letters, numbers, dots, dashes or underscores")
return wanted
end

local function mailDomain(value)
local wanted = mailAddress(value)
local ending = wanted:match("%.([a-z]+)$")
need(#wanted <= 24 and ending and #ending >= 2 and #ending <= 6
and wanted:match("^[a-z0-9][a-z0-9%-]*%.[a-z]+$") ~= nil, "BAD_DOMAIN",
"A name and an ending, like revolution.com")
need(not MAIL.reserved[wanted] and wanted ~= MAIL.personal_domain,
"DOMAIN_TAKEN", wanted .. " is the Bank's own")
return wanted
end




local function mailIdentity(caller)
local allowed = {}
if type(caller) == "table" and caller.kind == "terminal" then
for address, entry in pairs(mail.addresses) do
if entry.company_id == caller.company_id then allowed[address] = entry end
end
return allowed
end
local person = whoIsAsking(caller)
local mine = mail.personal[person.account_id]
if mine and mail.addresses[mine] then allowed[mine] = mail.addresses[mine] end
local owned = {}
for _, company in ipairs(type(caller.companies) == "table"
and caller.companies or {}) do
owned[tostring(company.company_id)] = true
end
for address, entry in pairs(mail.addresses) do
if entry.company_id and owned[entry.company_id] then
allowed[address] = entry
end
end
return allowed
end

local function mailbox(address)
mail.boxes[address] = mail.boxes[address] or { inbox = {}, sent = {} }
return mail.boxes[address]
end

local function letGo(id)
local message = mail.messages[id]
if not message then return end
message.refs = (message.refs or 1) - 1
if message.refs <= 0 then mail.messages[id] = nil end
end

local function fileMail(list, entry, cap)
table.insert(list, 1, entry)
while #list > cap do letGo(table.remove(list).id) end
end

local function unreadIn(address)
local count = 0
for _, entry in ipairs(mailbox(address).inbox) do
if not entry.read then count = count + 1 end
end
return count
end


local function mailReader(address)
local entry = mail.addresses[address]
if not entry then return nil end
if entry.account_id then return entry.account_id end
local domain = mail.domains[entry.domain or ""]
return domain and domain.owner_account_id
end

local function sendMail(from, rawTo, subject, body, extra)
extra = extra or {}
need(mail.addresses[from], "NO_SUCH_ADDRESS", "Send from an address you have")
local text = type(rawTo) == "table" and table.concat(rawTo, ",")
or tostring(rawTo or "")
local to, seen = {}, {}
for piece in text:gmatch("[^,;%s]+") do
local address = mailAddress(piece)
if not seen[address] then
seen[address] = true
need(mail.addresses[address], "NO_SUCH_ADDRESS",
"Nobody has the address " .. address)
to[#to + 1] = address
end
end
need(#to >= 1, "NO_RECIPIENT", "Who is it to?")
need(#to <= MAIL.recipients, "TOO_MANY_RECIPIENTS",
MAIL.recipients .. " people at most")
subject = util.safeText(util.trim(tostring(subject or "")), MAIL.subject)
body = util.safeText(util.trim(tostring(body or "")), MAIL.body)
need(#subject > 0 or #body > 0, "EMPTY_MAIL", "Write something first")
if #subject == 0 then subject = "(no subject)" end
local today = util.ingameDay()
local sent = mail.sent_today[from]
if not sent or sent.day ~= today then sent = { day = today, count = 0 } end
need(sent.count < MAIL.per_day, "MAIL_LIMIT",
"That address has sent all it can today")
sent.count = sent.count + 1
mail.sent_today[from] = sent

mail.sequence = mail.sequence + 1
local id = string.format("MAIL%08d", mail.sequence)
mail.messages[id] = {
id = id, from = from, to = to, subject = subject, body = body,
day = util.ingameDay(), time = util.formatClock(),
refs = #to + 1, app_name = extra.app_name,
reply_to = extra.reply_to and tostring(extra.reply_to) or nil,
}
fileMail(mailbox(from).sent, { id = id }, MAIL.sent)
for _, address in ipairs(to) do
fileMail(mailbox(address).inbox, { id = id, read = false }, MAIL.inbox)
local reader = mailReader(address)
if reader then
core.notify(reader, "Mail to " .. address, from .. ": " .. subject,
"info", { mail_id = id, address = address })
end
end
saveMail()
return { id = id, to = to }
end

local function mailSummary(message, read)
return {
id = message.id, from = message.from, to = util.copy(message.to),
subject = message.subject, day = message.day, time = message.time,
read = read, app_name = message.app_name,
preview = message.body:sub(1, 48),
}
end


local function mailEntry(caller, payload)
local address = mailAddress(payload.address)
need(mailIdentity(caller)[address], "NOT_YOURS",
"That is not one of your addresses")
local box = mailbox(address)
local id = tostring(payload.id or "")
for _, name in ipairs({ "inbox", "sent" }) do
for index, entry in ipairs(box[name]) do
if entry.id == id and mail.messages[id] then
return address, name, index, entry, mail.messages[id]
end
end
end
reject("NO_SUCH_MAIL", "That message is gone")
end

function actions.MAIL_ME(payload, caller)
local allowed = mailIdentity(caller)
local list = {}
for address, entry in pairs(allowed) do
local domain = entry.domain and mail.domains[entry.domain]
list[#list + 1] = { address = address, kind = entry.kind,
company_name = domain and domain.company_name or nil,
unread = unreadIn(address) }
end
table.sort(list, function(a, b)
if (a.kind == "personal") ~= (b.kind == "personal") then
return a.kind == "personal"
end
return a.address < b.address
end)
local companies = {}
if type(caller) == "table" and caller.kind ~= "terminal" then
for _, company in ipairs(type(caller.companies) == "table"
and caller.companies or {}) do
local domain
for name, entry in pairs(mail.domains) do
if entry.company_id == company.company_id then domain = name end
end
companies[#companies + 1] = { company_id = company.company_id,
name = company.name, domain = domain }
end
end
return { personal_domain = MAIL.personal_domain, addresses = list,
companies = companies,
personal = caller.kind ~= "terminal"
and mail.personal[whoIsAsking(caller).account_id] or nil }
end

function actions.MAIL_CLAIM(payload, caller)
local person = whoIsAsking(caller)
need(not mail.personal[person.account_id], "HAS_ADDRESS",
"You already have " .. tostring(mail.personal[person.account_id]))
local address = mailLocal(payload.name) .. "@" .. MAIL.personal_domain
need(not mail.addresses[address], "ADDRESS_TAKEN",
address .. " is taken")
mail.addresses[address] = { address = address, kind = "personal",
account_id = person.account_id, domain = MAIL.personal_domain,
created_day = util.ingameDay() }
mail.personal[person.account_id] = address
saveMail()
return { address = address }
end

local function ownedCompany(caller, companyId)
for _, company in ipairs(type(caller) == "table"
and type(caller.companies) == "table" and caller.companies or {}) do
if company.company_id == companyId then return company end
end
reject("NOT_OWNER", "You do not own that company")
end

function actions.MAIL_DOMAIN(payload, caller)
local person = whoIsAsking(caller)
local company = ownedCompany(caller, tostring(payload.company_id or ""))
for name, entry in pairs(mail.domains) do
need(entry.company_id ~= company.company_id, "HAS_DOMAIN",
company.name .. " already has " .. name)
end
local domain = mailDomain(payload.domain)
need(not mail.domains[domain], "DOMAIN_TAKEN", domain .. " is taken")
local first = mailLocal(payload.name or "hello") .. "@" .. domain
mail.domains[domain] = { domain = domain, company_id = company.company_id,
company_name = company.name, owner_account_id = person.account_id,
created_day = util.ingameDay() }
mail.addresses[first] = { address = first, kind = "company",
company_id = company.company_id, domain = domain,
created_day = util.ingameDay() }
saveMail()
return { domain = domain, address = first }
end

function actions.MAIL_ADDRESS(payload, caller)
whoIsAsking(caller)
local domain = mailAddress(payload.domain)
local entry = mail.domains[domain]
need(entry, "NO_DOMAIN", "Register the domain first")
ownedCompany(caller, entry.company_id)
local count = 0
for _, address in pairs(mail.addresses) do
if address.domain == domain then count = count + 1 end
end
need(count < MAIL.per_domain, "TOO_MANY_ADDRESSES",
MAIL.per_domain .. " addresses per domain")
local address = mailLocal(payload.name) .. "@" .. domain
need(not mail.addresses[address], "ADDRESS_TAKEN", address .. " is taken")
mail.addresses[address] = { address = address, kind = "company",
company_id = entry.company_id, domain = domain,
created_day = util.ingameDay() }
saveMail()
return { address = address }
end

function actions.MAIL_LIST(payload, caller)
local address = mailAddress(payload.address)
need(mailIdentity(caller)[address], "NOT_YOURS",
"That is not one of your addresses")
local box = payload.box == "sent" and "sent" or "inbox"
local list = {}
for _, entry in ipairs(mailbox(address)[box]) do
local message = mail.messages[entry.id]
if message then
list[#list + 1] = mailSummary(message, box == "sent" or entry.read)
end
end
return { address = address, box = box, messages = list,
unread = unreadIn(address) }
end

function actions.MAIL_READ(payload, caller)
local _, box, _, entry, message = mailEntry(caller, payload)
if box == "inbox" and not entry.read then
entry.read = true
saveMail()
end
local full = mailSummary(message, true)
full.body = message.body
full.reply_to = message.reply_to
return { message = full }
end

function actions.MAIL_SEND(payload, caller)
local from = mailAddress(payload.from)
need(mailIdentity(caller)[from], "NOT_YOURS",
"You cannot send as " .. from)
return sendMail(from, payload.to, payload.subject, payload.body,
{ reply_to = payload.reply_to })
end

function actions.MAIL_DELETE(payload, caller)
local address, box, index, entry = mailEntry(caller, payload)
table.remove(mailbox(address)[box], index)
letGo(entry.id)
saveMail()
return { deleted = true }
end



actions.KIOSK_MAIL_ME = actions.MAIL_ME
actions.KIOSK_MAIL_LIST = actions.MAIL_LIST
actions.KIOSK_MAIL_READ = actions.MAIL_READ
actions.KIOSK_MAIL_SEND = actions.MAIL_SEND
actions.KIOSK_MAIL_DELETE = actions.MAIL_DELETE



function actions.VAULT_MAIL_APP_SEND(payload)
local from = mailAddress(payload.from)
local entry = mail.addresses[from]
need(entry and entry.kind == "company", "NOT_YOURS",
"An app sends from its company's own address")
local allowed = false
for _, company in ipairs(type(payload.companies) == "table"
and payload.companies or {}) do
if company.company_id == entry.company_id then allowed = true end
end
need(allowed, "NOT_YOURS", "That address is not this app's company's")
return sendMail(from, payload.to, payload.subject, payload.body,
{ app_name = util.safeText(tostring(payload.app_name or "An app"), 18) })
end












local RECORDS = { dir = fs.combine(ROOT, "records"), t = 30, n = 20 }
local recordCache = {}

local function recordsOf(accountId)
local cached = recordCache[accountId]
if not cached then
cached = util.loadTable(fs.combine(RECORDS.dir, accountId .. ".dat"),
{ t = {}, n = {} })
cached.t, cached.n = cached.t or {}, cached.n or {}
recordCache[accountId] = cached
end
return cached
end




local function packRecord(kind, item)
if kind == "t" then
return { item.tx_id, item.type, item.amount, item.counterparty,
item.description, item.day, item.time }
end
local extra
for key, value in pairs(item) do
if key ~= "notification_id" and key ~= "title" and key ~= "body"
and key ~= "kind" and key ~= "created_day"
and key ~= "created_time" and key ~= "read" then
extra = extra or {}
extra[key] = value
end
end
return { item.notification_id, item.title, item.body, item.kind,
item.created_day, item.created_time, item.read == true, extra }
end

local function unpackRecord(kind, row)
if kind == "t" then
return { tx_id = row[1], type = row[2], amount = row[3],
counterparty = row[4], description = row[5], day = row[6],
time = row[7] }
end
local item = util.copy(row[8] or {})
item.notification_id, item.title, item.body, item.kind = row[1], row[2],
row[3], row[4]
item.created_day, item.created_time, item.read = row[5], row[6],
row[7] == true
return item
end

local vault = {}




function vault.VAULT_CALL(payload, sender)
need(sender == core.id, "NOT_MY_CORE",
"This Vault belongs to another Bank")
local handler = actions[tostring(payload.action or "")]
need(handler, "UNKNOWN_ACTION", "The Vault does not do that")
local caller = type(payload.caller) == "table" and payload.caller or {}
local result = handler(payload.payload or {}, caller)




if caller.account_id then touchBadges(caller.account_id) end
pushBadges()
return result
end


function vault.VAULT_RECORDS(payload, sender)
need(sender == core.id, "NOT_MY_CORE",
"This Vault belongs to another Bank")
local touched = {}
for _, entry in ipairs(type(payload.items) == "table" and payload.items
or {}) do
local accountId = tostring(entry.a or "")
if accountId:match("^[%w_]+$") then
local held = recordsOf(accountId)
if entry.k == "r" then
for _, row in ipairs(held.n) do row[7] = true end
touched[accountId] = true
elseif (entry.k == "t" or entry.k == "n")
and type(entry.i) == "table" then
local row = packRecord(entry.k, entry.i)
local list, repeated = held[entry.k], false
for _, existing in ipairs(list) do
if existing[1] == row[1] then repeated = true break end
end
if not repeated then
table.insert(list, 1, row)
while #list > RECORDS[entry.k] do table.remove(list) end
touched[accountId] = true
end
end
end
end
for accountId in pairs(touched) do
pcall(util.saveTable, fs.combine(RECORDS.dir, accountId .. ".dat"),
recordsOf(accountId))
end
return { stored = #(payload.items or {}) }
end

function vault.VAULT_RECORDS_READ(payload, sender)
need(sender == core.id, "NOT_MY_CORE",
"This Vault belongs to another Bank")
local accountId = tostring(payload.account_id or "")
need(accountId:match("^[%w_]+$"), "NO_ACCOUNT", "Whose records?")
local kind = payload.kind == "t" and "t" or "n"
local items = {}
for _, row in ipairs(recordsOf(accountId)[kind]) do
items[#items + 1] = unpackRecord(kind, row)
end
return { items = items }
end

function vault.PAIR_HELLO(payload, sender)
return {
computer = os.getComputerID(),
version = config.version,
role = "vault",
core = core.id,
holders = mapCount(state.holders),
}
end








local wire = { incoming = nil, restart = false }

local function wireAllowed()
local update = require("lib.update")
local allowed = {}
for _, path in ipairs(update.rolePaths("vault") or {}) do
allowed[update.installPath(path)] = true
end
return allowed, update
end

function vault.VAULT_UPDATE_BEGIN(payload, sender)
need(sender == core.id, "NOT_MY_CORE", "This Vault belongs to another Bank")
local version = tostring(payload.version or "")
need(net.isNewerVersion(version, PROGRAM_VERSION), "NOT_NEWER",
"This Vault already runs v" .. PROGRAM_VERSION)
local allowed, update = wireAllowed()
local files, total = {}, 0
for _, file in ipairs(type(payload.files) == "table" and payload.files or {}) do
local path = tostring(file.path or "")
need(allowed[path], "BAD_PATH", "A Vault does not install " .. path)
local size = math.floor(tonumber(file.size) or -1)
need(size >= 0 and type(file.checksum) == "string", "BAD_FILE",
path .. " was announced without a size or checksum")
files[path] = { size = size, checksum = file.checksum, parts = {},
received = 0 }
total = total + size
end
need(files["bank_vault.lua"] and files["config.lua"], "INCOMPLETE",
"An update needs the program and its config")
need(update.hasFreeSpace(ROOT, total), "NO_SPACE",
"Not enough room on the Vault for v" .. version)
wire.incoming = { version = version, files = files }
logActivity("Receiving v" .. version .. " over the cable", colors.cyan)
return { ready = true }
end

function vault.VAULT_UPDATE_CHUNK(payload, sender)
need(sender == core.id, "NOT_MY_CORE", "This Vault belongs to another Bank")
local incoming = wire.incoming
need(incoming, "NO_UPDATE", "No update was started")
local file = incoming.files[tostring(payload.path or "")]
need(file, "BAD_PATH", "That file is not part of this update")
local data = tostring(payload.data or "")
need(tonumber(payload.offset) == file.received + 1, "OUT_OF_ORDER",
"Pieces arrived out of order")
need(file.received + #data <= file.size, "TOO_LONG",
"More arrived than was announced")
file.parts[#file.parts + 1] = data
file.received = file.received + #data
return { received = file.received }
end

function vault.VAULT_UPDATE_COMMIT(payload, sender)
need(sender == core.id, "NOT_MY_CORE", "This Vault belongs to another Bank")
local incoming = wire.incoming
need(incoming and incoming.version == tostring(payload.version or ""),
"NO_UPDATE", "No update was started")
wire.incoming = nil
local _, update = wireAllowed()
local staging = fs.combine(ROOT, ".wire_update")
local backup = fs.combine(ROOT, ".wire_backup")
local function abandon(code, message)
if fs.exists(staging) then fs.delete(staging) end
reject(code, message)
end
if fs.exists(staging) then fs.delete(staging) end
local plan = { files = {} }
for path, file in pairs(incoming.files) do
local body = table.concat(file.parts)
if #body ~= file.size or util.checksum(body) ~= file.checksum then
abandon("DAMAGED", path .. " arrived damaged. Nothing was changed")
end
local wrote = pcall(util.writeFile, fs.combine(staging, path), body)
if not wrote then abandon("NO_SPACE", "Could not stage " .. path) end
plan.files[#plan.files + 1] = { path = path }
end
local merged, mergeError = update.mergeConfig(
fs.combine(staging, "config.lua"), config, incoming.version)
if not merged then abandon("BAD_CONFIG", tostring(mergeError)) end
save()
saveMail()
local committed, commitError = update.commitRelease(plan, staging, ROOT,
backup)
need(committed, "NOT_INSTALLED", tostring(commitError))
wire.restart = true
logActivity("Installed v" .. incoming.version .. "; restarting", colors.lime)
return { installed = incoming.version }
end



local function updatesItself() return core.id == nil end

function vault.VAULT_STATUS(payload, sender)
return {
version = PROGRAM_VERSION,
holders = mapCount(state.holders),
conversations = mapCount(state.conversations),
territories = mapCount(state.territories),
events = mapCount(state.events),
migrated = state.migrated,
}
end

if TEST_MODE then
return {
actions = actions,
vault = vault,
state = state,
core = core,
holder = holder,
scans = scans,
urgent_calls = urgentCalls,
sync_waiting = syncWaiting,
push_badges = pushBadges,
touch_badges = touchBadges,
social_badges = socialBadges,
sweep_travel = sweepTravel,
cleanup_calls = cleanupUrgentCalls,
sweep_orders = sweepOrders,
mail = mail,
wire = wire,
updates_itself = updatesItself,
}
end



local function serverLoop()
while running do
local sender, message = rednet.receive(PROTOCOL, 1)
if sender and type(message) == "table" and message.kind == "request"
and type(message.action) == "string" then
local handler = vault[message.action]
if not handler then
net.reply(sender, PROTOCOL, message.request_id, false, nil,
"Unknown vault action", "UNKNOWN_ACTION")
else
local ok, result = pcall(handler, message.payload or {},
sender)
if ok then
net.reply(sender, PROTOCOL, message.request_id, true,
result)
elseif type(result) == "table" and result.pumpe then
net.reply(sender, PROTOCOL, message.request_id, false,
nil, result.message, result.code)
else
logActivity("Error: " .. tostring(result), colors.red)
net.reply(sender, PROTOCOL, message.request_id, false,
nil, "Vault request failed", "VAULT_ERROR")
end
end
end
end
end

local function sweepLoop()
local everyMinute = 0
while running do

if wire.restart then
save()
saveMail()
sleep(0.5)
os.reboot()
end
pcall(cleanupUrgentCalls)
pcall(syncWaiting)
pcall(pushBadges)
if util.nowMs() >= everyMinute then
everyMinute = util.nowMs() + 60000
pcall(sweepTravel)
pcall(sweepOrders)
save()
end
sleep(1)
end
end

local function updateLoop()
while running do
if updatesItself() then
net.autoUpdate(config, "vault", ROOT, nil,
{ programVersion = PROGRAM_VERSION })
end
sleep(10)
end
end

local function dashboardLoop()
local target = term.current()
local blink = true
while running do
local width, height = target.getSize()
ui.clear(target)
ui.header(target, "PUMPE BANK VAULT", "v" .. PROGRAM_VERSION,
util.formatClock(blink))
local cardWidth = math.floor((width - 4) / 3)
local cards = {
{ "PEOPLE", mapCount(state.holders), colors.cyan },
{ "CHATS", mapCount(state.conversations), colors.magenta },
{ "TERRITORIES", mapCount(state.territories), colors.lime },
}
for index, card in ipairs(cards) do
local x = 2 + (index - 1) * (cardWidth + 1)
local panelWidth = index == #cards and width - 1 - x or cardWidth
ui.card(target, x, 5, panelWidth, 4, card[3])
ui.text(target, x + 2, 6, card[1], colors.lightGray, colors.gray)
ui.text(target, x + 2, 7, tostring(card[2]), colors.white,
colors.gray, panelWidth - 3)
end
ui.text(target, 2, 10, ui.truncate("CORE  " .. dash.core, width - 2),
dash.core_color)
ui.text(target, 2, 11,
ui.truncate("INTERNET  " .. dash.update_status, width - 2),
dash.update_color)
local scene = ui.scene(target)
local feedY = 13
ui.text(target, 2, feedY, "ACTIVITY", colors.lightGray)
local maxFeed = math.max(1, height - feedY - 2)
for index = 1, math.min(#activity, maxFeed) do
local item = activity[index]
ui.text(target, 2, feedY + index,
item.time .. "  " .. ui.truncate(item.text, width - 10),
item.color)
end
scene:button("save", width - 18, height, 8, 1, "SAVE",
{ background = colors.blue })
scene:button("stop", width - 9, height, 8, 1, "STOP",
{ background = colors.red })
local action = scene:wait({ tickRate = 0.5, flash = false })
blink = not blink
if core.id then
dash.core = "#" .. tostring(core.id)
.. (core.online == false and " NOT ANSWERING" or " LINKED")
dash.core_color = core.online == false and colors.red or colors.lime
end
if action == "save" then
save()
logActivity("Manual save complete", colors.lime)
elseif action == "stop" then
if ui.confirm(target, "STOP VAULT", "Save and shut down?",
"STOP", "BACK") then
running = false
save()
return
end
elseif action == "__terminate" then
running = false
save()
return
end
end
end

ui.boot(term.current(), "PUMPE VAULT", "BANK RECORDS")

if not core.load() then

ui.message(term.current(), "error", "NO CORE",
"This computer was installed as a Vault but is not paired to a Bank."
.. " Pair it from the Bank Server.", 6)
logActivity("No Core paired - pair this from the Bank Server", colors.red)
end

net.openModems()
rednet.host(PROTOCOL, config.pair_hostname or "BANK_VAULT")
if core.id then
rednet.host(PROTOCOL, "BANKPAIR_" .. os.getComputerID())
dash.core = "#" .. tostring(core.id)
logActivity("Vault online for Bank Core #" .. tostring(core.id),
colors.lime)
end
save()

parallel.waitForAny(serverLoop, sweepLoop, updateLoop, dashboardLoop)
pcall(rednet.unhost, PROTOCOL)
ui.clear(term.current())
print("PUMPE Bank Vault stopped safely.")
