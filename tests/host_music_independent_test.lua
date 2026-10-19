-- The Music Server without the Bank, FoxyOS 18: a real Bank Core and Vault,
-- five real Cloud Servers and the Music Server on one network.
--
-- What has to hold: with the Bank unreachable the radios still play, songs
-- from the library still play and are still counted, a Pocket that signed in
-- is still believed, uploads still go in, and giveaways -- which are the
-- Bank's -- are left out until it is back. A song from FoxyOS 17, kept by the
-- Bank's Vault, is moved onto the Music Server's own pieces and plays the
-- same. A piece nobody wants is swept off its Cloud Server. Offline
-- Listening is for FoxyMusic+.

package.path = "../?.lua;../?/init.lua;" .. package.path
sleep = function() end
require("config").cloud_chunk_size = 6000
local harness = require("bank_pair_harness")
local rejected = harness.rejected
local bank = harness.pair()
local config = require("config")
local net = require("lib.net")
local music = require("lib.music")

local world = require("cloud_harness").start(harness, bank)
local as = world.as
local POCKET, MUSIC_ID, KIT_PLAYER, ANA_PLAYER = world.pocket, 30, 40, 41
world.beatAll()

local ana = bank.register("Ana Fox", "1234")
local kit = bank.register("Kit Wolf", "5678")
bank.fund(ana, 1000)

local server = world.attach(MUSIC_ID, "music_server.lua", config.music_protocol, "music_server")
local registered = bank.request("MUSIC_SERVER_REGISTER", { code = "4040" })
server.state.server_token, server.state.server_id = registered.server_token,
    registered.server_id
as(MUSIC_ID, server.background.step)
world.beatAll()

local function ask(action, payload, from)
    return as(from or POCKET, net.ask, MUSIC_ID, config.music_protocol, action, payload, 3)
end
local function must(action, payload, from)
    local answer, err, code = ask(action, payload, from)
    assert(answer, action .. ": " .. tostring(code) .. " " .. tostring(err))
    return answer
end
local function refused(code, action, payload, from)
    local answer, err, got = ask(action, payload, from)
    assert(not answer and got == code, action .. " should be " .. code .. ", was "
        .. tostring(got) .. " " .. tostring(err))
end
local function import(title, kind, size)
    local track = as(MUSIC_ID, server.library.import, { title = title, artist = "Foxy",
        kind = kind, uploader_name = "Foxy Records" }, string.rep(title:sub(1, 1), size or 6000))
    assert(track, "imported " .. title)
    return track
end

local trot = import("Trot", "song")
local howl = import("Howl", "song")
local clip = import("Win", "giveaway", 3000)
local r = as(MUSIC_ID, server.radio.create, "Foxy FM", "lime")
assert(r.number, "a number while the Bank answers")
r.songs, r.giveaways = { trot.track_id, howl.track_id }, { clip.track_id }
r.host_chance, r.ads_every = 0, 99

-- FoxyMusic+ ------------------------------------------------------------------------------------

local joined = bank.request("MUSIC_PLUS_JOIN", bank.as(ana, { pin = "1234" }))
assert(joined.plan == "plus" and joined.price == 100)
local me = must("MUSIC_ME", { session_token = ana.token })
assert(me.music_plus and me.offline and me.plays_limit == nil and me.uploads_limit == nil,
    "unlimited, and Offline Listening")
local kitMe = must("MUSIC_ME", { session_token = kit.token })
assert(not kitMe.music_plus and kitMe.plays_limit == 10 and kitMe.uploads_limit == 2)

-- Two Music Players, signed in while the Bank answers.
local kitPlayer = must("MUSIC_HELLO", { session_token = kit.token, label = "Kit" }, KIT_PLAYER)
local anaPlayer = must("MUSIC_HELLO", { session_token = ana.token, label = "Ana" }, ANA_PLAYER)
local function player(hello, from, action, payload)
    payload = payload or {}
    payload.player_token = hello.player_token
    return ask(action, payload, from)
