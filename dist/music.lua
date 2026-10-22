-- PUMPE APP: Music
-- PUMPE APP ICON: 66666666/66600006/66606606/66606606/60006006/60066006
-- PUMPE APP ACTION: now | Now Playing | What your Music Player is playing
-- PUMPE APP ACTION: library | Music Library | Every song, play one
-- PUMPE APP ACTION: upload | Upload a song | From this Pocket or FoxyCloud
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



local function nowPage(tabs)
refreshPlayers()
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
if now then
if now.label then ui.center(target, 7, ui.truncate(now.label, width - 2),
colors.yellow) end
ui.center(target, 8, ui.truncate(now.title, width - 2), ui.theme.ink)
ui.center(target, 9, ui.truncate(now.artist, width - 2), ui.theme.muted)
local position = math.min(now.length_ms or 0, now.position_ms or 0)
ui.progress(target, 2, 11, width - 2, position,
math.max(1, now.length_ms or 1), radio and colorOf(radio.color) or PINK,
ui.theme.panel)
ui.text(target, 2, 12, clock(position), ui.theme.muted)
local total = clock(now.length_ms)
ui.text(target, width - #total, 12, total, ui.theme.muted)
else
ui.wrappedText(target, 2, 8, player.notice or (player.paused and "Paused")
or "Nothing playing. Pick a song in Library, or a station in the Radio app.",
width - 2, 3, player.notice and ui.theme.warning or ui.theme.muted)
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
local live = player.mode == "radio"
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



local function libraryPage(tabs)
local listed, err
while running() do
local width = target.getSize()
local per = math.max(1, bottom() - 6)
if not listed then
listed, err = ask("MUSIC_LIBRARY", { sort = state.sort, query = state.query,
page = state.page, per_page = per })
if not state.players then refreshPlayers() end
end
ui.clear(target)
ui.header(target, "Music Library", listed and (listed.total .. " songs")
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
or "No songs yet. Upload the first!", width - 2, 2, ui.theme.muted)
end
if listed.pages > 1 then
scene:button("prev", 2, bottom(), 4, 1, "<", { background = ui.theme.panel })
ui.center(target, bottom(), listed.page .. "/" .. listed.pages, ui.theme.muted)
scene:button("next", width - 4, bottom(), 4, 1, ">",
{ background = ui.theme.panel })
end
end
ui.tabBar(scene, target, tabs.list, tabs.active, tabs.color)
local action = scene:wait()
if action == "home" or action == "__terminate"
or (action or ""):match("^tab:") then
return action
end
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
elseif (playId or addId) and not current() then
said("error", "No Music Player", "Set one up first: a computer with a speaker", 2)
elseif playId then
local queue = {}
for _, track in ipairs(listed.tracks) do queue[#queue + 1] = track.track_id end
if control("play", { track_id = playId, queue = queue }) then
return "tab:now"
end
elseif addId then
if control("add", { track_id = addId }) then
said("success", "Queued", "On " .. current().label)
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
allowSpace = true })
if not title or util.trim(title) == "" then return end
local artist = ui.input(target, "Artist", { maxLength = 20, allowSpace = true })
if not artist or util.trim(artist) == "" then return end
local began, err = ask("MUSIC_UPLOAD_BEGIN", { title = title, artist = artist,
size = #body })
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
said("success", "In the Music Library", done.track.title .. ", by you", 1.8)
else
said("error", "Not uploaded", doneError, 2)
end
end


local function pick(title, names)
local page = 1
while running() do
local width, height = target.getSize()
ui.clear(target)
ui.header(target, title, #names .. " songs", util.formatClock())
local scene = ui.scene(target)
local per = math.max(1, math.floor((height - 6) / 2))
local items, actual, pages = util.page(names, page, per)
page = actual
for index, name in ipairs(items) do
scene:button("pick:" .. ((page - 1) * per + index), 2, 2 + index * 2, width - 2,
1, ui.truncate(name, width - 4), { background = ui.theme.panel })
end
if #names == 0 then
ui.wrappedText(target, 2, 5, "No .dfpwm songs here.", width - 2, 2, ui.theme.muted)
end
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
local index = pick("From this Pocket", names)
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
local index = pick("From FoxyCloud", names)
if not index then return end
ui.clear(target)
ui.header(target, "FoxyCloud", ui.truncate("Opening " .. songs[index].name,
target.getSize() - 3), util.formatClock())
local body, loadError = cloud.load(songs[index].file_id)
if body then upload(songs[index].name, body) else said("error", "Cannot open it", loadError) end
end



local function plusPage()
local plan, err = api.request("MUSIC_PLUS_PLAN", {}, true)
while running() do
local width, height = target.getSize()
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
scene:button("back", 1, height, 8, 1, "< Back", { background = ui.theme.panel })
local action = scene:wait()
if action == "back" or action == "__terminate" then return end
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

local function uploadPage(tabs)
local me
while running() do
local width = target.getSize()
me = me or ask("MUSIC_ME")
ui.clear(target)
ui.header(target, "Upload a song", "With your name on it", util.formatClock())
local scene = ui.scene(target)
ui.wrappedText(target, 2, 4, "Songs are DFPWM1a (.dfpwm). Drop one on this screen,"
.. " or pick one:", width - 2, 3, ui.theme.ink)
scene:button("pocket", 2, 8, width - 2, 2, "From this Pocket", {
background = PINK, foreground = colors.black })
scene:button("cloud", 2, 11, width - 2, 2, "From FoxyCloud", {
background = colors.lightBlue, foreground = colors.black })
if me then
ui.text(target, 2, 14, ui.truncate(me.uploads_limit and ("Today: " .. me.uploads
.. " of " .. me.uploads_limit .. " uploads") or "Upload all you like",
width - 2), ui.theme.muted)
end
scene:button("plus", 2, 16, width - 2, 2, me and me.music_plus and "FoxyMusic+: yours"
or "FoxyMusic+: no limits", { background = ui.theme.panel, foreground = PINK })
ui.tabBar(scene, target, tabs.list, tabs.active, tabs.color)
local action = scene:wait({ files = true })
if action == "home" or action == "__terminate"
or (action or ""):match("^tab:") then
return action
end
if action == "plus" then
plusPage()
me = nil
elseif action == "pocket" then
fromPocket()
me = nil
elseif action == "cloud" then
fromCloud()
me = nil
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



if not music then
said("error", "Music", "This Pocket needs the FoxyOS 17 update", 2)
return
end
local wanted = type(api.action) == "function" and api.action() or nil
if wanted == "plus" then
plusPage()
wanted = "upload"
end
ui.runTabs({
target = target,
list = { { id = "now", label = "Now" }, { id = "library", label = "Library",
short = "Songs" }, { id = "upload", label = "Upload", short = "Up" } },
color = PINK,
start = (wanted == "library" or wanted == "upload") and wanted or "now",
pages = { now = nowPage, library = libraryPage, upload = uploadPage },
running = running,
})
end
