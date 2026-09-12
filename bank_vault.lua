local ROOT = fs.getDir(shell.getRunningProgram())
package.path = package.path .. ";" .. fs.combine(ROOT, "?.lua")

-- PUMPE BANK VAULT
--
-- The other half of a Bank. The Core holds anything where being wrong means
-- money is wrong -- balances, sessions, the ledger, tax, escrow. This holds
-- everything that is merely ABOUT an account: conversations and calls,
-- territories and visas, events and tickets, the records apps keep, and the
-- scans people present to each other.
--
-- It exists because those are the parts that grow without limit. By 9.2 the
-- Bank was a 287 KB program inside a computer that cannot update a file past
-- about 300 KB, and every one of those subsystems was still getting bigger.
-- Splitting them off is what bought the room back.
--
-- Three rules hold this design together:
--
--   1. This program never touches a balance. When something here has to move
--      money -- a ticket bought, a note paid in a conversation -- it asks the
--      Core, which does both sides of the move in one step. So a Vault that
--      is broken, lying or switched off cannot invent money or lose any.
--
--   2. This program never decides who is asking. The Core authenticates every
--      request and passes down an identity, never a session token. A Vault
--      cannot be talked into acting as somebody else because it was never
--      given the means to check, or to be fooled.
--
--   3. Clients never talk to it. A PUMPE asks the Bank, as it always has.
--
-- The link to the Core is a wired modem, required at pairing time. These two
-- computers answer parts of the same request, so the cable is not a network
-- detail -- it is the reason the split is not felt.

local PROGRAM_VERSION = "9.4.0"
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
            ticket_type = 0, ticket = 0,
        },
        -- What this Vault knows about a person. Never their money.
        holders = {},
        -- Names, so a conversation can be titled without a cable round trip
        -- for every line of it. Refreshed from the Core whenever it speaks.
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
        -- What apps keep. The name matches the table the Core used before
        -- 9.3, because a handover ships it under that name.
        app_data = {},
        -- Pushed up to the Core so a PUMPE's poll never crosses the cable.
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
}

local function nextId(kind)
    state.sequence[kind] = (state.sequence[kind] or 0) + 1
    local format = prefixes[kind]
    return format[1]
        .. string.format("%0" .. format[2] .. "d", state.sequence[kind])
end

-- The Core ---------------------------------------------------------------------
-- Everything this Vault cannot do for itself. Each call is one hop down a
-- cable, which is why the hot paths above are built to avoid needing one.
local core = { id = nil, online = nil }

-- Accounts whose badge counts have moved and have not been pushed to the
-- Core yet. Declared up here because core.notify is the natural place to
-- catch them: it is called for precisely the people whose counts changed.
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

-- Asking the Core to move money. The move id is what makes a lost reply
-- harmless: the Core answers a repeat with the first result rather than
-- moving the money twice.
-- `priced` means this is money between two people, and costs what Send Money
-- costs. Without it the move is a plain credit, which is what a ticket sale
-- is: the buyer pays the face price and the organiser receives it.
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

-- A name, from memory where possible. Names change rarely and a stale one in
-- a conversation title is worth far less than a cable hop per message.
local function nameOf(accountId)
    if not accountId then return "Someone" end
    if accountId == "GOVERNMENT" then return "Government" end
    local known = state.names[accountId]
    if known then return known end
    local account = core.account(accountId)
    return account and account.name or "Unknown"
end

-- Who is asking ----------------------------------------------------------------
-- The Core has already decided this. A caller reaching here has been
-- authenticated over there; this Vault's job is to look up what it holds
-- about them, not to re-check them.
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

-- The moved code reads account.name and account.account_id in a hundred
-- places, so a holder carries both and the caller's name refreshes them.
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

-- Shared helpers ---------------------------------------------------------------

local function validateAmount(value, maximum)
    local amount = util.roundMoney(value)
    need(amount and amount > 0, "INVALID_AMOUNT", "Enter an amount above zero")
    need(not maximum or amount <= maximum, "INVALID_AMOUNT",
        "Amount is above the allowed maximum")
    return amount
end

-- Whether someone else can be dealt with at all. Only the Core knows, so
-- this is one of the few places a cable hop is unavoidable.
local function activeAccount(accountId, receiving)
    local account = accountId and core.account(accountId)
    -- The same refusals, in the same order, with the same codes as the Core
    -- applies. A client already knows what to do with each of them, and a
    -- route that moved computers must not start answering differently.
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

-- Friends and conversations ----------------------------------------------------
-- Conversations are persistent; urgent calls are deliberately not. A restart
-- drops a live call the way a dropped connection would, and only a transcript
-- both people agreed to save reaches the database.