end

-- Offline Listening is FoxyMusic+'s.
local _, _, needsPlus = player(kitPlayer, KIT_PLAYER, "MUSIC_DOWNLOAD", { track_id = trot.track_id })
assert(needsPlus == "NEEDS_MUSIC_PLUS")
local download = assert(player(anaPlayer, ANA_PLAYER, "MUSIC_DOWNLOAD", { track_id = trot.track_id }))
assert(as(ANA_PLAYER, net.cloud.get, download.plan, config.cloud_protocol) == string.rep("T", 6000),
    "the whole song, to keep on the player")
assert(download.track.title == "Trot")

-- The Bank goes away ------------------------------------------------------------------------------

world.lose[bank.core_id] = 1e9
-- The Music Server finds out at its next beat.
bank.advanceMs(31 * 1000)
as(MUSIC_ID, server.background.step)
assert(server.status.bank_down)

-- The radio plays on: the pieces are the Music Server's, and so are the tickets.
must("MUSIC_CONTROL", { player_token = kitPlayer.player_token, command = "radio",
    radio_id = r.radio_id }, KIT_PLAYER)
local onAir = assert(player(kitPlayer, KIT_PLAYER, "MUSIC_STREAM"))
assert(onAir.mode == "radio")
assert(as(KIT_PLAYER, net.cloud.get, onAir.plan, config.cloud_protocol),
    "a Cloud Server checks the ticket with the Music Server, not the Bank")

-- Songs from the library play, counted on the Music Server.
must("MUSIC_CONTROL", { player_token = kitPlayer.player_token, command = "play",
    track_id = howl.track_id }, KIT_PLAYER)
assert(player(kitPlayer, KIT_PLAYER, "MUSIC_STREAM"))
assert(server.state.usage[kit.id].plays == 1)
server.state.usage[kit.id].plays = 10
must("MUSIC_CONTROL", { player_token = kitPlayer.player_token, command = "next" }, KIT_PLAYER)
must("MUSIC_CONTROL", { player_token = kitPlayer.player_token, command = "play",
    track_id = trot.track_id }, KIT_PLAYER)
local _, limited, limitCode = player(kitPlayer, KIT_PLAYER, "MUSIC_STREAM")
assert(limitCode == "MUSIC_LIMIT" and limited:find("FoxyMusic%+"), "still ten a day")
-- Ana's plan, as the Bank last said, still counts.
must("MUSIC_CONTROL", { player_token = anaPlayer.player_token, command = "play",
    track_id = trot.track_id }, ANA_PLAYER)
server.state.usage[ana.id].plays = 50
assert(player(anaPlayer, ANA_PLAYER, "MUSIC_STREAM"), "FoxyMusic+ is unlimited")

-- A Pocket that signed in is still believed, for as long as a session lasts.
local stillMe = must("MUSIC_ME", { session_token = ana.token })
assert(stillMe.music_plus, "what the Bank last said")
refused("BANK_OFFLINE", "MUSIC_ME", { session_token = "SESSION_NEVER_SEEN" })

