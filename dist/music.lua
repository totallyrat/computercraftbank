-- PUMPE APP: Music
-- PUMPE APP ICON: 66666666/66600006/66606606/66606606/60006006/60066006
-- PUMPE APP ACTION: music | Music | Yours, then everything new
-- PUMPE APP ACTION: search | Search | Songs, artists and genres
-- PUMPE APP ACTION: me | Me | Your playlists and FoxyMusic+


















return function(api)
local ui, util, target, colors = api.ui, api.util, api.target, api.colors
local music, musicui = api.music, api.musicui
local PINK = colors.pink
local COLORS = { red = colors.red, orange = colors.orange, yellow = colors.yellow,
lime = colors.lime, green = colors.green, cyan = colors.cyan,
lightBlue = colors.lightBlue, blue = colors.blue, purple = colors.purple,
magenta = colors.magenta, pink = colors.pink, brown = colors.brown,
white = colors.white, lightGray = colors.lightGray }
local state = { players = nil, player_id = nil }

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






local function nowPage(app)
refreshPlayers()
local ticks = 0
while running() do
ticks = ticks + 1
if ticks % 2 == 0 then refreshPlayers() end
local width = target.getSize()
local player = current()
ui.clear(target)
local scene = ui.scene(target)
local top, last = app:chrome(scene, "Now Playing", { back = true })
local song
if not player then
noPlayer(top + 1)
else
scene:button("players", 2, top, width - 2, 1, ui.truncate((player.online
and "On " or "Off: ") .. player.label .. "  v", width - 4),
{ background = ui.theme.panel })
local now, radio = player.now, player.radio
if radio then
local band = colorOf(radio.color)
ui.fill(target, 2, top + 1, width - 2, 1, band)
ui.text(target, 3, top + 1, ui.truncate(radio.name .. "  LIVE", width - 4),
ui.inkOn(band), band)
end
local y = top + 2
local right = 2 + ui.COVER_WIDTH + 1
local room = width - right
if now then
ui.cover(target, 2, y, now.cover or (radio and radio.cover))
local line = y
if now.label then
ui.text(target, right, line, ui.truncate(now.label, room), colors.yellow)
line = line + 1
end
ui.text(target, right, line, ui.truncate(now.title, room), ui.theme.ink)
ui.text(target, right, line + 1, ui.truncate(now.artist or "", room),
ui.theme.muted)
scene:hotspot("by:now", right, line + 1, room, 1)
if now.kind == "song" and now.track_id and not radio then song = now end
if song and line + 2 <= y + 3 then
local loved = app:loved(song.track_id)
scene:button("heart", right, y + 3, math.min(room, 8), 1,
loved and "<3 Yes" or "<3", { background = loved and PINK
or ui.theme.panel, foreground = loved and colors.black or PINK })
end
local position = math.min(now.length_ms or 0, now.position_ms or 0)
ui.progress(target, 2, y + 5, width - 2, position,
math.max(1, now.length_ms or 1), radio and colorOf(radio.color) or PINK,
ui.theme.panel)
ui.text(target, 2, y + 6, clock(position), ui.theme.muted)
local total = clock(now.length_ms)
ui.text(target, width - #total + 1, y + 6, total, ui.theme.muted)
else
ui.cover(target, 2, y, radio and radio.cover)
ui.wrappedText(target, right, y, player.notice or (player.paused and "Paused")
or "Nothing playing. Pick a song on Music.", room, 4,
player.notice and ui.theme.warning or ui.theme.muted)
end
local note = y + 8
if radio and radio.giveaway then
ui.fill(target, 2, note, width - 2, 2, colors.yellow)
ui.text(target, 3, note, "GIVEAWAY! Call", colors.black, colors.yellow)
ui.text(target, 3, note + 1, radio.giveaway.number .. "  "
.. clock(radio.giveaway.closes_in_ms), colors.black, colors.yellow)
scene:button("callin", width - 7, note, 7, 2, "Call", {
background = colors.black, foreground = colors.yellow })
elseif radio and radio.winner and radio.winner.name then
ui.center(target, note, ui.truncate(radio.winner.name .. " won "
.. money(radio.winner.prize), width - 2), colors.yellow)
elseif radio and radio.special then
ui.center(target, note, ui.truncate(radio.special, width - 2), PINK)
elseif player.plays_left then
ui.center(target, note, ui.truncate(player.plays_left .. " songs left today",
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
scene:button(button[1], 2 + (index - 1) * each, last - 1, each - 1, 2,
button[2], { background = index == 2 and PINK or ui.theme.panel,
foreground = index == 2 and colors.black or ui.theme.ink,
disabled = button[3] or not player.online })
end
end
local action = scene:wait({ tickRate = 1, scroll = true })
if action == "back" or musicui.leaving(action) then return action end
if action == "players" then
choosePlayer()
elseif action == "by:now" and player and player.now then
local result = app:credits(player.now)
if musicui.leaving(result) then return result end
elseif action == "heart" and song then
app:heart(song)
elseif action == "callin" and player and player.radio and player.radio.giveaway then
callIn(player.radio)
elseif action == "quieter" or action == "louder" then
local volume = (tonumber(player.volume) or 2) + (action == "louder" and 0.5 or -0.5)
control("volume", { volume = math.max(0, math.min(3, volume)) })
elseif action and not action:match("^__") and action ~= "now" then
control(action)
end
end
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
if action == "back" or action == "__terminate" then return "back" end
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




if not music or not api.musicui then
said("error", "Music", "This Pocket needs the FoxyOS 18.4 update", 2)
return
end
local app = musicui.new({
ui = ui, util = util, colors = colors, target = target, accent = PINK, home = true,
running = running, ask = ask, nowPage = nowPage, plusPage = plusPage,
refresh = function() refreshPlayers() end,
current = function()
if not state.players then refreshPlayers() end
local player = current()
if not player then return { where = "No Music Player" } end
local now = player.now
if not now then
return { where = player.online and ("Nothing on " .. player.label)
or (player.label .. " is off") }
end
return { title = now.title, artist = now.artist, paused = player.paused }
end,
play = function(trackId, queue, playlistId)
if not current() then
said("error", "No Music Player", "Set one up first: a computer with a speaker", 2)
return false
end
return control("play", { track_id = trackId, queue = queue,
playlist_id = playlistId }) ~= nil
end,

marks = function() return { { key = "add", label = "+" } } end,
mark = function(_, track)
if not current() then
said("error", "No Music Player", "Set one up first: a computer with a speaker", 2)
elseif control("add", { track_id = track.track_id }) then
said("success", "Queued", track.title)
end
end,
})
local wanted = type(api.action) == "function" and api.action() or nil
app:run(wanted)
end
