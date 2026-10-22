local ROOT = fs.getDir(shell.getRunningProgram())
if ROOT == "" then ROOT = "." end
package.path = package.path .. ";" .. fs.combine(ROOT, "?.lua")
    .. ";" .. fs.combine(ROOT, "?/init.lua")

-- Stamped by tools/build_release_manifest.js. A program running beside a
-- config.lua from a different release means a partial install.
local PROGRAM_VERSION = "18.3.0"
local config = require("config")
local util = require("lib.util")
local net = require("lib.net")
local ui = require("lib.ui")
local music = require("lib.music")

-- The Music Player, FoxyOS 17: a computer with speakers that plays the Music
-- Library and the radios. Somebody signs in on it once, with their Foxy
-- name and PIN, and it is theirs: songs from the library count against their
-- day (radios never do), and the Music app on their Pocket can tell it what
-- to play from anywhere.
--
-- It never decides what to play by itself. The Music Server says, and this
-- fetches the song's pieces from the Cloud Servers one ahead of the speaker.
-- A monitor beside it, if there is one, shows what is on -- and during a
-- radio giveaway, the number to call.
--
-- FoxyOS 18, Offline Listening: with FoxyMusic+, songs from the library can
-- be kept on this computer. They play from here -- the Cloud Servers are not
-- asked -- and while the Music Server is off they are what the Library shows,
-- chosen and controlled on this screen.
local target = term.current()
local bank = net.client(config)
local running = true
local CLOUD = config.cloud_protocol or "PUMPE_CLOUD_V1"
local dataFile = fs.combine(ROOT, "music_player_v1.dat")
local state = util.loadTable(dataFile, {})
-- The Music Server is found through the Bank: a name anybody could take.
-- FoxyOS 18: the computer the Bank last named, while the Bank is not
-- answering -- the Music Server goes on without it.
local server = music.client(config, function()
    local where = bank:request("MUSIC_WHERE", {}, 4)
    if where and where.computer_id then
        if state.music_server ~= where.computer_id then
            state.music_server = where.computer_id
            util.saveTable(dataFile, state)
        end
        return where.computer_id
    end
    return state.music_server
end)
-- What the Music Server last said, and what is coming out of the speakers.
local shared = { player = nil, playing = nil, error = nil, seq = nil }
local view = { page = 1, sort = "new", query = "", radios = nil }

local function save()
    util.saveTable(dataFile, state)
end

local function ask(action, payload, timeout)
    payload = payload or {}
    payload.player_token = state.player_token
    return server:request(action, payload, timeout or 5)
end

local function say(kind, title, body)
    ui.message(target, kind, title, body, 1.6)
end

-- Signing in --------------------------------------------------------------------------

local function signIn()
    while not state.player_token do
        ui.clear(target)
        ui.header(target, "MUSIC PLAYER", "Sign in with your Foxy Account")
        local name = ui.input(target, "YOUR NAME", { maxLength = 20,
            hint = "The name of your Foxy Account" })
        if not name then return false end
        local pin = ui.pin(target, "PIN FOR " .. string.upper(name), true)
        if pin then
            local session, err = bank:request("LOGIN", { name = name, pin = pin }, 6)
            if not session then
                say("error", "NOT SIGNED IN", err or "The Bank did not answer")
            else
                local label = ui.input(target, "NAME THIS PLAYER", {
                    initial = session.account.name .. "'s Player", maxLength = 20,
                    hint = "How it is listed in the Music app" })
                local hello, helloError = server:request("MUSIC_HELLO", {
                    session_token = session.session_token,
                    label = label or (session.account.name .. "'s Player") }, 6)
                if hello then
                    state.player_token = hello.player_token
                    state.owner_name = session.account.name
                    save()
                    shared.player = hello.player
                    say("success", "SIGNED IN", "This Music Player is "
                        .. session.account.name .. "'s now")
                else
                    say("error", "MUSIC SERVER", helloError or "The Music Server did not answer")
                end
            end
        end
    end
    return true
end

-- Playing ------------------------------------------------------------------------------

local speakers = music.speakers()

local function changed()
    os.queueEvent("music_change")
end

-- Offline Listening, FoxyOS 18 -------------------------------------------------------------
-- Songs kept on this computer, by track id. They stay playable while the
-- Music Server is off for OFFLINE_DAYS in-game days after it last said the
-- owner has FoxyMusic+, and go the moment it says they do not.
local OFFLINE_DAYS = 10
local kept = { dir = fs.combine(ROOT, "offline") }
state.offline = type(state.offline) == "table" and state.offline or {}

function kept.path(trackId) return fs.combine(kept.dir, tostring(trackId) .. ".dfpwm") end

function kept.get(trackId)
    local entry = state.offline[tostring(trackId or "")]
    if entry and fs.exists(kept.path(entry.track_id)) then return entry end
    return nil
end

