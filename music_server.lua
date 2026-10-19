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
local music = require("lib.music")

-- The Music Server, FoxyOS 17. It keeps the Music Library -- every song,
-- with who uploaded it -- and runs the radios. The songs themselves are on
-- the Cloud Servers, so a library is as big as the world's Cloud Servers make
-- it, not one computer's disk.
--
-- FoxyOS 18: it works without the Bank. It puts songs on the Cloud Servers
-- itself and hands out the tickets to read them, counts each listener's day
-- itself, and keeps what the Bank last said about their plan. The Bank is
-- needed to register once, to sign a Music Player in, and for what is the
-- Bank's: phone numbers and giveaways.
--
-- A radio is live: a timeline of songs, hosts talking between them, ads and
-- now and then a giveaway, worked out here as it goes, and every listener
-- hears the same thing at the same moment. A giveaway opens at the Bank,
-- whose phone numbers they are: listeners call the radio's number, and one
-- of them wins.
--
-- Music Players sign in once and are then told what to play; the Music app on
-- a Pocket tells this server what each of its owner's players should play.
-- How many songs a day somebody plays from the library, and uploads, is
-- counted here against their plan -- radios are free.
local target = term.current()
local bank = net.client(config)
local running = true
local PROTOCOL = config.music_protocol or "PUMPE_MUSIC_V1"
local CLOUD = config.cloud_protocol or "PUMPE_CLOUD_V1"
local dataFile = fs.combine(ROOT, "music_server_v1.dat")
local activity = {}
local state = util.loadTable(dataFile, {})
state.tracks = state.tracks or {}
state.radios = state.radios or {}
state.players = state.players or {}
state.grants = state.grants or {}
state.seq = state.seq or { track = 0, radio = 0, player = 0, upload = 0 }
-- FoxyOS 18: listeners' plans as the Bank last said, and their day here.
state.entitled = state.entitled or {}
state.usage = state.usage or {}
state.drops = state.drops or {}

-- Never written down: what a radio is playing is worked out again on start,
-- and a session, a plan or an upload outlives nothing.
local live = {}
local cache = { sessions = {}, plans = {}, uploads = {} }
local status = { bank = "Not yet", bank_color = colors.lightGray, streams = 0,
    bank_seen = 0, bank_quiet_until = 0 }

-- How often, out of a hundred breaks, a radio starts a special on its own.
local SPECIAL_CHANCE = 8
local SPECIALS = {
    nonstop = "20 MINUTE NON-STOP",
    double = "DOUBLE PLAY",
    throwback = "THROWBACK",
}

local function logActivity(text, color)
    table.insert(activity, 1, {
        text = util.safeText(text, 46),
        color = color or colors.lightGray,
        time = util.formatClock(),
    })
    while #activity > 20 do table.remove(activity) end
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

-- The Bank, as this server: every errand carries its registration. FoxyOS
-- 18: a Bank that did not answer is not asked again for half a minute, so a
-- request here never waits on it over and over -- what was kept is used.
local function bankAsk(action, payload, timeout)
    payload = payload or {}
    payload.server_token = state.server_token
    if util.nowMs() < status.bank_quiet_until then
        return nil, "The Bank is not answering", nil
    end
    local answer, err, code = bank:request(action, payload, timeout or 5)
    if answer or code then
        status.bank_seen, status.bank_down = util.nowMs(), false
        status.bank, status.bank_color = "OK at " .. util.formatClock(), colors.lime
    else
        status.bank_down = true
        status.bank_quiet_until = util.nowMs() + 30 * 1000
        status.bank, status.bank_color = tostring(err or "No answer"), colors.red
    end
    return answer, err, code
end

-- Whether the Bank answered lately, and not since stopped: giveaways need it.
local function bankUp()
    return not status.bank_down and util.nowMs() - status.bank_seen < 2 * 60 * 1000
end

local function nextId(kind, prefix)
    state.seq[kind] = (state.seq[kind] or 0) + 1
    return prefix .. state.seq[kind]
end

-- The Cloud Servers, FoxyOS 18 -------------------------------------------------------
-- The Music Server finds the Cloud Servers on the network, puts each piece of
-- a song on whichever has the most room, and hands out the tickets to read
-- them. A Cloud Server checks a song's ticket with this server -- believing
-- only the computer the Bank named as the Music Server -- so nothing here
-- waits on the Bank. Songs from FoxyOS 17, which the Bank's Vault keeps,
-- still play through the Bank, and move here one at a time while it answers.

local store = { tickets = {}, servers = {}, checked_at = 0,
    chunk = math.max(512, math.floor(tonumber(config.cloud_chunk_size) or 16384)),
    copies = math.max(1, math.floor(tonumber(config.cloud_copies) or 1)),
    reserve = tonumber(config.cloud_server_reserve_bytes) or 20000 }

-- This server's number, as its songs' pieces are named: M<number>T<track>...
function store.number()
    return tonumber(tostring(state.server_id or ""):match("%d+")) or 0
end

function store.pieceId(trackId, version, index)
    return "M" .. store.number() .. "T" .. tostring(trackId):gsub("%D", "") .. "."
        .. version .. "." .. index
end

-- Which Cloud Servers answer, and how much room each has. Asked from the
-- background, never while a request waits.
function store.refresh()
    local found = {}
    for _, id in ipairs({ rednet.lookup(CLOUD) }) do
        local ping = net.ask(id, CLOUD, "CLOUD_PING", {}, 2)
        if ping and tonumber(ping.free) then
            found[#found + 1] = { computer_id = id, free = tonumber(ping.free),
                name = ping.name, server_id = ping.server_id }
        end
    end
    store.servers, store.checked_at = found, util.nowMs()
    return found
end