local SOCIAL = { max_group = 8, max_message = 160 }
-- Conversations are the first PUMPE feature that grows the database on its
-- own. At 160 characters plus metadata a message costs roughly 260 bytes, so
-- this cap keeps even a busy account well inside a ComputerCraft computer.
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

-- The name index belongs to whoever holds the account, so the search runs on
-- the Core and this only says what the result means to the person asking.
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

-- What the Core asks when a money route needs to know about a friendship.
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

-- Conversations ----------------------------------------------------------------

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
    -- Every line moves somebody's unread count, whether or not it was loud
    -- enough to raise an alert. Only the first unread in a conversation
    -- notifies, so marking them here rather than beside the alert is what
    -- keeps the second message counted.
    for _, memberId in ipairs(conversation.member_ids) do
        if memberId ~= senderId then dirty[memberId] = true end
    end
    return item
end

-- Only the first unread message in a conversation raises an alert, so a busy
-- group chat cannot flood the 50-entry Alerts list.
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
    -- An open chat polls this every second. Only write the database when the
    -- read marker actually moved.
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

-- The PIN was checked by the Core before this was forwarded. Every route
-- below moves money by asking the Core, never by editing a balance.
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
    -- A government demand is paid to the state. There is no counterpart
    -- account to credit, so it settles like a fine rather than a transfer.
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

-- The government's thread with one account. The Core does the money and the
-- tax demand; this only keeps the conversation.
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

-- The government's side of a thread. Only reachable with a caller the Core
-- marked as a government session, and the Core is the only thing that can
-- reach VAULT_CALL at all.
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

-- Every thread the government is holding, newest first, so the terminal can
-- see who has replied.
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

-- Urgent Contact ---------------------------------------------------------------
-- Deliberately not persisted. A restart drops a live call the way a dropped
-- connection would, and only a transcript both people agreed to save reaches
-- the database.
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

-- The Urgent Contact API. A messaging app can raise the same alert the PUMPE
-- raises, but the name on the alert comes from the grant the Core checked,
-- never from the app asking.
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

-- Proximity scans --------------------------------------------------------------
-- A PUMPE showing a ticket or a travel document tells the Bank what it is
-- holding up. A door or a border then asks who is nearest with the right
-- thing on screen, rather than anybody typing an eight character code.
--
-- Positions and what a phone is holding up stay on the Core: the OS poll
-- already carries both, so keeping them there costs nothing and moving them
-- would put a cable hop inside the most-called action on the network. The
-- Core hands back the nearest candidates; deciding whether a candidate's
-- ticket or visa is actually valid needs the records, so that happens here.
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

-- Hands the ask to the next nearest holder, or reports that nobody is there.
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

-- Scans are in-memory, so they need their own sweep. A settled one is kept
-- briefly so the scanner's next poll still sees the result.
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

-- The scan waiting on this account, pushed to the Core for the OS poll.
function scans.forAccount(accountId)
    for _, request in pairs(scans.requests) do
        if request.target_account_id == accountId
            and not scans.expired(request) then
            return scans.public(request), request.expires_at
        end
    end
    return nil
end

-- The scanner's own view of a request it started.
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

-- Accepting runs the scan's own settle step: admitting a ticket, or putting a
-- traveller through the border. A refusal there ends this person's turn and
-- tells the scanner why, rather than silently passing to the next one.
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

-- Customs, citizenship and visas -----------------------------------------------
-- Border Controllers are devices this Vault registered itself, so it checks
-- their tokens against its own list. That is not the same as deciding who an
-- account holder is -- which it never does -- because the secret and the list
-- it is checked against are both here. Anything about the owner behind the
-- device, their PIN included, still goes to the Core.

-- A scanner sends its own coordinates rather than borrowing an account's, so
-- an organiser standing at their own door is not mistaken for the terminal.
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

-- A visit that has run past its day. Ran inside the Core's sweep until 9.3,
-- where the records it reads stopped living there.
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

-- Customs, citizenship, and visa routes -------------------------------------

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

-- Border Controller routes --------------------------------------------------

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

-- Proximity Visa. The controller leaves this on and the Bank keeps asking
-- whoever is nearest with a travel document on screen. Accepting runs the
-- ordinary border check, so entry rules, cooldowns and visits are identical
-- to typing the code in by hand.

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
                -- Leaving if they are already inside, entering otherwise. A
                -- gate has no Enter/Exit buttons to press.
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

-- Events and tickets ----------------------------------------------------------
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

-- Event organizer routes ----------------------------------------------------

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

