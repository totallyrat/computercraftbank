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

-- The Radio Broadcaster, FoxyOS 18.2: an Advanced Computer with a modem that
-- runs one company's radio station, on one frequency. The station itself is
-- the Music Server's -- that is where listeners hear it -- and this decides
-- everything about it: what plays next, the breaks, the ad breaks (which
-- earn the company 25 a listener), the giveaways (paid out of Company Money),
-- its name, colour and frequency.
--
-- A station is on no list. Listeners find it on the Radio app's dial, or hear
-- it advertised. Without Radio+ it plays what is queued here while this
-- computer is on, and static otherwise. Radio+ -- the company's, 100 every 15
-- days out of Company Money, started from the Station page -- keeps it going
-- round the clock on its own, advertises it on the State Radios, lets
-- listeners save it, and makes any .dfpwm dropped on this screen go straight
-- into the playlist (Quick Upload): played once, never kept.

local TEST_MODE = rawget(_G, "PUMPE_TEST_MODE")
local target = term.current()
local dataFile = fs.combine(ROOT, "radio_broadcaster.dat")
local device = util.loadTable(dataFile, {})
local running = true
local CLOUD = config.cloud_protocol or "PUMPE_CLOUD_V1"
local bank = net.client(config)
-- The Music Server, as the Bank names it, like a Music Player finds it.
local server = music.client(config, function()
    local where = bank:request("MUSIC_WHERE", {}, 4)
    if where and where.computer_id then
        device.music_server = where.computer_id
        return where.computer_id
    end
    return device.music_server
end)
local shared = { view = nil, online = false, at = 0, page = "air" }

local function save() util.saveTable(dataFile, device) end
local function say(kind, title, body, seconds)
    ui.message(target, kind, title, body or "", seconds or 1.4)
end

-- The station's own requests: its id and token, which are what it is.
local function ask(action, payload, timeout)
    payload = payload or {}
    payload.station_id, payload.station_token = device.station_id, device.station_token
    return server:request(action, payload, timeout or 5)
end

local function colorOf(name) return music.color(name or device.color) end

-- Block letters ----------------------------------------------------------------------------
-- Three by five, for the frequency on the On Air page and for RADIO.

local font = {
    R = { "###", "# #", "## ", "# #", "# #" }, D = { "## ", "# #", "# #", "# #", "## " },
    I = { "###", " # ", " # ", " # ", "###" }, O = { "###", "# #", "# #", "# #", "###" },
    ["0"] = { "###", "# #", "# #", "# #", "###" }, ["1"] = { " # ", "## ", " # ", " # ", "###" },
    ["2"] = { "###", "  #", "###", "#  ", "###" }, ["3"] = { "###", "  #", " ##", "  #", "###" },
    ["4"] = { "# #", "# #", "###", "  #", "  #" }, ["5"] = { "###", "#  ", "###", "  #", "###" },
    ["6"] = { "###", "#  ", "###", "# #", "###" }, ["7"] = { "###", "  #", " # ", " # ", " # " },
    ["8"] = { "###", "# #", "###", "# #", "###" }, ["9"] = { "###", "# #", "###", "  #", "###" },
    ["."] = { " ", " ", " ", " ", "#" },
}

function font.width(text, scale)
    local total = 0
    for index = 1, #text do
        total = total + #(font[text:sub(index, index)] or font["0"])[1] * scale + scale
    end
    return total - scale
end

function font.draw(t, x, y, text, color, scale)
    for index = 1, #text do
        local glyph = font[text:sub(index, index)] or font["0"]
        for row, line in ipairs(glyph) do
            for column = 1, #line do
                if line:sub(column, column) == "#" then
                    ui.fill(t, x + (column - 1) * scale, y + (row - 1) * scale, scale, scale, color)
                end
            end
        end
        x = x + #glyph[1] * scale + scale
    end
end

-- The start ------------------------------------------------------------------------------------
-- A radio tower in the station's colour sends out three rings; RADIO comes
-- up around it, the tower being its A; one last ring starts small and takes
-- the whole screen; and the colour goes, top to bottom.

local intro = { FRAME = 0.05 }

-- A screen cell is about half again as tall as it is wide: a ring is drawn
-- with that in mind, or it would be an egg.
function intro.ring(t, cx, cy, radius, color, filled)
    local width, height = t.getSize()
    for y = 1, height do
        local dy = (y - cy) * 1.5
        for x = 1, width do
            local distance = math.sqrt((x - cx) ^ 2 + dy * dy)
            if (filled and distance <= radius) or (not filled and math.abs(distance - radius) < 0.6) then
                ui.fill(t, x, y, 1, 1, color)
            end
        end
    end
