-- PUMPE APP: Music
-- PUMPE APP ICON: 66666666/66600006/66606606/66606606/60006006/60066006
-- PUMPE APP ACTION: now | Now Playing | What your Music Player is playing
-- PUMPE APP ACTION: library | Library | New Music, Popular, your playlists
-- PUMPE APP ACTION: plus | FoxyMusic+ | Unlimited songs, Offline Listening























return function(api)
local ui, util, target, colors = api.ui, api.util, api.target, api.colors
local music, cloud = api.music, api.cloud
local PINK = colors.pink
local COLORS = { red = colors.red, orange = colors.orange, yellow = colors.yellow,
lime = colors.lime, green = colors.green, cyan = colors.cyan,
lightBlue = colors.lightBlue, blue = colors.blue, purple = colors.purple,
magenta = colors.magenta, pink = colors.pink, brown = colors.brown,
white = colors.white, lightGray = colors.lightGray }
local state = { players = nil, player_id = nil, sort = "new", query = "", page = 1 }

local function running() return api.running() end
local function ask(action, payload) return music.ask(action, payload or {}) end
local function said(kind, title, body, seconds)
ui.message(target, kind, title, body or "", seconds or 1.4)
end
local function money(value) return util.money(value, api.config and api.config.currency
or "$") end
local function clock(ms)
local seconds = math.max(0, math.floor((tonumber(ms) or 0) / 1000))
return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end
local function colorOf(name) return COLORS[tostring(name or "")] or PINK end
local function bottom() return ui.contentBottom(target) end



local function refreshPlayers()
local listed, err = ask("MUSIC_PLAYERS")
if not listed then return nil, err end
state.players = listed.players
local kept
for _, player in ipairs(state.players) do
if player.player_id == state.player_id then kept = player end
end
if not kept then
for _, player in ipairs(state.players) do
if not kept or (player.online and not kept.online) then kept = player end
end
end
state.player_id = kept and kept.player_id or nil
return kept
end

local function current()
for _, player in ipairs(state.players or {}) do
if player.player_id == state.player_id then return player end
end
return nil
end

local function control(command, extra)
local payload = extra or {}
payload.command, payload.player_id = command, state.player_id
local answer, err = ask("MUSIC_CONTROL", payload)
if not answer then
said("error", "Not done", err)
return nil
end
for index, player in ipairs(state.players or {}) do
if player.player_id == answer.player.player_id then state.players[index] = answer.player end
end
return answer.player
end

local function noPlayer(y)
local width = target.getSize()
ui.wrappedText(target, 2, y, "No Music Player yet. Put a speaker beside a computer,"
.. " run Easy Deployment, choose Music Player and sign in on it.", width - 2, 6,
ui.theme.muted)
end

local function choosePlayer()
local page = 1
while running() do
refreshPlayers()
local width, height = target.getSize()
ui.clear(target)
ui.header(target, "Music Players", #(state.players or {}) .. " yours",
util.formatClock())
local scene = ui.scene(target)
local per = math.max(1, math.floor((height - 6) / 3))
local items, actual, pages = util.page(state.players or {}, page, per)
page = actual
for index, player in ipairs(items) do
local y = 1 + index * 3
local on = player.player_id == state.player_id
scene:button("player:" .. player.player_id, 2, y, width - 2, 2, "", {
background = on and PINK or ui.theme.panel })
local ink, back = on and colors.black or ui.theme.ink, on and PINK or ui.theme.panel
ui.text(target, 3, y, ui.truncate(player.label, width - 4), ink, back)
ui.text(target, 3, y + 1, ui.truncate(player.online and (player.now
and player.now.title or "Ready") or "Off", width - 4),
on and colors.black or ui.theme.muted, back)
end
if #(state.players or {}) == 0 then noPlayer(5) end
scene:button("back", 1, height, 8, 1, "< Back", { background = ui.theme.panel })
if pages > 1 then
scene:button("more", width - 6, height, 6, 1, page .. "/" .. pages,
{ background = ui.theme.panel })
end
local action = scene:wait()
if action == "back" or action == "__terminate" then return end
if action == "more" then page = page % pages + 1 end
local id = action and action:match("^player:(.+)$")
if id then
state.player_id = id
return
end
end
end


