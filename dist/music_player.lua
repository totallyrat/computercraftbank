local ROOT = fs.getDir(shell.getRunningProgram())
if ROOT == "" then ROOT = "." end
package.path = package.path .. ";" .. fs.combine(ROOT, "?.lua")
    .. ";" .. fs.combine(ROOT, "?/init.lua")

-- Stamped by tools/build_release_manifest.js. A program running beside a
-- config.lua from a different release means a partial install.
local PROGRAM_VERSION = "17.0.0"
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
local target = term.current()
local bank = net.client(config)
-- The Music Server is found through the Bank: a name anybody could take.
local server = music.client(config, function()
    local where = bank:request("MUSIC_WHERE", {}, 4)
    return where and where.computer_id or nil
end)
local running = true
local CLOUD = config.cloud_protocol or "PUMPE_CLOUD_V1"
local dataFile = fs.combine(ROOT, "music_player_v1.dat")
local state = util.loadTable(dataFile, {})
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

-- Asks the Music Server what this player should be doing, and says where it
-- is in the song.
local function tickOnce()
    local position
    if shared.playing then position = util.nowMs() - shared.playing.started end
    local answer, _, code = ask("MUSIC_TICK", { position_ms = position,
        play_no = shared.playing and shared.playing.play_no, version = PROGRAM_VERSION }, 3)
    if answer then
        shared.player = answer.player
        if shared.player.seq ~= shared.seq then changed() end
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

local function moved()
    return not shared.player or shared.player.seq ~= shared.seq
end