-- Proximity ticket scanning. The organiser turns it on at the door and the
-- Bank asks whoever is nearest with a ticket for this event on screen.

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


-- App records -----------------------------------------------------------------
-- A small shared store so an app can keep posts, comments or anything else
-- without the Bank knowing what any of it means. Records are owned by whoever
-- wrote them; reactions are the one thing anybody can add. The Core decides
-- who you are and whether you are signed in to the app, so by the time a
-- request arrives here both questions are already answered.
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

    -- Opening a new collection is the only thing that is capped. An app that
    -- keeps one per conversation would otherwise be able to fill the Bank's
    -- disk a conversation at a time, and the disk is the scarce thing here.
    -- Emptied collections are swept first, so a chat whose messages have all
    -- expired gives its slot back rather than holding it forever.
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
            -- The author reading their own record back is not a read
            -- receipt, or every message would expire the moment it was sent.
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

-- Badges -----------------------------------------------------------------------
-- ACCOUNT_SUMMARY and the OS poll are the two most called actions on the
-- network, and both want an unread count. Putting a cable hop inside them to
-- colour a badge would be a poor trade, so the Vault tells the Core when a
-- count changes and the Core answers out of its own memory.
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

-- What is waiting on somebody ---------------------------------------------------
-- A ringing call and an open scan both have to reach a phone that is polling
-- the Core, not this. Rather than put the Vault on the poll path, the Vault
-- pushes the short list of people something is actually waiting on -- usually
-- nobody -- and the Core answers its polls locally. Re-sent every second, so a
-- push lost while the Core was restarting fixes itself.
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

-- What this Vault answers ------------------------------------------------------
local vault = {}

-- Every client request its Core forwarded. The Core has already decided who
-- is asking; refusing anything that did not come from the Core is what stops
-- another computer asking directly and being believed.
function vault.VAULT_CALL(payload, sender)
    need(sender == core.id, "NOT_MY_CORE",
        "This Vault belongs to another Bank")
    local handler = actions[tostring(payload.action or "")]
    need(handler, "UNKNOWN_ACTION", "The Vault does not do that")
    local caller = type(payload.caller) == "table" and payload.caller or {}
    local result = handler(payload.payload or {}, caller)
    -- Whoever's counts this just moved gets them sent back up now, while the
    -- cable is already open, rather than on the next sweep. One request can
    -- only touch the people in one conversation, so this is bounded by the
    -- size of a group chat; the sweep is left to catch what a crash missed.
    if caller.account_id then touchBadges(caller.account_id) end
    pushBadges()
    return result
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

-- Taking over the records the Core used to keep. Sent one table at a time
-- and acknowledged before the Core drops its copy, so an interrupted move
-- leaves the data on the Core rather than nowhere.
function vault.VAULT_MIGRATE(payload, sender)
    need(sender == core.id, "NOT_MY_CORE",
        "This Vault belongs to another Bank")
    local name = tostring(payload.table or "")
    local rows = type(payload.rows) == "table" and payload.rows or {}
    local accepted = 0
    if name == "holders" then
        for accountId, fields in pairs(rows) do
            local record = holder(accountId)
            for key, value in pairs(fields) do
                if key ~= "account_id" then record[key] = value end
            end
            if type(fields.name) == "string" then
                state.names[accountId] = fields.name
            end
            accepted = accepted + 1
        end
    elseif name == "sequence" then
        for key, value in pairs(rows) do
            if state.sequence[key] ~= nil then
                state.sequence[key] = math.max(state.sequence[key] or 0,
                    math.floor(tonumber(value) or 0))
                accepted = accepted + 1
            end
        end
    elseif state[name] ~= nil and type(state[name]) == "table" then
        for key, value in pairs(rows) do
            state[name][key] = value
            accepted = accepted + 1
        end
    else
        reject("UNKNOWN_TABLE", "The Vault does not hold " .. name)
    end
    state.migrated[name] = util.nowMs()
    save()
    logActivity("Took over " .. accepted .. " " .. name, colors.lime)
    return { table = name, accepted = accepted }
end

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
    }
end

-- Running ----------------------------------------------------------------------

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
        pcall(cleanupUrgentCalls)
        pcall(syncWaiting)
        pcall(pushBadges)
        if util.nowMs() >= everyMinute then
            everyMinute = util.nowMs() + 60000
            pcall(sweepTravel)
            save()
        end
        sleep(1)
    end
end

local function updateLoop()
    while running do
        net.autoUpdate(config, "vault", ROOT, nil,
            { programVersion = PROGRAM_VERSION })
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
    -- Nothing to be done from here: a Vault is made by pairing, on the Core.
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