-- Uploads go in.
local body = string.rep("u", 7000)
local began = must("MUSIC_UPLOAD_BEGIN", { session_token = ana.token, title = "Offline",
    artist = "Ana", size = #body })
assert(as(POCKET, music.upload, began.plan, body, config.cloud_protocol))
local added = must("MUSIC_UPLOAD_DONE", { session_token = ana.token,
    upload_id = began.upload_id }).track
assert(added.title == "Offline" and added.uploader_name == "Ana Fox")

-- No giveaway without the Bank: the clip is left out of the breaks.
server.radio.live(r).force_giveaway = true
server.state.radios[r.radio_id] = r
for _ = 1, 8 do
    local item = as(MUSIC_ID, server.radio.now, r)
    assert(item.kind ~= "giveaway", "a giveaway needs the Bank")
    bank.advanceMs(item.length_ms)
end
assert(not server.radio.live(r).giveaway)

-- The Bank is back: within a beat, giveaways come back too.
world.lose[bank.core_id] = 0
bank.advanceMs(60 * 1000)
as(MUSIC_ID, server.background.step)
local live = server.radio.live(r)
for _ = 1, 8 do
    if live.giveaway or live.wants_giveaway then break end
    local item = as(MUSIC_ID, server.radio.now, r)
    bank.advanceMs(item.length_ms)
end
assert(live.giveaway or live.wants_giveaway, "the giveaway asked for comes at the next break")
as(MUSIC_ID, server.radio.tick)
assert(live.giveaway and live.giveaway.number == r.number, "opened at the Bank")

-- A song from FoxyOS 17 -----------------------------------------------------------------------------
-- Stored the way a 17.0 Music Server did, through the Bank's Vault.

world.beatAll()
local oldBody = string.rep("o", 9000)
local old = bank.request("CLOUD_MUSIC_PUT", { server_token = registered.server_token,
    size = #oldBody, name = "song.dfpwm" })
assert(as(MUSIC_ID, music.upload, old, oldBody, config.cloud_protocol))
bank.request("CLOUD_MUSIC_PUT_DONE", { server_token = registered.server_token,
    file_id = old.file_id, version = old.version })
local legacy = as(MUSIC_ID, server.library.add, { file_id = old.file_id, size = #oldBody,
    title = "Old Song", artist = "Ana", kind = "song", uploader_name = "Ana Fox" })
local legacyPlan = as(MUSIC_ID, server.library.plan, legacy.track_id)
assert(legacyPlan.ticket:match("^CT_"), "it plays through the Bank until it is moved")
assert(as(MUSIC_ID, server.library.migrate) == true)
assert(legacy.pieces and not legacy.file_id, "on the Music Server's own pieces now")
assert(bank.vault.cloud.store().files[old.file_id] == nil, "and gone from the Vault")
local movedPlan = as(MUSIC_ID, server.library.plan, legacy.track_id)
assert(as(POCKET, net.cloud.get, movedPlan, config.cloud_protocol) == oldBody, "byte for byte")
assert(as(MUSIC_ID, server.library.migrate) == nil, "nothing left to move")

-- A piece nobody wants -------------------------------------------------------------------------------

local host = world.ids[1]
local disk = world.disks["cloud" .. host]
disk.files["cloud" .. host .. "/cloud/M1T99.1.1"] = "stray"
disk.files["cloud" .. host .. "/cloud/M7T1.1.1"] = "another server's"
local kept = 0
for name in pairs(disk.files) do if name:find("/cloud/M1T", 1, true) then kept = kept + 1 end end
as(host, world.servers[host].program.sweep)
assert(disk.files["cloud" .. host .. "/cloud/M1T99.1.1"] == nil,
    "the Music Server said nobody wants it")
assert(disk.files["cloud" .. host .. "/cloud/M7T1.1.1"],
    "a piece of a Music Server it does not know is not anybody's to judge here")
local after = 0
for name in pairs(disk.files) do if name:find("/cloud/M1T", 1, true) then after = after + 1 end end
assert(after == kept - 1, "and every song's piece is kept")

-- FoxyMusic+ ends: the Music Server hears so the next time it asks the Bank.
bank.request("MUSIC_PLUS_CANCEL", bank.as(ana))
bank.advanceDays(5)
bank.process_subscriptions()
bank.advanceMs(6 * 60 * 1000)
local lapsed = must("MUSIC_ME", { session_token = ana.token })
assert(not lapsed.music_plus and not lapsed.offline and lapsed.plays_limit == 10)
local _, _, noLonger = player(anaPlayer, ANA_PLAYER, "MUSIC_DOWNLOAD", { track_id = trot.track_id })
assert(noLonger == "NEEDS_MUSIC_PLUS")

io.write("host_music_independent_test: OK\n")
