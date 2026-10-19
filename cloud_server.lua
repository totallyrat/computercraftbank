local ROOT = fs.getDir(shell.getRunningProgram())
if ROOT == "" then ROOT = "." end
package.path = package.path .. ";" .. fs.combine(ROOT, "?.lua")
    .. ";" .. fs.combine(ROOT, "?/init.lua")

-- Stamped by tools/build_release_manifest.js. A program running beside a
-- config.lua from a different release means a partial install.
local PROGRAM_VERSION = "18.0.0"
local config = require("config")
local util = require("lib.util")
local net = require("lib.net")
local ui = require("lib.ui")

-- A Cloud Server, FoxyOS 16.3. It holds pieces of FoxyCloud files, and that is
-- all: it does not know whose they are, what they are called, or which other
-- servers hold the rest. The Bank's Vault keeps that directory and decides
-- where each piece goes -- to whichever server has the most room -- so a
-- world that runs five or more of these has five or more servers' worth of
-- storage, not one.
--
-- Nothing is stored or handed out without a ticket from the Bank. The first
-- time a ticket is shown here, the Bank is asked what it allows: which pieces,
-- and how big each may be. A Pocket cannot use one to put more here than its
-- plan has room for, or to read a piece of somebody else's file.
local target = term.current()
local bank = net.client(config)
local running = true
local PROTOCOL = config.cloud_protocol or "PUMPE_CLOUD_V1"
local dataFile = fs.combine(ROOT, "cloud_server_v1.dat")
local chunkDir = fs.combine(ROOT, "cloud")
local activity = {}
local state = util.loadTable(dataFile, {})

-- What this server keeps to itself on its disk, beyond what the Bank keeps.
local KEEP_FREE = 4096
local BEAT_SECONDS = 10
local SWEEP_SECONDS = 10 * 60

-- Tickets the Bank has answered for, until they run out. Never written down.
local tickets = {}
local held = { count = 0, bytes = 0 }
local status = { beat = "Not yet", beat_color = colors.lightGray,
    stored = 0, served = 0, dropped = 0 }

local function logActivity(text, color)
    table.insert(activity, 1, {
        text = util.safeText(text, 42),
        color = color or colors.lightGray,
        time = util.formatClock(),
    })
    while #activity > 16 do table.remove(activity) end
end

local function save()
    util.saveTable(dataFile, state)
end

local function reject(code, message)
    error({ pumpe = true, code = code, message = message }, 0)
end

local function need(condition, code, message)
    if not condition then reject(code, message) end
end

-- A piece is named <file>.<version>.<piece>, the way the Vault names it, and
-- nothing else is ever written here. FoxyOS 18: or M<server>T<track>.<version>.
-- <piece>, a piece of a song the Music Server put here itself.
local function musicId(chunkId)
    return type(chunkId) == "string" and chunkId:match("^M%d+T%d+%.%d+%.%d+$") ~= nil
end

local function validId(chunkId)
    return type(chunkId) == "string"
        and (chunkId:match("^F%d+%.%d+%.%d+$") ~= nil or musicId(chunkId))
end

-- FoxyOS 18: which computer each Music Server is, as the Bank last said.
-- Kept on disk, so songs keep playing while the Bank is away: the Music
-- Server vouches for its own tickets, and only the computer the Bank named
-- is believed.
state.music_servers = type(state.music_servers) == "table" and state.music_servers or {}

local function musicServerFor(chunkId)
    local number = tostring(chunkId):match("^M(%d+)T")
    return number and tonumber(state.music_servers["MS" .. number])
end

local function chunkPath(chunkId)
    return fs.combine(chunkDir, chunkId)
end

local function freeSpace()
    local ok, free = pcall(fs.getFreeSpace, chunkDir)
    return ok and tonumber(free) or 0
end

-- FoxyOS 16.3.1: the room this server keeps for updating itself -- a staged
-- copy of its own programs, and a little over. Pieces never take it, and the
-- Bank is told the room it has without it. A Cloud Server filled to the last
-- few kilobytes could never update again, not even to the fix for that.
local function updateRoom()
    local okLib, update = pcall(require, "lib.update")
    local total = 16 * 1024
    if okLib and type(update) == "table" and update.rolePaths then
        for _, path in ipairs(update.rolePaths("cloud") or {}) do
            local installed = fs.combine(ROOT, update.installPath
                and update.installPath(path) or path)
            if fs.exists(installed) then total = total + (fs.getSize(installed) or 0) end
        end
    end
    return total
end