local function callIn(radio)
local price = api.config and api.config.phone_call_price or 50
if not ui.confirm(target, "Call " .. radio.name, "A call is " .. money(price)
.. ". Every call is one more entry. Calling " .. radio.giveaway.number .. ".",
"Call", "Back") then
return
end
local placed, err = api.request("PHONE_CALL", { number = radio.giveaway.number }, true)
if placed then
said("success", "You're in!", placed.entries .. " entr" .. (placed.entries == 1
and "y" or "ies") .. " to win. " .. money(placed.price) .. " paid", 2)
api.refresh()
else
said("error", "No call", err, 2)
end
end

local function has(list, value)
for _, item in ipairs(list or {}) do if item == value then return true end end
return false
end





local function nowPage(tabs)
refreshPlayers()
if not state.favorites then
local home = ask("MUSIC_HOME")
state.favorites = home and home.favorites or nil
end
local ticks = 0
while running() do
ticks = ticks + 1
if ticks % 2 == 0 then refreshPlayers() end
local width = target.getSize()
local player = current()
ui.clear(target)
ui.header(target, "Now Playing", ui.truncate(player and (player.online
and "On " .. player.label or player.label .. " is off") or "Music", width - 3),
util.formatClock())
local scene = ui.scene(target)
local song
if not player then
noPlayer(5)
else
scene:button("players", 2, 4, width - 2, 1, ui.truncate(player.label .. "  v",
width - 4), { background = ui.theme.panel })
local now, radio = player.now, player.radio
if radio then
local band = colorOf(radio.color)
ui.fill(target, 2, 5, width - 2, 1, band)
ui.text(target, 3, 5, ui.truncate(radio.name .. "  LIVE", width - 4),
ui.inkOn(band), band)
end
local right = 2 + ui.COVER_WIDTH + 1
local room = width - right
if now then
ui.cover(target, 2, 6, now.cover or (radio and radio.cover))
local y = 6
if now.label then
ui.text(target, right, y, ui.truncate(now.label, room), colors.yellow)
y = y + 1
end
ui.text(target, right, y, ui.truncate(now.title, room), ui.theme.ink)
ui.text(target, right, y + 1, ui.truncate(now.artist or "", room),
ui.theme.muted)
if now.kind == "song" and now.track_id and not radio then song = now end
if song and y + 2 <= 9 then
local loved = state.favorites and has(state.favorites,
song.track_id)
scene:button("heart", right, 9, math.min(room, 8), 1,
loved and "<3 Yes" or "<3", { background = loved and PINK
or ui.theme.panel, foreground = loved and colors.black or PINK })
end
local position = math.min(now.length_ms or 0, now.position_ms or 0)
ui.progress(target, 2, 11, width - 2, position,
math.max(1, now.length_ms or 1), radio and colorOf(radio.color) or PINK,
ui.theme.panel)
ui.text(target, 2, 12, clock(position), ui.theme.muted)
local total = clock(now.length_ms)
ui.text(target, width - #total, 12, total, ui.theme.muted)
else
ui.cover(target, 2, 6, radio and radio.cover)
ui.wrappedText(target, right, 6, player.notice or (player.paused and "Paused")
or "Nothing playing. Pick a song in Library.", room, 4,
player.notice and ui.theme.warning or ui.theme.muted)
end
if radio and radio.giveaway then
ui.fill(target, 2, 13, width - 2, 2, colors.yellow)
ui.text(target, 3, 13, "GIVEAWAY! Call", colors.black, colors.yellow)
ui.text(target, 3, 14, radio.giveaway.number .. "  "
.. clock(radio.giveaway.closes_in_ms), colors.black, colors.yellow)
scene:button("callin", width - 7, 13, 7, 2, "Call", {
background = colors.black, foreground = colors.yellow })
elseif radio and radio.winner and radio.winner.name then
ui.center(target, 14, ui.truncate(radio.winner.name .. " won "
.. money(radio.winner.prize), width - 2), colors.yellow)
elseif radio and radio.special then
ui.center(target, 14, ui.truncate(radio.special, width - 2), PINK)
elseif player.plays_left then
ui.center(target, 14, ui.truncate(player.plays_left .. " songs left today",
width - 2), ui.theme.muted)
end
local live = player.mode == "radio" or player.mode == "station"
local idle = player.mode == "idle"
local buttons = {
{ "previous", "|<", live or idle },
{ player.paused and "resume" or "pause", player.paused and ">" or "||", idle },
{ "next", ">|", live or idle },
{ "quieter", "-", false }, { "louder", "+", false },
}
local each = math.floor((width - 1) / #buttons)
for index, button in ipairs(buttons) do
scene:button(button[1], 2 + (index - 1) * each, bottom() - 1, each - 1, 2,
button[2], { background = index == 2 and PINK or ui.theme.panel,
foreground = index == 2 and colors.black or ui.theme.ink,
disabled = button[3] or not player.online })
end
end
ui.tabBar(scene, target, tabs.list, tabs.active, tabs.color)
local action = scene:wait({ tickRate = 1 })
if action == "home" or action == "__terminate"
or (action or ""):match("^tab:") then
return action
end
if action == "players" then
choosePlayer()
elseif action == "heart" and song then
local hearted, err = ask("MUSIC_FAVORITE", { track_id = song.track_id })
if hearted then
state.favorites = hearted.favorites
said("success", hearted.favorite and "In Your Favorites" or "Out again",
song.title, 0.8)
else
said("error", "Not now", err)
end
elseif action == "callin" and player and player.radio and player.radio.giveaway then
callIn(player.radio)
elseif action == "quieter" or action == "louder" then
local volume = (tonumber(player.volume) or 2) + (action == "louder" and 0.5 or -0.5)
control("volume", { volume = math.max(0, math.min(3, volume)) })
elseif action and not action:match("^__") then
control(action)
end
end
end


local function playFrom(trackId, queue, playlistId)
if not current() then
said("error", "No Music Player", "Set one up first: a computer with a speaker", 2)
return false
end
return control("play", { track_id = trackId, queue = queue, playlist_id = playlistId })
~= nil
end



local function searchPage()
local listed, err
while running() do
local width, height = target.getSize()
local per = math.max(1, height - 7)
if not listed then
listed, err = ask("MUSIC_LIBRARY", { sort = state.sort, query = state.query,
page = state.page, per_page = per })
end
ui.clear(target)
ui.header(target, "Every song", listed and (listed.total .. " songs")
or "Not answering", util.formatClock())
local scene = ui.scene(target)
local sorts = { { "new", "New" }, { "title", "A-Z" }, { "popular", "Top" } }
for index, sort in ipairs(sorts) do
local on = state.sort == sort[1]
scene:button("sort:" .. sort[1], 2 + (index - 1) * 5, 4, 5, 1, sort[2], {
background = on and PINK or ui.theme.panel,
foreground = on and colors.black or ui.theme.ink })
end
scene:button("search", 18, 4, width - 17, 1, state.query ~= "" and
ui.truncate(state.query, width - 19) or "Search", { background = ui.theme.panel })
if not listed then
ui.wrappedText(target, 2, 7, tostring(err or "The Music Server is not running"),
width - 2, 3, ui.theme.warning)
else
for index, track in ipairs(listed.tracks) do
local y = 5 + index
local length = clock(track.length_ms)
ui.text(target, 2, y, ui.truncate(track.title .. " - " .. track.artist,
width - #length - 5), ui.theme.ink)
ui.text(target, width - #length - 2, y, length, ui.theme.muted)
scene:hotspot("play:" .. track.track_id, 1, y, width - 2, 1)
scene:button("add:" .. track.track_id, width, y, 1, 1, "+",
{ background = ui.theme.panel })
end
if #listed.tracks == 0 then
ui.wrappedText(target, 2, 7, state.query ~= "" and "No songs match."
or "No songs yet. Upload the first, in Music for Artists!", width - 2, 3,
ui.theme.muted)
end
if listed.pages > 1 then
scene:button("prev", 10, height, 3, 1, "<", { background = ui.theme.panel })
ui.text(target, 14, height, listed.page .. "/" .. listed.pages, ui.theme.muted)
scene:button("next", width - 2, height, 3, 1, ">",
{ background = ui.theme.panel })
end
end
scene:button("back", 1, height, 8, 1, "< Back", { background = ui.theme.panel })
local action = scene:wait()
if action == "back" or action == "__terminate" then return action end
local sort = action and action:match("^sort:(.+)$")
local playId = action and action:match("^play:(.+)$")
local addId = action and action:match("^add:(.+)$")
if sort then
state.sort, state.page, listed = sort, 1, nil
elseif action == "search" then
state.query = ui.input(target, "Search songs", { initial = state.query,
maxLength = 20, allowSpace = true, minLength = 0 }) or state.query
state.page, listed = 1, nil
elseif action == "prev" or action == "next" then
state.page = state.page + (action == "next" and 1 or -1)
listed = nil
elseif playId then
local queue = {}
for _, track in ipairs(listed.tracks) do queue[#queue + 1] = track.track_id end
if playFrom(playId, queue) then return "now" end
elseif addId and not current() then
said("error", "No Music Player", "Set one up first: a computer with a speaker", 2)
elseif addId then
if control("add", { track_id = addId }) then
said("success", "Queued", "On " .. current().label)
end
end
end
end





local function chooseSongs(title, chosen)
chosen = util.copy(chosen or {})
local page, query, listed, err = 1, "", nil, nil
while running() do
local width, height = target.getSize()
local per = math.max(1, height - 6)
if not listed then
listed, err = ask("MUSIC_LIBRARY", { sort = "title", query = query, page = page,
per_page = per })
end
ui.clear(target)
ui.header(target, ui.truncate(title, width - 10), #chosen .. " songs",
util.formatClock())
local scene = ui.scene(target)
scene:button("search", 2, 4, width - 2, 1, query ~= "" and ("Search: " .. query)
or "Search", { background = ui.theme.panel })
if not listed then
ui.wrappedText(target, 2, 6, tostring(err or "The Music Server is not running"),
width - 2, 3, ui.theme.warning)
else
page = listed.page
for index, track in ipairs(listed.tracks) do
local y = 4 + index
local on = has(chosen, track.track_id)
scene:hotspot("pick:" .. track.track_id, 1, y, width, 1)
ui.text(target, 2, y, on and "x" or "-", on and PINK or ui.theme.muted)
ui.text(target, 4, y, ui.truncate(track.title .. " - " .. track.artist,
width - 4), on and ui.theme.ink or ui.theme.muted)
end
if #listed.tracks == 0 then
ui.text(target, 2, 6, "No songs match.", ui.theme.muted)
end
if listed.pages > 1 then
scene:button("next", 10, height, 5, 1, listed.page .. "/" .. listed.pages,
{ background = ui.theme.panel })
end
end
scene:button("back", 1, height, 8, 1, "< Back", { background = ui.theme.panel })
scene:button("done", width - 5, height, 6, 1, "Done", { background = PINK,
foreground = colors.black })
local action = scene:wait()
if action == "back" or action == "__terminate" then return nil end
if action == "done" then return chosen end
if action == "search" then
query = ui.input(target, "Search songs", { initial = query, maxLength = 20,
allowSpace = true, minLength = 0 }) or query
page, listed = 1, nil
elseif action == "next" then
page, listed = page % listed.pages + 1, nil
end
local id = action and action:match("^pick:(.+)$")
if id then
local at
for index, chosenId in ipairs(chosen) do if chosenId == id then at = index end end
if at then table.remove(chosen, at)
elseif #chosen < 100 then chosen[#chosen + 1] = id end
end
end
end

local function idsOf(tracks)
local ids = {}
for _, track in ipairs(tracks or {}) do ids[#ids + 1] = track.track_id end
return ids
end


local function newPlaylist()
local name = ui.input(target, "New playlist", { hint = "Its name", maxLength = 24,
allowSpace = true, mode = "text" })
if not name or util.trim(name) == "" then return nil end
local cover = ui.iconCreator(target, nil, name, "cover")
local songs = chooseSongs(name, {})
if not songs then return nil end
local saved, err = ask("MUSIC_PLAYLIST_SAVE", { name = name, cover = cover,
tracks = songs })
if not saved then
said("error", "No playlist", err, 2)
return nil
end
said("success", saved.playlist.name, "Public: on the Playlists row", 1.2)
return saved.playlist
end


local function editPlaylist(list)
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
scene:button("back", 1, height, 8, 1, "< Back", { background = ui.theme.panel })
local action = scene:wait()
local payload = { playlist_id = list.playlist_id }
if action == "songs" then
payload.tracks = chooseSongs(list.name, idsOf(list.tracks))
if not payload.tracks then return list end
elseif action == "cover" then
payload.cover = ui.iconCreator(target, list.cover, list.name, "cover")
if not payload.cover then return list end
elseif action == "name" then
payload.name = ui.input(target, "Playlist name", { initial = list.name,
maxLength = 24, allowSpace = true, mode = "text" })
if not payload.name or util.trim(payload.name) == "" then return list end
elseif action == "public" then
payload.public = not list.public
elseif action == "delete" then
if not ui.confirm(target, "Delete?", list.name .. " is gone for everybody.",
"Delete", "Keep") then return list end
local deleted, err = ask("MUSIC_PLAYLIST_DELETE", payload)
if deleted then return nil end
said("error", "Not deleted", err)
return list
else
return list
end
local saved, err = ask("MUSIC_PLAYLIST_SAVE", payload)
if not saved then
said("error", "Not saved", err, 2)
return list
end
return saved.playlist
end


local function playlistPage(id)
local opened, err = ask("MUSIC_PLAYLIST", { playlist_id = id })
if not opened then
said("error", "Playlist", err)
return nil
end
local list, scroll = opened.playlist, 0
while running() do
local width, height = target.getSize()
ui.clear(target)
ui.header(target, "Playlist", ui.truncate(list.owner_name or "", width - 3),
util.formatClock())
local scene = ui.scene(target)
ui.cover(target, 2, 4, list.cover)
local right = 2 + ui.COVER_WIDTH + 1
ui.text(target, right, 4, ui.truncate(list.name, width - right), ui.theme.ink)
ui.text(target, right, 5, ui.truncate(list.songs_count .. " songs", width - right),
ui.theme.muted)
ui.text(target, right, 6, ui.truncate(list.plays .. " plays", width - right),
ui.theme.muted)
ui.text(target, right, 7, list.public and "Public" or "Private", ui.theme.muted)
scene:button("play", 2, 9, width - 2, 1, "> Play",
{ background = PINK, foreground = colors.black, disabled = #list.tracks == 0 })
local top, room = 11, height - 11
scroll = math.max(0, math.min(scroll, #list.tracks - room))
for index = 1, math.min(room, #list.tracks - scroll) do
local track = list.tracks[scroll + index]
local y = top + index - 1
ui.text(target, 2, y, ui.truncate(track.title .. " - " .. track.artist,
width - 4), ui.theme.ink)
scene:hotspot("song:" .. (scroll + index), 1, y, width - 3, 1)
end
if #list.tracks == 0 then ui.text(target, 2, top, "No songs yet", ui.theme.muted) end
if scroll > 0 then
scene:button("up", width - 1, top, 2, 1, "^", { background = ui.theme.panel })
end
if scroll + room < #list.tracks then
scene:button("down", width - 1, top + room - 1, 2, 1, "v",
{ background = ui.theme.panel })
end
scene:button("back", 1, height, 8, 1, "< Back", { background = ui.theme.panel })
if list.mine then
scene:button("edit", width - 5, height, 6, 1, "Edit",
{ background = ui.theme.panel })
end
local action = scene:wait({ scroll = true })
if action == "back" or action == "__terminate" then return action end
if action == "up" or action == "__scrollup" then scroll = scroll - 1 end
if action == "down" or action == "__scrolldown" then scroll = scroll + 1 end
local at = tonumber(action and action:match("^song:(%d+)$"))
if (action == "play" or at) and #list.tracks > 0 then
local queue = idsOf(list.tracks)
if playFrom(queue[at or 1], queue, list.playlist_id) then return "now" end
elseif action == "edit" then
list = editPlaylist(list)
if not list then return "back" end
end
end
end






local TILE_GAP, ROW_HEIGHT = 2, 7
local EMPTY = { new = "No songs yet", popular = "Nothing played yet",
favorites = "Tap <3 on Now Playing", radio = "No radio hits yet",
recent = "Play something!", playlists = "Make one with +" }

local function libraryPage(tabs)
local home, err
state.offsets = state.offsets or {}
state.scroll = state.scroll or 0
while running() do
if not home then
home, err = ask("MUSIC_HOME")
if home then state.favorites = home.favorites end
if not state.players then refreshPlayers() end
end
local width = target.getSize()
ui.clear(target)
ui.header(target, "Library", home and "Swipe the rows with < >" or "Not answering",
util.formatClock())
local scene = ui.scene(target)
scene:button("new", 2, 4, 3, 1, "+", { background = PINK, foreground = colors.black })
scene:button("search", 6, 4, width - 12, 1, "Search", { background = ui.theme.panel })
local rows = home and home.rows or {}
local fit = math.max(1, math.floor((bottom() - 4) / ROW_HEIGHT))
state.scroll = math.max(0, math.min(state.scroll, #rows - fit))
scene:button("pageup", width - 4, 4, 2, 1, "^", { background = ui.theme.panel,
disabled = state.scroll == 0 })
scene:button("pagedown", width - 1, 4, 2, 1, "v", { background = ui.theme.panel,
disabled = state.scroll + fit >= #rows })
if not home then
ui.wrappedText(target, 2, 6, tostring(err or "The Music Server is not running"),
width - 2, 3, ui.theme.warning)
end
local across = math.max(1, math.floor((width - 4 + TILE_GAP)
/ (ui.COVER_WIDTH + TILE_GAP)))
local left = 3 + math.floor((width - 4 - (across * (ui.COVER_WIDTH + TILE_GAP)
- TILE_GAP)) / 2)
for shown = 1, math.min(fit, #rows - state.scroll) do
local row = rows[state.scroll + shown]
local items = row.playlists or row.tracks or {}
local y = 5 + (shown - 1) * ROW_HEIGHT
ui.text(target, 2, y + 1, ui.truncate(row.title:upper(), width - 2), PINK)
local offset = math.max(0, math.min(state.offsets[row.id] or 0, #items - across))
state.offsets[row.id] = offset
for index = 1, math.min(across, #items - offset) do
local item = items[offset + index]
local x = left + (index - 1) * (ui.COVER_WIDTH + TILE_GAP)
ui.cover(target, x, y + 2, item.cover)
ui.text(target, x, y + 2 + ui.COVER_HEIGHT, ui.truncate(item.title
or item.name, ui.COVER_WIDTH), ui.theme.ink)
scene:hotspot((row.playlists and "list:" or "song:" .. row.id .. ":")
.. (row.playlists and item.playlist_id or (offset + index)), x, y + 2,
ui.COVER_WIDTH, ui.COVER_HEIGHT + 1)
end
if #items == 0 then
ui.text(target, 3, y + 3, ui.truncate(EMPTY[row.id] or "Nothing yet",
width - 4), ui.theme.muted)
end
if offset > 0 then
scene:button("left:" .. row.id, 1, y + 3, 1, 2, "<",
{ background = ui.theme.panel })
end
if offset + across < #items then
scene:button("right:" .. row.id, width, y + 3, 1, 2, ">",
{ background = ui.theme.panel })
end
end
ui.tabBar(scene, target, tabs.list, tabs.active, tabs.color)
local action = scene:wait({ scroll = true })
if action == "home" or action == "__terminate"
or (action or ""):match("^tab:") then
return action
end
local turn, turned = (action or ""):match("^(%a+):(.+)$")
if action == "pageup" or action == "__scrollup" then
state.scroll = state.scroll - 1
elseif action == "pagedown" or action == "__scrolldown" then
state.scroll = state.scroll + 1
elseif turn == "left" or turn == "right" then
state.offsets[turned] = (state.offsets[turned] or 0)
+ (turn == "right" and across or -across)
elseif action == "search" then
if searchPage() == "now" then return "tab:now" end
home = nil
elseif action == "new" then
local made = newPlaylist()
home = nil
if made and playlistPage(made.playlist_id) == "now" then return "tab:now" end
elseif turn == "list" then
local went = playlistPage(turned)
home = nil
if went == "now" then return "tab:now" end
elseif turn == "song" then
local rowId, at = turned:match("^(.+):(%d+)$")
for _, row in ipairs(rows) do
if row.id == rowId and row.tracks and row.tracks[tonumber(at)] then
if playFrom(row.tracks[tonumber(at)].track_id, idsOf(row.tracks)) then
return "tab:now"
end
end
end
end
end
end




local function plusPage(tabs)
local plan, err = api.request("MUSIC_PLUS_PLAN", {}, true)
while running() do
local width = target.getSize()
local height = bottom() + 1
local plus = plan and plan.plan == "plus"
ui.clear(target)
ui.header(target, "FoxyMusic+", plus and (plan.ends_day and "Until day "
.. plan.ends_day or "Yours") or "Music, unlimited", util.formatClock())
local scene = ui.scene(target)
if not plan then
ui.wrappedText(target, 2, 5, tostring(err or "The Bank is not answering."),
width - 2, 3, ui.theme.warning)
else
ui.fill(target, 2, 4, width - 2, 1, PINK)
ui.text(target, 3, 4, ui.truncate(money(plan.price) .. " "
.. util.everyText(plan.every_days), width - 4), colors.black, PINK)
ui.text(target, 2, 5, ui.truncate(plus and (plan.ends_day
and ("Cancelled. Ends day " .. plan.ends_day)
or ("Next charge day " .. tostring(plan.next_charge_day)))
or "Cancel any time", width - 2), ui.theme.muted)
local y, last = 7, height - 5
for _, perk in ipairs(plan.perks or {}) do
if y > last then break end
ui.text(target, 2, y, "+", PINK)
y = y + ui.wrappedText(target, 4, y, perk, width - 4, last - y + 1,
ui.theme.ink)
end
if plan.cloud_plus and y <= last then
ui.wrappedText(target, 2, y + 1, "FoxyCloud+ already makes songs and uploads"
.. " unlimited. This adds Offline Listening.", width - 2, last - y,
ui.theme.muted)
elseif not plus and y <= last then
ui.wrappedText(target, 2, y + 1, "Free: " .. table.concat(plan.free_perks
or {}, ", "), width - 2, last - y, ui.theme.muted)
end
local id = not plus and "join" or plan.ends_day and "keep" or "cancel"
scene:button(id, 2, height - 3, width - 2, 2, id == "join" and ("Join for "
.. money(plan.price)) or id == "keep" and "Keep FoxyMusic+"
or "Cancel FoxyMusic+", { background = id == "cancel" and ui.theme.panel
or PINK, foreground = id == "cancel" and ui.theme.ink or colors.black })
end
ui.tabBar(scene, target, tabs.list, tabs.active, tabs.color)
local action = scene:wait()
if action == "home" or action == "__terminate"
or (action or ""):match("^tab:") then
return action
end
if action == "join" or action == "keep" then
local pin = (action == "keep" or ui.confirm(target, "FoxyMusic+", money(plan.price)
.. " now, then " .. util.everyText(plan.every_days) .. " until you cancel.",
"OK", "Not now")) and ui.pin(target, "Confirm with PIN", true)
if pin then
local joined, joinError = api.request("MUSIC_PLUS_JOIN", { pin = pin }, true)
if joined then
plan = joined
api.refresh()
said("success", "FoxyMusic+", action == "keep" and "Keeping it"
or "Unlimited songs are yours", 1.6)
else
said("error", "Not joined", joinError, 2)
end
end
elseif action == "cancel" then
if ui.confirm(target, "Cancel?", "FoxyMusic+ stays until day "
.. tostring(plan.next_charge_day) .. ". Songs kept for Offline Listening"
.. " go then.", "Cancel", "Keep") then
local cancelled, cancelError = api.request("MUSIC_PLUS_CANCEL", {}, true)
if cancelled then plan = cancelled
else said("error", "Not cancelled", cancelError) end
end
end
end
end




if not music then
said("error", "Music", "This Pocket needs the FoxyOS 17 update", 2)
return
end
local wanted = type(api.action) == "function" and api.action() or nil
ui.runTabs({
target = target,
list = { { id = "now", label = "Now" }, { id = "library", label = "Library",
short = "Songs" }, { id = "plus", label = "Plus", short = "+" } },
color = PINK,
start = (wanted == "library" or wanted == "plus") and wanted or "now",
pages = { now = nowPage, library = libraryPage, plus = plusPage },
running = running,
})
end
