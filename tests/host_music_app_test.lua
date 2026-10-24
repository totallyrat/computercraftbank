-- The Music app, FoxyOS 18.4, on a 26x20 Pocket: the real app and the real
-- lib/musicui with the real api.music (net.musicApi), against a real Bank
-- Core and Vault, five real Cloud Servers and a Music Server. Every draw is
-- bounds-checked and every tap lands only on something that is on the
-- screen.
--
-- Ana has no Music Player yet. Music shows its rows -- turned with < >, the
-- page scrolled with the wheel down to every song -- and a tap on an
-- artist's name opens their profile. Search has the genres and the artists,
-- and finds a song. Me is her plan and her playlists. Then a Music Player is
-- hers, tuned to a radio in the middle of a giveaway: the top of the screen
-- opens Now Playing, and she calls in from there. She makes a playlist on
-- Me -- a name, a cover, its songs -- plays it, hearts the song on Now
-- Playing, and makes the playlist private. Last, FoxyMusic+ from Me, and
-- cancelled again.

package.path = "../?.lua;../?/init.lua;" .. package.path
sleep = function() end
require("config").cloud_chunk_size = 6000
local harness = require("bank_pair_harness")
local bank = harness.pair()
local world = require("cloud_harness").start(harness, bank)
local phone = require("phone_app_harness")
local config = require("config")
local net = require("lib.net")
local util = require("lib.util")
local as = world.as

world.beatAll()
local ana = bank.register("Ana Fox", "1234")
bank.fund(ana, 1000)
local MUSIC_ID, PLAYER_ID = 30, 40
local server = world.attach(MUSIC_ID, "music_server.lua", config.music_protocol, "music_server")
local registered = bank.core.actions.MUSIC_SERVER_REGISTER({ code = "4040" }, MUSIC_ID)
server.state.server_token, server.state.server_id = registered.server_token,
    registered.server_id
as(MUSIC_ID, server.background.step)
world.beatAll()
local trot = as(MUSIC_ID, server.library.import, { title = "Fox Trot", artist = "Ana",
    kind = "song", uploader_name = "Foxy Records", genre = "Lo-fi" }, string.rep("t", 9000))
local clip = as(MUSIC_ID, server.library.import, { title = "Win", artist = "DJ",
    kind = "giveaway", uploader_name = "Foxy Records" }, string.rep("w", 3000))
-- Enough songs for the New Music row to need its arrows.
local extra = {}
for index = 1, 3 do
    extra[index] = as(MUSIC_ID, server.library.import, { title = "Song " .. index,
        artist = "Kit", kind = "song", uploader_name = "Foxy Records", genre = "Synthwave" },
        string.rep("x", 3000))
end

local function cover(digit)
    local rows = {}
    for index = 1, 12 do rows[index] = string.rep(digit, 12) end
    return table.concat(rows, "/")
end
server.state.tracks[trot.track_id].cover = cover("e")

local function run(script, wanted)
    return phone.run({ bank = bank, who = ana, file = "../music.lua", app_id = "MUSIC",
        script = script, wanted = wanted,
        api = {
            music = function(api)
                return net.musicApi(config, function() return ana.token end,
                    function() return false end, function()
                        local where = api.request("MUSIC_WHERE", {})
                        return where and where.computer_id
                    end)
            end,
            musicui = function() return dofile("../lib/musicui.lua") end,
        } })
end
local function dump(frame) return "\n" .. table.concat(frame, "\n") end

-- 1. No player yet ------------------------------------------------------------------------------

local script = phone.script()
phone.push(script.actions, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "No Music Player"), "the top says so" .. dump(frame))
    assert(phone.has(frame, "NEW MUSIC") and phone.has(frame, "Play something"),
        "rows, and how to fill the top of the page" .. dump(frame))
    assert(phone.has(frame, "Music") and phone.has(frame, "Search") and phone.has(frame, "Me"),
        "the three tabs")
    assert(phone.has(frame, "Song 3") and phone.has(frame, "Song 1")
        and not phone.has(frame, "Fox Tro"), "three across, newest first" .. dump(frame))
    return "right:new"
end, function(seen)
    assert(phone.has(phone.last(seen), "Fox Tro"), "turned along")
    return "tile:new:4"
end, function(seen)
    assert(phone.said(seen, "No Music Player"), "nothing to play it on")
    return "__scrolldown"
end, "__scrolldown", "__scrolldown", function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "EVERY SONG") and phone.has(frame, "Fox Trot"),
        "down to every song, with the wheel" .. dump(frame))
    assert(not phone.has(frame, "Win"), "never a giveaway clip")
    local at
    for index, track in ipairs(server.actions.MUSIC_LIBRARY({ sort = "new", per_page = 20 })
        .tracks) do
        if track.track_id == trot.track_id then at = index end
    end
    return "by:all:" .. at
end, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "Ana") and phone.has(frame, "SONGS") and phone.has(frame, "ON THE RADIO"),
        "her profile, from her name on the song" .. dump(frame))
    return "back"
end, "tab:search", function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "GENRES") and phone.has(frame, "Synthwave")
        and phone.has(frame, "Lo-fi") and phone.has(frame, "ARTISTS"), "genres, then artists"
        .. dump(frame))
    return "genre:" .. server.state.genre_names["synthwave"]
end, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "3 songs") and phone.has(frame, "> Play the mix")
        and phone.has(frame, "Song 2"), "the genre, its mix and its songs" .. dump(frame))
    return "back"
end, "search", function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "Search: fox") and phone.has(frame, "Fox Trot")
        and not phone.has(frame, "Song 2"), "found" .. dump(frame))
    return "tab:me"
end, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "Ana Fox") and phone.has(frame, "Free: 0 of 10 songs today")
        and phone.has(frame, "+ New playlist") and phone.has(frame, "None yet."),
        "her plan and her playlists" .. dump(frame))
    return "home"
end)
phone.push(script.inputs, "fox")
run(script)

-- 2. A Music Player, a radio and a giveaway ---------------------------------------------------------

local hello = as(PLAYER_ID, net.ask, MUSIC_ID, config.music_protocol, "MUSIC_HELLO",
    { session_token = ana.token, label = "Ana's Den" }, 3)
assert(hello, "a Music Player signs in as Ana")
local r = as(MUSIC_ID, server.radio.create, "Foxy FM", "lime")
r.songs, r.giveaways = { trot.track_id }, { clip.track_id }
server.radio.live(r).giveaway = { giveaway_id = "G", number = r.number,
    closes_at = util.nowMs() + 120000 }
bank.request("MUSIC_GIVEAWAY_OPEN", { server_token = registered.server_token,
    radio_id = r.radio_id, seconds = 120 })
assert(as(PLAYER_ID, net.ask, MUSIC_ID, config.music_protocol, "MUSIC_CONTROL",
    { player_token = hello.player_token, command = "radio", radio_id = r.radio_id }, 3))

script = phone.script()
phone.push(script.actions, function(seen)
    assert(phone.has(phone.last(seen), "> Fox Trot - Ana"), "what is on, along the top")
    return "now"
end, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "On Ana's Den  v") and phone.has(frame, "Foxy FM  LIVE"),
        "her player, tuned in" .. dump(frame))
    assert(phone.has(frame, "GIVEAWAY! Call") and phone.has(frame, r.number),
        "the number to call, in Now Playing")
    return "callin"
end, function(seen)
    assert(phone.said(seen, "You're in!"), "called in from Now Playing")
    return "louder"
end, "back", "home")
phone.push(script.confirms, true)
local balance = bank.balanceOf(ana)
run(script)
assert(bank.balanceOf(ana) == balance - 50, "a call is fifty")
assert(server.state.players.P1.mode == "radio" and server.state.players.P1.volume == 2.5)

-- 3. A playlist, and a heart -------------------------------------------------------------------

script = phone.script()
phone.push(script.actions, "tab:me", "newlist", function(seen)
    assert(phone.has(phone.last(seen), "Fox Trot - Ana"), "every song, to tick")
    return "pick:" .. trot.track_id
end, "pick:" .. extra[1].track_id, "pick:" .. extra[2].track_id, "pick:" .. extra[2].track_id,
function(seen)
    assert(phone.has(phone.last(seen), "2 songs"), "ticked, and one unticked")
    return "done"
end, function(seen)
    local frame = phone.last(seen)
    assert(phone.said(seen, "Night Drive") and phone.has(frame, "2 songs")
        and phone.has(frame, "Public") and phone.has(frame, "By Ana Fox"), "made, public" .. dump(frame))
    return "playall"
end, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "> Fox Trot - Ana"), "playing it, along the top" .. dump(frame))
    return "now"
end, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "Fox Trot") and phone.has(frame, "cover") and phone.has(frame, "<3"),
        "Now Playing, with its cover" .. dump(frame))
    return "heart"
end, function(seen)
    assert(phone.said(seen, "In your Favorites") and phone.has(phone.last(seen), "<3 Yes"))
    -- The Music Player starts it: Recently Played.
    assert(as(PLAYER_ID, net.ask, MUSIC_ID, config.music_protocol, "MUSIC_STREAM",
        { player_token = hello.player_token }, 3))
    return "by:now"
end, function(seen)
    assert(phone.has(phone.last(seen), "SONGS"), "Ana's profile, from Now Playing")
    return "back"
end, "back", "edit", "public", function(seen)
    assert(phone.has(phone.last(seen), "Private"), "hers to hide")
    return "back"
end, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "Night D") and phone.has(frame, "YOUR PLAYLISTS"), "on Me" .. dump(frame))
    return "tab:music"
end, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "RECENTLY PLAYED") and phone.has(frame, "FAVORITES")
        and not phone.has(frame, "Play something"), "hers, on top" .. dump(frame))
    return "home"
end)
phone.push(script.inputs, "Night Drive")
phone.push(script.covers, cover("a"))
run(script)
local list = server.state.playlists.L1
assert(list and list.plays == 1 and list.cover == cover("a") and #list.tracks == 2
    and list.tracks[1] == trot.track_id and list.public == false, "as she made it")
assert(server.state.favorites[ana.id][1] == trot.track_id, "in her favorites")

-- 4. FoxyMusic+, from Me ------------------------------------------------------------------------

script = phone.script()
phone.push(script.actions, "plus", function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "every 5 days") and phone.has(frame, "Offline Listening")
        and phone.has(frame, "Join for"), "what it costs and gives")
    assert(phone.has(frame, "Free: 10 songs a day"), "and what free is")
    return "join"
end, function(seen)
    assert(phone.said(seen, "FoxyMusic+"))
    assert(phone.has(phone.last(seen), "Next charge day"), "hers now")
    return "back"
end, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "FoxyMusic+: unlimited songs") and phone.has(frame, "FoxyMusic+: yours"),
        "the Music Server heard at once" .. dump(frame))
    return "plus"
end, "cancel", function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "Cancelled. Ends day") and phone.has(frame, "Keep FoxyMusic+"), dump(frame))
    return "back"
end, "home")
phone.push(script.confirms, true, true)
phone.push(script.pins, "1234")
balance = bank.balanceOf(ana)
run(script, "me")
assert(bank.balanceOf(ana) == balance - 100, "a hundred")
assert(bank.state.accounts[ana.id].foxymusic.cancelled)

io.write("host_music_app_test: OK\n")
