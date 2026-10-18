-- FoxyCloud, FoxyOS 16.3, end to end: a real Bank Core and Vault, five real
-- Cloud Servers each with a disk of its own, and a Pocket saving and opening
-- files through lib/net -- over a network that delivers, loses and refuses
-- messages the way rednet does.
--
-- What has to hold: a file is cut into pieces and spread across the servers
-- by room; it comes back byte for byte, binary included; the plan's room is
-- the Bank's to decide and a Cloud Server enforces it; nobody opens a file
-- that is not theirs or shared with them; deleted and replaced pieces leave
-- the servers' disks; and FoxyCloud+ is billed every five days, takes the
-- Foxy Cash fee away, and when it ends the files stay.

package.path = "../?.lua;../?/init.lua;" .. package.path
sleep = function() end
local harness = require("bank_pair_harness")
local rejected = harness.rejected
local bank = harness.pair()
local config = require("config")
local util = require("lib.util")
local net = require("lib.net")

-- Disks -----------------------------------------------------------------------------
-- One per computer, each with its own size. ComputerCraft charges at least 500
-- bytes for a file however small, and so does this.
local disks = {}
local function clean(path)
    return (tostring(path):gsub("^/+", ""):gsub("/+$", ""))
end
local function rootOf(path) return clean(path):match("^([^/]+)") or "" end
local function diskFor(path)
    local root = rootOf(path)
    disks[root] = disks[root] or { files = {}, dirs = {}, capacity = 1000000 }
    return disks[root]