-- Counted once at start and on every sweep, and kept up to date in between.
local function countHeld()
    held.count, held.bytes = 0, 0
    if not fs.exists(chunkDir) then return held end
    for _, name in ipairs(fs.list(chunkDir)) do
        held.count = held.count + 1
        held.bytes = held.bytes + (fs.getSize(chunkPath(name)) or 0)
    end
    return held
end

local function dropChunk(chunkId)
    if not validId(chunkId) then return false end
    local path = chunkPath(chunkId)
    if not fs.exists(path) then return false end
    held.count = math.max(0, held.count - 1)
    held.bytes = math.max(0, held.bytes - (fs.getSize(path) or 0))
    pcall(fs.delete, path)
    status.dropped = status.dropped + 1
    return true
end

-- What a ticket allows here, asked of the Bank the first time it is shown.
local function allowed(ticket, chunkId, mode)
    need(type(ticket) == "string" and #ticket > 0, "BAD_TICKET", "No ticket")
    need(validId(chunkId), "BAD_CHUNK", "That is not a piece of a file")
    local now = util.nowMs()
    local known = tickets[ticket]
    if not known or known.expires_at <= now then
        tickets[ticket] = nil
        local answer, err, code
        if musicId(chunkId) then
            -- A song's piece: its Music Server says what the ticket allows.
            local host = musicServerFor(chunkId)
            need(host, "BAD_TICKET", "This Cloud Server does not know that Music Server yet")
            answer, err, code = net.ask(host, config.music_protocol or "PUMPE_MUSIC_V1",
                "MUSIC_TICKET", { ticket = ticket }, 3)
            need(answer, code or "MUSIC_OFFLINE", err or "The Music Server did not answer")
        else
            answer, err, code = bank:request("CLOUD_TICKET", {
                server_token = state.server_token, ticket = ticket }, 4)
            need(answer, code or "BANK_OFFLINE", err or "The Bank did not answer")
        end
        local chunks = type(answer.chunks) == "table" and answer.chunks or {}
        if musicId(chunkId) then
            -- A Music Server answers for its own songs' pieces and nothing else.
            local own = {}
            for id, size in pairs(chunks) do
                if musicId(id) and musicServerFor(id) == musicServerFor(chunkId) then
                    own[id] = size
                end
            end
            chunks = own
        end
        known = { mode = answer.mode, chunks = chunks,
            expires_at = now + math.max(1000, tonumber(answer.ttl_ms) or 60000) }
        tickets[ticket] = known
    end
    need(known.mode == mode, "BAD_TICKET", "That ticket is not for this")
    local size = tonumber(known.chunks[chunkId])
    need(size, "BAD_TICKET", "That piece is not on this ticket")
    return size
end

local actions = {}

function actions.CHUNK_PUT(payload)
    local size = allowed(payload.ticket, payload.chunk_id, "put")
    local data = payload.data
    need(type(data) == "string", "BAD_DATA", "Nothing to store")
    need(#data <= size, "TOO_BIG", "That piece is bigger than its ticket")
    local path = chunkPath(payload.chunk_id)
    local before = fs.exists(path) and (fs.getSize(path) or 0) or nil
    need(freeSpace() - math.max(#data, 500) >= KEEP_FREE + updateRoom(), "CLOUD_SERVER_FULL",
        "This Cloud Server is full")
    -- Binary: a MIDI file is bytes, not text, and must come back as it went.
    local file = fs.open(path, "wb")
    need(file, "CLOUD_SERVER_FULL", "This Cloud Server could not write")
    file.write(data)
    file.close()
    if before then
        held.bytes = held.bytes - before
    else
        held.count = held.count + 1
    end
    held.bytes = held.bytes + #data
    status.stored = status.stored + 1
    return { stored = payload.chunk_id, size = #data }
end

function actions.CHUNK_GET(payload)
    allowed(payload.ticket, payload.chunk_id, "get")
    local path = chunkPath(payload.chunk_id)
    need(fs.exists(path), "MISSING", "This Cloud Server does not have that piece")
    local file = fs.open(path, "rb")
    local data = file and file.readAll() or nil
    if file then file.close() end
    need(data, "MISSING", "That piece could not be read")
    status.served = status.served + 1
    return { chunk_id = payload.chunk_id, data = data }
end

-- FoxyOS 18: a Music Server taking back a piece of a song it deleted.
function actions.CHUNK_DROP(payload)
    allowed(payload.ticket, payload.chunk_id, "drop")
    need(musicId(payload.chunk_id), "BAD_CHUNK", "Only a song's pieces are dropped this way")
    return { dropped = dropChunk(payload.chunk_id) }
end

-- Anyone may ask whether this server is up and how full it is.
function actions.CLOUD_PING()
    return { server_id = state.server_id, name = state.name,
        free = math.max(0, freeSpace() - updateRoom()),
        chunks = held.count, used = held.bytes, version = PROGRAM_VERSION }
end

local function route(sender, message)
    if type(message) ~= "table" or message.kind ~= "request"
        or type(message.action) ~= "string" then return end
    local handler = actions[message.action]
    if not handler then
        net.reply(sender, PROTOCOL, message.request_id, false, nil,
            "Unknown cloud action", "UNKNOWN_ACTION")
        return
    end
    local ok, result = pcall(handler, message.payload or {}, sender)
    if ok then
        net.reply(sender, PROTOCOL, message.request_id, true, result)
    elseif type(result) == "table" and result.pumpe then
        net.reply(sender, PROTOCOL, message.request_id, false, nil,
            result.message, result.code)
    else
        logActivity("Error: " .. tostring(result), colors.red)
        net.reply(sender, PROTOCOL, message.request_id, false, nil,
            "Cloud Server error", "SERVER_ERROR")
    end
end

-- Telling the Bank how much room is left, and taking back the pieces of
-- files that were deleted or replaced. A Bank that no longer knows this
-- server -- its Vault's directory was lost -- means registering again.
local function beat()
    local answer, err, code = bank:request("CLOUD_BEAT", {
        server_token = state.server_token,
        free = math.max(0, freeSpace() - updateRoom()),
        used = held.bytes, chunks = held.count, version = PROGRAM_VERSION }, 4)
    if not answer then
        status.beat, status.beat_color = tostring(err or "No answer"), colors.red
        if code == "CLOUD_AUTH" then
            logActivity("The Bank no longer knows this server", colors.red)
            state.server_token, state.server_id = nil, nil
            save()
        end
        return false
    end
    if answer.server_id and answer.server_id ~= state.server_id then
        state.server_id = answer.server_id
        save()
    end
    state.name = answer.name or state.name
    -- FoxyOS 18: the Music Servers, by computer, kept for when the Bank is not.
    if type(answer.music_servers) == "table" then
        local known, changed = {}, false
        for serverId, computerId in pairs(answer.music_servers) do
            if type(serverId) == "string" and tonumber(computerId) then
                known[serverId] = tonumber(computerId)
                if state.music_servers[serverId] ~= known[serverId] then changed = true end
            end
        end
        for serverId in pairs(state.music_servers) do
            if not known[serverId] then changed = true end
        end
        if changed then
            state.music_servers = known
            save()
        end
    end
    local dropped = 0
    for _, chunkId in ipairs(answer.drop or {}) do
        if dropChunk(chunkId) then dropped = dropped + 1 end
    end
    if dropped > 0 then
        logActivity("Threw away " .. dropped .. " old piece"
            .. (dropped == 1 and "" or "s"), colors.orange)
    end
    status.beat, status.beat_color = "OK at " .. util.formatClock(), colors.lime
    return true
end

-- Every so often, everything held here is shown to the Bank a page at a time,
-- and whatever no file has any more -- an upload that never finished, a
-- delete missed while this was off -- goes.
local function sweep()
    if not fs.exists(chunkDir) then return 0 end
    local files, songs, dropped = {}, {}, 0
    -- FoxyOS 18: FoxyCloud's pieces are the Bank's to judge, a song's its
    -- Music Server's.
    for _, name in ipairs(fs.list(chunkDir)) do
        if musicId(name) then
            local host = musicServerFor(name)
            if host then
                songs[host] = songs[host] or {}
                table.insert(songs[host], name)
            end
        else
            files[#files + 1] = name
        end
    end
    local function ask(names, send)
        for first = 1, #names, 100 do
            local page = {}
            for index = first, math.min(#names, first + 99) do
                page[#page + 1] = names[index]
            end
            local answer = send(page)
            if not answer then return end
            for _, chunkId in ipairs(answer.drop or {}) do
                if dropChunk(chunkId) then dropped = dropped + 1 end
            end
        end
    end
    ask(files, function(page)
        return bank:request("CLOUD_KEEP", { server_token = state.server_token, chunks = page }, 6)
    end)
    for host, names in pairs(songs) do
        ask(names, function(page)
            return net.ask(host, config.music_protocol or "PUMPE_MUSIC_V1", "MUSIC_KEEP",
                { chunks = page }, 4)
        end)
    end
    countHeld()
    if dropped > 0 then
        logActivity("Sweep threw away " .. dropped .. " stray piece"
            .. (dropped == 1 and "" or "s"), colors.orange)
    end
    return dropped
end

local function serverLoop()
    while running do
        local sender, message = rednet.receive(PROTOCOL, 2)
        if sender then route(sender, message) end
    end
end

local function bankLoop()
    local nextSweep = util.nowMs() + 60 * 1000
    while running do
        if state.server_token then
            beat()
            if state.server_token and util.nowMs() >= nextSweep then
                nextSweep = util.nowMs() + SWEEP_SECONDS * 1000
                pcall(sweep)
            end
            -- Tickets the Bank has answered for, once they have run out.
            local now = util.nowMs()
            for ticket, known in pairs(tickets) do
                if known.expires_at <= now then tickets[ticket] = nil end
            end
        end
        sleep(BEAT_SECONDS)
    end
end

local function updateLoop()
    while running do
        net.autoUpdate(config, "cloud", ROOT, nil,
            { programVersion = PROGRAM_VERSION })
        sleep(10)
    end
end

local function dashboardLoop()
    ui.serverTabs({
        version = config.version,
        target = target, title = "CLOUD SERVER", subtitle = "v" .. config.version,
        cards = function()
            return { { "PIECES", held.count, ui.theme.accent },
                { "USED", util.sizeText(held.bytes), colors.magenta },
                { "FREE", util.sizeText(math.max(0, freeSpace() - updateRoom())),
                    ui.theme.success } }
        end,
        lines = function()
            return {
                { "SERVER  " .. tostring(state.server_id or "Not registered")
                    .. (state.name and ("  " .. state.name) or "") },
                { "BANK  " .. status.beat, status.beat_color },
                { "STORED " .. status.stored .. "  SERVED " .. status.served
                    .. "  THROWN " .. status.dropped, ui.theme.muted },
            }
        end,
        activity = activity, root = ROOT, colorTitle = "Server colour",
        actions = { { id = "stop", label = "STOP",
            hint = "Files with pieces here cannot be opened",
            color = ui.theme.danger, run = function(terminated)
                if terminated or ui.confirm(target, "STOP CLOUD SERVER",
                    "FoxyCloud files with pieces here will not open.", "STOP",
                    "BACK") then
                    running = false
                    save()
                    return true
                end
            end } },
        running = function() return running end,
    })
end

-- Registering with the Bank once, with the operator's code: everybody's files
-- are about to be kept here, so this has to be the operator's own machine.
local function register()
    while running and not state.server_token do
        if not bank:discover() then
            ui.message(target, "error", "BANK OFFLINE",
                "Start the Bank Server and check the modem", 2)
        else
            local code = ui.input(target, "OPERATOR CODE", {
                hint = "The same code that installs a Bank Server",
                mode = "number", maxLength = 8,
            })
            if not code then return false end
            local registered, err = bank:request("CLOUD_SERVER_REGISTER",
                { code = code, name = "Cloud " .. os.getComputerID() }, 6)
            if registered then
                state.server_token = registered.server_token
                state.server_id = registered.server_id
                save()
                logActivity("Registered as " .. tostring(registered.server_id),
                    colors.lime)
            else
                ui.message(target, "error", "NOT REGISTERED", err, 2)
            end
        end
    end
    return state.server_token ~= nil
end

if rawget(_G, "PUMPE_TEST_MODE") == "cloud_server" then
    return { actions = actions, state = state, tickets = tickets, held = held,
        beat = beat, sweep = sweep, count = countHeld, register = register,
        chunk_dir = chunkDir, update_room = updateRoom }
end

if type(ui.useMainColor) == "function" then ui.useMainColor(ROOT) end
ui.usePhoneStyle(false)
ui.boot(target, "CLOUD SERVER", (ui.osLabel and ui.osLabel(config) or "FoxyOS"))
net.autoUpdate(config, "cloud", ROOT, nil,
    { force = true, programVersion = PROGRAM_VERSION })
net.openModems()
if not fs.exists(chunkDir) then fs.makeDir(chunkDir) end
countHeld()

if not register() then
    ui.clear(target)
    print("Cloud Server not registered.")
    return
end

net.host(PROTOCOL, "CLOUD_" .. os.getComputerID())
logActivity("Cloud Server online on #" .. os.getComputerID(), colors.lime)
beat()

parallel.waitForAny(serverLoop, bankLoop, updateLoop, dashboardLoop)
pcall(rednet.unhost, PROTOCOL)
save()
ui.clear(target)
print("Cloud Server stopped safely.")
