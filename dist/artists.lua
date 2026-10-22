-- PUMPE APP: Music for Artists
-- PUMPE APP ICON: 66666666/66f66f66/6f0ff0f6/6ff00ff6/66ffff66/66666666
-- PUMPE APP ACTION: profile | Your Artist Profile | Your songs and listeners
-- PUMPE APP ACTION: upload | Upload a song | With a cover, credited
-- PUMPE APP ACTION: artists | Artists | Every artist in the Music Library














return function(api)
local ui, util, target, colors = api.ui, api.util, api.target, api.colors
local music, cloud = api.music, api.cloud
local PINK = colors.pink
local state = { query = "" }

local function running() return api.running() end
local function ask(action, payload) return music.ask(action, payload or {}) end
local function said(kind, title, body, seconds)
ui.message(target, kind, title, body or "", seconds or 1.4)
end
local function bottom() return ui.contentBottom(target) end



local function profileView(artist, own)
local scroll = 0
while running() do
local width, height = target.getSize()
ui.clear(target)
ui.header(target, "Artist", ui.truncate(artist.name, width - 3), util.formatClock())
local scene = ui.scene(target)
ui.cover(target, 2, 4, artist.cover)
local right = 2 + ui.COVER_WIDTH + 1
ui.text(target, right, 4, ui.truncate(artist.name, width - right), ui.theme.ink)
ui.text(target, right, 5, ui.truncate(artist.listeners_today .. " today", width - right),
PINK)
ui.text(target, right, 6, ui.truncate((artist.songs_count or 0) .. " songs",
width - right), ui.theme.muted)
ui.text(target, right, 7, ui.truncate((artist.plays or 0) .. " plays", width - right),
ui.theme.muted)
ui.text(target, 2, 9, ui.truncate(artist.claimed and "Their own profile"
or "From credits: nobody's yet", width - 2), ui.theme.muted)
local lines = {}
if artist.bio and artist.bio ~= "" then
for _, line in ipairs(ui.wrap(artist.bio, width - 2)) do
lines[#lines + 1] = { line, ui.theme.ink }
end
end
lines[#lines + 1] = { "SONGS", ui.theme.muted }
for _, song in ipairs(artist.songs or {}) do
lines[#lines + 1] = { song.title .. "  " .. (song.plays + (song.radio_plays or 0))
.. " plays", ui.theme.ink }
end
if #(artist.songs or {}) == 0 then lines[#lines + 1] = { "None yet", ui.theme.muted } end
lines[#lines + 1] = { "ON THE RADIO", ui.theme.muted }
for _, radio in ipairs(artist.radios or {}) do
lines[#lines + 1] = { radio.name .. (radio.frequency and ("  " .. string.format(
"%d.%d", math.floor(radio.frequency / 10), radio.frequency % 10)) or ""),
ui.theme.ink }
end
if #(artist.radios or {}) == 0 then lines[#lines + 1] = { "Not yet", ui.theme.muted } end
local top, room = 11, height - 12
scroll = math.max(0, math.min(scroll, #lines - room))
for index = 1, math.min(room, #lines - scroll) do
local line = lines[scroll + index]
ui.text(target, 2, top + index - 1, ui.truncate(line[1], width - 5), line[2])
end
if scroll > 0 then
scene:button("up", width - 2, top, 3, 1, "^", { background = ui.theme.panel })
end
if scroll + room < #lines then
scene:button("down", width - 2, top + room - 1, 3, 1, "v",
{ background = ui.theme.panel })
end
scene:button("back", 1, height, 8, 1, "< Back", { background = ui.theme.panel })
if own then
scene:button("edit", width - 13, height, 6, 1, "Edit", { background = ui.theme.panel })
scene:button("cover", width - 6, height, 7, 1, "Cover", { background = PINK,
foreground = colors.black })
end
local action = scene:wait({ scroll = true })
if action == "back" or action == "__terminate" then return action end
if action == "up" or action == "__scrollup" then scroll = scroll - 3 end
if action == "down" or action == "__scrolldown" then scroll = scroll + 3 end
if action == "edit" or action == "cover" then return action end
end
end


local function editProfile(artist, part)
local payload = {}
if not artist or part == "edit" then
payload.name = ui.input(target, "Artist name", { initial = artist and artist.name,
hint = "As your songs credit you", maxLength = 20, minLength = 2,
allowSpace = true, mode = "text" })
if not payload.name then return nil end
payload.bio = ui.input(target, "About you", { initial = artist and artist.bio or "",
hint = "One line", maxLength = 120, minLength = 0, allowSpace = true,
mode = "text" })
if not payload.bio then return nil end
end
if not artist or part == "cover" then
payload.cover = ui.iconCreator(target, artist and artist.cover,
payload.name or artist.name, "cover")
if not payload.cover and part == "cover" then return nil end
end
local saved, err = ask("MUSIC_ARTIST_SAVE", payload)
if not saved then
said("error", "Not saved", err, 2)
return nil
end
said("success", saved.artist.name, "Your Artist Profile", 1)
return saved.artist
end



local function profilePage(tabs)
while running() do
local mine, err = ask("MUSIC_MY_ARTIST")
local width = target.getSize()
ui.clear(target)
ui.header(target, "Music for Artists", "Your profile", util.formatClock())
local scene = ui.scene(target)
if not mine then
ui.wrappedText(target, 2, 5, tostring(err or "The Music Server is not running"),
width - 2, 3, ui.theme.warning)
elseif not mine.artist then
ui.wrappedText(target, 2, 5, "No Artist Profile yet. Make yours: a name, a line"
.. " about you and a cover. If an upload already credited your name, its"
.. " songs come with it.", width - 2, 6, ui.theme.muted)
scene:button("create", 2, 12, width - 2, 2, "Create your profile",
{ background = PINK, foreground = colors.black })
else
local artist = mine.artist
ui.cover(target, 2, 4, artist.cover)
local right = 2 + ui.COVER_WIDTH + 1
ui.text(target, right, 4, ui.truncate(artist.name, width - right), ui.theme.ink)
ui.text(target, right, 5, ui.truncate(artist.listeners_today .. " today",
width - right), PINK)
ui.text(target, right, 6, ui.truncate(artist.songs_count .. " songs",
width - right), ui.theme.muted)
ui.text(target, right, 7, ui.truncate(artist.plays .. " plays", width - right),
ui.theme.muted)
ui.text(target, 2, 9, ui.truncate("Listeners today, and " .. #artist.radios
.. " radios play you", width - 2), ui.theme.muted)
scene:button("open", 2, 11, width - 2, 2, "Your profile in full",
{ background = PINK, foreground = colors.black })
end
ui.tabBar(scene, target, tabs.list, tabs.active, tabs.color)
local action = scene:wait({ tickRate = 10 })
if action == "home" or action == "__terminate" or (action or ""):match("^tab:") then
return action
end
if action == "create" then
editProfile(nil)
elseif action == "open" and mine and mine.artist then
local artist = mine.artist
while running() do
local next = profileView(artist, true)
if next ~= "edit" and next ~= "cover" then break end
artist = editProfile(artist, next) or artist
end
end
end
end



local function isSong(name) return tostring(name or ""):lower():match("%.dfpwm$") ~= nil end

local function titleFrom(name)
local base = tostring(name or ""):match("([^/\\]+)$") or ""
return util.trim((base:gsub("%.[Dd][Ff][Pp][Ww][Mm]$", ""):gsub("_+", " "))):sub(1, 28)
end

local function upload(name, body)
local title = ui.input(target, "Song title", { initial = titleFrom(name), maxLength = 28,
allowSpace = true, mode = "text" })
if not title or util.trim(title) == "" then return end
local mine = ask("MUSIC_MY_ARTIST")
local artist = ui.input(target, "Artists", { initial = mine and mine.artist
and mine.artist.name or "", hint = "Ana, Kit & Noa: a profile each", maxLength = 40,
allowSpace = true, mode = "text" })
if not artist or util.trim(artist) == "" then return end
local cover
if ui.confirm(target, "A cover?", "Draw one now, or leave it for later.", "Draw it",
"Later") then
cover = ui.iconCreator(target, nil, title, "cover")
end
local began, err = ask("MUSIC_UPLOAD_BEGIN", { title = title, artist = artist,
size = #body, cover = cover })
if not began then
said("error", "Not uploaded", err, 2)
return
end
local width = target.getSize()
ui.clear(target)
ui.header(target, "Uploading", ui.truncate(title, width - 3), util.formatClock())
local ok, putError = music.upload(began.plan, body, function(done, total)
ui.progress(target, 2, 8, width - 2, done, total, PINK, ui.theme.panel)
ui.center(target, 10, done .. " of " .. total, ui.theme.muted)
end)
if not ok then
said("error", "Not uploaded", putError, 2)
return
end
local done, doneError = ask("MUSIC_UPLOAD_DONE", { upload_id = began.upload_id })
if done then
said("success", "In the Music Library", done.track.title .. ", by " .. done.track.artist,
1.8)
else
said("error", "Not uploaded", doneError, 2)
end
end

local function pick(title, names, empty)
local page = 1
while running() do
local width, height = target.getSize()
ui.clear(target)
ui.header(target, title, #names .. " to choose from", util.formatClock())
local scene = ui.scene(target)
local per = math.max(1, math.floor((height - 6) / 2))
local items, actual, pages = util.page(names, page, per)
page = actual
for index, name in ipairs(items) do
scene:button("pick:" .. ((page - 1) * per + index), 2, 2 + index * 2, width - 2,
1, ui.truncate(name, width - 4), { background = ui.theme.panel })
end
if #names == 0 then ui.wrappedText(target, 2, 5, empty, width - 2, 2, ui.theme.muted) end
scene:button("back", 1, height, 8, 1, "< Back", { background = ui.theme.panel })
if pages > 1 then
scene:button("more", width - 6, height, 6, 1, page .. "/" .. pages,
{ background = ui.theme.panel })
end
local action = scene:wait()
if action == "back" or action == "__terminate" then return nil end
if action == "more" then page = page % pages + 1 end
local index = tonumber(action and action:match("^pick:(%d+)$"))
if index then return index end
end
end

local function fromPocket()
local names = {}
for _, name in ipairs(cloud and cloud.pocketFiles() or {}) do
if isSong(name) then names[#names + 1] = name end
end
local index = pick("From this Pocket", names, "No .dfpwm songs here.")
if not index then return end
local body, err = cloud.readPocket(names[index])
if body then upload(names[index], body) else said("error", "Cannot read it", err) end
end

local function fromCloud()
local listed, err = api.request("CLOUD_FILES", {}, true)
if not listed then
said("error", "FoxyCloud", err, 2)
return
end
local songs, names = {}, {}
for _, file in ipairs(listed.files or {}) do
if file.kind == "audio" or isSong(file.name) then
songs[#songs + 1] = file
names[#names + 1] = file.name
end
end
local index = pick("From FoxyCloud", names, "No .dfpwm songs in your FoxyCloud.")
if not index then return end
local body, loadError = cloud.load(songs[index].file_id)
if body then upload(songs[index].name, body) else said("error", "Cannot open it", loadError) end
end


local function uploads()
local mine = ask("MUSIC_MY_ARTIST")
local list = mine and mine.uploads or {}
local names = {}
for _, track in ipairs(list) do names[#names + 1] = track.title .. " - " .. track.artist end
local index = pick("Your uploads", names, "Nothing uploaded yet.")
if not index then return end
local cover = ui.iconCreator(target, list[index].cover, list[index].title, "cover")
if not cover then return end
local edited, err = ask("MUSIC_TRACK_EDIT", { track_id = list[index].track_id, cover = cover })
if edited then said("success", "New cover", edited.track.title, 1) else said("error", "No", err) end
end

local function uploadPage(tabs)
local me
while running() do
local width = target.getSize()
me = me or ask("MUSIC_ME")
ui.clear(target)
ui.header(target, "Upload a song", "With a cover, credited", util.formatClock())
local scene = ui.scene(target)
ui.wrappedText(target, 2, 4, "Songs are DFPWM1a (.dfpwm). Drop one on this screen,"
.. " or pick one:", width - 2, 3, ui.theme.ink)
scene:button("pocket", 2, 7, width - 2, 2, "From this Pocket", {
background = PINK, foreground = colors.black })
scene:button("cloud", 2, 10, width - 2, 2, "From FoxyCloud", {
background = colors.lightBlue, foreground = colors.black })
scene:button("mine", 2, 13, width - 2, 1, "Your uploads, covers", {
background = ui.theme.panel })
if me then
ui.wrappedText(target, 2, 15, me.uploads_limit and ("Today: " .. me.uploads .. " of "
.. me.uploads_limit .. " uploads. FoxyMusic+ (Music app) for no limit")
or "Upload all you like", width - 2, 2, ui.theme.muted)
end
ui.tabBar(scene, target, tabs.list, tabs.active, tabs.color)
local action = scene:wait({ files = true })
if action == "home" or action == "__terminate" or (action or ""):match("^tab:") then
return action
end
if action == "pocket" then fromPocket() me = nil
elseif action == "cloud" then fromCloud() me = nil
elseif action == "mine" then uploads()
elseif action == "__files" then
local ok, files = pcall(function() return scene.dropped.getFiles() end)
for _, handle in ipairs(ok and files or {}) do
local name = handle.getName and handle.getName() or "song.dfpwm"
local body = handle.readAll and handle.readAll() or ""
pcall(handle.close)
if isSong(name) then upload(name, body)
else said("error", "Not a song", "Songs are .dfpwm files") end
end
me = nil
end
end
end



local function artistsPage(tabs)
local page = 1
while running() do
local listed, err = ask("MUSIC_ARTISTS", { query = state.query, page = page,
per_page = math.max(1, math.floor((bottom() - 5) / 2)) })
local width = target.getSize()
ui.clear(target)
ui.header(target, "Artists", listed and (listed.total .. " in the library")
or "Not answering", util.formatClock())
local scene = ui.scene(target)
scene:button("search", 2, 4, width - 2, 1, state.query ~= "" and ("Search: "
.. state.query) or "Search", { background = ui.theme.panel })
if listed then
page = listed.page
for index, artist in ipairs(listed.artists) do
local y = 4 + index * 2
scene:button("artist:" .. artist.artist_id, 2, y, width - 2, 1, "",
{ background = ui.theme.panel })
local count = artist.listeners_today .. " today"
ui.text(target, 3, y, ui.truncate(artist.name, width - #count - 5), ui.theme.ink,
ui.theme.panel)
ui.text(target, width - #count, y, count, PINK, ui.theme.panel)
end
if listed.pages > 1 then
scene:button("more", width - 6, bottom(), 6, 1, page .. "/" .. listed.pages,
{ background = ui.theme.panel })
end
if #listed.artists == 0 then
ui.wrappedText(target, 2, 6, "Nobody yet: upload a song and credit them.",
width - 2, 2, ui.theme.muted)
end
else
ui.wrappedText(target, 2, 6, tostring(err or "The Music Server is not running"),
width - 2, 3, ui.theme.warning)
end
ui.tabBar(scene, target, tabs.list, tabs.active, tabs.color)
local action = scene:wait()
if action == "home" or action == "__terminate" or (action or ""):match("^tab:") then
return action
end
if action == "search" then
state.query = ui.input(target, "Search artists", { initial = state.query,
maxLength = 20, minLength = 0, allowSpace = true }) or state.query
page = 1
elseif action == "more" then
page = page % listed.pages + 1
end
local id = action and action:match("^artist:(.+)$")
if id then
local full = ask("MUSIC_ARTIST", { artist_id = id })
if full then profileView(full.artist, false) end
end
end
end

if not music then
said("error", "Music for Artists", "This Pocket needs the FoxyOS 18.3 update", 2)
return
end
local wanted = type(api.action) == "function" and api.action() or nil
ui.runTabs({
target = target,
list = { { id = "profile", label = "You" }, { id = "upload", label = "Upload" },
{ id = "artists", label = "Artists" } },
color = PINK,
start = (wanted == "upload" or wanted == "artists") and wanted or "profile",
pages = { profile = profilePage, upload = uploadPage, artists = artistsPage },
running = running,
})
end
