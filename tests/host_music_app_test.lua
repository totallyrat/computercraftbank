-- The Music app, FoxyOS 17 and 18.3, on a 26x20 Pocket: the real app with
-- the real api.music (net.musicApi), against a real Bank Core and Vault,
-- five real Cloud Servers and a Music Server. Every draw is bounds-checked
-- and every tap lands only on something that is on the screen.
--
-- Ana has no Music Player yet: the app says how to get one, and still lets
-- her turn the Library's rows and search every song. Then a Music Player is
-- hers: it is tuned to a radio in the middle of a giveaway, Now Playing shows
-- the number, and she calls in from there. She makes a playlist -- a name, a
-- cover, its songs -- plays it, and hearts the song on Now Playing, which
-- shows its cover. Last, FoxyMusic+ from its own tab, and cancelled again.
-- (Uploading is in Music for Artists now: host_artists_app_test.)

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
    kind = "song", uploader_name = "Foxy Records" }, string.rep("t", 9000))
local clip = as(MUSIC_ID, server.library.import, { title = "Win", artist = "DJ",
    kind = "giveaway", uploader_name = "Foxy Records" }, string.rep("w", 3000))

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
            cloud = function(api)
                return net.cloud.api(function(action, payload)
                    return api.request(action, payload)
                end, config.cloud_protocol, function() return false end,
                    "/pocket" .. ana.id .. "/downloads")
            end,
        } })
end

-- 1. No player yet ------------------------------------------------------------------------------

local function cover(digit)
    local rows = {}
    for index = 1, 12 do rows[index] = string.rep(digit, 16) end
    return table.concat(rows, "/")
end
-- Enough songs for the New Music row to need its arrows.
local extra = {}
for index = 1, 3 do
    extra[index] = as(MUSIC_ID, server.library.import, { title = "Song " .. index,
        artist = "Kit", kind = "song", uploader_name = "Foxy Records" }, string.rep("x", 3000))
end
server.state.tracks[trot.track_id].cover = cover("e")

local script = phone.script()
phone.push(script.actions, function(seen)
    assert(phone.has(phone.last(seen), "No Music Player yet"), "it says how to get one")
    return "tab:library"
end, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "NEW MUSIC") and phone.has(frame, "POPULAR"), "rows, like a shop's")
    assert(phone.has(frame, "Song 3") and phone.has(frame, "Song 2")
        and not phone.has(frame, "Song 1"), "two across, newest first")
    return "right:new"
end, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "Song 1") and phone.has(frame, "Fox Trot"), "turned along")
    return "pagedown"
end, "__scrolldown", "__scrolldown", "__scrolldown", function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "PLAYLISTS") and phone.has(frame, "Make one with +"),
        "down to the last row, with the wheel too\n" .. table.concat(frame, "\n"))
    return "__scrollup"
end, "pageup", "pageup", "pageup", function(seen)
    assert(phone.has(phone.last(seen), "NEW MUSIC"))
    return "song:new:3"
end, function(seen)
    assert(phone.said(seen, "No Music Player"), "nothing to play it on")
    return "search"
end, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "4 songs") and phone.has(frame, "Fox Trot - Ana"),
        "every song, songs only")
    assert(not phone.has(frame, "Win"), "never a giveaway clip")
    return "back"
end, "home")
run(script)

-- 2. A Music Player, a radio and a giveaway ---------------------------------------------------------

local hello = as(PLAYER_ID, net.ask, MUSIC_ID, config.music_protocol, "MUSIC_HELLO",
    { session_token = ana.token, label = "Ana's Den" }, 3)
assert(hello, "a Music Player signs in as Ana")
local r = as(MUSIC_ID, server.radio.create, "Foxy FM", "lime")
r.songs, r.giveaways = { trot.track_id }, { clip.track_id }
server.radio.live(r).giveaway = { giveaway_id = "G", number = r.number,
    closes_at = util.nowMs() + 120000 }
-- The giveaway is open at the Bank too, for the call to land in.
bank.request("MUSIC_GIVEAWAY_OPEN", { server_token = registered.server_token,
    radio_id = r.radio_id, seconds = 120 })

script = phone.script()
phone.push(script.actions, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "Ana's Den"), "her player")
    assert(phone.has(frame, "Nothing playing"))
    assert(phone.has(frame, "Pick a song in Library"))
    -- Tuned from the Radio app (host_radio_app_test), while this is open.
    assert(as(PLAYER_ID, net.ask, MUSIC_ID, config.music_protocol, "MUSIC_CONTROL",
        { player_token = hello.player_token, command = "radio", radio_id = r.radio_id }, 3))
    return "__tick"
end, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "Foxy FM  LIVE"), "tuned in")
    assert(phone.has(frame, "GIVEAWAY! Call") and phone.has(frame, r.number),
        "the number to call, in Now Playing")
    return "callin"
end, function(seen)
    assert(phone.said(seen, "You're in!"), "called in from Now Playing")
    return "louder"
end, "home")
phone.push(script.confirms, true)
local balance = bank.balanceOf(ana)
run(script)
assert(bank.balanceOf(ana) == balance - 50, "a call is fifty")
assert(server.state.players.P1.mode == "radio" and server.state.players.P1.volume == 2.5)

-- 3. A playlist, and a heart -------------------------------------------------------------------

script = phone.script()
phone.push(script.actions, "tab:library", "new", function(seen)
    assert(phone.has(phone.last(seen), "Fox Trot - Ana"), "every song, to tick")
    return "pick:" .. trot.track_id
end, "pick:" .. extra[1].track_id, "pick:" .. extra[2].track_id, "pick:" .. extra[2].track_id,
function(seen)
    assert(phone.has(phone.last(seen), "2 songs"), "ticked, and one unticked")
    return "done"
end, function(seen)
    local frame = phone.last(seen)
    assert(phone.said(seen, "Night Drive") and phone.has(frame, "2 songs")
        and phone.has(frame, "0 plays") and phone.has(frame, "Public"), "made, public\n" .. table.concat(frame, "\n"))
    return "play"
end, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "Fox Trot") and phone.has(frame, "cover"),
        "Now Playing, with its cover\n" .. table.concat(frame, "\n"))
    return "heart"
end, function(seen)
    assert(phone.said(seen, "In Your Favorites") and phone.has(phone.last(seen), "<3 Yes"))
    -- The Music Player starts it: Recently Played.
    assert(as(PLAYER_ID, net.ask, MUSIC_ID, config.music_protocol, "MUSIC_STREAM",
        { player_token = hello.player_token }, 3))
    return "tab:library"
end, "pagedown", "pagedown", "pagedown", "pagedown", function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "Night Dr") and phone.has(frame, "Fox Trot"),
        "on the Playlists row, and Recently Played\n" .. table.concat(frame, "\n"))
    return "list:L1"
end, "edit", "public", function(seen)
    assert(phone.has(phone.last(seen), "Private"), "hers to hide")
    return "back"
end, "home")
phone.push(script.inputs, "Night Drive")
phone.push(script.covers, cover("a"))
run(script)
local list = server.state.playlists.L1
assert(list and list.plays == 1 and list.cover == cover("a") and #list.tracks == 2
    and list.tracks[1] == trot.track_id and list.public == false, "as she made it")
assert(server.state.favorites[ana.id][1] == trot.track_id, "in her favorites")

-- 4. FoxyMusic+, FoxyOS 18 ------------------------------------------------------------------------
-- 18.3: its own tab, joined with her PIN: no more limits.

script = phone.script()
phone.push(script.actions, "tab:plus", function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "every 5 days") and phone.has(frame, "Offline Listening")
        and phone.has(frame, "Join for"), "what it costs and gives")
    assert(phone.has(frame, "Free: 10 songs a day"), "and what free is")
    return "join"
end, function(seen)
    assert(phone.said(seen, "FoxyMusic+"))
    assert(phone.has(phone.last(seen), "Next charge day"), "hers now")
    return "home"
end)
phone.push(script.confirms, true)
phone.push(script.pins, "1234")
balance = bank.balanceOf(ana)
run(script)
assert(bank.balanceOf(ana) == balance - 100, "a hundred")
local me = as(world.pocket, net.ask, MUSIC_ID, config.music_protocol, "MUSIC_ME",
    { session_token = ana.token }, 3)
assert(me and me.uploads_limit == nil, "the Music Server heard at once: no limit")

-- Cancelled from the app's FoxyMusic+ action: it stays until the day paid for.
script = phone.script()
phone.push(script.actions, "cancel", function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "Cancelled. Ends day") and phone.has(frame, "Keep FoxyMusic+"),
        "\n" .. table.concat(frame, "\n"))
    return "home"
end)
phone.push(script.confirms, true)
run(script, "plus")
assert(bank.state.accounts[ana.id].foxymusic.cancelled)

io.write("host_music_app_test: OK\n")