end
fs = {
    getDir = function(path)
        local dir = clean(path):match("^(.*)/[^/]*$") or ""
        return "/" .. dir
    end,
    combine = function(left, right)
        return tostring(left):gsub("/+$", "") .. "/" .. tostring(right):gsub("^/+", "")
    end,
    exists = function(path)
        local disk = diskFor(path)
        return disk.files[clean(path)] ~= nil or disk.dirs[clean(path)] == true
    end,
    isDir = function(path) return diskFor(path).dirs[clean(path)] == true end,
    makeDir = function(path) diskFor(path).dirs[clean(path)] = true end,
    list = function(path)
        local prefix, names = clean(path) .. "/", {}
        for name in pairs(diskFor(path).files) do
            if name:sub(1, #prefix) == prefix and not name:sub(#prefix + 1):find("/") then
                names[#names + 1] = name:sub(#prefix + 1)
            end
        end
        table.sort(names)
        return names
    end,
    getSize = function(path) return #(diskFor(path).files[clean(path)] or "") end,
    getFreeSpace = function(path)
        local disk, used = diskFor(path), 0
        for _, data in pairs(disk.files) do used = used + math.max(500, #data) end
        return disk.capacity - used
    end,
    delete = function(path) diskFor(path).files[clean(path)] = nil end,
    open = function(path, mode)
        local disk, key = diskFor(path), clean(path)
        if mode:sub(1, 1) == "r" then
            local data = disk.files[key]
            if not data then return nil end
            return { readAll = function() return data end, close = function() end }
        end
        local parts = {}
        return { write = function(text) parts[#parts + 1] = text end,
            close = function() disk.files[key] = table.concat(parts) end }
    end,
}

-- The network ----------------------------------------------------------------------
-- rednet, as far as these programs use it. A send reaches its computer at
-- once, and the answer waits in the sender's mailbox; a receive with nothing
-- there lets the time it would have waited go by.
local BANK_ID, POCKET_ID = bank.core_id, 100
local current = POCKET_ID
local mail, servers, lose = {}, {}, {}

local function deliver(to, from, message, protocol)
    mail[to] = mail[to] or {}
    table.insert(mail[to], { sender = from, message = message, protocol = protocol })
end

local function answer(request, ok, result)
    local reply = { version = 5, kind = "response", request_id = request.request_id }
    if ok then
        reply.ok, reply.data = true, result
    elseif type(result) == "table" and result.pumpe then
        reply.ok, reply.error, reply.code = false, result.message, result.code
    else
        error(result, 0)
    end
    return reply
end

local function bankAnswer(from, request)
    local spec = bank.core.routes[request.action]
    if spec then
        return answer(request, pcall(bank.core.route_to_vault, request.action, spec,
            request.payload or {}, from))
    end
    local handler = bank.core.actions[request.action]
    assert(handler, "no bank action " .. tostring(request.action))
    return answer(request, pcall(handler, request.payload or {}, from))
end

term = term or { current = function() return {} end }
peripheral = {
    getNames = function() return { "top" } end,
    getType = function() return "modem" end,
}
rednet = {
    isOpen = function() return true end,
    open = function() end, close = function() end,
    host = function() end, unhost = function() end,
    lookup = function(protocol)
        if protocol == config.protocol then return BANK_ID end
        return nil
    end,
    send = function(to, message, protocol)
        local from = current
        if (lose[to] or 0) > 0 then
            lose[to] = lose[to] - 1
            return true
        end
        if to == BANK_ID and protocol == config.protocol then
            deliver(from, BANK_ID, bankAnswer(from, message), protocol)
        elseif servers[to] and servers[to].up and protocol == config.cloud_protocol then
            current = to
            local handler = servers[to].program.actions[message.action]
            local reply = answer(message, pcall(handler, message.payload or {}, from))
            current = from
            deliver(from, to, reply, protocol)
        end
        return true
    end,
    receive = function(protocol, timeout)
        local box = mail[current] or {}
        for index, item in ipairs(box) do
            if protocol == nil or item.protocol == protocol then
                table.remove(box, index)
                return item.sender, item.message, item.protocol
            end
        end
        harness.epoch = harness.epoch + math.floor((timeout or 1) * 1000)
        return nil
    end,
}

local function as(computerId, fn, ...)
    local before = current
    current = computerId
    local results = table.pack(pcall(fn, ...))
    current = before
    if not results[1] then error(results[2], 0) end
    return table.unpack(results, 2, results.n)
end

-- Five Cloud Servers ----------------------------------------------------------------

local function loadServer(computerId, capacity)
    shell = { getRunningProgram = function()
        return "/cloud" .. computerId .. "/cloud_server.lua"
    end }
    disks["cloud" .. computerId] = { files = {}, dirs = {}, capacity = capacity }
    PUMPE_TEST_MODE = "cloud_server"
    local program = assert(loadfile("../cloud_server.lua"))()
    PUMPE_TEST_MODE = nil
    fs.makeDir(program.chunk_dir)
    servers[computerId] = { program = program, up = true }
    return program
end

rejected(bank.request, "BAD_CODE", "CLOUD_SERVER_REGISTER",
    { code = "0000", computer_id = 11 })
local ids = { 11, 12, 13, 14, 15 }
for _, id in ipairs(ids) do
    local program = loadServer(id, 60000)
    local registered = bank.request("CLOUD_SERVER_REGISTER",
        { code = "4040", name = "Cloud " .. id, computer_id = id })
    program.state.server_token = registered.server_token
    program.state.server_id = registered.server_id
end
local function beatAll()
    for _, id in ipairs(ids) do
        if servers[id].up then as(id, servers[id].program.beat) end
    end
end
local function held(id) return servers[id].program.held end
local function heldTotal()
    local count = 0
    for _, id in ipairs(ids) do count = count + held(id).count end
    return count
end

-- People ------------------------------------------------------------------------------

local ana = bank.register("Ana Fox", "1234")
local kit = bank.register("Kit Wolf", "5678")
bank.fund(ana, 3000)
bank.fund(kit, 1000)

local function asker(who, appId)
    return function(action, payload)
        local merged = bank.as(who, payload)
        merged.app_id = appId
        local ok, result = pcall(bank.request, action, merged)
        if ok then return result end
        if type(result) == "table" and result.pumpe then
            return nil, result.message, result.code
        end
        error(result, 0)
    end
end
local anaAsk, kitAsk = asker(ana), asker(kit)
local PROTOCOL = config.cloud_protocol

-- Bytes 0 to 255, over and over: a file only comes back right if nothing on
-- the way treats it as text.
local function binary(size, seed)
    local parts = {}
    for index = 1, size do parts[index] = string.char((index * 7 + seed) % 256) end
    return table.concat(parts)
end

-- No server has said it is up yet: nothing can be stored.
local _, _, offline = net.cloud.save(anaAsk, { name = "early.txt" }, "hello", PROTOCOL)
assert(offline == "CLOUD_OFFLINE", "no Cloud Server running, nothing stored")
beatAll()

-- Saving and opening --------------------------------------------------------------------

local song = binary(30000, 3)
local saved = net.cloud.save(anaAsk, { name = "Theme.mid" }, song, PROTOCOL)
assert(saved and saved.file.size == 30000 and saved.file.kind == "midi")
assert(saved.used == 30000 and saved.quota == config.cloud_free_bytes)
-- Five pieces of 6000, each on whichever server had the most room: all five.
for _, id in ipairs(ids) do
    assert(held(id).count == 1, "one piece on every server, not five on one")
end
local opened, file = net.cloud.load(anaAsk, saved.file.file_id, PROTOCOL)
assert(opened == song, "it comes back byte for byte")
assert(file.name == "Theme.mid")

local listed = anaAsk("CLOUD_FILES", {})
assert(#listed.files == 1 and listed.used == 30000)
assert(listed.quota == 100 * 1024 and listed.plan == "free")
assert(listed.servers == 5, "five Cloud Servers online")

-- An empty note is a file too.
local note = net.cloud.save(anaAsk, { name = "todo.txt" }, "", PROTOCOL)
assert(note and note.file.size == 0)
assert(net.cloud.load(anaAsk, note.file.file_id, PROTOCOL) == "")

-- Names are a person's own: Kit can have a Theme.mid too, Ana cannot have two.
local _, _, taken = net.cloud.save(anaAsk, { name = "theme.mid" }, "x", PROTOCOL)
assert(taken == "NAME_TAKEN")
local kitTheme = net.cloud.save(kitAsk, { name = "Theme.mid" }, "kit's", PROTOCOL)
assert(kitTheme)
local _, _, badName = net.cloud.save(anaAsk, { name = "../boot" }, "x", PROTOCOL)
assert(badName == "BAD_NAME")

-- The plan's room ---------------------------------------------------------------------------

local _, quotaError, full = net.cloud.save(anaAsk, { name = "big.txt" },
    string.rep("a", 80000), PROTOCOL)
assert(full == "CLOUD_QUOTA", "30 KB used, 80 KB more is over 100 KB")
assert(quotaError:find("FoxyCloud+", 1, true), "and says where there is more room")

-- Nobody else's ------------------------------------------------------------------------------

local stolen, _, stolenCode = net.cloud.load(kitAsk, saved.file.file_id, PROTOCOL)
assert(not stolen and stolenCode == "NOT_FOUND", "Kit cannot open Ana's file")
rejected(bank.request, "WRONG_APP", "CLOUD_FILES",
    bank.as(ana, { app_id = "YAP" }))
assert(asker(ana, "CLOUD")("CLOUD_FILES", {}), "FoxyCloud itself may ask")

-- Tickets: what each is for, on which server, and how big.
local plan = anaAsk("CLOUD_GET", { file_id = saved.file.file_id })
local first = plan.chunks[1]
local firstHost = plan.hosts[first.servers[1]]
local secondHost = plan.hosts[plan.chunks[2].servers[1]]
local function server(host, action, payload)
    return as(POCKET_ID, net.ask, host, PROTOCOL, action, payload, 3)
end
local _, _, wrongMode = server(firstHost, "CHUNK_PUT",
    { ticket = plan.ticket, chunk_id = first.id, data = "overwritten" })
assert(wrongMode == "BAD_TICKET", "a ticket to read is not a ticket to write")
local _, _, wrongServer = server(secondHost, "CHUNK_GET",
    { ticket = plan.ticket, chunk_id = first.id })
assert(wrongServer == "BAD_TICKET", "a piece is only on the servers it names")
local _, _, forged = server(firstHost, "CHUNK_GET",
    { ticket = "CT_MADEUP", chunk_id = first.id })
assert(forged == "BAD_TICKET", "the Bank never issued that one")
local _, _, notAPiece = server(firstHost, "CHUNK_GET",
    { ticket = plan.ticket, chunk_id = "../../startup.lua" })
assert(notAPiece == "BAD_CHUNK", "only piece names, never a path")

-- A put ticket names how big each piece may be, and the server holds it to that.
local upload = anaAsk("CLOUD_PUT", { name = "small.txt", size = 10 })
local piece = upload.chunks[1]
local _, _, tooBig = server(upload.hosts[piece.servers[1]], "CHUNK_PUT",
    { ticket = upload.ticket, chunk_id = piece.id, data = string.rep("z", 5000) })
assert(tooBig == "TOO_BIG", "a 10 byte ticket does not store 5000 bytes")
-- That upload is never finished. Past its ticket it is gone, and a sweep takes
-- whatever was stored for it.
assert(server(upload.hosts[piece.servers[1]], "CHUNK_PUT",
    { ticket = upload.ticket, chunk_id = piece.id, data = "0123456789" }))
local before = heldTotal()
bank.advanceMs(config.cloud_ticket_ms + 31000)
beatAll()
assert(#anaAsk("CLOUD_FILES", {}).files == 2, "the unfinished file is not a file")
for _, id in ipairs(ids) do as(id, servers[id].program.sweep) end
assert(heldTotal() == before - 1, "and its piece was swept off the server")

-- A lost message is asked for again ---------------------------------------------------------

lose[plan.hosts[first.servers[1]]] = 1
local again = net.cloud.load(anaAsk, saved.file.file_id, PROTOCOL)
assert(again == song, "one lost reply is retried, not a failed open")

-- Replacing and deleting ---------------------------------------------------------------------

local edited = binary(12000, 9)
local replaced = net.cloud.save(anaAsk, { file_id = saved.file.file_id }, edited,
    PROTOCOL)
assert(replaced.file.version == 2 and replaced.file.size == 12000)
assert(net.cloud.load(anaAsk, saved.file.file_id, PROTOCOL) == edited)
beatAll()
-- 2 pieces now, plus Kit's one, and the five old pieces gone from the disks.
assert(heldTotal() == 3, "the old version's pieces were thrown away: "
    .. heldTotal())
assert(anaAsk("CLOUD_FILES", {}).used == 12000)

assert(anaAsk("CLOUD_RENAME", { file_id = saved.file.file_id, name = "Theme 2.mid" }))
rejected(bank.request, "NAME_TAKEN", "CLOUD_RENAME",
    bank.as(ana, { file_id = saved.file.file_id, name = "todo.txt" }))

-- Sharing -------------------------------------------------------------------------------------

local shared = anaAsk("CLOUD_SHARE", { file_id = saved.file.file_id }).file
assert(type(shared.share) == "string" and #shared.share == 6)
local body, info = net.cloud.shared(kitAsk, string.lower(shared.share), PROTOCOL)
assert(body == edited and info.owner_name == "Ana Fox",
    "Kit opens it with the code, read-only")
-- Even with no session at all: a code is the whole permission.
local publicAsk = function(action, payload)
    local ok, result = pcall(bank.request, action, payload)
    if ok then return result end
    return nil, result.message, result.code
end
assert(net.cloud.shared(publicAsk, shared.share, PROTOCOL) == edited)
anaAsk("CLOUD_SHARE", { file_id = saved.file.file_id, share = false })
local _, _, unshared = net.cloud.shared(kitAsk, shared.share, PROTOCOL)
assert(unshared == "NOT_FOUND", "taking the share away stops the code")

assert(anaAsk("CLOUD_DELETE", { file_id = saved.file.file_id }).used == 0)
beatAll()
assert(heldTotal() == 1, "only Kit's file is left on the servers")
local _, _, deleted = net.cloud.load(anaAsk, saved.file.file_id, PROTOCOL)
assert(deleted == "NOT_FOUND")

-- FoxyCloud+ -----------------------------------------------------------------------------------

local free = anaAsk("CLOUD_PLAN", {})
assert(free.plan == "free" and free.price == 500 and free.every_days == 5)
assert(free.cash_fee_rate == 0.02)
bank.request("FRIEND_REQUEST", bank.as(ana, { name = "Kit Wolf" }))
bank.request("FRIEND_REQUEST", bank.as(kit, { name = "Ana Fox" }))
local function cashFee()
    return bank.request("FOXY_CASH_QUOTE", bank.as(ana, { account_id = kit.id,
        amount = 100 })).fee
end
assert(cashFee() == 2, "two percent on the free plan")
rejected(bank.request, "BAD_PIN", "CLOUD_PLUS_JOIN", bank.as(ana, { pin = "0000" }))
rejected(bank.request, "WRONG_APP", "CLOUD_PLUS_JOIN",
    bank.as(ana, { pin = "1234", app_id = "YAP" }))
local balance = bank.balanceOf(ana)
local joined = bank.request("CLOUD_PLUS_JOIN", bank.as(ana, { pin = "1234" }))
assert(joined.plan == "plus" and joined.quota == 500 * 1024)
assert(bank.balanceOf(ana) == balance - 500, "the first five days, paid now")
assert(joined.cash_fee_rate == 0, "no Foxy Cash fee with FoxyCloud+")
assert(cashFee() == 0, "and the quote says so")
local kitBefore, anaBefore = bank.balanceOf(kit), bank.balanceOf(ana)
local sent = bank.request("FOXY_CASH_SEND", bank.as(ana, { account_id = kit.id,
    amount = 100, pin = "1234" }))
assert(sent.fee == 0 and bank.balanceOf(ana) == anaBefore - 100
    and bank.balanceOf(kit) == kitBefore + 100, "a hundred sent costs a hundred")
assert(bank.state.foxycloud_revenue == 500)
rejected(bank.request, "ALREADY_PLUS", "CLOUD_PLUS_JOIN", bank.as(ana, { pin = "1234" }))
local today = util.ingameDay()
assert(joined.next_charge_day == today + 5)

-- The room is the plan's: 80 KB that did not fit now does.
local bigger = net.cloud.save(anaAsk, { name = "big.txt" }, string.rep("a", 80000),
    PROTOCOL)
assert(bigger and bigger.quota == 500 * 1024, "80 KB fits in 500 KB")

-- It is with the rest of the subscriptions, billed every five days.
local function plusRow(who)
    for _, row in ipairs(bank.request("LIST_SUBSCRIPTIONS", bank.as(who)).subscriptions) do
        if row.subscription_id == "FOXYCLOUD_PLUS" then return row end
    end
end
local row = plusRow(ana)
assert(row and row.amount == 500 and row.every_days == 5 and row.active)

-- Four days on, nothing. The fifth, five hundred.
balance = bank.balanceOf(ana)
for _ = 1, 4 do
    bank.advanceDays(1)
    bank.process_subscriptions()
end
assert(bank.balanceOf(ana) == balance, "not charged before its five days are up")
bank.advanceDays(1)
bank.process_subscriptions()
assert(bank.balanceOf(ana) == balance - 500, "charged on the fifth day")
assert(plusRow(ana).next_charge_day == util.ingameDay() + 5)

-- Cancelled: it runs to the end of what was paid for, then ends with no charge.
bank.request("CANCEL_SUBSCRIPTION", bank.as(ana, { subscription_id = "FOXYCLOUD_PLUS" }))
local cancelled = anaAsk("CLOUD_PLAN", {})
assert(cancelled.plan == "plus" and cancelled.ends_day == util.ingameDay() + 5,
    "still Plus until the day it would have renewed")
balance = bank.balanceOf(ana)
bank.advanceDays(5)
bank.process_subscriptions()
assert(bank.balanceOf(ana) == balance, "a cancelled plan is not charged again")
local ended = anaAsk("CLOUD_PLAN", {})
assert(ended.plan == "free" and ended.quota == 100 * 1024)
assert(not plusRow(ana), "and it is gone from the subscriptions")

-- The files stay, though they are over the free room; nothing new fits.
local after = anaAsk("CLOUD_FILES", {})
assert(after.used == 80000 + 0 and #after.files == 2, "nothing was deleted")
local _, _, over = net.cloud.save(anaAsk, { name = "more.txt" }, string.rep("b", 30000),
    PROTOCOL)
assert(over == "CLOUD_QUOTA")
assert(net.cloud.load(anaAsk, bigger.file.file_id, PROTOCOL) == string.rep("a", 80000),
    "and every file still opens")

-- A plan that cannot be paid for stops, rather than running up a debt.
bank.request("CLOUD_PLUS_JOIN", bank.as(kit, { pin = "5678" }))
bank.state.accounts[kit.id].balance = 100
bank.advanceDays(5)
bank.process_subscriptions()
assert(bank.balanceOf(kit) == 100, "it does not take what is not there")
assert(kitAsk("CLOUD_PLAN", {}).plan == "free")

-- Two copies of every piece -----------------------------------------------------------------

bank.vault.cloud.copies = 2
local precious = binary(7000, 1)
local twice = net.cloud.save(kitAsk, { name = "precious.mid" }, precious, PROTOCOL)
local twicePlan = kitAsk("CLOUD_GET", { file_id = twice.file.file_id })
for _, chunk in ipairs(twicePlan.chunks) do
    assert(#chunk.servers == 2 and chunk.servers[1] ~= chunk.servers[2],
        "each piece on two different servers")
end
-- One of them goes down. The file still opens from the other copy.
local downHost = twicePlan.hosts[twicePlan.chunks[1].servers[1]]
servers[downHost].up = false
assert(net.cloud.load(kitAsk, twice.file.file_id, PROTOCOL) == precious,
    "a server down costs nothing while a copy is up")
servers[downHost].up = true
-- A piece that comes back short is a damaged copy: the whole one is used.
local function disk(host, chunkId)
    return disks["cloud" .. host].files["cloud" .. host .. "/cloud/" .. chunkId]
end
local firstId = twicePlan.chunks[1].id
assert(disk(downHost, firstId), "the piece is on that server's disk")
disks["cloud" .. downHost].files["cloud" .. downHost .. "/cloud/" .. firstId] = "short"
assert(net.cloud.load(kitAsk, twice.file.file_id, PROTOCOL) == precious,
    "a damaged copy is passed over for a whole one")
-- With one copy there is nothing to pass over to: it says so, rather than
-- handing back a broken file.
local kitPlan = kitAsk("CLOUD_GET", { file_id = kitTheme.file.file_id })
local kitHost = kitPlan.hosts[kitPlan.chunks[1].servers[1]]
disks["cloud" .. kitHost].files["cloud" .. kitHost .. "/cloud/" .. kitPlan.chunks[1].id] = "k"
local broken, _, damaged = net.cloud.load(kitAsk, kitTheme.file.file_id, PROTOCOL)
assert(not broken and damaged == "CLOUD_DAMAGED", "a short piece is not a file")
bank.vault.cloud.copies = 1

-- Full ------------------------------------------------------------------------------------------
-- Every server says it is nearly full: a file that does not fit anywhere is
-- refused before a byte is sent.
for _, id in ipairs(ids) do disks["cloud" .. id].capacity = 22000 end
beatAll()
bank.request("CLOUD_PLUS_JOIN", bank.as(ana, { pin = "1234" }))
local _, _, noRoom = net.cloud.save(anaAsk, { name = "huge.txt" },
    string.rep("c", 60000), PROTOCOL)
assert(noRoom == "CLOUD_FULL", "the Cloud Servers are full")

-- A server the Bank stops knowing ------------------------------------------------------------

local lost = servers[15].program
lost.state.server_token = "CLOUD_FORGOTTEN"
assert(not as(15, lost.beat), "an unknown server is refused")
assert(lost.state.server_token == nil, "and knows to register again")

print("host_foxycloud_test: OK")
