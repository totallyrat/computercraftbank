-- The Music app, FoxyOS 17, on a 26x20 Pocket: the real app with the real
-- api.music (net.musicApi) and api.cloud, against a real Bank Core and Vault,
-- five real Cloud Servers and a Music Server. Every draw is bounds-checked
-- and every tap lands only on something that is on the screen.
--
-- Ana has no Music Player yet: the app says how to get one, and still lets
-- her browse the library and upload a song dropped on her Pocket. Then a
-- Music Player is hers: it is tuned to a radio in the middle of a giveaway,
-- Now Playing shows the number, and she calls in from there. Last, a song
-- kept in her FoxyCloud goes into the library, and she joins FoxyMusic+ from
-- the Upload tab and cancels it again.

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

local song = string.rep("s", 7000)
local script = phone.script()
phone.push(script.actions, function(seen)
    assert(phone.has(phone.last(seen), "No Music Player yet"), "it says how to get one")
    return "tab:library"
end, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "1 songs") and phone.has(frame, "Fox Trot - Ana"),
        "the library, songs only")
    assert(not phone.has(frame, "Win"), "never a giveaway clip")
    return "play:" .. trot.track_id
end, function(seen)
    assert(phone.said(seen, "No Music Player"), "nothing to play it on")
    return "tab:upload"
end, function(seen)
    assert(phone.has(phone.last(seen), "Today: 0 of 2 uploads"))
    return { drop = { { name = "My_Tune.dfpwm", body = song } } }
end, function(seen)
    assert(phone.said(seen, "In the Music Library"), "uploaded")
    return "home"
end)
phone.push(script.inputs, function(seen)
    assert(seen.inputs[#seen.inputs].initial == "My Tune", "titled from the file's name")
    return "My Tune"
end, "Ana Fox")
run(script)
local mine
for _, track in pairs(server.state.tracks) do
    if track.title == "My Tune" then mine = track end
end
assert(mine and mine.uploader_name == "Ana Fox" and mine.size == 7000,
    "in the library, credited to Ana")

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
    assert(phone.has(frame, "the Radio app"), "FoxyOS 18.2: stations are in the Radio app")
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

-- 3. From FoxyCloud -------------------------------------------------------------------------------

local cloudSong = string.rep("c", 5000)
local saved = as(world.pocket, net.cloud.save, function(action, payload)
    payload.app_id, payload.session_token = "CLOUD", ana.token
    return bank.request(action, payload)
end, { name = "Cloud Song.dfpwm" }, cloudSong, config.cloud_protocol)
assert(saved and saved.file.kind == "audio", "a .dfpwm file in FoxyCloud is a song")
script = phone.script()
phone.push(script.actions, "tab:upload", "cloud", function(seen)
    assert(phone.has(phone.last(seen), "Cloud Song.dfpwm"))
    return "pick:1"
end, function(seen)
    assert(phone.said(seen, "In the Music Library"))
    return "home"
end)
phone.push(script.inputs, "Cloud Song", "Ana Fox")
run(script)
local fromCloud
for _, track in pairs(server.state.tracks) do
    if track.title == "Cloud Song" then fromCloud = track end
end
assert(fromCloud and fromCloud.size == 5000)
-- Two uploads: the free day's worth.
local _, _, limit = as(world.pocket, net.ask, MUSIC_ID, config.music_protocol,
    "MUSIC_UPLOAD_BEGIN", { session_token = ana.token, title = "Three", size = 10 }, 3)
assert(limit == "UPLOAD_LIMIT")

-- 4. FoxyMusic+, FoxyOS 18 ------------------------------------------------------------------------
-- Joined from the Upload tab, with her PIN: no more limits.

script = phone.script()
phone.push(script.actions, "tab:upload", function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "Today: 2 of 2 uploads") and phone.has(frame, "FoxyMusic+: no limits"),
        "the way past the limit, under it")
    return "plus"
end, function(seen)
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
    assert(phone.has(frame, "Upload all you like") and phone.has(frame, "FoxyMusic+: yours"),
        "the Music Server heard at once")
    return "home"
end)
phone.push(script.confirms, true)
phone.push(script.pins, "1234")
balance = bank.balanceOf(ana)
run(script)
assert(bank.balanceOf(ana) == balance - 100, "a hundred")
assert(as(world.pocket, net.ask, MUSIC_ID, config.music_protocol,
    "MUSIC_UPLOAD_BEGIN", { session_token = ana.token, title = "Three", size = 10 }, 3),
    "a third upload today")

-- Cancelled from the app's FoxyMusic+ action: it stays until the day paid for.
script = phone.script()
phone.push(script.actions, "cancel", function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "Cancelled. Ends day") and phone.has(frame, "Keep FoxyMusic+"),
        "\n" .. table.concat(frame, "\n"))
    return "back"
end, function(seen)
    assert(phone.has(phone.last(seen), "Upload a song"), "then the app, on Upload")
    return "home"
end)
phone.push(script.confirms, true)
run(script, "plus")
assert(bank.state.accounts[ana.id].foxymusic.cancelled)

io.write("host_music_app_test: OK\n")