end

-- The tower: an A of lattice, a bar across it, and a light on top.
function intro.tower(t, cx, top, height, lit)
    local half = math.max(2, math.floor(height * 0.45))
    for row = 0, height - 1 do
        local spread = math.floor(row * half / math.max(1, height - 1) + 0.5)
        ui.fill(t, cx - spread, top + row, 1, 1, colors.lightGray)
        ui.fill(t, cx + spread, top + row, 1, 1, colors.lightGray)
        if row == math.floor(height * 0.6) then
            ui.fill(t, cx - spread, top + row, spread * 2 + 1, 1, colors.lightGray)
        elseif row % 3 == 1 and spread >= 2 then
            ui.fill(t, cx, top + row, 1, 1, colors.gray)
        end
    end
    ui.fill(t, cx, top - 1, 1, 1, lit)
end

-- Where everything goes on this screen: RADIO at twice the size where it
-- fits, the tower as tall as the letters.
function intro.layout(t)
    local width, height = t.getSize()
    local scale = (width >= 46 and height >= 16) and 2 or 1
    local letterH = 5 * scale
    local towerW = math.floor(letterH * 0.45) * 2 + 1
    local total = font.width("R", scale) + scale + towerW + scale + font.width("DIO", scale)
    local x = math.max(1, math.floor((width - total) / 2) + 1)
    local top = math.max(2, math.floor((height - letterH) / 2) + 1)
    local towerX = x + font.width("R", scale) + scale + math.floor(towerW / 2)
    return { scale = scale, top = top, x = x, towerX = towerX, letterH = letterH,
        towerW = towerW, width = width, height = height }
end

function intro.frame(t, at, color, rings, letters)
    ui.fill(t, 1, 1, at.width, at.height, colors.black)
    for _, ring in ipairs(rings) do
        intro.ring(t, at.towerX, at.top - 1, ring, ring > at.width * 0.4 and colors.gray or color)
    end
    intro.tower(t, at.towerX, at.top, at.letterH, color)
    if letters >= 1 then font.draw(t, at.x, at.top, "R", colors.white, at.scale) end
    local after = at.towerX + math.floor(at.towerW / 2) + 1 + at.scale
    local word = ("DIO"):sub(1, math.max(0, letters - 1))
    if word ~= "" then font.draw(t, after, at.top, word, colors.white, at.scale) end
end

function intro.play(t, colorName)
    local color = colorOf(colorName)
    local at = intro.layout(t)
    -- Three rings, one after another.
    for step = 0, 26 do
        local rings = {}
        for ring = 0, 2 do
            local radius = (step - ring * 6) * 1.4
            if radius > 0 and radius < at.width * 0.6 then rings[#rings + 1] = radius end
        end
        intro.frame(t, at, color, rings, 0)
        sleep(intro.FRAME)
    end
    -- RADIO, a letter at a time, the tower already standing as its A.
    for letters = 1, 4 do
        intro.frame(t, at, color, {}, letters)
        sleep(intro.FRAME * 3)
    end
    sleep(0.4)
    -- One big ring: small, then everything.
    local most = math.sqrt(at.width ^ 2 + (at.height * 1.5) ^ 2) + 2
    for step = 1, 14 do
        intro.frame(t, at, color, {}, 4)
        intro.ring(t, at.towerX, at.top - 1, most * (step / 14) ^ 2, color, true)
        sleep(intro.FRAME)
    end
    ui.fill(t, 1, 1, at.width, at.height, color)
    sleep(0.15)
    -- The colour goes, top to bottom.
    for row = 1, at.height do
        ui.fill(t, 1, row, at.width, 1, ui.theme.background)
        sleep(0.025)
    end
end

-- Setting it up -------------------------------------------------------------------------------------

local setup = {}

function setup.pickColor(current)
    while running do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "Colour", "Rings, and the band on listeners' screens", util.formatClock())
        local scene = ui.scene(target)
        local each = math.floor((width - 2) / 4)
        for index, name in ipairs(music.COLORS) do
            local column, row = (index - 1) % 4, math.floor((index - 1) / 4)
            local color = colorOf(name)
            scene:button("color:" .. name, 2 + column * each, 5 + row * 3, each - 1, 2,
                (name == current and "> " or "") .. name, { background = color,
                foreground = ui.inkOn(color) })
        end
        scene:button("back", 1, height, 8, 1, "< Back", { background = ui.theme.panel })
        local action = scene:wait()
        if action == "back" or action == "__terminate" then return nil end
        local picked = action and action:match("^color:(.+)$")
        if picked then return picked end
    end
