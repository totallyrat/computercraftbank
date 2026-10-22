-- Music for Artists, FoxyOS 18.3, on a 26x20 Pocket: the real app with the
-- real api.music and api.cloud, against a real Bank Core and Vault, five real
-- Cloud Servers and the Music Server. Every draw is bounds-checked and every
-- tap lands only on something that is on the screen.
--
-- An upload has already credited "Ana Fox". Ana makes her Artist Profile --
-- a name, a line, a cover -- and the song comes with it; she changes the
-- cover from her profile. She uploads a song dropped on her Pocket, credits
-- Kit too and draws it a cover, then one from FoxyCloud without a cover, and
-- gives that one a cover from Your uploads. That is the free day's two. Kit
-- has a profile now, from the credit: Artists finds it, searched or not.

package.path = "../?.lua;../?/init.lua;" .. package.path
sleep = function() end
require("config").cloud_chunk_size = 6000
local harness = require("bank_pair_harness")
local bank = harness.pair()
local world = require("cloud_harness").start(harness, bank)
local phone = require("phone_app_harness")
local config = require("config")
local net = require("lib.net")
local as = world.as

world.beatAll()
local ana = bank.register("Ana Fox", "1234")
local MUSIC_ID = 30
local server = world.attach(MUSIC_ID, "music_server.lua", config.music_protocol, "music_server")
local registered = bank.core.actions.MUSIC_SERVER_REGISTER({ code = "4040" }, MUSIC_ID)
server.state.server_token, server.state.server_id = registered.server_token,
    registered.server_id
as(MUSIC_ID, server.background.step)
world.beatAll()
local trot = as(MUSIC_ID, server.library.import, { title = "Fox Trot", artist = "Ana Fox",
    kind = "song", uploader_name = "Foxy Records" }, string.rep("t", 9000))

local function cover(digit)
    local rows = {}
    for index = 1, 12 do rows[index] = string.rep(digit, 16) end
    return table.concat(rows, "/")
end

local function run(script, wanted)
    return phone.run({ bank = bank, who = ana, file = "../artists.lua", app_id = "ARTISTS",
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

-- 1. Her profile ---------------------------------------------------------------------------------

local script = phone.script()
phone.push(script.actions, function(seen)
    assert(phone.has(phone.last(seen), "No Artist Profile yet"))
    return "create"
end, function(seen)
    local frame = phone.last(seen)
    assert(phone.said(seen, "Ana Fox"), "made")
    assert(phone.has(frame, "0 today") and phone.has(frame, "1 songs"),
        "with the song that credited her\n" .. table.concat(frame, "\n"))
    return "open"
end, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "Foxes, mostly") and phone.has(frame, "Fox Trot  0 plays")
        and phone.has(frame, "ON THE RADIO") and phone.has(frame, "Their own profile"),
        "the profile in full\n" .. table.concat(frame, "\n"))
    return "cover"
end, "back", "home")
phone.push(script.inputs, "Ana Fox", "Foxes, mostly")
phone.push(script.covers, cover("1"), cover("2"))
run(script)
local profile = server.catalog and server.catalog.named and server.catalog.named("Ana Fox")
    or server.state.artists[server.state.artist_names["ana fox"]]
assert(profile and profile.owner_account_id == ana.id and profile.cover == cover("2"),
    "hers, with the second cover")

-- 2. Uploads ----------------------------------------------------------------------------------------

local cloudSong = string.rep("c", 5000)
assert(as(world.pocket, net.cloud.save, function(action, payload)
    payload.app_id, payload.session_token = "CLOUD", ana.token
    return bank.request(action, payload)
end, { name = "Cloud Song.dfpwm" }, cloudSong, config.cloud_protocol))

script = phone.script()
phone.push(script.actions, "tab:upload", function(seen)
    assert(phone.has(phone.last(seen), "Today: 0 of 2 uploads"))
    return { drop = { { name = "My_Tune.dfpwm", body = string.rep("s", 7000) } } }
end, function(seen)
    assert(phone.said(seen, "In the Music Library"), "uploaded")
    return "cloud"
end, function(seen)
    assert(phone.has(phone.last(seen), "Cloud Song.dfpwm"))
    return "pick:1"
end, function(seen)
    assert(phone.has(phone.last(seen), "Today: 2 of 2 uploads"), "the free day's two")
    return "mine"
end, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "Cloud Song - Ana Fox") and phone.has(frame, "My Tune - Ana Fox"),
        "her uploads\n" .. table.concat(frame, "\n"))
    return "pick:1"
end, function(seen)
    assert(phone.said(seen, "New cover"))
    return "home"
end)
phone.push(script.inputs, function(seen)
    assert(seen.inputs[#seen.inputs].initial == "My Tune", "titled from the file's name")
    return "My Tune"
end, function(seen)
    assert(seen.inputs[#seen.inputs].initial == "Ana Fox", "her artist name, offered")
    return "Ana Fox & Kit"
end, "Cloud Song", "Ana Fox")
phone.push(script.confirms, true, false)
phone.push(script.covers, cover("b"), cover("c"))
run(script)
local tune, cloudTrack
for _, track in pairs(server.state.tracks) do
    if track.title == "My Tune" then tune = track end
    if track.title == "Cloud Song" then cloudTrack = track end
end
assert(tune and tune.cover == cover("b") and tune.uploader_name == "Ana Fox"
    and #tune.artist_ids == 2, "credited to two, with its cover")
assert(cloudTrack and cloudTrack.size == 5000 and cloudTrack.cover == cover("c"),
    "from FoxyCloud, its cover drawn later")
local _, _, limit = as(world.pocket, net.ask, MUSIC_ID, config.music_protocol,
    "MUSIC_UPLOAD_BEGIN", { session_token = ana.token, title = "Three", size = 10 }, 3)
assert(limit == "UPLOAD_LIMIT")

-- 3. Artists -------------------------------------------------------------------------------------

local kit = server.state.artists[server.state.artist_names["kit"]]
assert(kit and not kit.owner_account_id, "Kit, from the credit")
script = phone.script()
phone.push(script.actions, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "2 in the library") and phone.has(frame, "Kit"))
    return "artist:" .. kit.artist_id
end, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "From credits") and phone.has(frame, "My Tune  0 plays")
        and not phone.has(frame, "Edit"), "Kit's, not hers to change")
    return "back"
end, "search", function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "1 in the library") and phone.has(frame, "Search: kit"))
    return "home"
end)
phone.push(script.inputs, "kit")
run(script, "artists")

io.write("host_artists_app_test: OK\n")