function kept.list()
    local list = {}
    for id in pairs(state.offline) do list[#list + 1] = kept.get(id) end
    table.sort(list, function(a, b) return a.title:lower() < b.title:lower() end)
    return list
end

function kept.bytes()
    local total = 0
    for _, entry in pairs(state.offline) do total = total + (tonumber(entry.size) or 0) end
    return total
end

function kept.allowed()
    return state.offline_day ~= nil and util.ingameDay() - state.offline_day <= OFFLINE_DAYS
end

function kept.remove(trackId)
    local entry = state.offline[tostring(trackId or "")]
    if not entry then return end
    pcall(fs.delete, kept.path(entry.track_id))
    state.offline[entry.track_id] = nil
    save()
end

function kept.clear()
    for id in pairs(state.offline) do pcall(fs.delete, kept.path(id)) end
    state.offline, state.offline_day = {}, nil
    save()
end

-- What the Music Server says of the owner's plan, every tick. Only a plain no
-- takes the songs away: a Music Server from before FoxyOS 18 says nothing.
function kept.heard(player)
    if type(player) ~= "table" then return end
    if player.offline == true and state.offline_day ~= util.ingameDay() then
        state.offline_day = util.ingameDay()
        save()
    elseif player.offline == false and (state.offline_day or next(state.offline)) then
        kept.clear()
    end
end

-- Keeps a song from the library, piece by piece -- a ticket that runs out
-- part way is asked for again -- with `progress(done, total)` as it goes.
function kept.download(trackId, progress)
    local got, err, code = ask("MUSIC_DOWNLOAD", { track_id = trackId }, 8)
    if not got then return nil, err, code end
    local track = got.track
    local most = tonumber(config.music_offline_bytes) or 16 * 1024 * 1024
    local before = state.offline[track.track_id]
    if kept.bytes() - (before and before.size or 0) + track.size > most then
        return nil, "Offline songs are full (" .. util.sizeText(most) .. "). Remove some first",
            "FULL"
    end
    if fs.getFreeSpace(ROOT) < track.size + 100 * 1024 then
        return nil, "This computer's disk is full", "FULL"
    end
    fs.makeDir(kept.dir)
    local path = kept.path(track.track_id)
    local part = path .. ".part"
    if fs.exists(part) then fs.delete(part) end
    local handle = fs.open(part, "wb")
    if not handle then return nil, "Cannot write to this computer", "DISK" end
    local index, plan, again = 1, got.plan, false
    while index <= #plan.chunks do
        local data, pieceError, pieceCode = music.piece(plan, index, CLOUD)
        if not data and pieceCode == "BAD_TICKET" and not again then
            again = true
            local renewed = ask("MUSIC_DOWNLOAD", { track_id = trackId }, 8)
            plan = renewed and renewed.plan or plan
        elseif not data then
            handle.close()
            fs.delete(part)
            return nil, pieceError, pieceCode
        else
            handle.write(data)
            if progress then progress(index, #plan.chunks) end
            index, again = index + 1, false
        end
    end
    handle.close()
    if fs.exists(path) then fs.delete(path) end
    fs.move(part, path)
    state.offline[track.track_id] = { track_id = track.track_id, title = track.title,
        artist = track.artist, uploader_name = track.uploader_name, size = track.size,
        length_ms = track.length_ms or music.lengthMs(track.size), kept_day = util.ingameDay() }
    save()
    return state.offline[track.track_id]
end

-- Playing what is kept from this screen alone, while the Music Server is off:
-- a queue, where in it, and a seq of its own, so the speakers stop at once
-- when it changes.
function kept.play(trackId, queue)
    local list, at = {}, 1
    for _, id in ipairs(queue or { trackId }) do
        if kept.get(id) then
            list[#list + 1] = id
            if id == trackId then at = #list end
        end
    end
    shared.here = { queue = list, index = at, offset_ms = 0, paused = false,
        seq = ((shared.here and shared.here.seq) or 0) + 1 }
    changed()
end

function kept.control(command)
    local here = shared.here
    if not here then return end
    if command == "stop" then
        shared.here = nil
    elseif command == "pause" then
        here.paused = true
        here.offset_ms = shared.playing and util.nowMs() - shared.playing.started
            or here.offset_ms
    elseif command == "resume" then
        here.paused = false
    elseif command == "next" or command == "previous" then
        here.index, here.offset_ms = math.max(1, here.index + (command == "next" and 1 or -1)), 0
        if here.index > #here.queue then shared.here = nil end
    end
    here.seq = here.seq + 1
    changed()
end

-- What is playing here, the way the Music Server describes a player.
function kept.view()
    local here = shared.here or {}
    local entry = kept.get((here.queue or {})[here.index or 1])
    return { mode = "offline", label = "Offline", paused = here.paused == true,
        volume = state.volume or 2, now = entry and { title = entry.title,
            artist = entry.artist, uploader_name = entry.uploader_name,
            length_ms = entry.length_ms, label = "OFFLINE" } }
end

-- Asks the Music Server what this player should be doing, and says where it
-- is in the song.
local function tickOnce()
    local position
    if shared.playing then position = util.nowMs() - shared.playing.started end
    local answer, _, code = ask("MUSIC_TICK", { position_ms = position,
        play_no = shared.playing and shared.playing.play_no, version = PROGRAM_VERSION }, 3)
    if answer then
        -- Told to play something else from the Music app: that takes over
        -- from songs playing here while it was off.
        if shared.here and shared.server_seq and answer.player.seq ~= shared.server_seq then
            shared.here = nil
        end
        shared.player, shared.server_seq = answer.player, answer.player.seq
        shared.misses, shared.server_down = 0, false
        kept.heard(answer.player)
        if (shared.here and "H" .. shared.here.seq or shared.player.seq) ~= shared.seq then
            changed()
        end
    elseif not code then
        -- Three ticks unanswered: the Music Server is off.
        shared.misses = (shared.misses or 0) + 1
        if shared.misses >= 3 and not shared.server_down then
            shared.server_down = true
            changed()
        end
    elseif code == "NOT_A_PLAYER" then
        -- Signed out from somewhere else.
        state.player_token = nil
        save()
        shared.player = nil
        running = false
        changed()
    end
end

local function tickLoop()
    while running do
        tickOnce()
        sleep(1)
    end
end

local function idle(player)
    return not player or player.mode == "idle" or player.paused
end

local function waitFor(seconds, stop)
    local timer = os.startTimer(seconds)
    repeat
        local event, id = os.pullEvent()
    until (event == "timer" and id == timer) or (event == "music_change" and stop())
end

-- What the speakers should be following: songs played here, or the Music
-- Server's player.
local function seqNow()
    if shared.here then return "H" .. shared.here.seq end
    return shared.player and shared.player.seq
end

local function moved()
    return seqNow() == nil or seqNow() ~= shared.seq
end

-- A song kept here, played from here.
local function playKept()
    local here = shared.here
    local entry = kept.get(here.queue[here.index])
    shared.seq = seqNow()
    if not entry or not kept.allowed() then
        shared.here, shared.playing = nil, nil
        shared.error = entry and ("FoxyMusic+ was last confirmed over " .. OFFLINE_DAYS
            .. " days ago") or nil
        return
    end
    if here.paused or #speakers == 0 then
        shared.playing = nil
        waitFor(2, function() return true end)
        return
    end
    shared.error = nil
    shared.playing = { item = entry, mode = "offline", started = util.nowMs()
        - (here.offset_ms or 0) }
    local finished, playError
    parallel.waitForAny(function()
        finished, playError = music.play(music.keptPlan(kept.path(entry.track_id), entry.size),
            speakers, { offset_ms = here.offset_ms,
                volume = function() return state.volume or 2 end })
    end, function()
        repeat os.pullEvent("music_change") until moved()
    end)
    if finished then
        here.index, here.offset_ms = here.index + 1, 0
        if here.index > #here.queue then shared.here, shared.playing = nil, nil end
    else
        music.stop(speakers)
        if playError then
            shared.error = playError
            kept.control("next")
        end
    end
end

-- One song, or one radio item, from asking what to play to its end -- or to
-- being told to do something else, which stops the speakers at once.
local function audioStep()
    local player = shared.player
    speakers = music.speakers()
    if shared.here then return playKept() end
    if idle(player) or #speakers == 0 or shared.server_down then
        shared.playing = nil
        shared.seq = player and player.seq
        waitFor(2, function() return true end)
        return
    end
    local stream, err, code = ask("MUSIC_STREAM", {}, 8)
    if not stream then
        shared.playing, shared.error = nil, err
        shared.seq = player.seq
        if code ~= "PAUSED" and code ~= "IDLE" and code ~= "MUSIC_LIMIT" then
            sleep(2)
        else
            waitFor(30, function() return true end)
        end
        return
    end
    shared.error = nil
    shared.seq = stream.seq
    local streamAt = util.nowMs()
    if stream.mode == "static" then
        -- FoxyOS 18.2: between stations on the dial, or a station with
        -- nothing on. Asked again when it runs out, or when tuned elsewhere.
        shared.playing = { mode = "static", station = stream.station, started = streamAt }
        parallel.waitForAny(function()
            music.static(speakers, stream.length_ms or 5000,
                shared.player and shared.player.volume or 2)
        end, function()
            repeat os.pullEvent("music_change") until moved()
        end)
        return
    end
    shared.playing = { item = stream.item, mode = stream.mode, play_no = stream.play_no,
        radio = stream.radio, started = streamAt - (stream.offset_ms or 0) }
    -- A song kept here plays from here, counted all the same.
    local plan = stream.plan
    local entry = stream.mode == "library" and stream.item and kept.get(stream.item.track_id)
    if entry and entry.size == stream.item.size then
        plan = music.keptPlan(kept.path(entry.track_id), entry.size)
    end
    local finished, playError
    parallel.waitForAny(function()
        finished, playError = music.play(plan, speakers, {
            offset_ms = stream.offset_ms, protocol = CLOUD,
            volume = function() return shared.player and shared.player.volume or 2 end })
    end, function()
        repeat os.pullEvent("music_change") until moved()
    end)
    if finished and stream.mode == "radio" then
        -- Everything is with the speakers: the radio's next item starts when
        -- this one is heard to the end.
        local wait = (streamAt + stream.item.length_ms - (stream.offset_ms or 0)
            - util.nowMs()) / 1000
        if wait > 0 then waitFor(wait, moved) end
    elseif finished then
        local nextUp = ask("MUSIC_NEXT", { play_no = stream.play_no })
        if nextUp then
            shared.player = nextUp.player
            shared.seq = nextUp.player.seq
        end
    elseif playError then
        shared.error = playError
        music.stop(speakers)
        sleep(2)
    else
        music.stop(speakers)
    end
end

local function audioLoop()
    while running do audioStep() end
end

-- The monitor -----------------------------------------------------------------------------

local function monitor()
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "monitor" then return peripheral.wrap(name) end
    end
    return nil
end

-- What is on, big enough to read from across a room.
local function drawMonitor()
    local screen = monitor()
    if not screen then return end
    pcall(screen.setTextScale, 1)
    local width, height = screen.getSize()
    local player = shared.here and kept.view() or shared.player
    local now = player and player.now
    local band = player and player.radio and music.color(player.radio.color)
        or ui.theme.accent
    ui.clear(screen, ui.theme.background)
    ui.fill(screen, 1, 1, width, 2, band)
    ui.text(screen, 2, 1, ui.truncate(player and player.radio and player.radio.name
        or "MUSIC PLAYER", width - 2), ui.inkOn(band), band)
    if player and player.radio and player.radio.number then
        ui.text(screen, 2, 2, "Call " .. player.radio.number, ui.inkOn(band), band)
    end
    if now then
        ui.center(screen, math.floor(height / 2) - 1, ui.truncate(now.title, width - 2),
            ui.theme.ink)
        ui.center(screen, math.floor(height / 2), ui.truncate(now.artist, width - 2),
            ui.theme.muted)
        if now.label then
            ui.center(screen, math.floor(height / 2) + 1, ui.truncate(now.label, width - 2),
                colors.yellow)
        end
    else
        ui.center(screen, math.floor(height / 2), player and player.paused and "Paused"
            or "Nothing playing", ui.theme.muted)
    end
    local giveaway = player and player.radio and player.radio.giveaway
    if giveaway then
        ui.fill(screen, 1, height - 1, width, 2, colors.yellow)
        ui.center(screen, height - 1, "GIVEAWAY! CALL " .. giveaway.number, colors.black,
            colors.yellow)
        ui.center(screen, height, music.clock(giveaway.closes_in_ms) .. " left",
            colors.black, colors.yellow)
    end
end

local function monitorLoop()
    while running do
        pcall(drawMonitor)
        sleep(1)
    end
end

-- The screen ------------------------------------------------------------------------------

local function control(command, extra)
    local payload = extra or {}
    payload.command = command
    local answer, err = ask("MUSIC_CONTROL", payload)
    if not answer then
        say("error", "MUSIC SERVER", err or "The Music Server did not answer")
        return nil
    end
    shared.player = answer.player
    changed()
    return answer.player
end

local function header(subtitle)
    ui.clear(target)
    ui.header(target, "MUSIC PLAYER", subtitle, util.formatClock())
end

local function nowPage(spec)
    while running do
        local here = shared.here ~= nil
        local player = here and kept.view() or shared.player or {}
        local now = player.now
        local width = target.getSize()
        header((state.owner_name or "") .. (player.label and ("  " .. player.label) or ""))
        local scene = ui.scene(target)
        local y = 5
        if player.radio then
            local band = music.color(player.radio.color)
            ui.fill(target, 2, 4, width - 2, 1, band)
            ui.text(target, 3, 4, ui.truncate(player.radio.name .. (player.radio.number
                and ("  " .. player.radio.number) or "") .. "  LIVE", width - 4),
                ui.inkOn(band), band)
            y = 6
        end
        if now then
            -- FoxyOS 18.3: the cover on the left -- the song's, or the radio's
            -- -- and what it is beside it.
            ui.cover(target, 3, y, now.cover or (player.radio and player.radio.cover))
            local x = 4 + ui.COVER_WIDTH + 1
            if now.label then ui.text(target, x, y, ui.truncate(now.label, width - x),
                colors.yellow) end
            ui.text(target, x, y + 1, ui.truncate(now.title, width - x), ui.theme.ink)
            ui.text(target, x, y + 2, ui.truncate(now.artist .. (now.uploader_name
                and ("  (by " .. now.uploader_name .. ")") or ""), width - x), ui.theme.muted)
            local position = shared.playing and (util.nowMs() - shared.playing.started)
                or now.position_ms or 0
            position = math.max(0, math.min(now.length_ms or 0, position))
            ui.progress(target, 8, y + 4, width - 15, position, math.max(1, now.length_ms or 1),
                player.radio and music.color(player.radio.color) or ui.theme.accent,
                ui.theme.panel)
            ui.text(target, 2, y + 4, music.clock(position), ui.theme.muted)
            ui.text(target, width - 5, y + 4, music.clock(now.length_ms), ui.theme.muted)
        elseif shared.server_down then
            ui.center(target, y + 1, "The Music Server is off", ui.theme.warning)
            ui.center(target, y + 2, next(state.offline) and "Your downloaded songs are in Library"
                or "Songs you download with FoxyMusic+ play even then", ui.theme.muted)
        else
            ui.center(target, y + 1, player.notice or "Nothing playing", player.notice
                and ui.theme.warning or ui.theme.muted)
            ui.center(target, y + 2, "Pick a song in Library or a station in Radio",
                ui.theme.muted)
        end
        local radio = player.radio
        if radio and radio.giveaway then
            ui.fill(target, 2, 13, width - 2, 1, colors.yellow)
            ui.center(target, 13, "GIVEAWAY! Call " .. radio.giveaway.number .. " now  "
                .. music.clock(radio.giveaway.closes_in_ms) .. " left", colors.black,
                colors.yellow)
        elseif radio and radio.winner and radio.winner.name then
            ui.center(target, 13, radio.winner.name .. " won " .. util.money(radio.winner.prize,
                config.currency) .. " in the giveaway", colors.yellow)
        elseif radio and radio.special then
            ui.center(target, 13, radio.special, ui.theme.accent)
        end
        local buttons = {
            { "previous", "|<" }, { player.paused and "resume" or "pause",
                player.paused and "PLAY" or "PAUSE" }, { "next", ">|" }, { "stop", "STOP" },
            { "quieter", "VOL -" }, { "louder", "VOL +" },
        }
        local each = math.floor((width - 1) / #buttons)
        for index, button in ipairs(buttons) do
            local live = player.mode == "radio" and (button[1] == "next"
                or button[1] == "previous")
            scene:button(button[1], 2 + (index - 1) * each, 15, each - 1, 2, button[2],
                { background = button[1] == "pause" and ui.theme.accent or ui.theme.panel,
                    foreground = button[1] == "pause" and ui.inkOn(ui.theme.accent)
                        or ui.theme.ink, disabled = live or player.mode == nil
                        or (player.mode == "idle" and button[1] ~= "quieter"
                            and button[1] ~= "louder") })
        end
        local volume = tonumber(player.volume) or 2
        local footer = "Volume " .. string.rep("#", math.floor(volume * 2 + 0.5))
            .. string.rep(".", 6 - math.floor(volume * 2 + 0.5))
        if #speakers == 0 then footer = "No speaker attached: put one beside this computer" end
        if shared.error then footer = tostring(shared.error) end
        ui.text(target, 2, 14, ui.truncate(footer, width - 2), (#speakers == 0
            or shared.error) and ui.theme.warning or ui.theme.muted)
        ui.tabBar(scene, target, spec.list, spec.active, nil, { home = false })
        local action = scene:wait({ tickRate = 1 })
        if action and action:match("^tab:") then return action end
        if action == "__terminate" then return "stop" end
        local step = (action == "louder" and 0.5) or (action == "quieter" and -0.5) or nil
        if step and here then
            state.volume = math.max(0, math.min(3, volume + step))
            save()
        elseif step then
            control("volume", { volume = math.max(0, math.min(3, volume + step)) })
        elseif here and action and not action:match("^__") then
            kept.control(action)
        elseif action and action ~= "__tick" and action ~= "__idle" and action ~= "__wake" then
            control(action)
        end
    end
end

-- Keeping a song here, with how far along it is.
local function download(trackId)
    local width = target.getSize()
    header("Downloading")
    ui.center(target, 7, "Keeping it on this Music Player", ui.theme.muted)
    local entry, err = kept.download(trackId, function(done, total)
        ui.progress(target, 4, 9, width - 6, done, total, ui.theme.accent, ui.theme.panel)
        ui.center(target, 11, done .. " of " .. total .. " pieces", ui.theme.muted)
    end)
    if entry then
        say("success", "DOWNLOADED", entry.title .. " plays even when the Music Server is off")
    else
        say("error", "NOT DOWNLOADED", err)
    end
end

-- FoxyOS 18: the songs kept here, the way the Music Server lists its own.
local function keptPage(page, per)
    local items, actual, pages = util.page(kept.list(), page, per)
    return { tracks = items, total = #kept.list(), page = actual, pages = pages, kept = true }
end

local function libraryPage(spec)
    local listed = nil
    while running do
        local width = target.getSize()
        local bottom = ui.contentBottom(target)
        local per = bottom - 6
        local offline = shared.server_down or view.sort == "kept"
        local canKeep = not shared.server_down and shared.player and shared.player.offline
        if offline then
            listed = keptPage(view.page, per)
            view.page = listed.page
        elseif not listed or listed.kept then
            listed = ask("MUSIC_LIBRARY", { query = view.query, sort = view.sort,
                page = view.page, per_page = per })
        end
        header((offline and "Downloaded" or "Music Library")
            .. (listed and ("  " .. listed.total .. " songs") or ""))
        local scene = ui.scene(target)
        if shared.server_down then
            ui.fill(target, 2, 4, width - 2, 1, ui.theme.warning)
            ui.text(target, 3, 4, ui.truncate("The Music Server is off: songs kept here",
                width - 4), ui.inkOn(ui.theme.warning), ui.theme.warning)
        else
            local x = 2
            local sorts = { { "new", "Newest" }, { "title", "A-Z" }, { "popular", "Popular" } }
            if canKeep or next(state.offline) then sorts[4] = { "kept", "Downloaded" } end
            for _, sort in ipairs(sorts) do
                local on = view.sort == sort[1]
                scene:button("sort:" .. sort[1], x, 4, #sort[2] + 2, 1, sort[2],
                    { background = on and ui.theme.accent or ui.theme.panel,
                        foreground = on and ui.inkOn(ui.theme.accent) or ui.theme.ink })
                x = x + #sort[2] + 3
            end
            if not offline then
                scene:button("search", width - 11, 4, 11, 1, view.query ~= "" and ("'" ..
                    ui.truncate(view.query, 7) .. "'") or "SEARCH",
                    { background = ui.theme.panel })
            end
        end
        if not listed then
            ui.center(target, 8, "The Music Server is not answering", ui.theme.warning)
        else
            for index, track in ipairs(listed.tracks) do
                local y = 5 + index
                local here = kept.get(track.track_id)
                ui.text(target, 2, y, ui.truncate(track.title .. "  " .. track.artist,
                    width - 29), ui.theme.ink)
                ui.text(target, width - 26, y, ui.truncate("by " .. tostring(track.uploader_name),
                    17), ui.theme.muted)
                ui.text(target, width - 8, y, music.clock(track.length_ms), ui.theme.muted)
                scene:hotspot("play:" .. track.track_id, 1, y, width - 4, 1)
                if canKeep or here then
                    scene:button("keep:" .. track.track_id, width - 2, y, 1, 1,
                        here and "*" or "v", { background = here and ui.theme.accent
                            or ui.theme.panel, foreground = here and ui.inkOn(ui.theme.accent)
                            or ui.theme.ink })
                end
                if not shared.server_down then
                    scene:button("add:" .. track.track_id, width, y, 1, 1, "+",
                        { background = ui.theme.panel })
                end
            end
            if #listed.tracks == 0 then
                ui.wrappedText(target, 2, 7, offline and (canKeep
                    and "Nothing downloaded yet. Tap v beside a song to keep it here."
                    or "Nothing downloaded. Offline Listening comes with FoxyMusic+.")
                    or view.query ~= "" and "No songs match that."
                    or "The library is empty. Upload the first song!", width - 2, 2,
                    ui.theme.muted)
            end
            if listed.pages > 1 then
                scene:button("prev", 2, bottom, 5, 1, "<", { background = ui.theme.panel })
                ui.center(target, bottom, listed.page .. " / " .. listed.pages, ui.theme.muted)
                scene:button("next", width - 5, bottom, 5, 1, ">", { background = ui.theme.panel })
            end
        end
        ui.tabBar(scene, target, spec.list, spec.active, nil, { home = false })
        local action = scene:wait({ tickRate = 5 })
        if action and action:match("^tab:") then return action end
        if action == "__terminate" then return "stop" end
        local sort = action and action:match("^sort:(.+)$")
        local playId = action and action:match("^play:(.+)$")
        local addId = action and action:match("^add:(.+)$")
        local keepId = action and action:match("^keep:(.+)$")
        if sort then
            view.sort, view.page, listed = sort, 1, nil
        elseif action == "search" then
            view.query = ui.input(target, "SEARCH SONGS", { initial = view.query,
                maxLength = 20 }) or view.query
            view.page, listed = 1, nil
        elseif action == "prev" or action == "next" then
            view.page = view.page + (action == "next" and 1 or -1)
            listed = nil
        elseif keepId and kept.get(keepId) then
            if ui.confirm(target, "REMOVE DOWNLOAD", kept.get(keepId).title .. " stays in the"
                .. " library. It just won't play here while the Music Server is off.",
                "REMOVE", "KEEP") then
                kept.remove(keepId)
            end
        elseif keepId then
            download(keepId)
        elseif playId and shared.server_down then
            local queue = {}
            for _, track in ipairs(listed.tracks) do queue[#queue + 1] = track.track_id end
            if not kept.allowed() then
                say("error", "NOT CONFIRMED", "FoxyMusic+ has to be confirmed by the Music"
                    .. " Server at least every " .. OFFLINE_DAYS .. " days")
            else
                kept.play(playId, queue)
                return "tab:now"
            end
        elseif playId then
            local queue = {}
            for _, track in ipairs(listed.tracks) do queue[#queue + 1] = track.track_id end
            if control("play", { track_id = playId, queue = queue }) then return "tab:now" end
        elseif addId then
            if control("add", { track_id = addId }) then
                say("success", "QUEUED", "Up next after this one")
            end
        elseif action == "__tick" and not offline then
            listed = nil
        end
    end
end

-- FoxyOS 18.2: the Radio app, made small. The dial on top -- a slider, a
-- tenth or a whole one at a time -- and under it the State Radios, today's
-- Featured station and the Radio+ stations saved on this player, all on one
-- page that scrolls when they do not fit.
local dial = { LOW = 875, HIGH = 1080, scroll = 0 }

function dial.label(frequency)
    return string.format("%d.%d", math.floor(frequency / 10), frequency % 10)
end

function dial.saved(stationId)
    for index, id in ipairs(state.saved_stations or {}) do
        if id == stationId then return index end
    end
end

local function radioPage(spec)
    while running do
        local width = target.getSize()
        local bottom = ui.contentBottom(target)
        local player = shared.player or {}
        local frequency = player.frequency or state.frequency or 984
        local tuned = ask("MUSIC_TUNE", { frequency = frequency })
        local favorites = ask("MUSIC_FAVORITES", { saved = state.saved_stations or {} })
        header("Radio  turn the dial")
        local scene = ui.scene(target)
        local found = tuned and tuned.station
        local tint = found and music.color(found.color) or ui.theme.muted
        local rows = {}
        rows[#rows + 1] = function(y)
            ui.text(target, 2, y, ui.truncate(dial.label(frequency) .. "  " .. (found
                and (found.name .. (found.plus and "  RADIO+" or "")) or "~ static ~"), width - 5),
                found and tint or ui.theme.muted)
        end
        rows[#rows + 1] = function(y)
            ui.text(target, 2, y, ui.truncate(found and (found.now and (found.now.title .. " - "
                .. (found.now.artist or "")) or (found.on_air and "Static" or "Off the air"))
                or "Nothing on this frequency", width - 5), ui.theme.muted)
        end
        rows[#rows + 1] = function(y)
            local barW = width - 5
            local at = math.floor((frequency - dial.LOW) / (dial.HIGH - dial.LOW) * (barW - 1) + 0.5)
            for column = 0, barW - 1 do
                local value = dial.LOW + math.floor(column * (dial.HIGH - dial.LOW) / (barW - 1) + 0.5)
                scene:button("dial:" .. value, 2 + column, y, 1, 1, column == at and "|" or ".",
                    { background = column == at and tint or ui.theme.panel, flash = false })
            end
        end
        rows[#rows + 1] = function(y)
            local each = math.floor((width - 9) / 5)
            local buttons = { { "down10", "<<" }, { "down", "<" }, { "up", ">" }, { "up10", ">>" } }
            if found and found.plus then
                buttons[5] = { "save", dial.saved(found.station_id) and "SAVED" or "SAVE" }
            end
            for index, button in ipairs(buttons) do
                scene:button(button[1], 2 + (index - 1) * (each + 1), y, each, 1, button[2],
                    { background = ui.theme.panel, flash = false })
            end
        end
        local function station(entry, id)
            rows[#rows + 1] = function(y)
                local band = music.color(entry.color)
                local line = (entry.label and (entry.label .. " ") or "") .. entry.name .. "  "
                    .. (entry.giveaway and ("GIVEAWAY " .. entry.giveaway.number)
                        or entry.now and entry.now.title or "Off air")
                scene:button(id, 2, y, width - 5, 1, "", { background = band })
                ui.text(target, 3, y, ui.truncate(line, width - 7), ui.inkOn(band), band)
            end
        end
        local function heading(text)
            rows[#rows + 1] = function(y) ui.text(target, 2, y, text, ui.theme.muted) end
        end
        if favorites then
            heading("STATE RADIOS")
            for _, radio in ipairs(favorites.radios) do station(radio, "radio:" .. radio.radio_id) end
            if favorites.featured then
                heading("FEATURED TODAY")
                station(favorites.featured, "station:" .. favorites.featured.station_id)
            end
            heading("SAVED")
            for _, saved in ipairs(favorites.saved) do station(saved, "station:" .. saved.station_id) end
        else
            heading("The Music Server is not answering")
        end
        local room = bottom - 3
        dial.scroll = math.max(0, math.min(dial.scroll, #rows - room))
        for index = 1, math.min(room, #rows - dial.scroll) do
            rows[dial.scroll + index](2 + index)
        end
        if dial.scroll > 0 then
            scene:button("scrollup", width - 2, 3, 3, 1, "^", { background = ui.theme.panel })
        end
        if dial.scroll + room < #rows then
            scene:button("scrolldown", width - 2, bottom - 1, 3, 1, "v",
                { background = ui.theme.panel })
        end
        ui.tabBar(scene, target, spec.list, spec.active, nil, { home = false })
        local action = scene:wait({ tickRate = 2 })
        if action and action:match("^tab:") then return action end
        if action == "__terminate" then return "stop" end
        local moves = { down10 = -10, down = -1, up = 1, up10 = 10 }
        local dialed = tonumber(action and action:match("^dial:(%d+)$"))
        if moves[action] or dialed then
            local value = dialed or frequency + moves[action]
            if value < dial.LOW then value = dial.HIGH end
            if value > dial.HIGH then value = dial.LOW end
            state.frequency = value
            save()
            control("tune", { frequency = value })
        elseif action == "save" and found then
            state.saved_stations = state.saved_stations or {}
            local index = dial.saved(found.station_id)
            if index then table.remove(state.saved_stations, index)
            elseif #state.saved_stations < 20 then
                state.saved_stations[#state.saved_stations + 1] = found.station_id
            end
            save()
        elseif action == "scrollup" then
            dial.scroll = math.max(0, dial.scroll - 3)
        elseif action == "scrolldown" then
            dial.scroll = dial.scroll + 3
        else
            local radioId = action and action:match("^radio:(.+)$")
            local stationId = action and action:match("^station:(.+)$")
            if radioId and control("radio", { radio_id = radioId }) then return "tab:now" end
            if stationId and control("station", { station_id = stationId }) then return "tab:now" end
        end
    end
end

-- Uploading a song dropped on this screen, or kept on a disk.
local function uploadBody(name, body)
    local title = ui.input(target, "SONG TITLE", { initial = music.titleFrom(name),
        maxLength = 28 })
    if not title or util.trim(title) == "" then return end
    local artist = ui.input(target, "ARTIST", { maxLength = 20 })
    if not artist or util.trim(artist) == "" then return end
    header("Uploading " .. title)
    local width = target.getSize()
    local began, err = ask("MUSIC_UPLOAD_BEGIN", { title = title, artist = artist,
        size = #body }, 8)
    if not began then
        say("error", "NOT UPLOADED", err)
        return
    end
    local ok, putError = music.upload(began.plan, body, CLOUD, function(done, total)
        ui.progress(target, 4, 9, width - 6, done, total, ui.theme.accent, ui.theme.panel)
        ui.center(target, 11, done .. " of " .. total .. " pieces", ui.theme.muted)
    end)
    if not ok then
        say("error", "NOT UPLOADED", putError)
        return
    end
    local done, doneError = ask("MUSIC_UPLOAD_DONE", { upload_id = began.upload_id }, 8)
    if done then
        say("success", "IN THE LIBRARY", done.track.title .. ", credited to "
            .. tostring(done.track.uploader_name))
    else
        say("error", "NOT UPLOADED", doneError)
    end
end

local function diskSongs()
    local found = {}
    for _, name in ipairs(fs.list("/")) do
        if name:match("^disk%d*$") and fs.isDir("/" .. name) then
            for _, file in ipairs(fs.list("/" .. name)) do
                if music.isAudio(file) then found[#found + 1] = "/" .. name .. "/" .. file end
            end
        end
    end
    table.sort(found)
    return found
end

local function uploadPage(spec)
    local me
    while running do
        local width = target.getSize()
        me = me or ask("MUSIC_ME", {})
        header("Upload a song")
        local scene = ui.scene(target)
        ui.wrappedText(target, 2, 5, "Drop a .dfpwm file on this screen to put it in the"
            .. " Music Library, with your name on it. Songs are DFPWM1a.", width - 2, 3,
            ui.theme.ink)
        if me then
            local plan = me.music_plus and "FoxyMusic+" or "FoxyCloud+"
            ui.text(target, 2, 9, ui.truncate(me.uploads_limit and ("Today: " .. me.uploads
                .. " of " .. me.uploads_limit .. " uploads. FoxyMusic+ has no limit.")
                or (plan .. ": upload as many as you like"), width - 2), ui.theme.muted)
            ui.text(target, 2, 10, ui.truncate(me.plays_limit and ("Today: " .. me.plays
                .. " of " .. me.plays_limit .. " songs played. Radios are free.")
                or (plan .. ": listen to as much as you like"), width - 2), ui.theme.muted)
        end
        if next(state.offline) then
            ui.text(target, 2, 11, ui.truncate("Offline Listening: " .. #kept.list()
                .. " songs, " .. util.sizeText(kept.bytes()) .. " on this computer", width - 2),
                ui.theme.muted)
        end
        local songs = diskSongs()
        for index, path in ipairs(songs) do
            if 12 + index > ui.contentBottom(target) - 2 then break end
            scene:button("disk:" .. index, 2, 12 + index, width - 2, 1, path,
                { background = ui.theme.panel })
        end
        local bottom = ui.contentBottom(target)
        scene:button("signout", width - 12, bottom, 12, 1, "SIGN OUT",
            { background = ui.theme.danger, foreground = colors.white })
        ui.tabBar(scene, target, spec.list, spec.active, nil, { home = false })
        local action = scene:wait({ files = true, tickRate = 5 })
        if action and action:match("^tab:") then return action end
        if action == "__terminate" then return "stop" end
        local diskIndex = tonumber(action and action:match("^disk:(%d+)$"))
        if action == "__files" then
            local ok, files = pcall(function() return scene.dropped.getFiles() end)
            for _, file in ipairs(ok and files or {}) do
                local name = file.getName and file.getName() or "song.dfpwm"
                local body = file.readAll and file.readAll() or ""
                pcall(file.close)
                if music.isAudio(name) then
                    uploadBody(name, body)
                else
                    say("error", "NOT A SONG", "Songs are .dfpwm files")
                end
            end
            me = nil
        elseif diskIndex and songs[diskIndex] then
            local file = fs.open(songs[diskIndex], "rb")
            local body = file and file.readAll() or ""
            if file then file.close() end
            uploadBody(songs[diskIndex], body)
            me = nil
        elseif action == "signout" then
            if ui.confirm(target, "SIGN OUT", "This Music Player stops being yours and goes"
                .. " quiet. Songs downloaded on it go too.", "SIGN OUT", "STAY") then
                ask("MUSIC_BYE", {})
                kept.clear()
                shared.here = nil
                state.player_token, state.owner_name = nil, nil
                save()
                running = false
                changed()
                return "stop"
            end
        elseif action == "__tick" then
            me = nil
        end
    end
end

local function screenLoop()
    ui.runTabs({
        target = target, title = "MUSIC PLAYER",
        list = { { id = "now", label = "Now Playing", short = "Now" },
            { id = "library", label = "Library", short = "Lib" },
            { id = "radio", label = "Radio" }, { id = "upload", label = "Upload", short = "Up" } },
        pages = { now = nowPage, library = libraryPage, radio = radioPage,
            upload = uploadPage },
        running = function() return running end,
    })
    running = false
end

local function updateLoop()
    while running do
        net.autoUpdate(config, "musicplayer", ROOT, nil,
            { programVersion = PROGRAM_VERSION })
        sleep(15)
    end
end

if rawget(_G, "PUMPE_TEST_MODE") == "music_player" then
    return { state = state, shared = shared, kept = kept, signIn = signIn, tickOnce = tickOnce,
        audioStep = audioStep, screenLoop = screenLoop, drawMonitor = drawMonitor,
        stop = function() running = false end, running = function() return running end }
end

if type(ui.useMainColor) == "function" then ui.useMainColor(ROOT) end
ui.usePhoneStyle(false)
ui.boot(target, "MUSIC PLAYER", (ui.osLabel and ui.osLabel(config) or "FoxyOS"))
net.autoUpdate(config, "musicplayer", ROOT, nil,
    { force = true, programVersion = PROGRAM_VERSION })
net.openModems()

while true do
    running = true
    if not signIn() then break end
    parallel.waitForAny(tickLoop, audioLoop, monitorLoop, screenLoop, updateLoop)
    music.stop(speakers)
    if state.player_token then break end
end
ui.clear(target)
print("Music Player stopped.")