end

-- The dial: a tenth at a time, or a whole one; whether it is free is the
-- Music Server's to say.
function setup.pickFrequency(current, mine)
    local frequency = current or 984
    local width, height = target.getSize()
    while running do
        local tuned = server:request("MUSIC_TUNE", { frequency = frequency }, 3)
        local holder = tuned and tuned.station
        local free = tuned and (not holder or holder.station_id == mine)
        ui.clear(target)
        ui.header(target, "Frequency", "87.5 to 108.0", util.formatClock())
        local label = string.format("%d.%d", math.floor(frequency / 10), frequency % 10)
        local scale = font.width(label, 2) <= width - 4 and 2 or 1
        font.draw(target, math.floor((width - font.width(label, scale)) / 2) + 1, 5, label,
            colorOf(device.color), scale)
        ui.center(target, 6 + 5 * scale, not tuned and "The Music Server is not answering"
            or free and "Free" or ("Taken by " .. holder.name), free and ui.theme.success
            or ui.theme.danger)
        local scene = ui.scene(target)
        local quarter = math.floor((width - 5) / 4)
        local y = height - 4
        scene:button("down10", 2, y, quarter, 2, "<< 1.0", { background = ui.theme.panel })
        scene:button("down", 3 + quarter, y, quarter, 2, "< 0.1", { background = ui.theme.panel })
        scene:button("up", 4 + quarter * 2, y, quarter, 2, "0.1 >", { background = ui.theme.panel })
        scene:button("up10", 5 + quarter * 3, y, width - 4 - quarter * 3, 2, "1.0 >>",
            { background = ui.theme.panel })
        scene:button("pick", math.floor(width / 2) - 5, height - 1, 12, 1, "CHOOSE",
            { background = free and ui.theme.success or ui.theme.panel, foreground = colors.black,
              disabled = not free })
        scene:button("back", 1, height, 8, 1, "< Back", { background = ui.theme.panel })
        local action = scene:wait()
        if action == "back" or action == "__terminate" then return nil end
        if action == "pick" then return frequency end
        local steps = { down10 = -10, down = -1, up = 1, up10 = 10 }
        if steps[action] then
            frequency = frequency + steps[action]
            if frequency < 875 then frequency = 1080 end
            if frequency > 1080 then frequency = 875 end
        end
    end
end

-- The company's owner signs in; this computer keeps the station, not them.
function setup.signIn(name)
    if not name then
        name = ui.input(target, "Foxy Account", { hint = "The company's owner", maxLength = 20,
            allowSpace = true })
        if not name then return nil end
    end
    local pin = ui.pin(target, "PIN for " .. ui.truncate(name, 14), true)
    if not pin then return nil end
    local signed, err = bank:request("LOGIN", { name = name, pin = pin }, 6)
    if not signed then
        say("error", "NOT SIGNED IN", err, 1.6)
        return nil
    end
    return signed.session_token, name
end

function setup.signOut(session)
    pcall(bank.request, bank, "LOGOUT", { session_token = session }, 2)
end

function setup.run()
    local width, height = target.getSize()
    ui.clear(target)
    ui.header(target, "RADIO BROADCASTER", "Set up", util.formatClock())
    ui.wrappedText(target, 2, 5, "A radio station for one of your companies, on a frequency"
        .. " of its own. Listeners find it on the Radio app's dial. Sign in with the Foxy"
        .. " Account that owns the company.", width - 2, 6, ui.theme.muted)
    local scene = ui.scene(target)
    scene:button("start", 2, height - 4, width - 2, 3, "SIGN IN WITH FOXY",
        { background = ui.theme.accent, foreground = colors.black })
    local action = scene:wait()
    if action == "__terminate" then running = false return end
    if action ~= "start" then return end
    local session, name = setup.signIn()
    if not session then return end
    local owned, err = server:request("STATION_COMPANIES", { session_token = session }, 6)
    if not owned then
        setup.signOut(session)
        say("error", "NO MUSIC SERVER", err, 2)
        return
    end
    if #owned.companies == 0 then
        setup.signOut(session)
        say("warning", "NO COMPANY", "Start one in the Company app first", 2.4)
        return
    end
    local company
    while not company do
        ui.clear(target)
        ui.header(target, "RADIO BROADCASTER", "Which company?", util.formatClock())
        local pick = ui.scene(target)
        for index, entry in ipairs(owned.companies) do
            if index > math.floor((height - 6) / 3) then break end
            pick:button("company:" .. index, 2, 2 + index * 3, width - 2, 2,
                ui.truncate(entry.name .. (entry.radio_plus and "  RADIO+" or ""), width - 4),
                { background = ui.theme.panel })
        end
        pick:button("back", 1, height, 8, 1, "< Back", { background = ui.theme.panel })
        local chosen = pick:wait()
        if chosen == "back" or chosen == "__terminate" then
            setup.signOut(session)
            return
        end
        company = owned.companies[tonumber(chosen:match("^company:(%d+)$") or "")]
    end
    local stationName = ui.input(target, "Name the station", { initial = company.name,
        maxLength = 20, minLength = 2, allowSpace = true })
    local color = stationName and setup.pickColor("orange")
    device.color = color
    local frequency = color and setup.pickFrequency(984)
    if not frequency then
        setup.signOut(session)
        return
    end
    local made, madeError = server:request("STATION_REGISTER", { session_token = session,
        company_id = company.company_id, name = stationName, color = color,
        frequency = frequency }, 6)
    setup.signOut(session)
    if not made then
        say("error", "NOT SET UP", madeError, 2.4)
        return
    end
    device = { station_id = made.station_id, station_token = made.station_token,
        company_id = company.company_id, company_name = company.name, owner_name = name,
        color = color, music_server = device.music_server }
    save()
    shared.view = made.station
    intro.play(target, color)
