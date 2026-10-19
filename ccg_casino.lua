-- CCG Casino, FoxyOS 17.
-- An Advanced Computer with a wireless or Ender modem, an Advanced Monitor,
-- and -- if it is to make a sound -- speakers.
--
-- A casino table: Roulette, Blackjack, Heads or Tails and Poker, dealt by
-- the CCG Server and played from the CCG app. It belongs to a company, and
-- whoever owns the company runs it from the app's My Casino tab: the game,
-- Auto, the dealer, the music. The monitor is only a display -- nothing is
-- pressed on it -- and the computer's own screen is where it is set up: a
-- Foxy sign-in, a company, a name. That name is in the top left corner of
-- the monitor, so a casino with several tables can tell them apart.
--
-- Music: drop .mid files onto this computer's screen and they are kept in
-- its music folder; the app plays them through the speakers, and they go
-- quieter while a game is on. FoxyOS 17: MIDI from the owner's FoxyCloud,
-- and DFPWM -- songs and radios from the Music Library -- while the owner
-- has FoxyCloud+.

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

local TEST_MODE = rawget(_G, "PUMPE_TEST_MODE")
local devicePath = fs.combine(ROOT, "ccg_casino.dat")
local musicDir = fs.combine(ROOT, "music")
local device = util.loadTable(devicePath, {})
local running = true
local screen = term.current()

local ccg = net.client({
    protocol = config.ccg_protocol or "PUMPE_CCG_V1",
    hostname = config.ccg_hostname or "CCG_SERVER",
})
local bank = net.client(config)

local function saveDevice() util.saveTable(devicePath, device) end
local function now() return util.nowMs() end

-- Drawing ------------------------------------------------------------------------------------
-- A 3x5 font for the code and the numbers that matter, drawn in blocks.

local draw = {}
draw.FONT = {
    ["0"] = { "###", "#.#", "#.#", "#.#", "###" }, ["1"] = { ".#.", "##.", ".#.", ".#.", "###" },
    ["2"] = { "###", "..#", "###", "#..", "###" }, ["3"] = { "###", "..#", ".##", "..#", "###" },
    ["4"] = { "#.#", "#.#", "###", "..#", "..#" }, ["5"] = { "###", "#..", "###", "..#", "###" },
    ["6"] = { "###", "#..", "###", "#.#", "###" }, ["7"] = { "###", "..#", ".#.", ".#.", ".#." },
    ["8"] = { "###", "#.#", "###", "#.#", "###" }, ["9"] = { "###", "#.#", "###", "..#", "###" },
    A = { ".#.", "#.#", "###", "#.#", "#.#" }, B = { "##.", "#.#", "##.", "#.#", "##." },
    C = { ".##", "#..", "#..", "#..", ".##" }, D = { "##.", "#.#", "#.#", "#.#", "##." },
    E = { "###", "#..", "##.", "#..", "###" }, F = { "###", "#..", "##.", "#..", "#.." },
    G = { ".##", "#..", "#.#", "#.#", ".##" }, H = { "#.#", "#.#", "###", "#.#", "#.#" },
    I = { "###", ".#.", ".#.", ".#.", "###" }, J = { "..#", "..#", "..#", "#.#", ".#." },
    K = { "#.#", "#.#", "##.", "#.#", "#.#" }, L = { "#..", "#..", "#..", "#..", "###" },
    M = { "#.#", "###", "###", "#.#", "#.#" }, N = { "##.", "#.#", "#.#", "#.#", "#.#" },
    O = { "###", "#.#", "#.#", "#.#", "###" }, P = { "##.", "#.#", "##.", "#..", "#.." },
    Q = { ".#.", "#.#", "#.#", "##.", ".##" }, R = { "##.", "#.#", "##.", "#.#", "#.#" },
    S = { ".##", "#..", ".#.", "..#", "##." }, T = { "###", ".#.", ".#.", ".#.", ".#." },
    U = { "#.#", "#.#", "#.#", "#.#", "###" }, V = { "#.#", "#.#", "#.#", "#.#", ".#." },
    W = { "#.#", "#.#", "###", "###", "#.#" }, X = { "#.#", "#.#", ".#.", "#.#", "#.#" },
    Y = { "#.#", "#.#", ".#.", ".#.", ".#." }, Z = { "###", "..#", ".#.", "#..", "###" },
    [" "] = { "...", "...", "...", "...", "..." }, ["-"] = { "...", "...", "###", "...", "..." },
    ["+"] = { "...", ".#.", "###", ".#.", "..." }, ["!"] = { ".#.", ".#.", ".#.", "...", ".#." },
}

-- How wide `text` is in the big font at a scale (columns per block).
function draw.bigWidth(text, scale)
    return #text * 3 * scale + math.max(0, #text - 1) * scale
end

-- The biggest scale (up to `most`) at which `text` fits in `room` columns.
function draw.bigScale(text, room, most)
    for scale = most or 3, 1, -1 do
        if draw.bigWidth(text, scale) <= room then return scale end
    end
    return nil
end

function draw.big(target, x, y, text, color, scale, rows)
    scale, rows = scale or 1, rows or 1
    text = string.upper(text)
    for index = 1, #text do
        local glyph = draw.FONT[text:sub(index, index)] or draw.FONT[" "]
        local left = x + (index - 1) * 4 * scale
        for row = 1, 5 do
            local line = glyph[row]
            for column = 1, 3 do
                if line:sub(column, column) == "#" then
                    ui.fill(target, left + (column - 1) * scale, y + (row - 1) * rows,
                        scale, rows, color)
                end
            end
        end
    end
end

-- The big font, centred on a row.
function draw.bigCenter(target, y, text, color, most)
    local width = target.getSize()
    local scale = draw.bigScale(text, width - 2, most)
    if not scale then
        ui.center(target, y + 2, text, color, colors.black)
        return 5
    end
    draw.big(target, math.floor((width - draw.bigWidth(text, scale)) / 2) + 1, y, text,
        color, scale, 1)
    return 5
end

-- Cards: 1..52, rank 2..14 (J Q K A), suit 1..4 (hearts diamonds clubs
-- spades). 0 is face down.
draw.SUITS = { string.char(3), string.char(4), string.char(5), string.char(6) }
draw.RANKS = { [11] = "J", [12] = "Q", [13] = "K", [14] = "A" }
function draw.rankOf(card) return (card - 1) % 13 + 2 end
function draw.suitOf(card) return math.floor((card - 1) / 13) + 1 end
function draw.label(card)
    local rank = draw.rankOf(card)
    return (draw.RANKS[rank] or tostring(rank)), draw.SUITS[draw.suitOf(card)],
        draw.suitOf(card) <= 2 and colors.red or colors.black