-- Where each piece goes: on the servers with the most room, a different one
-- for each copy, the room counted down as it is handed out.
function store.place(trackId, version, size)
    local servers = {}
    for _, server in ipairs(store.servers) do
        servers[#servers + 1] = server
    end
    need(#servers > 0, "CLOUD_OFFLINE", "No Cloud Server is answering")
    local copies = math.min(#servers, store.copies)
    local pieces, left, index = {}, size, 0
    while left > 0 do
        index = index + 1
        local pieceSize = math.min(store.chunk, left)
        table.sort(servers, function(a, b) return a.free > b.free end)
        local hosts = {}
        for copy = 1, copies do
            local server = servers[copy]
            need(server.free - store.reserve >= math.max(pieceSize, 500), "CLOUD_FULL",
                "The Cloud Servers are full")
            server.free = server.free - math.max(pieceSize, 500)
            hosts[copy] = server.computer_id
        end
        pieces[index] = { id = store.pieceId(trackId, version, index), size = pieceSize,
            hosts = hosts }
        left = left - pieceSize
    end
    return pieces
end

-- A ticket for pieces, and the plan a Pocket, a player or this server uses
-- to move them (the shape net.cloud.put and net.cloud.get take).
function store.plan(mode, pieces, ttl)
    local token = util.token("MT")
    local chunks, hosts, allowed = {}, {}, {}
    for index, piece in ipairs(pieces) do
        local servers = {}
        for _, id in ipairs(piece.hosts) do
            servers[#servers + 1] = "C" .. id
            hosts["C" .. id] = id
        end
        chunks[index] = { id = piece.id, size = piece.size, servers = servers }
        allowed[piece.id] = { size = piece.size, hosts = piece.hosts }
    end
    store.tickets[token] = { mode = mode, chunks = allowed,
        expires_at = util.nowMs() + ttl }
    return { ticket = token, chunks = chunks, hosts = hosts, expires_in_ms = ttl,
        chunk_size = store.chunk }
end

function store.size(pieces)
    local total = 0
    for _, piece in ipairs(pieces or {}) do total = total + piece.size end
    return total
end

-- Pieces nobody wants any more, taken back from their Cloud Servers from the
-- background. A server that is off is asked by its own sweep instead.
function store.forget(pieces)
    for _, piece in ipairs(pieces or {}) do
        for _, host in ipairs(piece.hosts) do
            state.drops[#state.drops + 1] = { id = piece.id, host = host, size = piece.size }
        end
    end
end

function store.dropPending()
    if #state.drops == 0 then return 0 end
    local batch = {}
    while #state.drops > 0 and #batch < 40 do batch[#batch + 1] = table.remove(state.drops, 1) end
    local pieces = {}
    for _, drop in ipairs(batch) do
        pieces[#pieces + 1] = { id = drop.id, size = drop.size or 1, hosts = { drop.host } }
    end
    local plan = store.plan("drop", pieces, 60 * 1000)
    local dropped = 0
    for _, drop in ipairs(batch) do
        if net.ask(drop.host, CLOUD, "CHUNK_DROP", { ticket = plan.ticket, chunk_id = drop.id }, 2) then
            dropped = dropped + 1
        end
    end
    store.tickets[plan.ticket] = nil
    save()
    return dropped
end

-- Every piece this server wants kept: its songs', and uploads under way.
function store.wanted()
    local wanted = {}
    for _, track in pairs(state.tracks) do
        for _, piece in ipairs(track.pieces or {}) do wanted[piece.id] = true end
    end
    for _, upload in pairs(cache.uploads) do
        for _, piece in ipairs(upload.pieces or {}) do wanted[piece.id] = true end
    end
    return wanted
end

-- The library ------------------------------------------------------------------------

local library = {}

function library.public(track)
    if not track then return nil end
    return {
        track_id = track.track_id, title = track.title, artist = track.artist,
        kind = track.kind, length_ms = music.lengthMs(track.size), size = track.size,
        uploader_name = track.uploader_name, added_day = track.added_day,
        plays = track.plays or 0,
    }
end

-- Oldest first: T1 before T2 before T10.
function library.order(a, b)
    return (tonumber(a:match("%d+")) or 0) < (tonumber(b:match("%d+")) or 0)
end

function library.list(kind, query)
    local wanted = util.normalName(query or "")
    local list = {}
    for id, track in pairs(state.tracks) do
        local hay = string.lower(tostring(track.title) .. " " .. tostring(track.artist)
            .. " " .. tostring(track.uploader_name))
        if (not kind or kind == "all" or track.kind == kind)
            and (wanted == "" or hay:find(wanted, 1, true)) then
            list[#list + 1] = id
        end
    end
    table.sort(list, library.order)
    return list
end

function library.bytes()
    local total = 0
    for _, track in pairs(state.tracks) do total = total + (track.size or 0) end
    return total
end

function library.clean(value, most, fallback)
    local text = util.safeText(util.trim(tostring(value or "")), most)
    return text ~= "" and text or fallback
end

-- A finished upload becomes a track: credited to whoever sent it.
function library.add(fields)
    local id = fields.track_id or nextId("track", "T")
    state.tracks[id] = {
        track_id = id, file_id = fields.file_id, size = fields.size,
        pieces = fields.pieces, version = fields.pieces and 1 or nil,
        title = library.clean(fields.title, 28, "Untitled"),
        artist = library.clean(fields.artist, 20, "Unknown"),
        kind = music.KIND_NAMES[fields.kind or ""] and fields.kind or "song",
        uploader_id = fields.uploader_id,
        uploader_name = library.clean(fields.uploader_name, 20, "Music Server"),
        added_day = util.ingameDay(), plays = 0,
    }
    save()
    logActivity("Added " .. state.tracks[id].title .. " by "
        .. state.tracks[id].uploader_name, colors.lime)
    return state.tracks[id]
end

-- Gone from the Cloud Servers, every radio and every queue.
function library.remove(trackId)
    local track = state.tracks[trackId]
    if not track then return false end
    if track.pieces then
        store.forget(track.pieces)
    else
        -- A FoxyOS 17 song, still the Vault's.
        local _, err, code = bankAsk("CLOUD_MUSIC_DELETE", { file_id = track.file_id })
        if err and code ~= "NOT_FOUND" then return false, err end
    end
    state.tracks[trackId] = nil
    cache.plans[trackId] = nil
    for _, station in pairs(state.radios) do
        for _, kind in ipairs(music.KINDS) do
            local list = station[kind .. "s"] or {}
            for index = #list, 1, -1 do
                if list[index] == trackId then table.remove(list, index) end
            end
        end
    end
    for _, player in pairs(state.players) do
        for index = #(player.queue or {}), 1, -1 do
            if player.queue[index] == trackId then
                table.remove(player.queue, index)
                if index < player.index then player.index = player.index - 1 end
            end
        end
    end
    save()
    logActivity("Removed " .. track.title, colors.orange)
    return true
end

-- Where to fetch a track from. A ticket lasts as long as the song plays and
-- a few minutes more, so one answer serves everybody who starts it soon.
function library.plan(trackId)
    local track = state.tracks[trackId]
    need(track, "NOT_FOUND", "That song is not in the library")
    local now = util.nowMs()
    local known = cache.plans[trackId]
    if known and known.expires_at - now > music.lengthMs(track.size) + 60000 then
        return known.plan
    end
    local plan
    if track.pieces then
        plan = store.plan("get", track.pieces, 7 * 60 * 1000 + music.lengthMs(track.size))
    else
        local err, code
        plan, err, code = bankAsk("CLOUD_MUSIC_GET", { file_id = track.file_id }, 6)
        need(plan, code or "BANK_OFFLINE", err or "The Bank did not answer")
    end
    cache.plans[trackId] = { plan = plan, expires_at = now + (plan.expires_in_ms or 0) }
    return plan
end

-- The Music Server's own import, from a file on its disk or dropped on its
-- screen: straight to the Cloud Servers, credited as whoever is named.
function library.import(fields, body, progress)
    body = tostring(body or "")
    local most = tonumber(config.music_max_bytes) or 12 * 1024 * 1024
    if #body == 0 then return nil, "That file is empty" end
    if #body > most then return nil, "A song is at most " .. util.sizeText(most) end
    if #store.servers == 0 then store.refresh() end
    local trackId = nextId("track", "T")
    local placed, pieces = pcall(store.place, trackId, 1, #body)
    if not placed then return nil, type(pieces) == "table" and pieces.message or tostring(pieces) end
    local plan = store.plan("put", pieces, 60 * 1000 + #pieces * 3000)
    local ok, putError = music.upload(plan, body, CLOUD, progress)
    store.tickets[plan.ticket] = nil
    if not ok then
        store.forget(pieces)
        return nil, putError
    end
    fields.track_id, fields.pieces, fields.size = trackId, pieces, #body
    return library.add(fields)
end

-- FoxyOS 18: a FoxyOS 17 song -- kept for the library by the Bank's Vault --
-- moved onto pieces of this server's own, one at a time while the Bank
-- answers. Until then it plays as it always did, through the Bank.
function library.migrate()
    if not bankUp() or #store.servers == 0 then return nil end
    local track
    for _, id in ipairs(library.list("all")) do
        local candidate = state.tracks[id]
        if candidate.file_id and not candidate.pieces then
            track = candidate
            break
        end
    end
    if not track then return nil end
    local plan = bankAsk("CLOUD_MUSIC_GET", { file_id = track.file_id }, 6)
    local body = plan and net.cloud.get(plan, CLOUD)
    if not body then return false end
    local version = (track.version or 0) + 1
    local placed, pieces = pcall(store.place, track.track_id, version, #body)
    if not placed then return false end
    local put = store.plan("put", pieces, 60 * 1000 + #pieces * 3000)
    local ok = music.upload(put, body, CLOUD)
    store.tickets[put.ticket] = nil
    if not ok or not state.tracks[track.track_id] then
        store.forget(pieces)
        return false
    end
    local old = track.file_id
    track.pieces, track.version, track.file_id = pieces, version, nil
    cache.plans[track.track_id] = nil
    save()
    bankAsk("CLOUD_MUSIC_DELETE", { file_id = old })
    logActivity("Moved " .. track.title .. " to the Music Server's own pieces", colors.cyan)
    return true
end

-- Radios -----------------------------------------------------------------------------
-- A radio is its name, its colour, its phone number and four lists from the
-- library -- songs in rotation, hosts, ads and giveaways -- and a few dials.

local radio = {}

function radio.live(r)
    local l = live[r.radio_id]
    if not l then
        l = { queue = {}, recent = {}, since_ad = 0 }
        live[r.radio_id] = l
    end
    return l
end

-- The radio's tracks of one kind that are still in the library.
function radio.tracksOf(r, kind)
    local list = {}
    for _, id in ipairs(r[kind .. "s"] or {}) do
        local track = state.tracks[id]
        if track and track.kind == kind then list[#list + 1] = id end
    end
    return list
end

-- One at random, but not one of the last few of its kind.
function radio.pick(r, l, kind, filter)
    local all = {}
    for _, id in ipairs(radio.tracksOf(r, kind)) do
        if not filter or filter(id) then all[#all + 1] = id end
    end
    if #all == 0 then return nil end
    local recent, avoid = {}, math.min(#all - 1, kind == "song" and 5 or 2)
    for index = 1, avoid do
        local id = (l.recent[kind] or {})[index]
        if id then recent[id] = true end
    end
    local fresh = {}
    for _, id in ipairs(all) do
        if not recent[id] then fresh[#fresh + 1] = id end
    end
    if #fresh == 0 then fresh = all end
    return fresh[math.random(1, #fresh)]
end

function radio.item(trackId, label)
    local track = state.tracks[trackId]
    return { track_id = trackId, kind = track.kind, title = track.title,
        artist = track.artist, uploader = track.uploader_name,
        length_ms = math.max(1000, music.lengthMs(track.size)), label = label }
end

-- 20 Minute Non-Stop: songs and nothing else. Double Play: two songs in a
-- row by one artist. Throwback: three from the oldest in rotation.
function radio.startSpecial(r, l, kind, now)
    local kinds = kind and { kind } or { "nonstop", "double", "throwback" }
    kind = kinds[math.random(1, #kinds)]
    local songs = radio.tracksOf(r, "song")
    if kind == "nonstop" then
        l.special = { kind = kind, name = SPECIALS.nonstop, ends_at = now + 20 * 60 * 1000 }
    elseif kind == "double" then
        local count, artists = {}, {}
        for _, id in ipairs(songs) do
            local artist = state.tracks[id].artist
            count[artist] = (count[artist] or 0) + 1
            if count[artist] == 2 then artists[#artists + 1] = artist end
        end
        if #artists == 0 then return false end
        table.sort(artists)
        local artist = artists[math.random(1, #artists)]
        l.special = { kind = kind, name = SPECIALS.double .. ": " .. artist,
            artist = artist, left = 2 }
    else
        if #songs < 3 then return false end
        table.sort(songs, library.order)
        local pool = {}
        for index = 1, math.max(1, math.floor(#songs / 3)) do pool[songs[index]] = true end
        l.special = { kind = kind, name = SPECIALS.throwback, pool = pool, left = 3 }
    end
    return true
end

-- What follows what has just played. After a song comes a break -- a
-- giveaway, ads every few songs, or a host -- unless it is Non-Stop.
function radio.nextItem(r, l, now)
    if #l.queue > 0 then return table.remove(l.queue, 1) end
    local special = l.special
    if special and ((special.ends_at and special.ends_at <= now)
        or (special.left and special.left <= 0)) then
        l.special, special = nil, nil
    end
    local last = l.item
    if last and last.kind == "song" and not (special and special.kind == "nonstop") then
        l.since_ad = (l.since_ad or 0) + 1
        -- A giveaway is the Bank's: without it, the clip is not played.
        local give = bankUp() and r.number and radio.pick(r, l, "giveaway")
        if give and not l.giveaway and (l.force_giveaway
            or math.random(1, 100) <= (tonumber(r.giveaway_chance) or 4)) then
            l.force_giveaway = nil
            return radio.item(give, "GIVEAWAY")
        end
        local ad = radio.pick(r, l, "ad")
        if ad and l.since_ad >= (tonumber(r.ads_every) or 4) then
            l.since_ad = 0
            local second = math.random(1, 2) == 2 and radio.pick(r, l, "ad",
                function(id) return id ~= ad end)
            if second then l.queue[#l.queue + 1] = radio.item(second, "ADVERTISEMENT") end
            return radio.item(ad, "ADVERTISEMENT")
        end
        local host = radio.pick(r, l, "host")
        if host and math.random(1, 100) <= (tonumber(r.host_chance) or 60) then
            if not special and r.specials ~= false and math.random(1, 100) <= SPECIAL_CHANCE then
                radio.startSpecial(r, l, nil, now)
            end
            return radio.item(host, l.special and l.special.name or "ON AIR")
        end
    end
    special = l.special
    local filter
    if special and special.kind == "double" then
        filter = function(id) return state.tracks[id].artist == special.artist end
    elseif special and special.kind == "throwback" then
        filter = function(id) return special.pool[id] == true end
    end
    local song = radio.pick(r, l, "song", filter) or radio.pick(r, l, "song")
    -- Hosts and ads alone would only talk about songs that never come.
    if not song then return nil end
    if special and special.left then special.left = special.left - 1 end
    return radio.item(song, special and special.name or nil)
end

-- What is on now, moving the timeline on to the present. A radio nobody kept
-- going -- the server was off -- starts again from now.
function radio.now(r, now)
    now = now or util.nowMs()
    local l = radio.live(r)
    if l.item and now - (l.item.started_at + l.item.length_ms) > 60000 then l.item = nil end
    for _ = 1, 50 do
        if l.item and l.item.started_at + l.item.length_ms > now then break end
        local startAt = l.item and (l.item.started_at + l.item.length_ms) or now
        local item = radio.nextItem(r, l, now)
        if not item then
            l.item = nil
            break
        end
        item.started_at = startAt
        l.item = item
        l.recent[item.kind] = l.recent[item.kind] or {}
        table.insert(l.recent[item.kind], 1, item.track_id)
        while #l.recent[item.kind] > 8 do table.remove(l.recent[item.kind]) end
        -- Opened at the Bank by the radio loop, never while a request waits.
        if item.kind == "giveaway" then l.wants_giveaway = true end
    end
    return l.item, l
end

function radio.publicItem(item, now)
    if not item then return nil end
    return { track_id = item.track_id, kind = item.kind, title = item.title,
        artist = item.artist, uploader_name = item.uploader, length_ms = item.length_ms,
        position_ms = math.max(0, math.min(item.length_ms, now - item.started_at)),
        label = item.label }
end

function radio.listeners(radioId)
    local count, now = 0, util.nowMs()
    for _, player in pairs(state.players) do
        if player.mode == "radio" and player.radio_id == radioId and not player.paused
            and now - (player.last_seen or 0) < 15000 then
            count = count + 1
        end
    end
    return count
end

function radio.public(r, now)
    now = now or util.nowMs()
    local item, l = radio.now(r, now)
    return {
        radio_id = r.radio_id, name = r.name, color = r.color, number = r.number,
        now = radio.publicItem(item, now), special = l.special and l.special.name or nil,
        giveaway = l.giveaway and { number = l.giveaway.number,
            closes_in_ms = math.max(0, l.giveaway.closes_at - now) } or nil,
        winner = l.winner and { name = l.winner.name, prize = l.winner.prize } or nil,
        songs = #radio.tracksOf(r, "song"), listeners = radio.listeners(r.radio_id),
    }
end

function radio.askNumber(r)
    local answer = bankAsk("MUSIC_RADIO_NUMBER", { radio_id = r.radio_id, name = r.name })
    if answer and answer.number ~= r.number then
        r.number = answer.number
        save()
        logActivity(r.name .. " is on " .. r.number, colors.cyan)
    end
    return answer ~= nil
end

function radio.create(name, color)
    local id = nextId("radio", "R")
    state.radios[id] = { radio_id = id, name = library.clean(name, 20, "Radio " .. id),
        color = color or music.COLORS[(state.seq.radio - 1) % #music.COLORS + 1],
        songs = {}, hosts = {}, ads = {}, giveaways = {},
        host_chance = 60, ads_every = 4, giveaway_chance = 4, specials = true,
        created_day = util.ingameDay() }
    save()
    radio.askNumber(state.radios[id])
    logActivity("New radio " .. state.radios[id].name, colors.lime)
    return state.radios[id]
end

-- Every couple of seconds: every radio moved on, giveaways opened at the Bank
-- when their clip starts, and drawn there when the lines close.
function radio.tick()
    local now = util.nowMs()
    for _, r in pairs(state.radios) do
        if not r.number and state.server_token then radio.askNumber(r) end
        local _, l = radio.now(r, now)
        if l.wants_giveaway then
            l.wants_giveaway = nil
            local opened, err = bankAsk("MUSIC_GIVEAWAY_OPEN", { radio_id = r.radio_id,
                seconds = tonumber(config.giveaway_seconds) or 180 })
            if opened then
                l.giveaway = { giveaway_id = opened.giveaway_id, number = opened.number,
                    closes_at = now + (opened.closes_in_ms or 0) }
                logActivity("Giveaway on " .. r.name .. ": " .. tostring(opened.number),
                    colors.yellow)
            else
                logActivity("No giveaway on " .. r.name .. ": " .. tostring(err), colors.red)
            end
        end
        if l.giveaway and now >= l.giveaway.closes_at + 1000 then
            local result = bankAsk("MUSIC_GIVEAWAY_STATE",
                { giveaway_id = l.giveaway.giveaway_id })
            if result and result.status ~= "open" then
                l.winner = { name = result.winner_name, prize = result.prize,
                    until_ms = now + 3 * 60 * 1000 }
                l.giveaway = nil
                logActivity(result.winner_name and (result.winner_name .. " won "
                    .. util.money(result.prize, config.currency) .. " on " .. r.name)
                    or ("Nobody called " .. r.name), colors.yellow)
            elseif not result and now > l.giveaway.closes_at + 60000 then
                l.giveaway = nil
            end
        end
        if l.winner and l.winner.until_ms <= now then l.winner = nil end
    end
end

-- Who is listening ---------------------------------------------------------------------

local people = {}

-- A Pocket's session, asked of the Bank once a minute. FoxyOS 18: while the
-- Bank does not answer, a session it has vouched for in the last twelve hours
-- -- as long as a session lasts there -- is still believed.
function people.session(payload)
    local token = payload.session_token
    need(type(token) == "string" and #token > 0, "SIGN_IN", "Sign in first")
    local now = util.nowMs()
    local known = cache.sessions[token]
    if not known or known.until_ms <= now then
        local who, err, code = bankAsk("MUSIC_WHO", { session_token = token })
        if who then
            known = { account_id = who.account_id, name = who.name, until_ms = now + 60000,
                vouched_at = now }
            cache.sessions[token] = known
            people.remember(who)
        elseif code or not (known and now - known.vouched_at < 12 * 60 * 60 * 1000) then
            cache.sessions[token] = nil
            reject(code or "BANK_OFFLINE", err or "The Bank did not answer")
        end
    end
    return known
end

-- A Music Player, by the token it was given when it signed in.
function people.player(payload)
    local token = tostring(payload.player_token or "")
    for _, player in pairs(state.players) do
        if player.token == token then
            player.last_seen = util.nowMs()
            return player
        end
    end
    reject("NOT_A_PLAYER", "This Music Player is not signed in")
end

-- Whoever is asking: a Music Player for its owner, or a Pocket for its person.
function people.caller(payload)
    if payload.player_token then
        local player = people.player(payload)
        return { account_id = player.account_id, name = player.owner_name }, player
    end
    return people.session(payload)
end

-- An account's plan, as the Bank said it (MUSIC_WHO and MUSIC_ACCOUNT answer
-- the same), kept on disk for when it is not answering.
function people.remember(who)
    if type(who) ~= "table" or not who.account_id then return end
    state.entitled[who.account_id] = { name = who.name, plus = who.plus == true,
        music_plus = who.music_plus == true, offline = who.offline == true,
        tier = who.tier, unlimited_plays = who.plays_limit == nil,
        unlimited_uploads = who.uploads_limit == nil, plays_limit = who.plays_limit,
        uploads_limit = who.uploads_limit, checked_at = util.nowMs() }
    save()
end

-- What an account may do: its plan as last heard -- asked again once a few
-- minutes have passed, or sooner when `fresh` says (true: now; a number: that
-- many milliseconds) -- or the free plan if the Bank has never said.
function people.allowance(accountId, fresh)
    local known = state.entitled[accountId]
    local most = fresh == true and 0 or tonumber(fresh) or 5 * 60 * 1000
    local stale = not known or fresh == true or util.nowMs() - (known.checked_at or 0) > most
    if stale then
        local who = bankAsk("MUSIC_ACCOUNT", { account_id = accountId })
        if who then people.remember(who) end
        known = state.entitled[accountId]
    end
    return known or {}
end

-- Today's songs and uploads, counted here, by in-game day.
function people.usage(accountId)
    local today = util.ingameDay()
    local usage = state.usage[accountId]
    if type(usage) ~= "table" or usage.day ~= today then
        usage = { day = today, plays = 0, uploads = 0 }
        state.usage[accountId] = usage
    end
    return usage
end

-- A day's songs or uploads ("plays", "uploads"), or nil for no limit.
function people.limit(accountId, what)
    local allowed = people.allowance(accountId)
    if allowed["unlimited_" .. what] then return nil end
    local free = type(config.foxycloud_free) == "table" and config.foxycloud_free or {}
    return tonumber(allowed[what .. "_limit"]) or tonumber(free[what])
        or (what == "plays" and 10 or 2)
end

-- Refuses what today does not allow, and counts it if `count`.
function people.spend(accountId, what, count)
    local usage, limit = people.usage(accountId), people.limit(accountId, what)
    if what == "plays" then
        need(not limit or usage.plays < limit, "MUSIC_LIMIT", tostring(limit)
            .. " songs a day without FoxyMusic+. Radios are free")
    else
        need(not limit or usage.uploads < limit, "UPLOAD_LIMIT", tostring(limit)
            .. " uploads a day without FoxyMusic+")
    end
    if count then
        usage[what] = usage[what] + 1
        save()
    end
    return usage
end

-- What somebody may do today, as the Music app and a player show it.
function people.me(accountId, name)
    local allowed, usage = people.allowance(accountId), people.usage(accountId)
    return { account_id = accountId, name = allowed.name or name, tier = allowed.tier,
        plus = allowed.plus == true, music_plus = allowed.music_plus == true,
        offline = allowed.offline == true, plays = usage.plays,
        plays_limit = people.limit(accountId, "plays"), uploads = usage.uploads,
        uploads_limit = people.limit(accountId, "uploads") }
end

function people.publicPlayer(player, now)
    now = now or util.nowMs()
    local out = {
        player_id = player.player_id, label = player.label, owner_name = player.owner_name,
        online = now - (player.last_seen or 0) < 15000, mode = player.mode or "idle",
        paused = player.paused == true, volume = player.volume or 2, seq = player.seq or 0,
        play_no = player.play_no or 0, index = player.index or 1,
        queue_size = #(player.queue or {}), notice = player.notice,
    }
    if out.mode == "radio" then
        local r = state.radios[player.radio_id or ""]
        if r then
            out.radio = radio.public(r, now)
            out.now = out.radio.now
        end
    elseif out.mode == "library" then
        local track = state.tracks[(player.queue or {})[player.index or 1] or ""]
        out.now = library.public(track)
        if out.now then out.now.position_ms = player.position_ms or 0 end
        local limit = people.limit(player.account_id, "plays")
        out.plays_left = limit and math.max(0, limit - people.usage(player.account_id).plays)
            or nil
    end
    -- FoxyOS 18: whether its owner may keep songs on it for Offline Listening.
    out.offline = people.allowance(player.account_id).offline == true
    return out
end

function people.ownPlayer(payload)
    local who, itself = people.caller(payload)
    if itself and (payload.player_id == nil or payload.player_id == itself.player_id) then
        return itself, who
    end
    local player = state.players[tostring(payload.player_id or "")]
    need(player and player.account_id == who.account_id, "NOT_YOURS",
        "That Music Player is not yours")
    return player, who
end

-- A different song (or a radio) is a new play_no: counted once, however often
-- it is paused and resumed.
function people.changed(player, newTrack)
    player.seq = (player.seq or 0) + 1
    if newTrack then
        player.play_no = (player.play_no or 0) + 1
        player.position_ms = 0
    end
    player.notice = nil
end

-- Actions ----------------------------------------------------------------------------------

local actions = {}

function actions.MUSIC_PING()
    local count = 0
    for _ in pairs(state.tracks) do count = count + 1 end
    return { server_id = state.server_id, name = state.name, version = PROGRAM_VERSION,
        tracks = count }
end

-- The Music Library as a listener sees it: songs, newest first unless asked.
function actions.MUSIC_LIBRARY(payload)
    local ids = library.list("song", payload.query)
    local list = {}
    for _, id in ipairs(ids) do list[#list + 1] = library.public(state.tracks[id]) end
    local sort = payload.sort
    table.sort(list, function(a, b)
        if sort == "title" then return a.title:lower() < b.title:lower() end
        if sort == "popular" and a.plays ~= b.plays then return a.plays > b.plays end
        return library.order(b.track_id, a.track_id)
    end)
    local per = math.max(1, math.min(50, math.floor(tonumber(payload.per_page) or 20)))
    local items, page, pages = util.page(list, tonumber(payload.page) or 1, per)
    return { tracks = items, page = page, pages = pages, total = #list }
end

function actions.MUSIC_RADIOS()
    local list, now = {}, util.nowMs()
    for _, r in pairs(state.radios) do list[#list + 1] = radio.public(r, now) end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    return { radios = list }
end

-- What somebody may play and upload today.
function actions.MUSIC_ME(payload)
    local who = people.caller(payload)
    people.allowance(who.account_id, true)
    return people.me(who.account_id, who.name)
end

-- A Cloud Server asking what one of this server's tickets allows -- on that
-- Cloud Server only, so it never learns where the rest of a song is.
function actions.MUSIC_TICKET(payload, sender)
    local ticket = store.tickets[tostring(payload.ticket or "")]
    local now = util.nowMs()
    need(ticket and ticket.expires_at > now, "BAD_TICKET", "That ticket has expired")
    local mine = {}
    for id, entry in pairs(ticket.chunks) do
        for _, host in ipairs(entry.hosts) do
            if host == sender then mine[id] = entry.size end
        end
    end
    return { mode = ticket.mode, chunks = mine, ttl_ms = ticket.expires_at - now }
end

-- A Cloud Server's sweep: which of this server's pieces it holds that no
-- song wants any more -- an upload that never finished, a song deleted while
-- that Cloud Server was off.
function actions.MUSIC_KEEP(payload)
    local wanted, drop = store.wanted(), {}
    for index, id in ipairs(type(payload.chunks) == "table" and payload.chunks or {}) do
        if index > 200 then break end
        if not wanted[tostring(id)] then drop[#drop + 1] = tostring(id) end
    end
    return { drop = drop }
end

-- Offline Listening, FoxyOS 18: a song kept on a Music Player, for while this
-- server is off. FoxyMusic+ only, asked of the Bank now if it answers.
function actions.MUSIC_DOWNLOAD(payload)
    local player = people.player(payload)
    local allowed = people.allowance(player.account_id, true)
    need(allowed.offline, "NEEDS_MUSIC_PLUS", "Offline Listening comes with FoxyMusic+")
    local track = state.tracks[tostring(payload.track_id or "")]
    need(track and track.kind == "song", "NOT_FOUND", "That song is not in the library")
    return { track = library.public(track), plan = library.plan(track.track_id) }
end

-- A Music Player signing in, once. Signing in again on the same computer
-- replaces it rather than adding a second.
function actions.MUSIC_HELLO(payload, sender)
    local who = people.session(payload)
    for id, player in pairs(state.players) do
        if player.computer_id == sender and sender ~= nil then state.players[id] = nil end
    end
    local id = nextId("player", "P")
    local player = { player_id = id, token = util.token("MP"), account_id = who.account_id,
        owner_name = who.name, computer_id = sender,
        label = library.clean(payload.label, 20, who.name .. "'s Player"),
        mode = "idle", queue = {}, index = 1, volume = 2, seq = 0, play_no = 0,
        last_seen = util.nowMs() }
    state.players[id] = player
    save()
    logActivity(player.label .. " signed in", colors.lime)
    return { player_token = player.token, player = people.publicPlayer(player) }
end

function actions.MUSIC_BYE(payload)
    local player = people.player(payload)
    state.players[player.player_id] = nil
    save()
    logActivity(player.label .. " signed out", colors.orange)
    return { signed_out = true }
end

-- A Music Player every second or so: where it is in the song, and what it
-- should be doing.
function actions.MUSIC_TICK(payload)
    local player = people.player(payload)
    if tonumber(payload.position_ms) and payload.play_no == player.play_no then
        player.position_ms = math.max(0, math.floor(tonumber(payload.position_ms)))
    end
    player.version = payload.version
    return { player = people.publicPlayer(player) }
end

function actions.MUSIC_PLAYERS(payload)
    local who = people.session(payload)
    local list, now = {}, util.nowMs()
    for _, player in pairs(state.players) do
        if player.account_id == who.account_id then
            list[#list + 1] = people.publicPlayer(player, now)
        end
    end
    table.sort(list, function(a, b) return a.label:lower() < b.label:lower() end)
    return { players = list }
end

-- Telling a Music Player what to do: from the Music app, or from the
-- player's own screen.
function actions.MUSIC_CONTROL(payload)
    local player = people.ownPlayer(payload)
    local command = tostring(payload.command or "")
    if command == "radio" then
        local r = state.radios[tostring(payload.radio_id or "")]
        need(r, "NOT_FOUND", "There is no such radio")
        player.mode, player.radio_id, player.paused = "radio", r.radio_id, false
        people.changed(player, true)
    elseif command == "play" or command == "add" then
        local trackId = tostring(payload.track_id or "")
        local track = state.tracks[trackId]
        need(track and track.kind == "song", "NOT_FOUND", "That song is not in the library")
        if command == "add" and player.mode == "library" then
            player.queue[#player.queue + 1] = trackId
            player.seq = (player.seq or 0) + 1
        else
            local queue = {}
            for _, id in ipairs(type(payload.queue) == "table" and payload.queue or {}) do
                local listed = state.tracks[tostring(id)]
                if listed and listed.kind == "song" and #queue < 100 then
                    queue[#queue + 1] = tostring(id)
                end
            end
            local at
            for index, id in ipairs(queue) do
                if id == trackId then at = index break end
            end
            if not at then
                table.insert(queue, 1, trackId)
                at = 1
            end
            player.mode, player.queue, player.index, player.paused = "library", queue, at, false
            people.changed(player, true)
        end
    elseif command == "pause" or command == "resume" then
        need(player.mode ~= "idle", "IDLE", "Nothing is playing")
        player.paused = command == "pause"
        people.changed(player, false)
    elseif command == "next" or command == "previous" then
        need(player.mode == "library", "LIVE", "A radio is live: it cannot be skipped")
        local step = command == "next" and 1 or -1
        if command == "previous" and (player.position_ms or 0) > 5000 then step = 0 end
        player.index = math.max(1, player.index + step)
        if player.index > #player.queue then player.mode = "idle" end
        player.paused = false
        people.changed(player, true)
    elseif command == "shuffle" then
        need(player.mode == "library", "IDLE", "Play some songs first")
        local current = player.queue[player.index]
        for index = #player.queue, 2, -1 do
            local swap = math.random(1, index)
            player.queue[index], player.queue[swap] = player.queue[swap], player.queue[index]
        end
        for index, id in ipairs(player.queue) do
            if id == current then
                player.queue[index], player.queue[1] = player.queue[1], player.queue[index]
            end
        end
        player.index = 1
        player.seq = (player.seq or 0) + 1
    elseif command == "stop" then
        player.mode, player.paused = "idle", false
        people.changed(player, true)
    elseif command == "volume" then
        player.volume = math.max(0, math.min(3, tonumber(payload.volume) or 2))
    elseif command == "rename" then
        player.label = library.clean(payload.label, 20, player.label)
    else
        reject("BAD_COMMAND", "A Music Player does not do that")
    end
    save()
    return { player = people.publicPlayer(player) }
end

-- What a Music Player, or a CCG Casino, should play right now and where to
-- fetch it. A song from the library is counted once, when it starts; a radio
-- is free and always where everybody else is in it.
function actions.MUSIC_STREAM(payload)
    local now = util.nowMs()
    local mode, radioId, trackId, player, grant
    if payload.grant then
        grant = state.grants[tostring(payload.grant)]
        need(grant, "NO_GRANT", "That music is not set up any more")
        -- Asked again every minute a casino plays, while the Bank answers.
        local owner = people.allowance(grant.account_id, 60 * 1000)
        need(owner.plus, "NEEDS_PLUS", "Music on a CCG Casino needs FoxyCloud+")
        mode = grant.kind == "radio" and "radio" or "library"
        radioId, trackId = grant.id, grant.id
    else
        player = people.player(payload)
        need(not player.paused, "PAUSED", "Paused")
        mode, radioId = player.mode, player.radio_id
        trackId = (player.queue or {})[player.index or 1]
    end
    status.streams = status.streams + 1
    if mode == "radio" then
        local r = state.radios[tostring(radioId or "")]
        need(r, "NOT_FOUND", "That radio is gone")
        local item = radio.now(r, now)
        need(item, "RADIO_EMPTY", r.name .. " has no songs yet")
        return { mode = "radio", seq = player and player.seq, item = radio.publicItem(item, now),
            offset_ms = math.max(0, now - item.started_at), plan = library.plan(item.track_id),
            radio = radio.public(r, now) }
    end
    need(mode == "library", "IDLE", "Nothing to play")
    local track = state.tracks[tostring(trackId or "")]
    need(track, "NOT_FOUND", "That song is not in the library any more")
    if player and player.counted ~= player.play_no then
        local ok, err = pcall(people.spend, player.account_id, "plays", true)
        if not ok then
            if type(err) == "table" and err.code == "MUSIC_LIMIT" then
                people.changed(player, true)
                player.mode, player.notice = "idle", err.message
                save()
            end
            error(err, 0)
        end
        player.counted = player.play_no
        track.plays = (track.plays or 0) + 1
        save()
    end
    return { mode = "library", seq = player and player.seq, play_no = player and player.play_no,
        item = library.public(track), plan = library.plan(track.track_id),
        offset_ms = player and player.position_ms or tonumber(payload.offset_ms) or 0 }
end

-- A song ran out on a Music Player: the next in its queue, or quiet.
function actions.MUSIC_NEXT(payload)
    local player = people.player(payload)
    if player.mode == "library" and payload.play_no == player.play_no then
        player.index = player.index + 1
        if player.index > #player.queue then
            player.mode, player.index = "idle", 1
        end
        people.changed(player, true)
        save()
    end
    return { player = people.publicPlayer(player) }
end

-- A CCG Casino owner choosing a song or a radio for their tables. The
-- casino is given the grant, never the owner's session; FoxyCloud+ is asked
-- for now and every minute the casino plays.
function actions.MUSIC_GRANT(payload)
    local who = people.session(payload)
    local owner = people.allowance(who.account_id, true)
    need(owner.plus, "NEEDS_PLUS", "Songs and radios on a CCG Casino need FoxyCloud+")
    local kind = payload.kind == "radio" and "radio" or "track"
    local id, label = tostring(payload.id or ""), nil
    if kind == "radio" then
        need(state.radios[id], "NOT_FOUND", "There is no such radio")
        label = state.radios[id].name
    else
        local track = state.tracks[id]
        need(track and track.kind == "song", "NOT_FOUND", "That song is not in the library")
        label = track.title .. " - " .. track.artist
    end
    -- An owner's older grants go: the casino only ever plays the last one.
    for token, grant in pairs(state.grants) do
        if grant.account_id == who.account_id and grant.casino == payload.casino_id then
            state.grants[token] = nil
        end
    end
    local token = util.token("MG")
    state.grants[token] = { account_id = who.account_id, kind = kind, id = id,
        casino = payload.casino_id, created_at = util.nowMs() }
    save()
    return { grant = token, kind = kind, id = id, label = label }
end

-- Uploading a song: whether today allows another, and where on the Cloud
-- Servers its pieces go. The bytes go there from the uploader, not through
-- here.
function actions.MUSIC_UPLOAD_BEGIN(payload)
    local who = people.caller(payload)
    local size = math.floor(tonumber(payload.size) or 0)
    local most = tonumber(config.music_max_bytes) or 12 * 1024 * 1024
    need(size > 0, "BAD_SIZE", "That song is empty")
    need(size <= most, "TOO_BIG", "A song is at most " .. util.sizeText(most))
    people.spend(who.account_id, "uploads", false)
    local trackId = nextId("track", "T")
    local pieces = store.place(trackId, 1, size)
    local plan = store.plan("put", pieces, 60 * 1000 + #pieces * 3000)
    local id = nextId("upload", "U")
    cache.uploads[id] = { upload_id = id, account_id = who.account_id, name = who.name,
        track_id = trackId, pieces = pieces, ticket = plan.ticket, size = size,
        title = payload.title, artist = payload.artist,
        expires_at = util.nowMs() + plan.expires_in_ms }
    return { upload_id = id, plan = plan }
end

function actions.MUSIC_UPLOAD_DONE(payload)
    local who = people.caller(payload)
    local upload = cache.uploads[tostring(payload.upload_id or "")]
    need(upload and upload.account_id == who.account_id, "NOT_UPLOADING",
        "That upload is over. Try it again")
    cache.uploads[upload.upload_id] = nil
    store.tickets[upload.ticket] = nil
    people.spend(upload.account_id, "uploads", true)
    local track = library.add({ track_id = upload.track_id, pieces = upload.pieces,
        size = upload.size, title = upload.title, artist = upload.artist, kind = "song",
        uploader_id = upload.account_id, uploader_name = upload.name })
    return { track = library.public(track) }
end

local function route(sender, message)
    if type(message) ~= "table" or message.kind ~= "request"
        or type(message.action) ~= "string" then return end
    local handler = actions[message.action]
    if not handler then
        net.reply(sender, PROTOCOL, message.request_id, false, nil,
            "Unknown music action", "UNKNOWN_ACTION")
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
            "Music Server error", "SERVER_ERROR")
    end
end

-- The Music Server's own screen ---------------------------------------------------------
-- Library: everything uploaded, with what kind of track each is. Radios:
-- each radio's lists and dials, and a giveaway or a special on demand.

local admin = { kind = "all", page = 1, radioPage = 1 }

function admin.header(title, subtitle)
    ui.clear(target)
    ui.header(target, title, subtitle, util.formatClock())
end

function admin.say(kind, title, body)
    ui.message(target, kind, title, body, 1.6)
end

-- A list of rows, a page at a time, each a tap. Returns the action.
function admin.rows(scene, y, bottom, ids, page, draw)
    local width = target.getSize()
    local per = math.max(1, bottom - y)
    local items, actual, pages = util.page(ids, page, per)
    for index, id in ipairs(items) do
        local rowY = y + index - 1
        draw(id, rowY, width)
        scene:hotspot("row:" .. id, 1, rowY, width, 1)
    end
    if pages > 1 then
        scene:button("page:prev", 2, bottom, 5, 1, "<", { background = ui.theme.panel })
        ui.center(target, bottom, actual .. " / " .. pages, ui.theme.muted)
        scene:button("page:next", width - 5, bottom, 5, 1, ">",
            { background = ui.theme.panel })
    end
    return actual, pages
end

function admin.trackLine(id, y, width, mark)
    local track = state.tracks[id]
    local kindColor = ({ song = ui.theme.ink, host = colors.cyan, ad = colors.orange,
        giveaway = colors.yellow })[track.kind] or ui.theme.ink
    local left = (mark or "") .. track.title .. "  " .. track.artist
    local right = music.KIND_NAMES[track.kind] .. "  " .. music.clock(music.lengthMs(track.size))
    ui.text(target, 2, y, ui.truncate(left, width - #right - 4), kindColor)
    ui.text(target, width - #right, y, right, ui.theme.muted)
end

-- Files to bring in: dropped on this screen, or .dfpwm files on its disks.
function admin.importBodies(bodies)
    local added = 0
    for index, entry in ipairs(bodies) do
        ui.clear(target)
        ui.header(target, "IMPORTING", index .. " of " .. #bodies)
        local title = ui.input(target, "TITLE", { initial = music.titleFrom(entry.name),
            maxLength = 28 })
        if not title then break end
        local artist = ui.input(target, "ARTIST", { initial = "", maxLength = 20 })
        if not artist then break end
        local kind = admin.chooseKind("song")
        local credit = ui.input(target, "CREDIT", { initial = state.credit or "Music Server",
            maxLength = 20, hint = "Whose name is on the track" })
        if not credit then break end
        state.credit = credit
        admin.header("UPLOADING", title)
        local width = target.getSize()
        local track, err = library.import({ title = title, artist = artist, kind = kind,
            uploader_name = credit }, entry.body, function(done, total)
                ui.progress(target, 4, 8, width - 6, done, total, ui.theme.accent,
                    ui.theme.panel)
            end)
        if track then
            added = added + 1
        else
            admin.say("error", "NOT IMPORTED", err)
        end
    end
    if added > 0 then admin.say("success", "IMPORTED", added .. " track"
        .. (added == 1 and "" or "s") .. " in the library") end
end

function admin.diskFiles()
    local found = {}
    local function look(dir)
        if not fs.exists(dir) or not fs.isDir(dir) then return end
        for _, name in ipairs(fs.list(dir)) do
            local path = fs.combine(dir, name)
            if not fs.isDir(path) and music.isAudio(name) then found[#found + 1] = path end
        end
    end
    look(ROOT)
    look(fs.combine(ROOT, "music"))
    for _, name in ipairs(fs.list("/")) do
        if name:match("^disk%d*$") then look("/" .. name) end
    end
    table.sort(found)
    return found
end

function admin.importDisk()
    local paths, page = admin.diskFiles(), 1
    if #paths == 0 then
        admin.say("error", "NO SONGS HERE", "Put .dfpwm files in a disk drive, or drop them"
            .. " on this screen")
        return
    end
    while running do
        admin.header("IMPORT", "From this computer's disks")
        local scene = ui.scene(target)
        local bottom = ui.contentBottom(target)
        page = admin.rows(scene, 5, bottom, paths, page, function(path, y, width)
            ui.text(target, 2, y, ui.truncate(path, width - 12), ui.theme.ink)
            ui.text(target, width - 9, y, util.sizeText(fs.getSize(path) or 0), ui.theme.muted)
        end)
        scene:button("back", 2, bottom + 1, 8, 1, "BACK", { background = ui.theme.panel })
        local action = scene:wait()
        if action == "back" or action == "__terminate" then return end
        if action == "page:prev" then page = page - 1 end
        if action == "page:next" then page = page + 1 end
        local path = action and action:match("^row:(.+)$")
        if path then
            local file = fs.open(path, "rb")
            local body = file and file.readAll() or ""
            if file then file.close() end
            admin.importBodies({ { name = path, body = body } })
            return
        end
    end
end

function admin.dropped(handle)
    local ok, files = pcall(function() return handle.getFiles() end)
    local bodies = {}
    for _, file in ipairs(ok and files or {}) do
        local name = file.getName and file.getName() or "song.dfpwm"
        local body = file.readAll and file.readAll() or ""
        pcall(file.close)
        if music.isAudio(name) then bodies[#bodies + 1] = { name = name, body = body } end
    end
    if #bodies == 0 then
        admin.say("error", "NOT A SONG", "Songs are .dfpwm files")
        return
    end
    admin.importBodies(bodies)
end

function admin.chooseKind(current)
    while true do
        admin.header("WHAT KIND OF TRACK", "Listeners only ever see songs")
        local scene = ui.scene(target)
        local width = target.getSize()
        local hints = { song = "In the library and in rotation",
            host = "Talking between songs on a radio", ad = "In a radio's ad breaks",
            giveaway = "Starts a giveaway on a radio" }
        for index, kind in ipairs(music.KINDS) do
            local y = 3 + index * 3
            local on = kind == current
            scene:button("kind:" .. kind, 2, y, 14, 2, music.KIND_NAMES[kind],
                { background = on and ui.theme.accent or ui.theme.panel,
                    foreground = on and ui.inkOn(ui.theme.accent) or ui.theme.ink })
            ui.text(target, 18, y, ui.truncate(hints[kind], width - 18), ui.theme.muted)
        end
        local action = scene:wait()
        local kind = action and action:match("^kind:(.+)$")
        if kind then return kind end
        if action == "__terminate" then return current end
    end
end

function admin.editTrack(trackId)
    while running do
        local track = state.tracks[trackId]
        if not track then return end
        admin.header(track.title, track.track_id .. "  " .. music.KIND_NAMES[track.kind])
        local width = target.getSize()
        local on = {}
        for _, r in pairs(state.radios) do
            for _, id in ipairs(r[track.kind .. "s"] or {}) do
                if id == trackId then on[#on + 1] = r.name end
            end
        end
        local lines = {
            { "ARTIST    " .. track.artist },
            { "LENGTH    " .. music.clock(music.lengthMs(track.size)) .. "  ("
                .. util.sizeText(track.size) .. ")" },
            { "BY        " .. tostring(track.uploader_name) .. ", day "
                .. tostring(track.added_day) },
            { "PLAYS     " .. tostring(track.plays or 0) },
            { "RADIOS    " .. (#on > 0 and table.concat(on, ", ") or "None"), ui.theme.muted },
        }
        for index, line in ipairs(lines) do
            ui.text(target, 2, 4 + index, ui.truncate(line[1], width - 2), line[2] or ui.theme.ink)
        end
        local scene = ui.scene(target)
        local third = math.floor((width - 4) / 3)
        scene:button("title", 2, 12, third, 2, "TITLE", { background = ui.theme.panel })
        scene:button("artist", 3 + third, 12, third, 2, "ARTIST", { background = ui.theme.panel })
        scene:button("kind", 4 + third * 2, 12, width - 4 - third * 2, 2, "KIND",
            { background = ui.theme.panel })
        scene:button("radios", 2, 15, third, 2, "RADIOS", { background = ui.theme.accent,
            foreground = ui.inkOn(ui.theme.accent) })
        scene:button("delete", 3 + third, 15, third, 2, "DELETE",
            { background = ui.theme.danger, foreground = colors.white })
        scene:button("back", 4 + third * 2, 15, width - 4 - third * 2, 2, "BACK",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 1 })
        if action == "back" or action == "__terminate" then return end
        if action == "title" or action == "artist" then
            local value = ui.input(target, string.upper(action), { initial = track[action],
                maxLength = action == "title" and 28 or 20 })
            if value and util.trim(value) ~= "" then
                track[action] = library.clean(value, action == "title" and 28 or 20, track[action])
                save()
            end
        elseif action == "kind" then
            local kind = admin.chooseKind(track.kind)
            if kind ~= track.kind then
                for _, r in pairs(state.radios) do
                    local list = r[track.kind .. "s"] or {}
                    for index = #list, 1, -1 do
                        if list[index] == trackId then table.remove(list, index) end
                    end
                end
                track.kind = kind
                save()
            end
        elseif action == "radios" then
            admin.trackRadios(trackId)
        elseif action == "delete" then
            if ui.confirm(target, "DELETE TRACK", "Delete " .. track.title
                .. "? It goes from every radio and every queue.", "DELETE", "KEEP") then
                local ok, err = library.remove(trackId)
                if not ok then admin.say("error", "NOT DELETED", err) end
                return
            end
        end
    end
end

-- Which radios a track is on, a tap each.
function admin.trackRadios(trackId)
    while running do
        local track = state.tracks[trackId]
        if not track then return end
        admin.header("RADIOS", track.title .. " as a " .. music.KIND_NAMES[track.kind])
        local ids = {}
        for id in pairs(state.radios) do ids[#ids + 1] = id end
        table.sort(ids, library.order)
        local scene = ui.scene(target)
        local bottom = ui.contentBottom(target)
        admin.radioPage = admin.rows(scene, 5, bottom, ids, admin.radioPage, function(id, y, width)
            local r = state.radios[id]
            local listed = false
            for _, listedId in ipairs(r[track.kind .. "s"] or {}) do
                if listedId == trackId then listed = true end
            end
            ui.text(target, 2, y, listed and "[x]" or "[ ]", listed and ui.theme.success
                or ui.theme.muted)
            ui.fill(target, 6, y, 2, 1, music.color(r.color))
            ui.text(target, 9, y, ui.truncate(r.name, width - 10), ui.theme.ink)
        end)
        if #ids == 0 then ui.text(target, 2, 6, "No radios yet. Make one on Radios.",
            ui.theme.muted) end
        scene:button("back", 2, bottom + 1, 8, 1, "DONE", { background = ui.theme.panel })
        local action = scene:wait()
        if action == "back" or action == "__terminate" then return end
        if action == "page:prev" then admin.radioPage = admin.radioPage - 1 end
        if action == "page:next" then admin.radioPage = admin.radioPage + 1 end
        local id = action and action:match("^row:(.+)$")
        if id and state.radios[id] then admin.toggle(state.radios[id], track.kind, trackId) end
    end
end

function admin.toggle(r, kind, trackId)
    local field = kind .. "s"
    r[field] = r[field] or {}
    for index, id in ipairs(r[field]) do
        if id == trackId then
            table.remove(r[field], index)
            save()
            return false
        end
    end
    r[field][#r[field] + 1] = trackId
    save()
    return true
end

-- A radio's list of one kind: every track of that kind, ticked if it is in.
function admin.pickTracks(r, kind)
    local page = 1
    while running do
        admin.header(r.name .. ": " .. music.KIND_NAMES[kind] .. "s",
            "Tap to put a track in or take it out")
        local ids = library.list(kind)
        local scene = ui.scene(target)
        local bottom = ui.contentBottom(target)
        local inList = {}
        for _, id in ipairs(r[kind .. "s"] or {}) do inList[id] = true end
        page = admin.rows(scene, 5, bottom, ids, page, function(id, y, width)
            admin.trackLine(id, y, width, inList[id] and "[x] " or "[ ] ")
        end)
        if #ids == 0 then
            ui.wrappedText(target, 2, 6, "No " .. string.lower(music.KIND_NAMES[kind])
                .. " tracks in the library. Import one and set its kind.",
                target.getSize() - 2, 3, ui.theme.muted)
        end
        local width = target.getSize()
        scene:button("all", 2, bottom + 1, 7, 1, "ALL", { background = ui.theme.panel })
        scene:button("none", 10, bottom + 1, 7, 1, "NONE", { background = ui.theme.panel })
        scene:button("back", width - 8, bottom + 1, 8, 1, "DONE", { background = ui.theme.panel })
        local action = scene:wait()
        if action == "back" or action == "__terminate" then return end
        if action == "page:prev" then page = page - 1 end
        if action == "page:next" then page = page + 1 end
        if action == "all" then
            r[kind .. "s"] = ids
            save()
        elseif action == "none" then
            r[kind .. "s"] = {}
            save()
        end
        local id = action and action:match("^row:(.+)$")
        if id then admin.toggle(r, kind, id) end
    end
end

function admin.pickColor(current)
    while true do
        admin.header("RADIO COLOUR")
        local scene = ui.scene(target)
        for index, name in ipairs(music.COLORS) do
            local column, row = (index - 1) % 7, math.floor((index - 1) / 7)
            local x, y = 2 + column * 7, 5 + row * 4
            scene:button("color:" .. name, x, y, 6, 3, name == current and "*" or "",
                { background = music.color(name), foreground = ui.inkOn(music.color(name)) })
        end
        local action = scene:wait()
        local name = action and action:match("^color:(.+)$")
        if name then return name end
        if action == "__terminate" then return current end
    end
end

local DIALS = {
    host_chance = { 0, 20, 40, 60, 80, 100 },
    ads_every = { 2, 3, 4, 5, 6, 8 },
    giveaway_chance = { 0, 2, 4, 8, 15 },
}

function admin.nextDial(field, value)
    local steps = DIALS[field]
    for index, step in ipairs(steps) do
        if step == value then return steps[index % #steps + 1] end
    end
    return steps[1]
end

function admin.editRadio(radioId)
    while running do
        local r = state.radios[radioId]
        if not r then return end
        local now = util.nowMs()
        local public = radio.public(r, now)
        local l = radio.live(r)
        local width = target.getSize()
        ui.clear(target)
        ui.fill(target, 1, 1, width, 2, music.color(r.color))
        ui.text(target, 2, 1, ui.truncate(r.name, width - 10), ui.inkOn(music.color(r.color)),
            music.color(r.color))
        ui.text(target, 2, 2, "Call " .. tostring(r.number or "(no number yet)")
            .. "   " .. public.listeners .. " listening", ui.inkOn(music.color(r.color)),
            music.color(r.color))
        local nowLine = public.now and ((public.now.label and (public.now.label .. ": ") or "")
            .. public.now.title .. " - " .. public.now.artist .. "  "
            .. music.clock(public.now.position_ms) .. "/" .. music.clock(public.now.length_ms))
            or "Nothing to play: put songs in rotation"
        ui.text(target, 2, 4, ui.truncate("NOW  " .. nowLine, width - 2), ui.theme.ink)
        local extra = public.giveaway and ("GIVEAWAY OPEN  call " .. public.giveaway.number
            .. "  " .. music.clock(public.giveaway.closes_in_ms))
            or public.winner and (public.winner.name and ("WINNER  " .. public.winner.name .. " won "
                .. util.money(public.winner.prize, config.currency)) or "Nobody called in")
            or public.special or (l.force_giveaway and "Giveaway at the next break") or ""
        ui.text(target, 2, 5, ui.truncate(extra, width - 2), colors.yellow)
        local scene = ui.scene(target)
        local quarter = math.floor((width - 5) / 4)
        for index, kind in ipairs(music.KINDS) do
            local x = 2 + (index - 1) * (quarter + 1)
            scene:button("list:" .. kind, x, 7, index == 4 and width - x or quarter, 2,
                music.KIND_NAMES[kind] .. "s " .. #radio.tracksOf(r, kind),
                { background = ui.theme.panel })
        end
        local dials = {
            { "dial:host_chance", "HOSTS", (r.host_chance or 60) .. "%" },
            { "dial:ads_every", "ADS EVERY", (r.ads_every or 4) .. " songs" },
            { "dial:giveaway_chance", "GIVEAWAYS", (r.giveaway_chance or 4) .. "%" },
            { "specials", "SPECIALS", r.specials == false and "OFF" or "ON" },
        }
        for index, dial in ipairs(dials) do
            local x = 2 + (index - 1) * (quarter + 1)
            ui.text(target, x, 10, dial[2], ui.theme.muted)
            scene:button(dial[1], x, 11, index == 4 and width - x or quarter, 1, dial[3],
                { background = ui.theme.panel })
        end
        local rows = {
            { { "giveaway", "GIVEAWAY NOW", colors.yellow },
                { "nonstop", "NON-STOP NOW", ui.theme.accent }, { "skip", "SKIP", ui.theme.panel } },
            { { "rename", "RENAME", ui.theme.panel }, { "color", "COLOUR", music.color(r.color) },
                { "delete", "DELETE", ui.theme.danger }, { "back", "BACK", ui.theme.panel } },
        }
        for row, buttons in ipairs(rows) do
            local each = math.floor((width - 1) / #buttons)
            for index, button in ipairs(buttons) do
                local x = 2 + (index - 1) * each
                scene:button(button[1], x, 10 + row * 3, index == #buttons and width - x
                    or each - 1, 2, button[2],
                    { background = button[3], foreground = ui.inkOn(button[3]) })
            end
        end
        local action = scene:wait({ tickRate = 1 })
        if action == "back" or action == "__terminate" then return end
        local kind = action and action:match("^list:(.+)$")
        local dial = action and action:match("^dial:(.+)$")
        if kind then
            admin.pickTracks(r, kind)
        elseif dial then
            r[dial] = admin.nextDial(dial, r[dial])
            save()
        elseif action == "specials" then
            r.specials = r.specials == false
            save()
        elseif action == "giveaway" then
            if #radio.tracksOf(r, "giveaway") == 0 then
                admin.say("error", "NO GIVEAWAY CLIP", "Add a Giveaway track to this radio first")
            elseif not r.number then
                admin.say("error", "NO NUMBER", "The Bank has not given this radio a number yet")
            else
                l.force_giveaway = true
                admin.say("success", "GIVEAWAY", "At the next break on " .. r.name)
            end
        elseif action == "nonstop" then
            radio.startSpecial(r, l, "nonstop", now)
        elseif action == "skip" then
            -- Everyone listening moves on with it: they ask again when the
            -- item they are playing is over, and it already is.
            if l.item then l.item.length_ms = math.max(1, now - l.item.started_at) end
            radio.now(r)
        elseif action == "rename" then
            local name = ui.input(target, "RADIO NAME", { initial = r.name, maxLength = 20 })
            if name and util.trim(name) ~= "" then
                r.name = library.clean(name, 20, r.name)
                save()
                radio.askNumber(r)
            end
        elseif action == "color" then
            r.color = admin.pickColor(r.color)
            save()
        elseif action == "delete" then
            if ui.confirm(target, "DELETE RADIO", "Delete " .. r.name
                .. "? Its tracks stay in the library.", "DELETE", "KEEP") then
                state.radios[radioId] = nil
                live[radioId] = nil
                save()
                logActivity("Deleted radio " .. r.name, colors.orange)
                return
            end
        end
    end
end

local function libraryPage()
    return {
        id = "library", label = "Library", short = "Lib",
        draw = function(scene)
            local width = target.getSize()
            local bottom = ui.contentBottom(target)
            local ids = library.list(admin.kind)
            ui.text(target, 2, 4, "LIBRARY  " .. #ids .. "  " .. util.sizeText(library.bytes()),
                ui.theme.muted)
            scene:button("import", width - 9, 4, 9, 1, "IMPORT", { background = ui.theme.accent,
                foreground = ui.inkOn(ui.theme.accent) })
            local x = 2
            for _, kind in ipairs({ "all", "song", "host", "ad", "giveaway" }) do
                local label = kind == "all" and "All" or music.KIND_NAMES[kind] .. "s"
                local on = admin.kind == kind
                scene:button("kind:" .. kind, x, 5, #label + 2, 1, label,
                    { background = on and ui.theme.accent or ui.theme.panel,
                        foreground = on and ui.inkOn(ui.theme.accent) or ui.theme.ink })
                x = x + #label + 3
            end
            admin.page = admin.rows(scene, 7, bottom, ids, admin.page, function(id, y)
                admin.trackLine(id, y, width)
            end)
            if #ids == 0 then
                ui.wrappedText(target, 2, 8, "Drop .dfpwm files on this screen, or IMPORT"
                    .. " them from a disk drive.", width - 2, 3, ui.theme.muted)
            end
        end,
        act = function(action, scene)
            if action == "__files" then
                admin.dropped(scene.dropped)
            elseif action == "import" then
                admin.importDisk()
            elseif action == "page:prev" or action == "page:next" then
                admin.page = admin.page + (action == "page:next" and 1 or -1)
            elseif action:match("^kind:") then
                admin.kind, admin.page = action:match("^kind:(.+)$"), 1
            elseif action:match("^row:") then
                admin.editTrack(action:match("^row:(.+)$"))
            else
                return false
            end
            return true
        end,
    }
end

local function radiosPage()
    return {
        id = "radios", label = "Radios", short = "Radio",
        draw = function(scene)
            local width = target.getSize()
            local bottom = ui.contentBottom(target)
            local ids = {}
            for id in pairs(state.radios) do ids[#ids + 1] = id end
            table.sort(ids, library.order)
            ui.text(target, 2, 4, "RADIOS  " .. #ids, ui.theme.muted)
            scene:button("new", width - 12, 4, 12, 1, "NEW RADIO", { background = ui.theme.accent,
                foreground = ui.inkOn(ui.theme.accent) })
            local now = util.nowMs()
            admin.radioPage = admin.rows(scene, 6, bottom, ids, admin.radioPage, function(id, y)
                local r = state.radios[id]
                local public = radio.public(r, now)
                ui.fill(target, 2, y, 2, 1, music.color(r.color))
                local left = r.name .. "  " .. tostring(r.number or "--")
                ui.text(target, 5, y, ui.truncate(left, 26), ui.theme.ink)
                local right = public.giveaway and "GIVEAWAY" or public.now
                    and (public.now.title) or "Off air"
                ui.text(target, 32, y, ui.truncate(right .. "  " .. public.listeners,
                    width - 32), public.giveaway and colors.yellow or ui.theme.muted)
            end)
            if #ids == 0 then
                ui.wrappedText(target, 2, 7, "A radio plays songs from the library with hosts,"
                    .. " ads and giveaways between them. Make one with NEW RADIO.",
                    width - 2, 3, ui.theme.muted)
            end
        end,
        act = function(action)
            if action == "new" then
                local name = ui.input(target, "RADIO NAME", { maxLength = 20 })
                if name and util.trim(name) ~= "" then
                    local r = radio.create(name)
                    admin.editRadio(r.radio_id)
                end
            elseif action == "page:prev" or action == "page:next" then
                admin.radioPage = admin.radioPage + (action == "page:next" and 1 or -1)
            elseif action:match("^row:") then
                admin.editRadio(action:match("^row:(.+)$"))
            else
                return false
            end
            return true
        end,
    }
end

local function serverLoop()
    while running do
        local sender, message = rednet.receive(PROTOCOL, 2)
        if sender then route(sender, message) end
    end
end

-- Everything this server does in the background, a step at a time, so the
-- radio keeps moving whatever else is slow.
local background = { beat_at = 0, cloud_at = 0, migrate_at = 0 }

function background.step()
    local now = util.nowMs()
    if state.server_token then pcall(radio.tick) end
    for id, upload in pairs(cache.uploads) do
        if upload.expires_at + 30000 <= now then
            cache.uploads[id] = nil
            store.tickets[upload.ticket or ""] = nil
            store.forget(upload.pieces)
        end
    end
    -- FoxyOS 18: telling the Bank it is up -- which is how Pockets and Cloud
    -- Servers learn which computer it is -- and finding the Cloud Servers.
    if state.server_token and now >= background.beat_at then
        background.beat_at = now + 30 * 1000
        local beat, _, code = bankAsk("MUSIC_BEAT", { version = PROGRAM_VERSION })
        if not beat and code == "MUSIC_AUTH" then
            logActivity("The Bank no longer knows this Music Server", colors.red)
        end
    end
    if now >= background.cloud_at then
        background.cloud_at = now + 60 * 1000
        pcall(store.refresh)
    end
    pcall(store.dropPending)
    if now >= background.migrate_at then
        background.migrate_at = now + 30 * 1000
        pcall(library.migrate)
    end
end

local function radioLoop()
    while running do
        background.step()
        sleep(2)
    end
end

local function updateLoop()
    while running do
        net.autoUpdate(config, "music", ROOT, nil,
            { programVersion = PROGRAM_VERSION })
        sleep(10)
    end
end

local function dashboardLoop()
    ui.serverTabs({
        version = config.version, files = true,
        target = target, title = "MUSIC SERVER", subtitle = "v" .. config.version,
        cards = function()
            local tracks, radios, online = 0, 0, 0
            for _ in pairs(state.tracks) do tracks = tracks + 1 end
            for _ in pairs(state.radios) do radios = radios + 1 end
            local now = util.nowMs()
            for _, player in pairs(state.players) do
                if now - (player.last_seen or 0) < 15000 then online = online + 1 end
            end
            return { { "TRACKS", tracks, ui.theme.accent },
                { "RADIOS", radios, colors.magenta },
                { "PLAYERS", online .. " on", ui.theme.success } }
        end,
        lines = function()
            local banked = 0
            for _, track in pairs(state.tracks) do
                if not track.pieces then banked = banked + 1 end
            end
            local lines = {
                { "SERVER  " .. tostring(state.server_id or "Not registered") },
                { "BANK  " .. status.bank .. (bankUp() and "" or "  (playing without it)"),
                    status.bank_color },
                { "CLOUD SERVERS  " .. #store.servers .. (banked > 0 and ("  MOVING "
                    .. banked .. " SONG" .. (banked == 1 and "" or "S")) or ""),
                    #store.servers > 0 and ui.theme.ink or ui.theme.warning },
                { "LIBRARY  " .. util.sizeText(library.bytes()) .. " on the Cloud Servers  "
                    .. status.streams .. " streams", ui.theme.muted },
            }
            local now = util.nowMs()
            for _, player in pairs(state.players) do
                local public = people.publicPlayer(player, now)
                lines[#lines + 1] = { (public.online and "+ " or "- ") .. public.label .. "  "
                    .. (public.now and public.now.title or public.mode),
                    public.online and ui.theme.ink or ui.theme.muted }
            end
            return lines
        end,
        pages = { libraryPage(), radiosPage() },
        activity = activity, root = ROOT, colorTitle = "Server colour",
        actions = { { id = "stop", label = "STOP",
            hint = "Players and radios go quiet",
            color = ui.theme.danger, run = function(terminated)
                if terminated or ui.confirm(target, "STOP MUSIC SERVER",
                    "Every Music Player and radio goes quiet.", "STOP", "BACK") then
                    running = false
                    save()
                    return true
                end
            end } },
        running = function() return running end,
    })
end

-- Registering with the Bank once, with the operator's code: the library is
-- kept on the Cloud Servers in the Bank's name.
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
            local registered, err = bank:request("MUSIC_SERVER_REGISTER",
                { code = code, name = "Music " .. os.getComputerID() }, 6)
            if registered then
                state.server_token = registered.server_token
                state.server_id = registered.server_id
                save()
                logActivity("Registered as " .. tostring(registered.server_id), colors.lime)
            else
                ui.message(target, "error", "NOT REGISTERED", err, 2)
            end
        end
    end
    return state.server_token ~= nil
end

if rawget(_G, "PUMPE_TEST_MODE") == "music_server" then
    admin.libraryPage, admin.radiosPage = libraryPage, radiosPage
    return { actions = actions, state = state, live = live, cache = cache,
        library = library, radio = radio, people = people, admin = admin,
        store = store, background = background, status = status,
        register = register, route = route, stop = function() running = false end }
end

if type(ui.useMainColor) == "function" then ui.useMainColor(ROOT) end
ui.usePhoneStyle(false)
ui.boot(target, "MUSIC SERVER", (ui.osLabel and ui.osLabel(config) or "FoxyOS"))
net.autoUpdate(config, "music", ROOT, nil,
    { force = true, programVersion = PROGRAM_VERSION })
net.openModems()

if not register() then
    ui.clear(target)
    print("Music Server not registered.")
    return
end

net.host(PROTOCOL, config.music_hostname or "MUSIC_SERVER")
logActivity("Music Server online on #" .. os.getComputerID(), colors.lime)

parallel.waitForAny(serverLoop, radioLoop, updateLoop, dashboardLoop)
pcall(rednet.unhost, PROTOCOL)
save()
ui.clear(target)
print("Music Server stopped safely.")
