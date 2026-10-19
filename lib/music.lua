-- Music, FoxyOS 17. Songs are DFPWM1a at 48 kHz: one bit a sample, so 6000
-- bytes a second, and a Cloud Server piece of 16 KB is about 2.7 seconds --
-- exactly what a speaker takes at once. The Music Server keeps the library
-- and the radios; the pieces are on the Cloud Servers like any FoxyCloud
-- file, and whatever plays a song fetches them itself, one piece ahead.
--
-- Shared by the Music Player, the CCG Casino, the Music Server and, FoxyOS 18,
-- the Pocket Desktop.

local util = require("lib.util")
local net = require("lib.net")

local music = { BYTES_PER_SECOND = 6000, MOST_SAMPLES = 128 * 1024 }

music.KINDS = { "song", "host", "ad", "giveaway" }
music.KIND_NAMES = { song = "Song", host = "Host", ad = "Ad", giveaway = "Giveaway" }

-- How long a song of `size` bytes plays, in milliseconds.
function music.lengthMs(size)
    return math.floor((tonumber(size) or 0) * 1000 / music.BYTES_PER_SECOND)
end

-- 3:05, or 1:02:03 for anything an hour long.
function music.clock(ms)
    local seconds = math.max(0, math.floor((tonumber(ms) or 0) / 1000))
    local hours, minutes = math.floor(seconds / 3600), math.floor(seconds / 60) % 60
    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, minutes, seconds % 60)
    end
    return string.format("%d:%02d", minutes, seconds % 60)
end

-- The colours a radio may have, by the name ComputerCraft gives them.
music.COLORS = { "red", "orange", "yellow", "lime", "green", "cyan", "lightBlue",
    "blue", "purple", "magenta", "pink", "brown", "white", "lightGray" }

function music.color(name)
    return colors[tostring(name or "")] or colors.orange
end

-- Asking the Music Server, the way a Pocket asks the Bank. Given `where` --
-- a function asking the Bank which computer the registered Music Server is
-- (MUSIC_WHERE) -- it goes only there: anything that hands the Music Server
-- a session must not hand it to any computer that took the name.
function music.client(config, where)
    local client = net.client({ protocol = config.music_protocol or "PUMPE_MUSIC_V1",
        hostname = config.music_hostname or "MUSIC_SERVER" })
    if where then
        function client:discover()
            self.serverId = where()
            return self.serverId
        end
    end
    return client
end