end

-- Keeping in touch ------------------------------------------------------------------------------------
-- Asked every few seconds: what is on, what is queued. It is also what keeps
-- a station without Radio+ on the air.

function shared.refresh()
    local answer, err, code = ask("STATION_VIEW", {}, 4)
    if answer then
        shared.view, shared.online, shared.at = answer.station, true, util.nowMs()
        device.color = answer.station.color
    else
        shared.online = false
        if code == "STATION_AUTH" then
            device = { music_server = device.music_server }
            save()
            shared.view = nil
        end
    end
    return answer, err, code
end

function shared.edit(op, extra)
    local payload = extra or {}
    payload.op = op
    local answer, err = ask("STATION_EDIT", payload, 5)
    if answer then
        shared.view, shared.at = answer.station, util.nowMs()
        return true
    end
    say("error", "NOT DONE", err, 1.6)
    return false
end

-- The pages ------------------------------------------------------------------------------------------

local pages = { per = 12, library = { kind = "song", query = "", page = 1, mode = "playlist",
    picked = {} }, list_page = 1 }
local TYPE_NAMES = { song = "SONG", ["break"] = "BREAK", ads = "ADS", giveaway = "GIVEAWAY",
    clip = "UPLOAD" }

function pages.tabs(scene)
    local width = target.getSize()
    local view = shared.view or {}
    local band = colorOf(view.color)
    ui.fill(target, 1, 1, width, 1, band)
    ui.text(target, 2, 1, ui.truncate((view.name or "RADIO") .. "  " .. (view.label or ""),
        width - 12), ui.inkOn(band), band)
    local clock = util.formatClock()
    ui.text(target, width - #clock, 1, clock, ui.inkOn(band), band)
    local tabs = { { "air", "ON AIR" }, { "list", "PLAYLIST" }, { "add", "ADD" },
        { "station", "STATION" } }
    local each = math.floor(width / #tabs)
    for index, tab in ipairs(tabs) do
        local on = shared.page == tab[1]
        scene:button("tab:" .. tab[1], 1 + (index - 1) * each, 2, index == #tabs
            and (width - (index - 1) * each) or each, 1, tab[2],
            { background = on and band or ui.theme.panel,
              foreground = on and ui.inkOn(band) or ui.theme.ink })
    end
end

function pages.air(scene)
    local width, height = target.getSize()
    local view = shared.view
    if not view then
        ui.center(target, 8, shared.online and "..." or "Looking for the Music Server",
            ui.theme.muted)
        return
    end
    -- Twice the size only where everything under it still fits.
    local scale = font.width(view.label, 2) <= width - 4 and height >= 24 and 2 or 1
    font.draw(target, math.floor((width - font.width(view.label, scale)) / 2) + 1, 4,
        view.label, colorOf(view.color), scale)
    local y = 5 + 5 * scale
    local status = not view.on_air and "OFF AIR: switch this on, or get Radio+"
        or view.static and "ON AIR: static. Queue something" or "ON AIR"
    ui.center(target, y, ui.truncate(status, width - 2), view.on_air and not view.static
        and ui.theme.success or ui.theme.warning)
    local now = view.now
    if now then
        ui.text(target, 2, y + 1, ui.truncate((now.label and (now.label .. "  ") or "")
            .. now.title .. (now.artist and (" - " .. now.artist) or ""), width - 2), ui.theme.ink)
        local left = math.max(0, (now.position_ms or 0) + (util.nowMs() - shared.at))
        ui.progress(target, 2, y + 2, width - 2, math.min(left, now.length_ms), now.length_ms,
            colorOf(view.color), ui.theme.panel)
    end
    local facts = view.listeners .. " listening" .. (view.plus and "  RADIO+" or "")
        .. (view.featured and "  FEATURED TODAY" or "")
    if view.last_ad then
        facts = facts .. "  Last ad break " .. util.money(view.last_ad.paid or 0, config.currency)
            .. (view.last_ad.too_soon and " (too soon)" or "")
    end
    ui.text(target, 2, y + 3, ui.truncate(facts, width - 2), ui.theme.muted)
    if view.giveaway then
        ui.text(target, 2, y + 4, ui.truncate("GIVEAWAY: call " .. tostring(view.giveaway.number)
            .. "  " .. music.clock(view.giveaway.closes_in_ms), width - 2), ui.theme.warning)
    elseif view.winner and view.winner.name then
        ui.text(target, 2, y + 4, ui.truncate(view.winner.name .. " won "
            .. util.money(view.winner.prize or 0, config.currency), width - 2), ui.theme.success)
    end
    local nextUp = view.playlist[1]
    ui.text(target, 2, y + 5, ui.truncate(nextUp and ("Next: " .. TYPE_NAMES[nextUp.type]
        .. "  " .. nextUp.title) or (view.plus and "Next: Radio+ picks" or "Next: nothing queued"),
        width - 2), ui.theme.muted)
    local third = math.floor((width - 4) / 3)
    scene:button("skip", 2, height - 1, third, 2, "SKIP", { background = ui.theme.panel })
    scene:button("loop", 3 + third, height - 1, third, 2, "LOOP " .. (view.loop and "ON" or "OFF"),
        { background = view.loop and colorOf(view.color) or ui.theme.panel,
          foreground = view.loop and ui.inkOn(colorOf(view.color)) or nil })
    scene:button("tab:add", 4 + third * 2, height - 1, width - 3 - third * 2, 2, "+ ADD",
        { background = ui.theme.success, foreground = colors.black })
end

function pages.list(scene)
    local width, height = target.getSize()
    local view = shared.view or { playlist = {} }
    local per = height - 6
    local items, page, count = util.page(view.playlist, pages.list_page, per)
    pages.list_page = page
    for index, entry in ipairs(items) do
        local at = (page - 1) * per + index
        local y = 3 + index
        ui.text(target, 2, y, ui.truncate(at .. " " .. TYPE_NAMES[entry.type] .. "  " .. entry.title
            .. (entry.prize and ("  " .. util.money(entry.prize, config.currency)) or ""),
            width - 15), ui.theme.ink)
        local id = entry.entry_id
        scene:button("next:" .. id, width - 12, y, 3, 1, ">", { background = ui.theme.panel })
        scene:button("up:" .. id, width - 9, y, 3, 1, "^", { background = ui.theme.panel })
        scene:button("down:" .. id, width - 6, y, 3, 1, "v", { background = ui.theme.panel })
        scene:button("remove:" .. id, width - 3, y, 3, 1, "x", { background = ui.theme.danger })
    end
    if #view.playlist == 0 then
        ui.wrappedText(target, 2, 5, "Nothing queued. ADD songs, breaks, ad breaks and"
            .. " giveaways" .. (view.plus and ", or drop a .dfpwm file on this screen." or ".")
            .. " With Radio+ the station plays on by itself when this runs out.",
            width - 2, 5, ui.theme.muted)
    end
    scene:button("clear", 2, height - 1, 10, 1, "CLEAR", { background = ui.theme.danger,
        disabled = #view.playlist == 0 })
    if count > 1 then
        scene:button("listpage", width - 8, height - 1, 8, 1, page .. "/" .. count,
            { background = ui.theme.panel })
    end
end

-- The Music Library, by kind, to add from -- or, with Radio+, to choose what
-- the station picks from by itself.
function pages.add(scene)
    local width, height = target.getSize()
    local state = pages.library
    local view = shared.view or {}
    local kinds = { { "song", "SONGS" }, { "host", "BREAKS" }, { "ad", "ADS" },
        { "giveaway", "GIVEAWAYS" } }
    local each = math.floor((width - 1) / #kinds)
    for index, kind in ipairs(kinds) do
        scene:button("kind:" .. kind[1], 2 + (index - 1) * each, 4, each - 1, 1, kind[2],
            { background = state.kind == kind[1] and ui.theme.accent or ui.theme.panel,
              foreground = state.kind == kind[1] and colors.black or nil })
    end
    local picks = state.mode == "pool" and state.kind ~= "giveaway"
    scene:button("search", 2, 5, math.floor(width / 2) - 2, 1, state.query ~= ""
        and ("Search: " .. state.query) or "Search", { background = ui.theme.panel })
    if view.plus and state.kind ~= "giveaway" then
        scene:button("mode", math.floor(width / 2) + 1, 5, width - math.floor(width / 2) - 1, 1,
            picks and "ADDS TO: RADIO+ PICKS" or "ADDS TO: PLAYLIST",
            { background = picks and colorOf(view.color) or ui.theme.panel })
    end
    local listed = shared.library
    if not listed or listed.kind ~= state.kind or listed.query ~= state.query
        or listed.page ~= state.page then
        local answer = ask("STATION_LIBRARY", { kind = state.kind, query = state.query,
            page = state.page, per_page = height - 9 }, 4)
        listed = answer and { kind = state.kind, query = state.query, page = answer.page,
            pages = answer.pages, tracks = answer.tracks } or { tracks = {}, pages = 1, page = 1 }
        shared.library = listed
        state.page = listed.page
    end
    local pool = {}
    for _, id in ipairs(((view.pools or {})[state.kind]) or {}) do pool[id] = true end
    for index, track in ipairs(listed.tracks) do
        local marked = (picks and pool[track.track_id]) or state.picked[track.track_id]
        scene:button("track:" .. track.track_id, 2, 6 + index, width - 2, 1,
            ui.truncate((marked and "* " or "") .. track.title .. " - " .. track.artist .. "  "
                .. music.clock(track.length_ms), width - 4),
            { background = marked and colorOf(view.color) or ui.theme.panel })
    end
    if #listed.tracks == 0 then
        ui.center(target, 8, "Nothing like that in the Music Library", ui.theme.muted)
    end
    local count = 0
    for _ in pairs(state.picked) do count = count + 1 end
    if state.kind == "ad" and not picks then
        scene:button("adbreak", 2, height - 1, 24, 1, "ADD AD BREAK (" .. count .. ")",
            { background = ui.theme.success, foreground = colors.black, disabled = count == 0 })
    end
    if (listed.pages or 1) > 1 then
        scene:button("libpage", width - 8, height - 1, 8, 1, listed.page .. "/" .. listed.pages,
            { background = ui.theme.panel })
    end
end

function pages.station(scene)
    local width, height = target.getSize()
    local view = shared.view or {}
    local lines = {
        { "Station", view.name or "-" }, { "Frequency", view.label or "-" },
        { "Company", device.company_name or "-" },
        { "Phone", view.number or "Not yet" },
        { "Radio+", view.plus and "Yes: on round the clock, Quick Upload, saveable"
            or "No: on while this is, static when the playlist ends" },
        { "Cover", view.cover and "Yes: beside every Now Playing" or "None yet" },
        { "Version", PROGRAM_VERSION },
    }
    for index, line in ipairs(lines) do
        ui.text(target, 2, 3 + index, line[1], ui.theme.muted)
        ui.text(target, 13, 3 + index, ui.truncate(tostring(line[2]), width - 14), ui.theme.ink)
    end
    local third = math.floor((width - 4) / 3)
    -- FoxyOS 18.3: and its cover.
    local quarter = math.floor((width - 5) / 4)
    scene:button("rename", 2, 11, quarter, 1, "RENAME", { background = ui.theme.panel })
    scene:button("color", 3 + quarter, 11, quarter, 1, "COLOUR", { background = ui.theme.panel })
    scene:button("cover", 4 + quarter * 2, 11, quarter, 1, "COVER", { background = ui.theme.panel })
    scene:button("frequency", 5 + quarter * 3, 11, width - 4 - quarter * 3, 1, "FREQUENCY",
        { background = ui.theme.panel })
    scene:button("plus", 2, 13, width - 2, 2, view.plus and "RADIO+: MANAGE"
        or ("GET RADIO+  " .. util.money(tonumber(config.radio_plus_price) or 100, config.currency)
            .. " / " .. (tonumber(config.radio_plus_days) or 15) .. " DAYS"),
        { background = colorOf(view.color), foreground = ui.inkOn(colorOf(view.color)) })
    scene:button("money", 2, 16, third, 1, "COMPANY MONEY", { background = ui.theme.panel })
    scene:button("beta", 3 + third, 16, third, 1, "BETA", { background = ui.theme.panel })
    scene:button("unlink", 4 + third * 2, 16, width - 3 - third * 2, 1, "OFF AIR FOR GOOD",
        { background = ui.theme.danger })
end

-- Doing what was pressed ------------------------------------------------------------------------------

local act = {}

-- The owner's PIN for the company's money: signed in for one request.
function act.asOwner(action, extra)
    local session = setup.signIn(device.owner_name)
    if not session then return nil end
    extra = extra or {}
    extra.session_token, extra.company_id, extra.app_id = session, device.company_id, "RADIO"
    local answer, err = bank:request(action, extra, 6)
    setup.signOut(session)
    if not answer then say("error", "NOT DONE", err, 2) end
    return answer
end

function act.plus()
    local view = shared.view or {}
    if view.plus then
        if ui.confirm(target, "RADIO+", "Stop Radio+ at the end of the days paid for?",
            "STOP IT", "KEEP IT") then
            if act.asOwner("RADIO_PLUS_CANCEL") then say("success", "Radio+", "Ends on its day") end
        end
        return
    end
    if not ui.confirm(target, "RADIO+", util.money(tonumber(config.radio_plus_price) or 100,
        config.currency) .. " every " .. (tonumber(config.radio_plus_days) or 15)
        .. " days, out of " .. tostring(device.company_name) .. "'s Company Money.",
        "GET IT", "NOT NOW") then return end
    if act.asOwner("RADIO_PLUS_START") then
        say("success", "RADIO+", "On round the clock", 1.6)
        shared.refresh()
    end
end

function act.track(trackId)
    local state = pages.library
    if state.mode == "pool" and state.kind ~= "giveaway" and (shared.view or {}).plus then
        return shared.edit("pool", { kind = state.kind, track_id = trackId })
    end
    if state.kind == "song" then
        if shared.edit("add", { type = "song", track_id = trackId }) then say("success", "Queued", nil, 0.6) end
    elseif state.kind == "host" then
        if shared.edit("add", { type = "break", track_id = trackId }) then say("success", "Queued", nil, 0.6) end
    elseif state.kind == "ad" then
        state.picked[trackId] = (not state.picked[trackId]) or nil
    elseif state.kind == "giveaway" then
        local prize = tonumber(ui.input(target, "The prize", { hint = "Out of Company Money,"
            .. " held until the draw", mode = "number", maxLength = 7 }) or "")
        if prize and prize >= 1 and shared.edit("add", { type = "giveaway", track_id = trackId,
            prize = math.floor(prize) }) then
            say("success", "Giveaway queued", util.money(math.floor(prize), config.currency), 0.9)
        end
    end
end

function act.press(action)
    local view = shared.view or {}
    local id = action and action:match("^[a-z]+:(.+)$")
    if action:match("^tab:") then
        shared.page = action:sub(5)
    elseif action == "skip" then
        shared.edit("skip")
    elseif action == "loop" then
        shared.edit("loop", { on = not view.loop })
    elseif action:match("^next:") or action:match("^up:") or action:match("^down:")
        or action:match("^remove:") then
        shared.edit(action:match("^([a-z]+):"), { entry_id = id })
    elseif action == "clear" then
        if ui.confirm(target, "CLEAR?", "Everything queued goes.", "CLEAR", "BACK") then
            shared.edit("clear")
        end
    elseif action == "listpage" then
        pages.list_page = pages.list_page + 1
    elseif action:match("^kind:") then
        pages.library.kind, pages.library.page, pages.library.picked = id, 1, {}
    elseif action == "search" then
        pages.library.query = ui.input(target, "Search", { initial = pages.library.query,
            maxLength = 20, allowSpace = true }) or pages.library.query
        pages.library.page = 1
    elseif action == "mode" then
        pages.library.mode = pages.library.mode == "pool" and "playlist" or "pool"
    elseif action == "libpage" then
        pages.library.page = (pages.library.page % ((shared.library or {}).pages or 1)) + 1
    elseif action:match("^track:") then
        act.track(id)
    elseif action == "adbreak" then
        local ids = {}
        for trackId in pairs(pages.library.picked) do ids[#ids + 1] = trackId end
        table.sort(ids)
        if shared.edit("add", { type = "ads", track_ids = ids }) then
            pages.library.picked = {}
            say("success", "Ad break queued", #ids .. " ads", 0.8)
        end
    elseif action == "rename" then
        local name = ui.input(target, "Station name", { initial = view.name, maxLength = 20,
            minLength = 2, allowSpace = true })
        if name then shared.edit("rename", { name = name }) end
    elseif action == "color" then
        local color = setup.pickColor(view.color)
        if color and shared.edit("color", { color = color }) then device.color = color save() end
    elseif action == "cover" then
        local cover = ui.iconCreator(target, view.cover, view.name, "cover")
        if cover then shared.edit("cover", { cover = cover }) end
    elseif action == "frequency" then
        local frequency = setup.pickFrequency(view.frequency, view.station_id)
        if frequency then shared.edit("frequency", { frequency = frequency }) end
    elseif action == "plus" then
        act.plus()
    elseif action == "money" then
        local money = act.asOwner("COMPANY_MONEY")
        if money then
            say("info", "COMPANY MONEY", util.money(money.free, config.currency) .. " free of "
                .. util.money(money.balance, config.currency), 2.4)
        end
    elseif action == "beta" and type(ui.betaUpdates) == "function" then
        ui.betaUpdates(target, ROOT, { kind = "Radio Broadcaster", version = config.version })
    elseif action == "unlink" then
        if ui.confirm(target, "OFF AIR FOR GOOD?", "The station, its playlist and its frequency"
            .. " go. Listeners who saved it lose it.", "GO OFF AIR", "BACK") then
            local done, err = ask("STATION_UNLINK", {}, 5)
            if done then
                device = { music_server = device.music_server }
                save()
                shared.view = nil
            else
                say("error", "STILL ON AIR", err, 1.6)
            end
        end
    end
end

-- Quick Upload: .dfpwm files dropped on this screen, with Radio+.
function act.dropped(files)
    if not (shared.view or {}).plus then return "Quick Upload comes with Radio+" end
    local added, problem = {}, nil
    for _, file in ipairs(files) do
        local name = fs.getName(tostring(file.getName and file.getName() or ""))
        if music.isAudio(name) then
            local body = file.readAll() or ""
            local began, err = ask("STATION_UPLOAD_BEGIN", { size = #body,
                title = music.titleFrom(name) }, 6)
            local ok = began and music.upload(began.plan, body, CLOUD)
            local done = ok and ask("STATION_UPLOAD_DONE", { upload_id = began.upload_id }, 6)
            if done then
                shared.view = done.station
                added[#added + 1] = music.titleFrom(name)
            else
                problem = err or "It did not reach the Cloud Servers"
            end
        else
            problem = name .. " is not a .dfpwm file"
        end
    end
    if #added > 0 then return "Queued " .. table.concat(added, ", ") end
    return problem or "Nothing to add"
end

-- Running --------------------------------------------------------------------------------------------

local loops = {}

function loops.screen()
    while running do
        if not device.station_id then
            setup.run()
        else
            local scene = ui.scene(target)
            ui.clear(target)
            pages.tabs(scene)
            pages[shared.page](scene)
            if shared.dropped then
                local _, height = target.getSize()
                ui.text(target, 2, height - 2, ui.truncate(shared.dropped, 49), ui.theme.success)
            end
            local action = scene:wait({ tickRate = 1, files = true })
            if action == "__terminate" then
                running = false
            elseif action == "__files" then
                local ok, files = pcall(function() return scene.dropped.getFiles() end)
                local done, said = pcall(act.dropped, ok and files or {})
                for _, file in ipairs(ok and files or {}) do pcall(file.close) end
                shared.dropped = done and said or tostring(said)
            elseif action and action ~= "__tick" and action ~= "__wake" and action ~= "__idle" then
                act.press(action)
            end
        end
    end
end

-- Every few seconds, whatever the screen is doing: what is on, and staying
-- on the air.
function loops.beat()
    local updatedAt = util.nowMs()
    while running do
        if device.station_id then pcall(shared.refresh) end
        if util.nowMs() - updatedAt > 60000 then
            updatedAt = util.nowMs()
            net.autoUpdate(config, "radio", ROOT, nil)
        end
        sleep(3)
    end
end

if TEST_MODE == "radio_broadcaster" then
    return { intro = intro, font = font, setup = setup, shared = shared, pages = pages,
        act = act, loops = loops, device = function() return device end,
        stop = function() running = false end, go = function() running = true end }
end

net.openModems()
if type(ui.useMainColor) == "function" then ui.useMainColor(ROOT) end
net.autoUpdate(config, "radio", ROOT, nil, { force = true, programVersion = PROGRAM_VERSION })
intro.play(target, device.color or "orange")
parallel.waitForAny(loops.screen, loops.beat)
ui.clear(target)