end

-- A card 5 wide and 4 tall, or 3 by 2 when `small`. `fresh` lights its edge:
-- it has just been dealt.
function draw.card(target, x, y, card, small, fresh)
    local w, h = small and 3 or 5, small and 2 or 4
    if card == 0 then
        ui.fill(target, x, y, w, h, colors.blue)
        for row = 0, h - 1 do
            ui.text(target, x, y + row, string.rep(row % 2 == 0 and "\127" or " ", w),
                colors.lightBlue, colors.blue)
        end
        return
    end
    local rank, suit, ink = draw.label(card)
    ui.fill(target, x, y, w, h, fresh and colors.yellow or colors.white)
    if small then
        ui.text(target, x, y, rank, ink, fresh and colors.yellow or colors.white)
        ui.text(target, x + w - 1, y + 1, suit, ink, fresh and colors.yellow or colors.white)
    else
        local face = fresh and colors.yellow or colors.white
        ui.text(target, x, y, rank, ink, face)
        ui.text(target, x + 2, y + 1, suit, ink, face)
        ui.text(target, x + 2, y + 2, suit, ink, face)
        ui.text(target, x + w - #rank, y + h - 1, rank, ink, face)
    end
end

-- A row of cards, overlapping when there is not room for them side by side.
function draw.hand(target, x, y, cards, small, room, freshFrom)
    local w = small and 3 or 5
    local step = w + 1
    if #cards > 1 and (#cards - 1) * step + w > room then
        step = math.max(1, math.floor((room - w) / (#cards - 1)))
    end
    for index, card in ipairs(cards) do
        draw.card(target, x + (index - 1) * step, y, card, small,
            freshFrom and index >= freshFrom)
    end
end

function draw.money(value)
    return util.money(value or 0, config.currency)
end

-- The colours of the games, on the wheel and in their headers.
draw.GAME = {
    roulette = { color = colors.green, ink = colors.white, mark = "0-36", short = "ROULETTE" },
    blackjack = { color = colors.gray, ink = colors.white, mark = "21", short = "BLACKJACK" },
    heads_tails = { color = colors.yellow, ink = colors.black, mark = "H/T", short = "HEADS OR TAILS" },
    poker = { color = colors.purple, ink = colors.white,
        mark = draw.SUITS[4] .. draw.SUITS[1] .. draw.SUITS[2] .. draw.SUITS[3], short = "POKER" },
}

-- Roulette's wheel, in the order the pockets go round it (single zero).
draw.WHEEL = { 0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10, 5,
    24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26 }
draw.RED = {}
for _, number in ipairs({ 1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32,
    34, 36 }) do draw.RED[number] = true end
function draw.pocketColor(number)
    if number == 0 then return colors.green end
    return draw.RED[number] and colors.red or colors.black
end

-- Easing: fast, then slowing to a stop.
function draw.easeOut(x)
    x = math.max(0, math.min(1, x))
    return 1 - (1 - x) ^ 3
end

-- Sound -------------------------------------------------------------------------------------
-- Every speaker attached, taking turns, so more notes can sound at once: a
-- speaker plays a handful a tick. Game sounds are short note patterns, each
-- note at a time after the event, played by soundLoop.

local sound = { speakers = {}, at = 1, queue = {} }

function sound.find()
    sound.speakers = {}
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "speaker" then
            sound.speakers[#sound.speakers + 1] = peripheral.wrap(name)
        end
    end
    return #sound.speakers
end

function sound.note(instrument, volume, pitch)
    local count = #sound.speakers
    if count == 0 then return false end
    local speaker = sound.speakers[sound.at]
    sound.at = sound.at % count + 1
    local ok, played = pcall(speaker.playNote, instrument,
        math.max(0, math.min(3, volume)), math.max(0, math.min(24, math.floor(pitch + 0.5))))
    return ok and played ~= false
end

-- { milliseconds after, instrument, volume, pitch }
sound.EFFECTS = {
    wheel = { { 0, "pling", 1, 10 }, { 120, "pling", 1, 14 }, { 240, "pling", 1, 17 } },
    stop = { { 0, "bell", 1.6, 12 }, { 150, "bell", 1.6, 16 }, { 300, "bell", 1.8, 19 } },
    bets_open = { { 0, "chime", 1.2, 12 }, { 100, "chime", 1.2, 16 }, { 200, "chime", 1.2, 19 } },
    chip = { { 0, "hat", 1.4, 20 }, { 70, "hat", 1.2, 15 }, { 130, "hat", 1, 18 } },
    deal = { { 0, "snare", 0.7, 22 } },
    card = { { 0, "snare", 0.7, 22 } },
    spin = { { 0, "basedrum", 1.2, 6 } },
    flip = { { 0, "bell", 1.2, 20 }, { 100, "bell", 1, 24 } },
    reveal = { { 0, "chime", 1.3, 14 }, { 120, "chime", 1.3, 19 } },
    bust = { { 0, "bass", 1.6, 6 }, { 180, "bass", 1.6, 2 } },
    sit = { { 0, "pling", 1, 16 }, { 90, "pling", 1, 21 } },
    control = { { 0, "bit", 1, 12 }, { 100, "bit", 1, 17 } },
    win = { { 0, "bell", 2, 6 }, { 130, "bell", 2, 10 }, { 260, "bell", 2, 13 },
        { 390, "bell", 2.4, 18 }, { 520, "chime", 2, 18 } },
    lose = { { 0, "bass", 1.6, 10 }, { 220, "bass", 1.6, 7 }, { 440, "bass", 1.8, 3 } },
    tick = { { 0, "hat", 0.8, 14 } },
}

function sound.effect(name)
    local effect = sound.EFFECTS[name]
    if not effect or #sound.speakers == 0 then return end
    local at = now()
    for _, step in ipairs(effect) do
        sound.queue[#sound.queue + 1] = { at = at + step[1], instrument = step[2],
            volume = step[3], pitch = step[4] }
    end
end

-- Music: MIDI ---------------------------------------------------------------------------------
-- A Standard MIDI File, read into a list of notes: when (seconds), which of
-- the speaker's instruments, its pitch (the speaker's 0 to 24) and how loud.
-- General MIDI's instruments go to the nearest the speaker has; channel 10
-- is drums. A note out of an instrument's two octaves is moved by octaves
-- into them, so a tune keeps its shape.

local midi = { MAX_NOTES = 40000 }

-- The MIDI note each instrument's pitch 0 is.
midi.BASE = { harp = 54, bass = 30, didgeridoo = 30, guitar = 42, flute = 66, bell = 78,
    chime = 78, xylophone = 78, iron_xylophone = 54, cow_bell = 66, bit = 54, banjo = 54,
    pling = 54, basedrum = 54, snare = 54, hat = 54 }

function midi.instrument(program, channel, note)
    if channel == 9 then
        if note == 35 or note == 36 or note == 41 or note == 43 or note == 45 then
            return "basedrum", 6
        elseif note == 38 or note == 40 or note == 37 or note == 39 then
            return "snare", 12
        end
        return "hat", 18
    end
    local group = math.floor(program / 8)
    local names = { [0] = "harp", "bell", "flute", "guitar", "bass", "flute", "harp", "bit",
        "flute", "flute", "bit", "pling", "chime", "banjo", "iron_xylophone", "snare" }
    if program == 13 then return "xylophone" end
    return names[group] or "harp"
end

function midi.parse(data, yield)
    local pos = 1
    local function byte()
        local value = data:byte(pos)
        if not value then error("the file ends early", 0) end
        pos = pos + 1
        return value
    end
    local function u16() return byte() * 256 + byte() end
    local function u32() return u16() * 65536 + u16() end
    local function varlen()
        local value = 0
        for _ = 1, 4 do
            local b = byte()
            value = value * 128 + b % 128
            if b < 128 then return value end
        end
        return value
    end
    if data:sub(1, 4) ~= "MThd" then error("that is not a MIDI file", 0) end
    pos = 5
    local headerLength = u32()
    local _, tracks, division = u16(), u16(), u16()
    pos = 9 + headerLength
    if division >= 32768 or division == 0 then division = 96 end
    local events, tempos = {}, { { tick = 0, us = 500000 } }
    for _ = 1, tracks do
        if pos > #data - 8 then break end
        if data:sub(pos, pos + 3) ~= "MTrk" then break end
        pos = pos + 4
        local stop = u32() + pos
        local tick, channelStatus, programs = 0, nil, {}
        while pos < stop do
            tick = tick + varlen()
            local status = data:byte(pos)
            if not status then break end
            if status >= 128 then
                pos = pos + 1
                if status < 240 then channelStatus = status end
            else
                status = channelStatus
                if not status then break end
            end
            if status == 255 then
                local kind = byte()
                local length = varlen()
                if kind == 81 and length == 3 then
                    tempos[#tempos + 1] = { tick = tick,
                        us = data:byte(pos) * 65536 + data:byte(pos + 1) * 256 + data:byte(pos + 2) }
                end
                pos = pos + length
                if kind == 47 then break end
            elseif status == 240 or status == 247 then
                pos = pos + varlen()
            else
                local kind, channel = math.floor(status / 16), status % 16
                if kind == 9 then
                    local note, velocity = byte(), byte()
                    if velocity > 0 and #events < midi.MAX_NOTES then
                        events[#events + 1] = { tick = tick, channel = channel, note = note,
                            velocity = velocity, program = programs[channel] or 0 }
                    end
                elseif kind == 12 then
                    programs[channel] = byte()
                elseif kind == 13 then
                    pos = pos + 1
                elseif kind >= 8 then
                    pos = pos + 2
                end
            end
            if yield and #events % 500 == 0 then yield() end
        end
        pos = stop
    end
    table.sort(tempos, function(a, b) return a.tick < b.tick end)
    table.sort(events, function(a, b) return a.tick < b.tick end)
    -- Ticks to seconds, through every change of tempo.
    local notes, tempoAt, seconds, lastTick, us = {}, 1, 0, 0, tempos[1].us
    for _, event in ipairs(events) do
        while tempos[tempoAt + 1] and tempos[tempoAt + 1].tick <= event.tick do
            local nextTempo = tempos[tempoAt + 1]
            seconds = seconds + (nextTempo.tick - lastTick) * us / division / 1000000
            lastTick, us, tempoAt = nextTempo.tick, nextTempo.us, tempoAt + 1
        end
        local when = seconds + (event.tick - lastTick) * us / division / 1000000
        local instrument, fixed = midi.instrument(event.program, event.channel, event.note)
        local pitch = fixed or (event.note - (midi.BASE[instrument] or 54))
        while pitch < 0 do pitch = pitch + 12 end
        while pitch > 24 do pitch = pitch - 12 end
        notes[#notes + 1] = { t = when, instrument = instrument, pitch = pitch,
            loud = event.velocity / 127 }
    end
    return notes
end

-- The songs this computer has.
function midi.library()
    local names = {}
    if fs.exists(musicDir) and fs.isDir(musicDir) then
        for _, name in ipairs(fs.list(musicDir)) do
            if name:lower():match("%.midi?$") then names[#names + 1] = name end
        end
    end
    table.sort(names)
    return names
end

function midi.notes(data)
    local ok, notes = pcall(midi.parse, data or "", function()
        os.queueEvent("ccg_midi_yield")
        os.pullEvent("ccg_midi_yield")
    end)
    if not ok then return nil, tostring(notes) end
    return notes
end

function midi.load(name)
    local path = fs.combine(musicDir, fs.getName(tostring(name or "")))
    if not fs.exists(path) then return nil, "No such song here" end
    local file = fs.open(path, "rb")
    if not file then return nil, "Cannot read it" end
    local data = file.readAll()
    file.close()
    return midi.notes(data)
end

-- FoxyOS 17: a song in the owner's FoxyCloud, fetched from the Cloud Servers
-- with the ticket My Casino sent, and kept only in memory.
function midi.fromCloud(plan)
    if not (net.cloud and net.cloud.get) then return nil, "This console needs an update" end
    local data, err = net.cloud.get(plan, config.cloud_protocol or "PUMPE_CLOUD_V1")
    if not data then return nil, err end
    return midi.notes(data)
end

-- The display ----------------------------------------------------------------------------------
-- The monitor shows the table as the CCG Server last described it, moving
-- on between polls: the wheel turns, the ball runs, the coin flips, all
-- worked out from how far into each step the table is. Drawn into a hidden
-- window and shown whole, so nothing flickers.

local show = { table = nil, at = 0, online = false, seq = nil, reel = 0, roll = 0,
    counts = {}, fresh = {}, ticked = nil, frame = 0 }

-- Milliseconds left of a timed part of the view, as of now.
function show.left(view, field)
    local left = view and view[field]
    if not left then return nil end
    return math.max(0, left - (now() - show.at))
end

function show.progress(view, leftField, totalField)
    local left, total = show.left(view, leftField), view and view[totalField]
    if not left or not total or total <= 0 then return nil end
    return 1 - left / total
end

-- A tick each time something passes the pointer, at most every 40ms.
function show.tickAt(position)
    local whole = math.floor(position)
    if show.ticked ~= whole then
        show.ticked = whole
        if not show.lastTick or now() - show.lastTick > 40 then
            show.lastTick = now()
            sound.note("hat", 0.7, 16)
        end
    end
end

function show.header(t, view)
    local width = t.getSize()
    ui.fill(t, 1, 1, width, 1, colors.red)
    ui.text(t, 2, 1, ui.truncate(string.upper(view.name or "CCG CASINO"), math.floor(width / 2)),
        colors.white, colors.red)
    local right = view.controlled and ("DEALER " .. string.upper(tostring(view.controller_name)))
        or (view.auto and "AUTO" or "")
    local music = view.music
    if music and music.playing and music.track then
        right = string.char(14) .. " " .. ui.truncate(music.track:gsub("%.midi?$", ""), 12)
            .. (right ~= "" and "  " or "") .. right
    end
    right = ui.truncate(right, math.max(1, width - 4 - math.min(#(view.name or ""),
        math.floor(width / 2))))
    ui.text(t, width - #right, 1, right, colors.yellow, colors.red)
end

-- The code, as big as there is room for, under "JOIN".
function show.code(t, y, view, most)
    local width = t.getSize()
    ui.center(t, y, "JOIN IN THE CCG APP", colors.lightGray, colors.black)
    local scale = draw.bigScale(view.code or "", width - 2, most or 3)
    if scale then
        draw.big(t, math.floor((width - draw.bigWidth(view.code, scale)) / 2) + 1, y + 2,
            view.code, colors.white, scale, 1)
        return 7
    end
    ui.center(t, y + 1, view.code or "", colors.white, colors.black)
    return 2
end

function show.footer(t, view)
    local width, height = t.getSize()
    ui.fill(t, 1, height, width, 1, colors.gray)
    local text = "CODE " .. tostring(view.code) .. "  //  CCG APP > BET"
    ui.text(t, 2, height, ui.truncate(text, width - 2), colors.white, colors.gray)
    if view.round and view.round > 0 then
        local round = "ROUND " .. view.round
        if #text + #round + 4 < width then
            ui.text(t, width - #round, height, round, colors.lightGray, colors.gray)
        end
    end
end

function show.tile(t, x, y, w, h, game, lit)
    local look = draw.GAME[game] or draw.GAME.roulette
    ui.fill(t, x, y, w, h, look.color)
    if lit then
        ui.fill(t, x, y, w, 1, colors.yellow)
        ui.fill(t, x, y + h - 1, w, 1, colors.yellow)
    end
    local name = ui.truncate(look.short, w - 2)
    local middle = y + math.floor(h / 2) - 1
    ui.text(t, x + math.floor((w - #name) / 2), middle, name, look.ink, look.color)
    local mark = ui.truncate(look.mark, w - 2)
    ui.text(t, x + math.floor((w - #mark) / 2), middle + 2, mark, look.ink, look.color)
end

-- The game wheel: the four games going by, stopping on the next. In Auto it
-- spins for five seconds and slows to a stop; waiting for the dealer, it
-- turns slowly until they pick.
function show.wheel(t, view)
    local width, height = t.getSize()
    local games = view.games or { "roulette", "blackjack", "heads_tails", "poker" }
    local progress = show.progress(view, "left_ms", "phase_ms")
    local target
    for index, game in ipairs(games) do
        if game == view.wheel_target then target = index - 1 end
    end
    local p
    if progress and target then
        if show.spin ~= view.seq then
            show.spin, show.spinFrom = view.seq, show.reel
            local turns = (view.phase_ms or 0) >= 4000 and 3 or 1
            local base = (math.floor(show.reel / #games) + turns) * #games
            show.spinTo = base + target
        end
        p = show.spinFrom + (show.spinTo - show.spinFrom) * draw.easeOut(progress)
    else
        show.spin = nil
        p = show.reel + (target and 0 or 0.04)
    end
    show.reel = p
    show.tickAt(p)
    local tileW = math.max(10, math.min(22, math.floor((width - 6) / 3)))
    local tileH = math.max(5, math.min(9, height - 14))
    local y = 5
    local center = math.floor(width / 2) + 1
    for k = -3, 3 do
        local index = math.floor(p) + k
        local game = games[index % #games + 1]
        local x = center - math.floor(tileW / 2) + math.floor((index - p) * (tileW + 2) + 0.5)
        show.tile(t, x, y, tileW, tileH, game, math.abs(index - p) < 0.5)
    end
    ui.text(t, center, y - 1, "v", colors.yellow, colors.black)
    ui.text(t, center, y + tileH, "^", colors.yellow, colors.black)
    local caption
    if progress and progress >= 1 or (progress and not show.left(view, "left_ms")) then
        caption = "NEXT: " .. string.upper((view.names or {})[view.wheel_target] or "")
    elseif progress then
        caption = "THE NEXT GAME IS..."
    else
        caption = "THE DEALER PICKS THE GAME"
    end
    ui.center(t, 3, caption, colors.white, colors.black)
    if height - (y + tileH + 1) >= 8 then show.code(t, y + tileH + 2, view, 2) end
end

-- Bets open: the game, the big code, the clock, and who is in.
function show.betting(t, view)
    local width, height = t.getSize()
    local look = draw.GAME[view.game] or draw.GAME.roulette
    ui.fill(t, 1, 2, width, 3, look.color)
    ui.center(t, 3, string.upper(view.game_name or ""), look.ink, look.color)
    local y = 6
    y = y + show.code(t, y, view, 3)
    local left = show.left(view, "left_ms")
    local barW = width - 4
    if left and view.phase_ms then
        local filled = math.floor(barW * left / view.phase_ms + 0.5)
        ui.fill(t, 3, y, barW, 1, colors.gray)
        ui.fill(t, 3, y, filled, 1, left < 5000 and colors.red or colors.lime)
        ui.center(t, y + 1, "PLACE YOUR BETS  " .. math.ceil(left / 1000) .. "s",
            colors.white, colors.black)
    else
        ui.center(t, y + 1, "PLACE YOUR BETS", colors.white, colors.black)
        if view.controlled then
            ui.center(t, y + 2, "THE DEALER DEALS WHEN READY", colors.lightGray, colors.black)
        end
    end
    y = y + 3
    for _, player in ipairs(view.players or {}) do
        if y >= height then break end
        local line = ui.truncate(player.name, 14)
        local bet = player.playing and (draw.money(player.total) .. "  " .. show.betWords(player))
            or "..."
        ui.text(t, 3, y, line, player.playing and colors.lime or colors.lightGray, colors.black)
        ui.text(t, math.min(width - #bet, 19), y, ui.truncate(bet, width - 19), colors.white,
            colors.black)
        y = y + 1
    end
end

-- A player's bets in a few words: RED, 17, 1ST 12, HEADS, HAND.
function show.betWords(player)
    local words = {}
    for _, bet in ipairs(player.bets or {}) do
        if bet.kind == "straight" then words[#words + 1] = tostring(bet.pick)
        elseif bet.kind == "dozen" then words[#words + 1] = ({ "1-12", "13-24", "25-36" })[bet.pick]
        elseif bet.kind == "column" then words[#words + 1] = "COL " .. tostring(bet.pick)
        elseif bet.pick then words[#words + 1] = string.upper(tostring(bet.pick)) end
    end
    return table.concat(words, " ")
end

-- Roulette: the pockets go by under the ball, and slow to the one it lands in.
function show.roulette(t, view, settled)
    local width, height = t.getSize()
    local landing
    for index, number in ipairs(draw.WHEEL) do
        if number == view.outcome then landing = index - 1 end
    end
    local p = show.roll
    local progress = show.progress(view, "step_left_ms", "step_ms")
    if view.step == "spin" and landing and progress then
        if show.rollSpin ~= view.seq then
            show.rollSpin, show.rollFrom = view.seq, show.roll
            local base = (math.floor(show.roll / 37) + 4) * 37
            show.rollTo = base + landing
        end
        p = show.rollFrom + (show.rollTo - show.rollFrom) * draw.easeOut(progress)
        show.tickAt(p)
    elseif settled and landing then
        p = math.floor(show.roll / 37) * 37 + landing
        if show.rollTo then p = show.rollTo end
    else
        p = show.roll + 0.15
    end
    show.roll = p
    local pocketW, y = 4, 6
    local center = math.floor(width / 2) + 1
    for k = -math.ceil(width / pocketW), math.ceil(width / pocketW) do
        local index = math.floor(p) + k
        local number = draw.WHEEL[index % 37 + 1]
        local x = center - 1 + math.floor((index - p) * pocketW + 0.5)
        local colour = draw.pocketColor(number)
        ui.fill(t, x, y, pocketW - 1, 3, colour)
        local label = tostring(number)
        ui.text(t, x + math.floor((pocketW - 1 - #label) / 2), y + 1, label, colors.white, colour)
    end
    ui.text(t, center, y - 1, "o", colors.white, colors.black)
    ui.text(t, center, y + 3, "^", colors.yellow, colors.black)
    if settled and view.outcome then
        local number = view.outcome
        local words = number == 0 and "ZERO" or ((draw.RED[number] and "RED" or "BLACK")
            .. "  " .. (number % 2 == 1 and "ODD" or "EVEN"))
        draw.bigCenter(t, 11, tostring(number), draw.pocketColor(number) == colors.black
            and colors.white or draw.pocketColor(number), 3)
        ui.center(t, 17, words, colors.white, colors.black)
    else
        ui.center(t, 11, "NO MORE BETS", colors.white, colors.black)
    end
end

-- Heads or Tails: a coin turning over and over, landing on its face.
function show.coin(t, view, settled)
    local width, height = t.getSize()
    local face, squash = view.outcome or "heads", 1
    local progress = show.progress(view, "step_left_ms", "step_ms")
    if view.step == "flip" and progress and view.outcome then
        local halves = view.outcome == "heads" and 14 or 15
        local angle = draw.easeOut(progress) * halves * math.pi
        squash = math.abs(math.cos(angle))
        face = math.floor(angle / math.pi + 0.5) % 2 == 0 and "heads" or "tails"
        local flips = math.floor(angle / math.pi)
        if show.flips ~= flips then show.flips = flips sound.note("bell", 0.6, 20) end
    elseif not settled then
        squash = math.abs(math.cos(now() / 300))
    end
    local radius = math.max(3, math.min(math.floor((height - 8) / 2), 7))
    local cx, cy = math.floor(width / 2) + 1, 4 + radius
    local rx = math.max(0.6, radius * 2 * squash)
    local colour = face == "heads" and colors.yellow or colors.orange
    for dy = -radius, radius do
        local half = math.floor(rx * math.sqrt(math.max(0, 1 - (dy / radius) ^ 2)) + 0.5)
        if half > 0 then ui.fill(t, cx - half, cy + dy, half * 2, 1, colour) end
    end
    if squash > 0.55 then
        draw.big(t, cx - 2, cy - 2, face == "heads" and "H" or "T", colors.black, 1, 1)
    end
    if settled then
        ui.center(t, cy + radius + 2, string.upper(face), colors.white, colors.black)
    end
end

-- Blackjack and Poker: the dealer at the top, the players along the bottom.
-- A card that has just appeared is lit for a moment, with a flick of sound.
function show.freshFrom(key, cards)
    local count = #(cards or {})
    local before = show.counts[key] or 0
    show.counts[key] = count
    if count > before then
        show.fresh[key] = { from = before + 1, at = now() }
        if before > 0 or key == "dealer" then sound.note("snare", 0.6, 22) end
    end
    local fresh = show.fresh[key]
    if fresh and now() - fresh.at < 450 then return fresh.from end
    return nil
end

function show.status(player, settled)
    local result = settled and player.result
    if result then
        if (result.payout or 0) > 0 then return "WIN " .. draw.money(result.payout), colors.lime end
        if (result.pushed or 0) > 0 then return "PUSH", colors.yellow end
        return "LOSE", colors.red
    end
    local words = { bust = "BUST", blackjack = "BLACKJACK", stood = "STAND", doubled = "DOUBLE",
        raised = "RAISE", checked = "CHECK", folded = "FOLD", playing = "" }
    return words[player.status or ""] or (player.playing and draw.money(player.total) or "WATCHING"),
        player.status == "bust" and colors.red or colors.white
end

function show.cards(t, view, settled)
    local width, height = t.getSize()
    local small = width < 46
    local cardH = small and 2 or 4
    -- The dealer.
    local dealer = view.dealer or { cards = {} }
    ui.text(t, 2, 3, "DEALER", colors.lightGray, colors.black)
    if dealer.total then
        ui.text(t, 9, 3, tostring(dealer.total), dealer.total > 21 and colors.red or colors.white,
            colors.black)
    elseif dealer.hand_name then
        ui.text(t, 9, 3, string.upper(dealer.hand_name), colors.white, colors.black)
    end
    draw.hand(t, 2, 4, dealer.cards or {}, small, math.floor(width / 2) - 3,
        show.freshFrom("dealer", dealer.cards))
    -- Poker: the board, beside the dealer.
    if view.board then
        local boardX = math.floor(width / 2) + 1
        ui.text(t, boardX, 3, "BOARD", colors.lightGray, colors.black)
        local board = {}
        for index = 1, 5 do board[index] = view.board.cards[index] or 0 end
        draw.hand(t, boardX, 4, board, small, width - boardX, show.freshFrom("board", view.board.cards))
        if not small and width - boardX > 32 then
            ui.text(t, boardX, 4 + cardH, "TIES GO TO THE DEALER", colors.gray, colors.black)
        end
    end
    -- The players: in columns, as many as fit.
    local players = {}
    for _, player in ipairs(view.players or {}) do
        if player.playing then players[#players + 1] = player end
    end
    local top = 6 + cardH
    local columns = math.max(1, math.min(4, math.floor(width / (small and 14 or 20))))
    local panelW = math.floor((width - 1) / columns)
    local panelH = cardH + 3
    for index, player in ipairs(players) do
        local column = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        local x, y = 2 + column * panelW, top + row * (panelH + 1)
        if y + panelH - 1 >= height then break end
        ui.text(t, x, y, ui.truncate(string.upper(player.name), panelW - 2), colors.white,
            colors.black)
        local words, colour = show.status(player, settled)
        local extra = player.hand_total and (tostring(player.hand_total) .. " ") or ""
        if player.hand_name and settled then extra = string.upper(player.hand_name) .. " " end
        ui.text(t, x, y + 1, ui.truncate(extra .. words, panelW - 2), colour, colors.black)
        draw.hand(t, x, y + 2, player.cards or {}, small, panelW - 2,
            show.freshFrom("p" .. player.seat, player.cards))
    end
    if #players == 0 then ui.center(t, top + 1, "NOBODY IS PLAYING", colors.gray, colors.black) end
end

-- Who won, under whichever game it was.
function show.winners(t, view)
    local width, height = t.getSize()
    local y = height - 3
    ui.fill(t, 1, y, width, 2, colors.black)
    local winners = view.winners or {}
    if #winners == 0 then
        ui.center(t, y, "THE HOUSE WINS", colors.red, colors.black)
    else
        local words = {}
        for _, winner in ipairs(winners) do
            words[#words + 1] = string.upper(winner.name) .. " +" .. draw.money(winner.payout)
        end
        ui.center(t, y, ui.truncate(table.concat(words, "  "), width - 2), colors.lime, colors.black)
    end
    local left = show.left(view, "left_ms")
    ui.center(t, y + 1, left and ("NEXT GAME IN " .. math.ceil(left / 1000) .. "s")
        or (view.controlled and "THE DEALER STARTS THE NEXT GAME" or ""), colors.lightGray,
        colors.black)
end

-- Everything on the monitor, once a frame.
function show.render(t)
    local width, height = t.getSize()
    ui.fill(t, 1, 1, width, height, colors.black)
    local view = show.table
    if not device.console_id then
        draw.bigCenter(t, 3, "CCG", colors.red, 3)
        ui.center(t, 10, "CCG CASINO", colors.white, colors.black)
        ui.center(t, 12, "SET ME UP ON THE COMPUTER", colors.lightGray, colors.black)
        return
    end
    if not view then
        show.header(t, { name = device.name })
        ui.center(t, math.floor(height / 2), show.online and "..." or "LOOKING FOR THE CCG SERVER",
            colors.lightGray, colors.black)
        return
    end
    show.header(t, view)
    local phase = view.phase
    local settled = phase == "settling" or phase == "result"
    if phase == "wheel" then
        show.wheel(t, view)
    elseif phase == "betting" then
        show.betting(t, view)
    elseif view.game == "roulette" then
        show.roulette(t, view, settled)
    elseif view.game == "heads_tails" then
        show.coin(t, view, settled)
    else
        show.cards(t, view, settled)
    end
    if phase == "result" then show.winners(t, view) end
    if phase ~= "betting" and not (phase == "wheel" and height >= 26) then show.footer(t, view) end
    if not show.online then
        ui.text(t, width - 8, 2, "OFFLINE", colors.red, colors.black)
    end
end

-- The computer's own screen -------------------------------------------------------------------
-- Setting the table up: sign in with Foxy, choose one of your companies,
-- name it. Then it says how it is doing, and is where the music goes in.

local console = { dropped = nil }

function console.ask(action, payload, timeout)
    local result, err, code = ccg:request(action, payload or {}, timeout or 5)
    return result, err, code
end

function console.setup()
    local width, height = screen.getSize()
    ui.clear(screen)
    ui.header(screen, "CCG CASINO", "Set up", util.formatClock())
    ui.wrappedText(screen, 2, 5, "This table belongs to a company. Sign in with the Foxy"
        .. " Account that owns it; you run the table from the CCG app's My Casino tab.",
        width - 2, 5, ui.theme.muted)
    local scene = ui.scene(screen)
    scene:button("start", 2, height - 4, width - 2, 3, "SIGN IN WITH FOXY",
        { background = colors.orange, foreground = colors.black })
    local action = scene:wait()
    if action == "__terminate" then running = false return end
    if action ~= "start" then return end
    local name = ui.input(screen, "Foxy Account", { hint = "The company's owner",
        maxLength = 20, allowSpace = true })
    if not name then return end
    local pin = ui.pin(screen, "PIN for " .. ui.truncate(name, 14), true)
    if not pin then return end
    local signed, err = bank:request("LOGIN", { name = name, pin = pin }, 6)
    if not signed then
        ui.message(screen, "error", "NOT SIGNED IN", err, 2)
        return
    end
    local session = signed.session_token
    local owned, ownedError = console.ask("CASINO_COMPANIES", { session_token = session })
    if not owned then
        ui.message(screen, "error", "NO CCG SERVER", ownedError, 2.4)
        return
    end
    if #owned.companies == 0 then
        ui.message(screen, "warning", "NO COMPANY", "Start one in the Company app first", 2.6)
        return
    end
    local company
    while not company do
        ui.clear(screen)
        ui.header(screen, "CCG CASINO", "Which company?", util.formatClock())
        local pick = ui.scene(screen)
        for index, entry in ipairs(owned.companies) do
            if index > math.floor((height - 6) / 3) then break end
            pick:button("company:" .. index, 2, 2 + index * 3, width - 2, 2,
                ui.truncate(entry.name, width - 4), { background = ui.theme.panel })
        end
        pick:button("back", 1, height, 8, 1, "< Back", { background = ui.theme.panel })
        local chosen = pick:wait()
        if chosen == "back" or chosen == "__terminate" then return end
        company = owned.companies[tonumber(chosen:match("^company:(%d+)$") or "")]
    end
    local tableName = ui.input(screen, "Name this table", { hint = "Shown in its top left corner",
        initial = "Table 1", maxLength = 16, minLength = 2, allowSpace = true })
    if not tableName then return end
    local made, madeError = console.ask("CASINO_REGISTER", { session_token = session,
        company_id = company.company_id, name = tableName })
    pcall(bank.request, bank, "LOGOUT", { session_token = session }, 2)
    if not made then
        ui.message(screen, "error", "NOT SET UP", madeError, 2.4)
        return
    end
    device = { console_id = made.console_id, console_token = made.console_token,
        code = made.code, name = made.name, company_name = made.company_name }
    saveDevice()
    ui.message(screen, "success", made.name, "Code " .. made.code .. ". Open My Casino.", 2.2)
end

function console.status()
    local width, height = screen.getSize()
    ui.clear(screen)
    ui.header(screen, ui.truncate(device.name or "CCG CASINO", width - 9),
        ui.truncate(device.company_name or "", width - 3), util.formatClock())
    local view = show.table
    local lines = {
        { "Code", tostring(device.code or (view and view.code) or "-") },
        { "CCG Server", show.online and "Connected" or "Looking..." },
        { "Game", view and view.game_name and (view.game_name .. " / " .. tostring(view.phase))
            or "-" },
        { "Speakers", tostring(#sound.speakers) },
        { "Music", #midi.library() .. " songs" },
        { "Playing", console.musicStatus or "-" },
        { "Version", PROGRAM_VERSION },
    }
    for index, line in ipairs(lines) do
        ui.text(screen, 2, 3 + index, line[1], ui.theme.muted)
        ui.text(screen, 14, 3 + index, ui.truncate(line[2], width - 14), ui.theme.ink)
    end
    ui.wrappedText(screen, 2, 11, console.dropped or ("Drop .mid files on this screen to add"
        .. " music. Play it from My Casino in the CCG app."), width - 2, 3,
        console.dropped and ui.theme.success or ui.theme.muted)
    local scene = ui.scene(screen)
    local third = math.floor((width - 4) / 3)
    scene:button("speakers", 2, height - 2, third, 2, "SPEAKERS", { background = ui.theme.panel })
    scene:button("beta", 3 + third, height - 2, third, 2, "BETA", { background = ui.theme.panel })
    scene:button("unlink", 4 + third * 2, height - 2, width - 4 - third * 2, 2, "UNLINK",
        { background = ui.theme.danger })
    local action = scene:wait({ tickRate = 1 })
    if action == "__terminate" then
        running = false
    elseif action == "speakers" then
        ui.message(screen, "success", sound.find() .. " speakers", "Found and in use", 1.2)
        sound.effect("win")
    elseif action == "beta" and type(ui.betaUpdates) == "function" then
        ui.betaUpdates(screen, ROOT, { kind = "CCG Casino", version = config.version })
    elseif action == "unlink" and ui.confirm(screen, "UNLINK?", "This table leaves its company."
        .. " Set it up again to use it.", "UNLINK", "BACK") then
        local done, err = console.ask("CASINO_UNLINK", { console_id = device.console_id,
            console_token = device.console_token })
        if done or err == "This CCG Casino is not registered" then
            device = {}
            saveDevice()
            show.table = nil
        else
            ui.message(screen, "error", "NOT UNLINKED", err, 2)
        end
    end
end

-- Running ------------------------------------------------------------------------------------

local loops = {}

function loops.screen()
    while running do
        if device.console_id then console.status() else console.setup() end
    end
end

-- Asking the CCG Server what to show, three times a second.
function loops.poll()
    local libraryAt, updatedAt, lastLibrary = 0, now(), nil
    while running do
        if device.console_id then
            -- FoxyOS 17: what this console can play, and how it is going, so
            -- My Casino can say so rather than leave the owner guessing.
            local payload = { console_id = device.console_id, console_token = device.console_token,
                version = PROGRAM_VERSION,
                features = { cloud_midi = true, dfpwm = console.musiclib() ~= nil },
                music_status = console.musicStatus }
            local library = midi.library()
            local joined = table.concat(library, "|")
            if joined ~= lastLibrary or now() - libraryAt > 30000 then
                payload.library, lastLibrary, libraryAt = library, joined, now()
            end
            local result, err = ccg:request("CASINO_TICK", payload, 2)
            if result then
                local view = result.table
                -- The sounds of whatever happened since the last look.
                for _, event in ipairs(view.events or {}) do
                    if show.seq and event.seq > show.seq then sound.effect(event.kind) end
                end
                show.seq = view.seq
                if view.round ~= (show.table and show.table.round) then
                    show.counts, show.fresh = {}, {}
                end
                show.table, show.at, show.online = view, now(), true
                local music = view.music or {}
                if music.seq ~= console.musicSeq then
                    console.musicSeq = music.seq
                    console.music = { track = music.track, playing = music.playing,
                        volume = music.volume or 5, cloud = music.cloud, stream = music.stream }
                    os.queueEvent("ccg_music")
                end
                if console.music then console.music.volume = music.volume or 5 end
            else
                show.online = false
                if err == "This CCG Casino is not registered" then
                    device = {}
                    saveDevice()
                    show.table = nil
                end
            end
        end
        if now() - updatedAt > 60000 then
            updatedAt = now()
            net.autoUpdate(config, "ccgcasino", ROOT, nil)
        end
        sleep(0.3)
    end
end

-- The monitor, about twelve times a second.
function loops.display()
    local monitor = console.monitor
    local buffer, bufferW, bufferH
    while running do
        local width, height = monitor.getSize()
        if not buffer or width ~= bufferW or height ~= bufferH then
            buffer = window.create(monitor, 1, 1, width, height, false)
            bufferW, bufferH = width, height
        end
        local ok, err = pcall(show.render, buffer)
        if not ok then
            buffer.setBackgroundColor(colors.black)
            buffer.clear()
            buffer.setCursorPos(1, 1)
            buffer.setTextColor(colors.red)
            buffer.write(ui.truncate(tostring(err), width))
        end
        buffer.setVisible(true)
        buffer.setVisible(false)
        sleep(0.08)
    end
end

-- Notes queued by game sounds, each at its moment.
function loops.sound()
    while running do
        local at, waiting = now(), {}
        for _, note in ipairs(sound.queue) do
            if note.at <= at then
                sound.note(note.instrument, note.volume, note.pitch)
            else
                waiting[#waiting + 1] = note
            end
        end
        sound.queue = waiting
        sleep(0.05)
    end
end

-- Files dropped onto this computer's screen: MIDI files go in the music
-- folder; anything else is left alone.
function loops.drop()
    while running do
        local _, transfer = os.pullEvent("file_transfer")
        local kept = {}
        local ok, files = pcall(function() return transfer.getFiles() end)
        for _, file in ipairs(ok and files or {}) do
            local name = fs.getName(tostring(file.getName and file.getName() or ""))
            if name:lower():match("%.midi?$") then
                local body = file.readAll()
                if not fs.exists(musicDir) then fs.makeDir(musicDir) end
                local out = fs.open(fs.combine(musicDir, name), "wb")
                if out and body then
                    out.write(body)
                    out.close()
                    kept[#kept + 1] = name
                end
            end
            pcall(file.close)
        end
        console.dropped = #kept > 0 and ("Added " .. table.concat(kept, ", ") .. ".")
            or "Only .mid files can be music."
        os.queueEvent("ccg_dropped")
    end
end

-- The music: the song the app chose, round and round, quieter while a game
-- is on, until it is stopped or changed.

-- How loud, now: the owner's volume, and quieter while a game is on.
function console.level()
    local level = ((console.music and console.music.volume) or 5) / 10 * 3
    local phase = show.table and show.table.phase
    if phase and phase ~= "wheel" then level = level * 0.35 end
    return level
end

-- Waits `seconds`, or less if the owner chooses something else. True when
-- they did.
function console.waitOrChange(seconds, seq)
    local timer = os.startTimer(seconds)
    while true do
        local event, id = os.pullEvent()
        if event == "ccg_music" and console.musicSeq ~= seq then return true end
        if event == "timer" and id == timer then return console.musicSeq ~= seq end
    end
end

-- lib/music came with FoxyOS 17.0. A console updated by an updater from
-- before it does not have it until its next check fetches what its role
-- lacks, so it is loaded when it is first wanted -- and asked again until it
-- is there -- rather than stopping the console from starting.
function console.musiclib()
    if not console.loadedMusic then
        local ok, lib = pcall(require, "lib.music")
        if ok and type(lib) == "table" then console.loadedMusic = lib end
    end
    return console.loadedMusic
end

-- FoxyOS 17: a song or a radio from the Music Library, as DFPWM, through the
-- speakers. The console holds a grant for it, never the owner's session; the
-- Music Server checks the owner still has FoxyCloud+ every time it is asked.
function console.stream(want, seq)
    local musiclib = console.musiclib()
    if not musiclib then return nil, "This CCG Casino is still updating", "UPDATING" end
    console.musicClient = console.musicClient or musiclib.client(config)
    local answer, err, code = console.musicClient:request("MUSIC_STREAM",
        { grant = want.stream.grant }, 6)
    if not answer then return nil, err, code end
    console.musicStatus = (answer.mode == "radio" and answer.radio and (answer.radio.name .. ": ")
        or "") .. tostring(answer.item and answer.item.title)
    local startedAt = now()
    local finished, playError, playCode
    parallel.waitForAny(function()
        finished, playError, playCode = musiclib.play(answer.plan, sound.speakers, {
            offset_ms = answer.offset_ms, protocol = config.cloud_protocol, volume = console.level })
    end, function()
        repeat os.pullEvent("ccg_music") until console.musicSeq ~= seq
    end)
    if not finished then
        musiclib.stop(sound.speakers)
        if playError then return nil, playError, playCode end
        return true
    end
    -- A radio's next item starts when this one has been heard to the end.
    if answer.mode == "radio" and answer.item then
        local wait = (startedAt + answer.item.length_ms - (answer.offset_ms or 0) - now()) / 1000
        if wait > 0 then console.waitOrChange(wait, seq) end
    end
    return true
end

-- A song that will not play is tried again a few times -- a Cloud Server
-- can be out of reach for a moment -- before the console gives up on it.
function console.failed(want, seq, err, code)
    console.failures = (console.failSeq == seq and console.failures or 0) + 1
    console.failSeq = seq
    console.musicStatus = "Cannot play: " .. tostring(err or "no answer")
    if code == "NEEDS_PLUS" or code == "NO_GRANT" or console.failures >= 5 then
        want.playing = false
        return
    end
    console.waitOrChange(10 + console.failures * 5, seq)
end

function loops.music()
    local cached = {}
    while running do
        local want = console.music
        if not (want and want.playing and want.track) then
            if want and not want.playing and not (console.musicStatus or ""):match("^Cannot") then
                console.musicStatus = nil
            end
            os.pullEvent("ccg_music")
        elseif want.stream then
            local seq = console.musicSeq
            local ok, err, code = console.stream(want, seq)
            if not ok and console.musicSeq == seq then console.failed(want, seq, err, code) end
        else
            local seq = console.musicSeq
            -- FoxyOS 17: a song from FoxyCloud is fetched into memory and
            -- played from there; nothing of it is written to this disk.
            local key = (want.cloud and "cloud:" or "") .. want.track
            local notes = cached[key]
            if not notes then
                local err
                if want.cloud then
                    notes, err = midi.fromCloud(want.cloud)
                else
                    notes, err = midi.load(want.track)
                end
                if notes then
                    cached = { [key] = notes }
                elseif console.musicSeq == seq then
                    console.failed(want, seq, err)
                end
            end
            if notes and #notes > 0 then
                console.musicStatus = want.track
                local start, index = now() / 1000, 1
                while running and console.musicSeq == seq and index <= #notes do
                    local at = now() / 1000 - start
                    local master = console.level()
                    while index <= #notes and notes[index].t <= at + 0.03 do
                        local note = notes[index]
                        if master > 0 then
                            sound.note(note.instrument, math.max(0.05, master * note.loud), note.pitch)
                        end
                        index = index + 1
                    end
                    sleep(0.05)
                end
                if console.musicSeq == seq then sleep(1) end
            elseif notes then
                want.playing = false
            end
        end
    end
end

if TEST_MODE == "ccg_casino" then
    return { draw = draw, show = show, midi = midi, sound = sound, console = console,
        device = device }
end

-- Starting -----------------------------------------------------------------------------------

local function findMonitor()
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "monitor" then
            local monitor = peripheral.wrap(name)
            if monitor and type(monitor.isColor) == "function" and monitor.isColor() then
                pcall(monitor.setTextScale, 0.5)
                return monitor, name
            end
        end
    end
end

local monitorName
console.monitor, monitorName = findMonitor()
if not console.monitor then
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.red)
    term.clear()
    term.setCursorPos(1, 2)
    print("CCG Casino needs an Advanced Monitor. Attach one and restart.")
    return
end
net.updateTarget = console.monitor
-- Only a display: a tap on it presses nothing, least of all a button on
-- this computer's own screen.
if type(ui.customerScreen) == "function" then ui.customerScreen(monitorName) end
net.openModems()
sound.find()
if type(ui.useMainColor) == "function" then ui.useMainColor(ROOT) end
net.autoUpdate(config, "ccgcasino", ROOT, nil, { force = true, programVersion = PROGRAM_VERSION })
sound.effect("bets_open")
parallel.waitForAny(loops.screen, loops.poll, loops.display, loops.sound, loops.drop, loops.music)
console.monitor.setBackgroundColor(colors.black)
console.monitor.clear()