-- One song, or one radio item, from asking what to play to its end -- or to
-- being told to do something else, which stops the speakers at once.
local function audioStep()
    local player = shared.player
    speakers = music.speakers()
    if idle(player) or #speakers == 0 then
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
    shared.playing = { item = stream.item, mode = stream.mode, play_no = stream.play_no,
        radio = stream.radio, started = streamAt - (stream.offset_ms or 0) }
    local finished, playError
    parallel.waitForAny(function()
        finished, playError = music.play(stream.plan, speakers, {
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
    local player = shared.player
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
        local player = shared.player or {}
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
            if now.label then ui.center(target, y, now.label, colors.yellow) end
            ui.center(target, y + 1, ui.truncate(now.title, width - 4), ui.theme.ink)
            ui.center(target, y + 2, ui.truncate(now.artist .. (now.uploader_name
                and ("  (by " .. now.uploader_name .. ")") or ""), width - 4), ui.theme.muted)
            local position = shared.playing and (util.nowMs() - shared.playing.started)
                or now.position_ms or 0
            position = math.max(0, math.min(now.length_ms or 0, position))
            ui.progress(target, 8, y + 4, width - 15, position, math.max(1, now.length_ms or 1),
                player.radio and music.color(player.radio.color) or ui.theme.accent,
                ui.theme.panel)
            ui.text(target, 2, y + 4, music.clock(position), ui.theme.muted)
            ui.text(target, width - 5, y + 4, music.clock(now.length_ms), ui.theme.muted)
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
        if action == "quieter" or action == "louder" then
            local step = action == "louder" and 0.5 or -0.5
            control("volume", { volume = math.max(0, math.min(3, volume + step)) })
        elseif action and action ~= "__tick" and action ~= "__idle" and action ~= "__wake" then
            control(action)
        end
    end
end

local function libraryPage(spec)
    local listed = nil
    while running do
        local width = target.getSize()
        local bottom = ui.contentBottom(target)
        local per = bottom - 6
        if not listed then
            listed = ask("MUSIC_LIBRARY", { query = view.query, sort = view.sort,
                page = view.page, per_page = per })
        end
        header("Music Library" .. (listed and ("  " .. listed.total .. " songs") or ""))
        local scene = ui.scene(target)
        local x = 2
        for _, sort in ipairs({ { "new", "Newest" }, { "title", "A-Z" },
            { "popular", "Popular" } }) do
            local on = view.sort == sort[1]
            scene:button("sort:" .. sort[1], x, 4, #sort[2] + 2, 1, sort[2],
                { background = on and ui.theme.accent or ui.theme.panel,
                    foreground = on and ui.inkOn(ui.theme.accent) or ui.theme.ink })
            x = x + #sort[2] + 3
        end
        scene:button("search", width - 11, 4, 11, 1, view.query ~= "" and ("'" ..
            ui.truncate(view.query, 7) .. "'") or "SEARCH", { background = ui.theme.panel })
        if not listed then
            ui.center(target, 8, "The Music Server is not answering", ui.theme.warning)
        else
            for index, track in ipairs(listed.tracks) do
                local y = 5 + index
                local right = music.clock(track.length_ms)
                ui.text(target, 2, y, ui.truncate(track.title .. "  " .. track.artist,
                    width - 27), ui.theme.ink)
                ui.text(target, width - 24, y, ui.truncate("by " .. tostring(track.uploader_name),
                    17), ui.theme.muted)
                ui.text(target, width - 6, y, right, ui.theme.muted)
                scene:hotspot("play:" .. track.track_id, 1, y, width - 2, 1)
                scene:button("add:" .. track.track_id, width, y, 1, 1, "+",
                    { background = ui.theme.panel })
            end
            if #listed.tracks == 0 then
                ui.wrappedText(target, 2, 7, view.query ~= "" and "No songs match that."
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
        if sort then
            view.sort, view.page, listed = sort, 1, nil
        elseif action == "search" then
            view.query = ui.input(target, "SEARCH SONGS", { initial = view.query,
                maxLength = 20 }) or view.query
            view.page, listed = 1, nil
        elseif action == "prev" or action == "next" then
            view.page = view.page + (action == "next" and 1 or -1)
            listed = nil
        elseif playId then
            local queue = {}
            for _, track in ipairs(listed.tracks) do queue[#queue + 1] = track.track_id end
            if control("play", { track_id = playId, queue = queue }) then return "tab:now" end
        elseif addId then
            if control("add", { track_id = addId }) then
                say("success", "QUEUED", "Up next after this one")
            end
        elseif action == "__tick" then
            listed = nil
        end
    end
end

local function radioPage(spec)
    while running do
        local width = target.getSize()
        local listed = ask("MUSIC_RADIOS", {})
        header("Radio  live, and always free")
        local scene = ui.scene(target)
        local radios = listed and listed.radios or {}
        for index, radio in ipairs(radios) do
            local y = 2 + index * 2
            if y + 1 > ui.contentBottom(target) then break end
            local band = music.color(radio.color)
            local on = shared.player and shared.player.mode == "radio"
                and shared.player.radio and shared.player.radio.radio_id == radio.radio_id
            scene:button("radio:" .. radio.radio_id, 2, y, width - 2, 2, "", { background = band })
            ui.text(target, 3, y, ui.truncate((on and "> " or "") .. radio.name .. "  "
                .. tostring(radio.number or ""), width - 14), ui.inkOn(band), band)
            ui.text(target, width - 10, y, radio.listeners .. " on", ui.inkOn(band), band)
            local line = radio.giveaway and ("GIVEAWAY! Call " .. radio.giveaway.number)
                or radio.now and (radio.now.title .. " - " .. radio.now.artist)
                or "Off air"
            ui.text(target, 3, y + 1, ui.truncate(line, width - 4), ui.inkOn(band), band)
        end
        if not listed then
            ui.center(target, 8, "The Music Server is not answering", ui.theme.warning)
        elseif #radios == 0 then
            ui.center(target, 8, "No radios yet", ui.theme.muted)
        end
        ui.tabBar(scene, target, spec.list, spec.active, nil, { home = false })
        local action = scene:wait({ tickRate = 2 })
        if action and action:match("^tab:") then return action end
        if action == "__terminate" then return "stop" end
        local radioId = action and action:match("^radio:(.+)$")
        if radioId and control("radio", { radio_id = radioId }) then return "tab:now" end
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
            ui.text(target, 2, 9, me.uploads_limit and ("Today: " .. me.uploads .. " of "
                .. me.uploads_limit .. " uploads. FoxyCloud+ has no limit.")
                or "FoxyCloud+: upload as many as you like", ui.theme.muted)
            ui.text(target, 2, 10, me.plays_limit and ("Today: " .. me.plays .. " of "
                .. me.plays_limit .. " songs played. Radios are free.")
                or "FoxyCloud+: listen to as much as you like", ui.theme.muted)
        end
        local songs = diskSongs()
        for index, path in ipairs(songs) do
            if 11 + index > ui.contentBottom(target) - 2 then break end
            scene:button("disk:" .. index, 2, 11 + index, width - 2, 1, path,
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
                .. " quiet.", "SIGN OUT", "STAY") then
                ask("MUSIC_BYE", {})
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
    return { state = state, shared = shared, signIn = signIn, tickOnce = tickOnce,
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