-- Every speaker on this computer, wired or beside it.
function music.speakers()
    local found = {}
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "speaker" then
            found[#found + 1] = peripheral.wrap(name)
        end
    end
    return found
end

function music.stop(speakers)
    for _, speaker in ipairs(speakers or {}) do
        if speaker.stop then pcall(speaker.stop) end
    end
end

-- A song kept on this computer, FoxyOS 18 (Offline Listening), as a plan
-- music.play takes: the same pieces, read from the file one at a time.
function music.keptPlan(path, size, each)
    each = math.max(1, tonumber(each) or 16 * 1024)
    local plan = { path = path, chunks = {} }
    for first = 1, math.max(0, tonumber(size) or 0), each do
        plan.chunks[#plan.chunks + 1] = { at = first - 1,
            size = math.min(each, size - first + 1) }
    end
    return plan
end

local function keptPiece(plan, chunk)
    local handle = fs.open(plan.path, "rb")
    if not handle then return nil, "That song is not on this computer any more", "MISSING" end
    local ok, data = pcall(function()
        if handle.seek and handle.read then
            handle.seek("set", chunk.at)
            return handle.read(chunk.size)
        end
        return (handle.readAll() or ""):sub(chunk.at + 1, chunk.at + chunk.size)
    end)
    pcall(handle.close)
    if ok and type(data) == "string" and #data == chunk.size then return data end
    return nil, "The song kept here is damaged", "DAMAGED"
end

-- One piece of a song, from whichever of its copies answers whole.
function music.piece(plan, index, protocol)
    local chunk = plan.chunks and plan.chunks[index]
    if not chunk then return nil, "There is no such piece", "MISSING" end
    if plan.path then return keptPiece(plan, chunk) end
    local err, code
    for _, serverId in ipairs(chunk.servers or {}) do
        local got
        got, err, code = net.cloud.ask(plan, serverId, "CHUNK_GET",
            { ticket = plan.ticket, chunk_id = chunk.id }, protocol)
        if got and type(got.data) == "string" and #got.data == chunk.size then
            return got.data
        elseif got then
            err, code = "A piece came back damaged", "CLOUD_DAMAGED"
        end
    end
    return nil, err or "A Cloud Server is not answering", code or "CLOUD_OFFLINE"
end

-- Hands samples to every speaker, waiting while one is still full. A speaker
-- says it has room with an event, and an event can be missed while a piece
-- is being fetched -- so it is asked again every half second regardless.
function music.feed(speakers, samples, volume)
    local pending = {}
    for index, speaker in ipairs(speakers) do pending[index] = speaker end
    while #pending > 0 do
        local left = {}
        for _, speaker in ipairs(pending) do
            if not speaker.playAudio(samples, volume) then left[#left + 1] = speaker end
        end
        pending = left
        if #pending > 0 then
            local timer = os.startTimer(0.5)
            while true do
                local event, id = os.pullEvent()
                if event == "speaker_audio_empty" or (event == "timer" and id == timer) then
                    break
                end
            end
        end
    end
end

-- Where `offsetMs` falls: the piece, and how far into it.
function music.seek(plan, offsetMs)
    local skip = math.max(0, math.floor((tonumber(offsetMs) or 0)
        * music.BYTES_PER_SECOND / 1000))
    local index = 1
    while plan.chunks and plan.chunks[index] and skip >= plan.chunks[index].size do
        skip = skip - plan.chunks[index].size
        index = index + 1
    end
    return index, skip
end

-- Plays what `plan` (CLOUD_MUSIC_GET's answer) points at on `speakers`, from
-- options.offset_ms. options.volume() is asked before every piece, so a
-- volume change is heard within a few seconds; options.dfpwm stands in for
-- cc.audio.dfpwm. True at the end, or nil and why it stopped.
function music.play(plan, speakers, options)
    options = options or {}
    local dfpwm = options.dfpwm or require("cc.audio.dfpwm")
    local decoder = dfpwm.make_decoder()
    local index, skip = music.seek(plan, options.offset_ms)
    if not (plan.chunks and plan.chunks[index]) then return true end
    local data, err, code = music.piece(plan, index, options.protocol)
    if not data then return nil, err, code end
    if skip > 0 then data = data:sub(skip + 1) end
    while data do
        local samples = decoder(data)
        local volume = options.volume and options.volume() or 1
        -- A piece bigger than a speaker takes goes in turns.
        for first = 1, #samples, music.MOST_SAMPLES do
            local part = samples
            if first > 1 or #samples > music.MOST_SAMPLES then
                part = {}
                for at = first, math.min(#samples, first + music.MOST_SAMPLES - 1) do
                    part[#part + 1] = samples[at]
                end
            end
            music.feed(speakers, part, volume)
        end
        if options.progress then options.progress(index, #plan.chunks) end
        index = index + 1
        if not plan.chunks[index] then break end
        -- Fetched while the last one plays.
        data, err, code = music.piece(plan, index, options.protocol)
        if not data then return nil, err, code end
    end
    return true
end

-- Sends a song's bytes where an upload's plan says (net.cloud.put), for a
-- Music Player, a Pocket or the Music Server itself.
function music.upload(plan, body, protocol, progress)
    return net.cloud.put(plan, body, protocol, progress)
end

-- What a song is called, from what a file was called: "My Song.dfpwm" is
-- "My Song".
function music.titleFrom(name)
    local base = tostring(name or ""):match("([^/\\]+)$") or ""
    base = base:gsub("%.[Dd][Ff][Pp][Ww][Mm]$", ""):gsub("[_]+", " ")
    return util.safeText(util.trim(base), 28)
end

function music.isAudio(name)
    return tostring(name or ""):lower():match("%.dfpwm$") ~= nil
end

return music
