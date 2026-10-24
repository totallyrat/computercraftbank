-- The Music app's screens, FoxyOS 18.4, shared by the Music app on a Pocket
-- and the Music Player's own screen.
--
-- Three tabs along the bottom -- Music, Search and Me -- in a bar of their
-- own, and what is playing along the top: tap it for Now Playing. Every page
-- scrolls with the scroll wheel.
--
--   Music   yours first -- Recently Played, Favorites, Replayed -- then New
--           Music, Popular, Radio Hits, the Charts, the Mixes and everybody's
--           playlists, each a row of covers turned with its < >. Under them,
--           every song in the library.
--   Search  a box on top; under it every genre (tap one for its songs and
--           its mix) and every artist. Typed in, it finds artists, genres
--           and songs.
--   Me      your plan and your playlists, and + for a new one.
--
-- Tap an artist's name on a song -- in a list, under a cover, on Now
-- Playing -- for their profile.
--
-- musicui.new(env) is the app. `env` holds ui, util, colors, target and:
--   ask(action, payload)        the Music Server, as whoever is listening
--   play(trackId, queue, listId) start a song on the player; true if it did
--   current()                   what is playing: { title, artist, paused,
--                               where } -- `where` when nothing is
--   nowPage(app)                Now Playing; returns like a page (below)
--   running()                   false to stop
-- and optionally: accent, home (a "<" that leaves), plusPage(app), tabs (more
-- tabs: { id, label, page(app) }), marks(track) and mark(key, track, app)
-- (buttons at the end of a song's line), meButtons ({ id, label, run(app) }),
-- refresh() (each tick), offline() and offlinePage(app).
--
-- A page returns "tab:<id>" to change tab, "home" or "__terminate" to leave,
-- or "back" to go back to the page that opened it.

local musicui = {}

local TILE = 7       -- a cover (6 wide) and the lines under it
local ROW = 7        -- a row: its title, the covers and two lines under them

local App = {}
App.__index = App

function musicui.new(env)
    local app = setmetatable({ env = env, ui = env.ui, util = env.util, colors = env.colors,
        target = env.target, accent = env.accent or env.colors.pink, offsets = {},
        query = "", handlers = {} }, App)
    app.tabs = { { id = "music", label = "Music" }, { id = "search", label = "Search" },
        { id = "me", label = "Me" } }
    app.pages = { music = App.musicPage, search = App.searchPage, me = App.mePage }
    for _, tab in ipairs(env.tabs or {}) do
        app.tabs[#app.tabs + 1] = { id = tab.id, label = tab.label }
        app.pages[tab.id] = tab.page
    end
    return app
end

function App:running() return not self.env.running or self.env.running() end

function App:ask(action, payload) return self.env.ask(action, payload or {}) end

function App:said(kind, title, body, seconds)
    self.ui.message(self.target, kind, title, body or "", seconds or 1.4)
end

local function leaving(result)
    return type(result) == "string" and (result:match("^tab:") or result == "home"
        or result == "__terminate" or result == "stop")
end
musicui.leaving = leaving

-- The chrome ------------------------------------------------------------------------------------

-- Along the top, what is playing -- a tap opens Now Playing -- and the page's
-- title under it; along the bottom, the tabs. Returns the first and last rows
-- left for the page.
function App:chrome(scene, title, options)
    options = options or {}
    local ui, target, colors = self.ui, self.target, self.colors
    local width, height = target.getSize()
    local accent = self.accent
    ui.fill(target, 1, 1, width, 1, accent)
    local x = 1
    if self.env.home then
        scene:button("home", 1, 1, 1, 1, "<", { background = colors.black, foreground = accent,
            flash = false })
        x = 3
    end
    local now = self.env.current and self.env.current() or nil
    local clock = self.util.formatClock()
    local line = now and now.title and ((now.paused and "|| " or "> ") .. now.title
        .. (now.artist and (" - " .. now.artist) or ""))
        or (now and now.where) or "Nothing playing"
    ui.text(target, x, 1, ui.truncate(line, math.max(1, width - x - #clock - 1)), colors.black,
        accent)
    ui.text(target, width - #clock + 1, 1, clock, colors.black, accent)
    scene:hotspot("now", x, 1, math.max(1, width - x - #clock), 1)
    local titleX = 2
    if options.back then
        scene:button("back", 1, 2, 3, 1, "<", { background = ui.theme.panel })
        titleX = 5
    end
    local subtitle = options.subtitle and tostring(options.subtitle) or ""
    local room = width - titleX - (#subtitle > 0 and #subtitle + 1 or 0)
    ui.text(target, titleX, 2, ui.truncate(title or "", math.max(1, room)), ui.theme.ink)
    if #subtitle > 0 and room > 4 then
        ui.text(target, width - #subtitle + 1, 2, subtitle, ui.theme.muted)
    end
    self:tabBar(scene, options.tab)
    return 3, height - 1
end

-- The tabs, FoxyOS 18.4: the whole bottom row, each tab an equal part of it,
-- the one you are on lit.
function App:tabBar(scene, active)
    local ui, target = self.ui, self.target
    local width, height = target.getSize()
    ui.fill(target, 1, height, width, 1, ui.theme.panel)
    local each, over = math.floor(width / #self.tabs), width % #self.tabs
    local x = 1
    for index, tab in ipairs(self.tabs) do
        local slot = each + (index <= over and 1 or 0)
        local on = tab.id == active
        if on then ui.fill(target, x, height, slot, 1, self.accent) end
        local label = ui.truncate(tab.label, slot)
        ui.text(target, x + math.floor((slot - #label) / 2), height, label,
            on and self.colors.black or ui.theme.muted, on and self.accent or ui.theme.panel)
        scene:hotspot("tab:" .. tab.id, x, height, slot, 1)
        x = x + slot
    end
end

-- Blocks: what a page is made of ------------------------------------------------------------------
-- Each is { height, draw(app, scene, y, width) }. A page scrolls a block at a
-- time (three, among lines of songs).

local block = {}
musicui.block = block

function block.text(text, color)
    return { kind = "text", text = text, color = color,
        height = function(app, width) return #app.ui.wrap(text, width - 2) end,
        draw = function(app, _, y, width, lines)
            app.ui.wrappedText(app.target, 2, y, text, width - 2, lines,
                color or app.ui.theme.muted)
        end }
end

function block.heading(text)
    return { kind = "heading", height = 2, draw = function(app, _, y, width)
        app.ui.text(app.target, 2, y + 1, app.ui.truncate(text:upper(), width - 2), app.accent)
    end }
end

function block.button(id, label, run, primary)
    return { kind = "button", height = 2, draw = function(app, scene, y, width)
        local ui = app.ui
        scene:button(id, 2, y, width - 2, 1, ui.truncate(label, width - 4), {
            background = primary and app.accent or ui.theme.panel,
            foreground = primary and app.colors.black or ui.theme.ink })
        app.handlers[id] = run
    end }
end

-- A song on a line of its own: its title plays it (and what follows it in
-- the list), its artist opens their profile.
function block.song(listId, index, tracks, playlistId)
    local track = tracks[index]
    return { kind = "line", height = 1, draw = function(app, scene, y, width)
        local ui = app.ui
        local marks = app.env.marks and app.env.marks(track) or {}
        local room = width - 2 - #marks * 2
        local titleWidth = math.floor(room * 0.55)
        local artistX, artistWidth = 2 + titleWidth + 1, room - titleWidth - 1
        local id = listId .. ":" .. index
        ui.text(app.target, 2, y, ui.truncate(track.title, titleWidth), ui.theme.ink)
        ui.text(app.target, artistX, y, ui.truncate(track.artist or "", artistWidth),
            ui.theme.muted)
        scene:hotspot("song:" .. id, 1, y, titleWidth + 1, 1)
        scene:hotspot("by:" .. id, artistX, y, math.max(1, artistWidth), 1)
        app.handlers["song:" .. id] = function()
            return app:play(track.track_id, app.idsOf(tracks), playlistId)
        end
        app.handlers["by:" .. id] = function() return app:credits(track) end
        for at, mark in ipairs(marks) do
            local markId = "mark:" .. mark.key .. ":" .. id
            scene:button(markId, width - #marks * 2 + at * 2 - 1, y, 1, 1, mark.label,
                { background = ui.theme.panel })
            app.handlers[markId] = function() return app.env.mark(mark.key, track, app) end
        end
    end }
end

function block.artist(artist)
    return { kind = "line", height = 1, draw = function(app, scene, y, width)
        local ui = app.ui
        local count = (artist.listeners_today or 0) .. " today"
        ui.text(app.target, 2, y, ui.truncate(artist.name, width - #count - 3), ui.theme.ink)
        ui.text(app.target, width - #count + 1, y, count, ui.theme.muted)
        local id = "artist:" .. artist.artist_id
        scene:hotspot(id, 1, y, width, 1)
        app.handlers[id] = function() return app:artistPage(artist.artist_id) end
    end }
end

function block.genre(genre)
    return { kind = "line", height = 1, draw = function(app, scene, y, width)
        local ui = app.ui
        local count = genre.songs .. " songs"
        ui.text(app.target, 2, y, ui.truncate(genre.name, width - #count - 3), ui.theme.ink)
        ui.text(app.target, width - #count + 1, y, count, ui.theme.muted)
        local id = "genre:" .. genre.genre_id
        scene:hotspot(id, 1, y, width, 1)
        app.handlers[id] = function() return app:genrePage(genre.genre_id) end
    end }
end

-- A cover with its two lines: a song's title and artist, or a playlist's
-- name and who made it.
local function tile(app, scene, rowId, index, item, items, x, y, playlistId)
    local ui = app.ui
    ui.cover(app.target, x, y, item.cover)
    ui.text(app.target, x, y + ui.COVER_HEIGHT, ui.truncate(item.title or item.name, TILE),
        ui.theme.ink)
    local id = rowId .. ":" .. index
    scene:hotspot("tile:" .. id, x, y, TILE, ui.COVER_HEIGHT + 1)
    if item.track_id then
        ui.text(app.target, x, y + ui.COVER_HEIGHT + 1, ui.truncate(item.artist or "", TILE),
            ui.theme.muted)
        scene:hotspot("by:" .. id, x, y + ui.COVER_HEIGHT + 1, TILE, 1)
        app.handlers["tile:" .. id] = function()
            return app:play(item.track_id, app.idsOf(items), playlistId)
        end
        app.handlers["by:" .. id] = function() return app:credits(item) end
    else
        ui.text(app.target, x, y + ui.COVER_HEIGHT + 1, ui.truncate(item.owner_name or "", TILE),
            ui.theme.muted)
        app.handlers["tile:" .. id] = function() return app:playlistPage(item.playlist_id) end
    end
end

local function across(width)
    local count = math.max(1, math.floor((width - 1) / (TILE + 1)))
    local left = 2 + math.floor((width - 2 - (count * (TILE + 1) - 1)) / 2)
    return count, left
end

-- A row of covers under its title, turned with its own < >.
function block.row(row)
    local items = row.tracks or row.playlists or {}
    return { kind = "row", height = ROW, draw = function(app, scene, y, width)
        local ui = app.ui
        local count, left = across(width)
        ui.text(app.target, 2, y, ui.truncate(row.title:upper(), width - 2), app.accent)
        local offset = math.max(0, math.min(app.offsets[row.id] or 0, #items - count))
        app.offsets[row.id] = offset
        for index = 1, math.min(count, #items - offset) do
            tile(app, scene, row.id, offset + index, items[offset + index], items,
                left + (index - 1) * (TILE + 1), y + 1)
        end
        if offset > 0 then
            scene:button("left:" .. row.id, 1, y + 1, 1, ui.COVER_HEIGHT, "<",
                { background = ui.theme.panel })
            app.handlers["left:" .. row.id] = function()
                app.offsets[row.id] = offset - count
            end
        end
        if offset + count < #items then
            scene:button("right:" .. row.id, width, y + 1, 1, ui.COVER_HEIGHT, ">",
                { background = ui.theme.panel })
            app.handlers["right:" .. row.id] = function()
                app.offsets[row.id] = offset + count
            end
        end
    end }
end

-- Covers in rows that do not turn: every one of them, a row at a time.
function block.grid(gridId, items, width)
    local count = across(width)
    local list = {}
    for first = 1, #items, count do
        local at = first
        list[#list + 1] = { kind = "grid", height = ROW, draw = function(app, scene, y)
            local _, left = across(width)
            for index = at, math.min(#items, at + count - 1) do
                tile(app, scene, gridId, index, items[index], items,
                    left + (index - at) * (TILE + 1), y)
            end
        end }
    end
    return list
end

-- A profile's or a playlist's top: the cover, and lines beside it.
function block.top(cover, lines)
    return { kind = "top", height = 5, draw = function(app, _, y, width)
        local ui = app.ui
        ui.cover(app.target, 2, y, cover)
        local x = 2 + ui.COVER_WIDTH + 1
        for index, line in ipairs(lines) do
            if index > 4 then break end
            ui.text(app.target, x, y + index - 1, ui.truncate(line[1], width - x + 1),
                line[2] or ui.theme.ink)
        end
    end }
end

-- Pages ----------------------------------------------------------------------------------------------

-- A page of blocks. spec: title, subtitle, tab (lit in the bar), back (a <
-- that returns "back"), build(app) -> blocks, err; more(app) -> more blocks,
-- for a page that goes on as it is scrolled; tick (seconds) to refresh.
function App:feed(spec)
    local ui, target = self.ui, self.target
    local offset, blocks, err = 0, nil, nil
    while self:running() do
        if not blocks then
            blocks, err = spec.build(self)
            blocks = blocks or {}
        end
        local width = target.getSize()
        ui.clear(target)
        local scene = ui.scene(target)
        self.handlers = {}
        local top, bottom = self:chrome(scene, spec.title, { tab = spec.tab, back = spec.back,
            subtitle = spec.subtitle })
        offset = math.max(0, math.min(offset, #blocks - 1))
        local y, last = top, offset
        if err then
            y = y + ui.wrappedText(target, 2, y, tostring(err), width - 2, 3, ui.theme.warning) + 1
        end
        for index = offset + 1, #blocks do
            local item = blocks[index]
            local height = type(item.height) == "function" and item.height(self, width)
                or item.height
            local room = bottom - y + 1
            if height > room and not (item.kind == "text" and room > 0) then break end
            item.draw(self, scene, y, width, math.min(height, room))
            y, last = y + height, index
            if y > bottom then break end
        end
        local more = spec.more and last >= #blocks - 1 and spec.more(self) or nil
        if more and #more > 0 then
            for _, item in ipairs(more) do blocks[#blocks + 1] = item end
        else
            local action = scene:wait({ scroll = true, tickRate = spec.tick or 2 })
            local step = blocks[offset + 1] and blocks[offset + 1].kind == "line" and 3 or 1
            if action == "__scrolldown" then
                if last < #blocks then offset = offset + step end
            elseif action == "__scrollup" then
                offset = math.max(0, offset - step)
            elseif action == "back" or leaving(action) then
                return action
            elseif action == "now" then
                local result = self.env.nowPage(self)
                if leaving(result) then return result end
            elseif action == "__tick" then
                if self.env.refresh then self.env.refresh() end
                if spec.live then blocks = nil end
            elseif self.handlers[action] then
                local result = self.handlers[action]()
                if leaving(result) then return result end
                if result == "refresh" then blocks = nil end
            end
        end
    end
    return "stop"
end

function App.idsOf(tracks)
    local ids = {}
    for _, track in ipairs(tracks or {}) do ids[#ids + 1] = track.track_id end
    return ids
end

function App:play(trackId, queue, playlistId)
    if self.env.play(trackId, queue, playlistId) then return "played" end
end

-- An artist's name on a song: their profile, or a choice of them.
function App:credits(track)
    local credited = track.artists or {}
    if #credited == 1 then return self:artistPage(credited[1].artist_id) end
    if #credited == 0 then return self:artistPage(nil, track.artist) end
    return self:feed({ title = "Artists", subtitle = track.title, back = true,
        build = function()
            local list = {}
            for _, artist in ipairs(credited) do
                list[#list + 1] = block.artist({ artist_id = artist.artist_id,
                    name = artist.name, listeners_today = artist.listeners_today })
            end
            return list
        end })
end

function App:artistPage(artistId, name)
    return self:feed({ title = "Artist", back = true, build = function(app)
        local found, err = app:ask("MUSIC_ARTIST", { artist_id = artistId, name = name })
        if not found then return nil, err end
        local artist = found.artist
        local list = { block.top(artist.cover, {
            { artist.name, app.ui.theme.ink },
            { artist.listeners_today .. " today", app.accent },
            { artist.songs_count .. " songs", app.ui.theme.muted },
            { (artist.plays or 0) .. " plays", app.ui.theme.muted } }) }
        if artist.bio and artist.bio ~= "" then list[#list + 1] = block.text(artist.bio) end
        if #(artist.songs or {}) > 0 then
            list[#list + 1] = block.button("playall", "> Play", function()
                return app:play(artist.songs[1].track_id, App.idsOf(artist.songs))
            end, true)
        end
        list[#list + 1] = block.heading("Songs")
        for index in ipairs(artist.songs or {}) do
            list[#list + 1] = block.song("artist", index, artist.songs)
        end
        list[#list + 1] = block.heading("On the radio")
        for _, radio in ipairs(artist.radios or {}) do
            list[#list + 1] = block.text(radio.name .. (radio.frequency and string.format("  %d.%d",
                math.floor(radio.frequency / 10), radio.frequency % 10) or ""), app.ui.theme.ink)
        end
        if #(artist.radios or {}) == 0 then list[#list + 1] = block.text("Not yet") end
        return list
    end })
end

function App:genrePage(genreId)
    return self:feed({ title = "Genre", back = true, build = function(app)
        local found, err = app:ask("MUSIC_GENRE", { genre_id = genreId })
        if not found then return nil, err end
        local list = { block.top(found.mix and found.mix.cover, {
            { found.genre.name, app.ui.theme.ink },
            { found.genre.songs .. " songs", app.ui.theme.muted } }) }
        if found.mix then
            list[#list + 1] = block.button("mix", "> Play the mix", function()
                return app:playPlaylist(found.mix.playlist_id)
            end, true)
        end
        list[#list + 1] = block.heading("Songs")
        for index in ipairs(found.tracks) do
            list[#list + 1] = block.song("genre", index, found.tracks)
        end
        return list
    end })
end

function App:playPlaylist(playlistId)
    local opened, err = self:ask("MUSIC_PLAYLIST", { playlist_id = playlistId })
    if not opened or #opened.playlist.tracks == 0 then
        self:said("error", "Nothing to play", err or "It has no songs")
        return nil
    end
    local tracks = opened.playlist.tracks
    return self:play(tracks[1].track_id, App.idsOf(tracks), playlistId)
end

function App:playlistPage(playlistId)
    local list
    local result
    result = self:feed({ title = "Playlist", back = true, build = function(app)
        local opened, err = app:ask("MUSIC_PLAYLIST", { playlist_id = playlistId })
        if not opened then return nil, err end
        list = opened.playlist
        local blocks = { block.top(list.cover, {
            { list.name, app.ui.theme.ink },
            { "By " .. tostring(list.owner_name or "?"), app.ui.theme.muted },
            { list.songs_count .. " songs", app.ui.theme.muted },
            { list.auto and "New every day" or (list.public and "Public" or "Private"),
                app.ui.theme.muted } }) }
        if list.about then blocks[#blocks + 1] = block.text(list.about) end
        if #list.tracks > 0 then
            blocks[#blocks + 1] = block.button("playall", "> Play", function()
                return app:play(list.tracks[1].track_id, App.idsOf(list.tracks), list.playlist_id)
            end, true)
        end
        if list.mine then
            blocks[#blocks + 1] = block.button("edit", "Edit", function()
                local edited = app:editPlaylist(list)
                if not edited then return "back" end
                return "refresh"
            end)
        end
        for index in ipairs(list.tracks) do
            blocks[#blocks + 1] = block.song("playlist", index, list.tracks, list.playlist_id)
        end
        if #list.tracks == 0 then blocks[#blocks + 1] = block.text("No songs yet") end
        return blocks
    end })
    return result
end

-- Music ------------------------------------------------------------------------------------------------

local EMPTY = "Play something: what you play, love and replay shows up here."

function App:musicPage()
    if self.env.offline and self.env.offline() and self.env.offlinePage then
        return self.env.offlinePage(self)
    end
    local page, pages = 0, 1
    return self:feed({ title = "Music", tab = "music", build = function(app)
        page, pages = 0, 1
        local home, err = app:ask("MUSIC_HOME")
        if not home then return nil, err end
        app.favorites = home.favorites
        local list, personal = {}, 0
        for _, row in ipairs(home.rows) do
            local items = row.tracks or row.playlists or {}
            if #items > 0 then
                list[#list + 1] = block.row(row)
                if row.personal then personal = personal + 1 end
            end
        end
        if personal == 0 then table.insert(list, 1, block.text(EMPTY)) end
        list[#list + 1] = block.heading("Every song")
        return list
    end, more = function(app)
        if page >= pages then return nil end
        local listed = app:ask("MUSIC_LIBRARY", { sort = "new", page = page + 1, per_page = 20 })
        if not listed then return nil end
        page, pages = listed.page, listed.pages
        app.library = app.library or {}
        if page == 1 then app.library = {} end
        local first = #app.library
        for _, track in ipairs(listed.tracks) do app.library[#app.library + 1] = track end
        local list = {}
        for index = first + 1, #app.library do list[#list + 1] = block.song("all", index, app.library) end
        if #app.library == 0 then list[1] = block.text("No songs yet.") end
        if page >= pages then pages = page end
        return list
    end })
end

-- Search -----------------------------------------------------------------------------------------------

function App:searchPage()
    return self:feed({ title = "Search", tab = "search", build = function(app)
        local list = { block.button("search", app.query ~= "" and ("Search: " .. app.query)
            or "Search songs, artists, genres", function()
                local typed = app.ui.input(app.target, "Search", { initial = app.query,
                    maxLength = 20, minLength = 0, allowSpace = true })
                if typed then app.query = app.util.trim(typed) end
                return "refresh"
            end, true) }
        if app.query ~= "" then
            list[#list + 1] = block.button("clear", "Clear", function()
                app.query = ""
                return "refresh"
            end)
            local found, err = app:ask("MUSIC_SEARCH", { query = app.query })
            if not found then return list, err end
            if #found.artists > 0 then list[#list + 1] = block.heading("Artists") end
            for _, artist in ipairs(found.artists) do list[#list + 1] = block.artist(artist) end
            if #found.genres > 0 then list[#list + 1] = block.heading("Genres") end
            for _, genre in ipairs(found.genres) do list[#list + 1] = block.genre(genre) end
            list[#list + 1] = block.heading("Songs")
            for index in ipairs(found.tracks) do
                list[#list + 1] = block.song("found", index, found.tracks)
            end
            if #found.tracks == 0 then list[#list + 1] = block.text("No songs match.") end
            return list
        end
        local genres, err = app:ask("MUSIC_GENRES")
        list[#list + 1] = block.heading("Genres")
        for _, genre in ipairs(genres and genres.genres or {}) do
            list[#list + 1] = block.genre(genre)
        end
        if genres and #genres.genres == 0 then list[#list + 1] = block.text("No genres yet.") end
        local artists = app:ask("MUSIC_ARTISTS", { per_page = 40 })
        list[#list + 1] = block.heading("Artists")
        for _, artist in ipairs(artists and artists.artists or {}) do
            list[#list + 1] = block.artist(artist)
        end
        return list, err
    end })
end

-- Me -----------------------------------------------------------------------------------------------------

function App:mePage()
    return self:feed({ title = "Me", tab = "me", build = function(app)
        local profile, err = app:ask("MUSIC_PROFILE")
        if not profile then return nil, err end
        local me, ui = profile.me or {}, app.ui
        local width = app.target.getSize()
        local list = { block.text(profile.name or "You", ui.theme.ink),
            block.text(me.music_plus and "FoxyMusic+: unlimited songs" or me.plays_limit
                and ("Free: " .. (me.plays or 0) .. " of " .. me.plays_limit .. " songs today")
                or "Every song you like", me.music_plus and app.accent or ui.theme.muted),
            block.text(profile.favorites .. " favorites, " .. profile.played .. " plays") }
        if app.env.plusPage then
            list[#list + 1] = block.button("plus", me.music_plus and "FoxyMusic+: yours"
                or "Get FoxyMusic+", function()
                    local result = app.env.plusPage(app)
                    if leaving(result) then return result end
                    return "refresh"
                end)
        end
        if profile.artist then
            list[#list + 1] = block.button("myartist", "Your Artist Profile: "
                .. profile.artist.name, function()
                    return app:artistPage(profile.artist.artist_id)
                end)
        end
        list[#list + 1] = block.heading("Your playlists")
        list[#list + 1] = block.button("newlist", "+ New playlist", function()
            local made = app:newPlaylist()
            if made then
                local result = app:playlistPage(made.playlist_id)
                if leaving(result) then return result end
            end
            return "refresh"
        end, true)
        for _, item in ipairs(block.grid("mine", profile.playlists, width)) do
            list[#list + 1] = item
        end
        if #profile.playlists == 0 then list[#list + 1] = block.text("None yet.") end
        for _, extra in ipairs(app.env.meButtons or {}) do
            list[#list + 1] = block.button(extra.id, extra.label, function()
                local result = extra.run(app)
                if leaving(result) then return result end
                return "refresh"
            end)
        end
        return list
    end })
end

-- Playlists, made and changed ------------------------------------------------------------------------------

-- Choosing a playlist's songs: every song, a page at a time, ticked or not.
-- Their order is the order they were ticked in.
function App:chooseSongs(title, chosen)
    local ui, util, target, colors = self.ui, self.util, self.target, self.colors
    chosen = util.copy(chosen or {})
    local page, query, listed, err = 1, "", nil, nil
    local function has(id)
        for index, chosenId in ipairs(chosen) do if chosenId == id then return index end end
        return nil
    end
    while self:running() do
        local width, height = target.getSize()
        local per = math.max(1, height - 6)
        if not listed then
            listed, err = self:ask("MUSIC_LIBRARY", { sort = "title", query = query, page = page,
                per_page = per })
        end
        ui.clear(target)
        ui.header(target, ui.truncate(title, width - 10), #chosen .. " songs", util.formatClock())
        local scene = ui.scene(target)
        scene:button("search", 2, 4, width - 2, 1, ui.truncate(query ~= "" and ("Search: " .. query)
            or "Search", width - 4), { background = ui.theme.panel })
        if not listed then
            ui.wrappedText(target, 2, 6, tostring(err or "The Music Server is not running"),
                width - 2, 3, ui.theme.warning)
        else
            page = listed.page
            for index, track in ipairs(listed.tracks) do
                local y = 4 + index
                local on = has(track.track_id)
                scene:hotspot("pick:" .. track.track_id, 1, y, width, 1)
                ui.text(target, 2, y, on and "x" or "-", on and self.accent or ui.theme.muted)
                ui.text(target, 4, y, ui.truncate(track.title .. " - " .. track.artist, width - 4),
                    on and ui.theme.ink or ui.theme.muted)
            end
            if #listed.tracks == 0 then ui.text(target, 2, 6, "No songs match.", ui.theme.muted) end
            if listed.pages > 1 then
                scene:button("next", 10, height, 7, 1, listed.page .. "/" .. listed.pages,
                    { background = ui.theme.panel })
            end
        end
        scene:button("cancel", 1, height, 8, 1, "< Back", { background = ui.theme.panel })
        scene:button("done", width - 5, height, 6, 1, "Done", { background = self.accent,
            foreground = colors.black })
        local action = scene:wait({ scroll = true })
        if action == "cancel" or action == "__terminate" then return nil end
        if action == "done" then return chosen end
        if action == "search" then
            query = ui.input(target, "Search songs", { initial = query, maxLength = 20,
                allowSpace = true, minLength = 0 }) or query
            page, listed = 1, nil
        elseif (action == "next" or action == "__scrolldown") and listed and listed.pages > 1 then
            page, listed = page % listed.pages + 1, nil
        elseif action == "__scrollup" and listed and page > 1 then
            page, listed = page - 1, nil
        end
        local id = action and action:match("^pick:(.+)$")
        if id then
            local at = has(id)
            if at then table.remove(chosen, at)
            elseif #chosen < 100 then chosen[#chosen + 1] = id end
        end
    end
end

-- A new playlist: its name, its cover -- drawn here -- and then its songs.
function App:newPlaylist()
    local ui, util = self.ui, self.util
    local name = ui.input(self.target, "New playlist", { hint = "Its name", maxLength = 24,
        allowSpace = true, mode = "text" })
    if not name or util.trim(name) == "" then return nil end
    local cover = ui.iconCreator(self.target, nil, name, "cover")
    local songs = self:chooseSongs(name, {})
    if not songs then return nil end
    local saved, err = self:ask("MUSIC_PLAYLIST_SAVE", { name = name, cover = cover, tracks = songs })
    if not saved then
        self:said("error", "No playlist", err, 2)
        return nil
    end
    self:said("success", saved.playlist.name, "Public, unless you make it private", 1.2)
    return saved.playlist
end

-- Changing one of yours. Returns it as it is now, or nil once it is deleted.
function App:editPlaylist(list)
    local ui, util, target, colors = self.ui, self.util, self.target, self.colors
    local width, height = target.getSize()
    ui.clear(target)
    ui.header(target, "Edit", ui.truncate(list.name, width - 3), util.formatClock())
    local scene = ui.scene(target)
    local options = { { "songs", "Songs" }, { "cover", "Cover" }, { "name", "Name" },
        { "public", list.public and "Make it private" or "Make it public" },
        { "delete", "Delete" } }
    for index, option in ipairs(options) do
        scene:button(option[1], 2, 2 + index * 2, width - 2, 1, option[2], {
            background = option[1] == "delete" and colors.red or ui.theme.panel,
            foreground = option[1] == "delete" and colors.white or ui.theme.ink })
    end
    scene:button("cancel", 1, height, 8, 1, "< Back", { background = ui.theme.panel })
    local action = scene:wait()
    local payload = { playlist_id = list.playlist_id }
    if action == "songs" then
        payload.tracks = self:chooseSongs(list.name, App.idsOf(list.tracks))
        if not payload.tracks then return list end
    elseif action == "cover" then
        payload.cover = ui.iconCreator(target, list.cover, list.name, "cover")
        if not payload.cover then return list end
    elseif action == "name" then
        payload.name = ui.input(target, "Playlist name", { initial = list.name, maxLength = 24,
            allowSpace = true, mode = "text" })
        if not payload.name or util.trim(payload.name) == "" then return list end
    elseif action == "public" then
        payload.public = not list.public
    elseif action == "delete" then
        if not ui.confirm(target, "Delete?", list.name .. " is gone for everybody.", "Delete",
            "Keep") then return list end
        local deleted, err = self:ask("MUSIC_PLAYLIST_DELETE", payload)
        if deleted then return nil end
        self:said("error", "Not deleted", err)
        return list
    else
        return list
    end
    local saved, err = self:ask("MUSIC_PLAYLIST_SAVE", payload)
    if not saved then
        self:said("error", "Not saved", err, 2)
        return list
    end
    return saved.playlist
end

-- Hearts --------------------------------------------------------------------------------------------------

function App:loved(trackId)
    if not self.favorites then
        local home = self:ask("MUSIC_HOME")
        self.favorites = home and home.favorites or {}
    end
    for _, id in ipairs(self.favorites) do if id == trackId then return true end end
    return false
end

function App:heart(track)
    local hearted, err = self:ask("MUSIC_FAVORITE", { track_id = track.track_id })
    if not hearted then
        self:said("error", "Not now", err)
        return
    end
    self.favorites = hearted.favorites
    self:said("success", hearted.favorite and "In your Favorites" or "Out again", track.title, 0.8)
end

-- The app ---------------------------------------------------------------------------------------------------

function App:run(start)
    local tab = self.pages[start or ""] and start or "music"
    while self:running() do
        local result = self.pages[tab](self)
        local nextTab = type(result) == "string" and result:match("^tab:(.+)$")
        if nextTab and self.pages[nextTab] then
            tab = nextTab
        elseif result == "home" or result == "__terminate" or result == "stop" then
            return result
        end
    end
    return "stop"
end

return musicui
