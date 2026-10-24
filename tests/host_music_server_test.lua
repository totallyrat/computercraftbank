-- The Music Server, FoxyOS 17, end to end: a real Bank Core and Vault, five
-- real Cloud Servers, and the Music Server on the same network. Songs go to
-- the Cloud Servers under the library's name and come back byte for byte; a
-- listener's songs are counted by the Bank and radios are not; a radio's
-- timeline has its breaks -- hosts, ads every few songs, giveaways and
-- specials -- and a giveaway opens at the Bank, where listeners call in; a
-- CCG Casino plays only while its owner has FoxyCloud+.

package.path = "../?.lua;../?/init.lua;" .. package.path
sleep = function() end
require("config").cloud_chunk_size = 6000
local harness = require("bank_pair_harness")
local rejected = harness.rejected
local bank = harness.pair()
local config = require("config")
local util = require("lib.util")
local net = require("lib.net")
local music = require("lib.music")

local world = require("cloud_harness").start(harness, bank)
local as, beatAll, heldTotal = world.as, world.beatAll, world.heldTotal
local POCKET = world.pocket
local MUSIC_ID = 30
beatAll()

local ana = bank.register("Ana Fox", "1234")
local kit = bank.register("Kit Wolf", "5678")
bank.fund(ana, 5000)

-- The Music Server comes up, and registers with the operator code.
local server = world.attach(MUSIC_ID, "music_server.lua", config.music_protocol, "music_server")
local registered = bank.request("MUSIC_SERVER_REGISTER", { code = "4040" })
server.state.server_token, server.state.server_id = registered.server_token,
    registered.server_id
-- FoxyOS 18: its first beat tells the Bank which computer it is, and finds the
-- Cloud Servers; theirs tell them, and they keep it.
as(MUSIC_ID, server.background.step)
assert(#server.store.servers == 5, "five Cloud Servers found on the network")
beatAll()
for _, id in ipairs(world.ids) do
    assert(world.servers[id].program.state.music_servers.MS1 == MUSIC_ID,
        "every Cloud Server knows which computer the Music Server is")
end

-- What a Pocket or a Music Player says to it, over the network.
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
    return err
end

local function audio(size, seed)
    local parts = {}
    for index = 1, size do parts[index] = string.char((index * 13 + seed) % 256) end
    return table.concat(parts)
end

-- The Music Server's own import ---------------------------------------------------------------

local heldBefore = heldTotal()
local song = audio(15000, 1)
local imported = as(MUSIC_ID, server.library.import, { title = "Fox Trot", artist = "Ana",
    kind = "song", uploader_name = "Foxy Records" }, song)
assert(imported and imported.track_id == "T1" and imported.uploader_name == "Foxy Records")
assert(heldTotal() == heldBefore + 3, "three pieces of 6000 on the Cloud Servers")
-- FoxyOS 18: the Music Server's own pieces, placed by it, with no file at the Bank.
assert(imported.pieces[1].id == "M1T1.1.1" and not imported.file_id)
local onServers = {}
for _, piece in ipairs(imported.pieces) do onServers[piece.hosts[1]] = true end
local spread = 0
for _ in pairs(onServers) do spread = spread + 1 end
assert(spread == 3, "each piece on the server with the most room")
local plan = as(MUSIC_ID, server.library.plan, "T1")
assert(as(POCKET, net.cloud.get, plan, config.cloud_protocol) == song, "byte for byte")
assert(plan.expires_in_ms >= 15000 / 6 + 5 * 60 * 1000, "a ticket lasts the song and more")
-- Only a ticket the Music Server issued opens a song: one nobody issued is
-- refused when the Cloud Server asks it.
local forged = { ticket = "MT_made_up", chunks = plan.chunks, hosts = plan.hosts }
local _, _, forgedCode = as(POCKET, net.cloud.get, forged, config.cloud_protocol)
assert(forgedCode == "BAD_TICKET", tostring(forgedCode))
-- And a Cloud Server believes only the computer the Bank named: one that has
-- not been told yet believes nobody.
local firstHost = plan.hosts[plan.chunks[1].servers[1]]
local keptTrust = world.servers[firstHost].program.state.music_servers
world.servers[firstHost].program.state.music_servers = {}
world.servers[firstHost].program.tickets[plan.ticket] = nil
local _, _, untrusted = as(POCKET, net.ask, firstHost, config.cloud_protocol, "CHUNK_GET",
    { ticket = plan.ticket, chunk_id = plan.chunks[1].id }, 3)
assert(untrusted == "BAD_TICKET")
world.servers[firstHost].program.state.music_servers = keptTrust
-- The Bank's own music storage (FoxyOS 17) still answers only a Music Server.
rejected(bank.request, "MUSIC_AUTH", "CLOUD_MUSIC_GET", bank.as(ana, { file_id = "F1" }))
rejected(bank.vault.actions.CLOUD_MUSIC_GET, "MUSIC_AUTH", { file_id = "F1" },
    { kind = "session", account_id = ana.id })

local function import(title, artist, kind, size)
    local track = as(MUSIC_ID, server.library.import, { title = title, artist = artist,
        kind = kind, uploader_name = "Foxy Records" }, audio(size or 6000, #title))
    assert(track, "imported " .. title)
    return track
end
local s2 = import("Moon Howl", "Kit", "song")
local s3 = import("Den Beat", "Ana", "song")
local s4 = import("Tail Spin", "Bo", "song")
local host = import("Morning Host", "DJ Fox", "host", 3000)
local ad = import("Buy Carrots", "Carrot Co", "ad", 3000)
local give = import("Giveaway Time", "DJ Fox", "giveaway", 3000)

-- Listeners see songs, never hosts, ads or giveaway clips.
local listed = must("MUSIC_LIBRARY", {})
assert(listed.total == 4, "four songs, " .. listed.total)
assert(listed.tracks[1].track_id == s4.track_id, "newest first")
assert(must("MUSIC_LIBRARY", { query = "moon" }).tracks[1].title == "Moon Howl")
assert(must("MUSIC_LIBRARY", { sort = "title" }).tracks[1].title == "Den Beat")

-- Uploading from a Pocket ----------------------------------------------------------------------
-- The Bank says whether today allows it and where the pieces go; they go
-- there from the Pocket, and the song is credited to who sent it.

local function upload(who, title, body)
    local began, err, code = ask("MUSIC_UPLOAD_BEGIN", { session_token = who.token,
        title = title, artist = who.name, size = #body, genre = "Pop" })
    if not began then return nil, err, code end
    assert(as(POCKET, music.upload, began.plan, body, config.cloud_protocol))
    return must("MUSIC_UPLOAD_DONE", { session_token = who.token,
        upload_id = began.upload_id }).track
end
local mine = upload(kit, "Kit Song", audio(7000, 5))
assert(mine.uploader_name == "Kit Wolf" and mine.kind == "song")
assert(upload(kit, "Kit Song 2", audio(100, 6)))
local _, limitText, limitCode = upload(kit, "Kit Song 3", audio(100, 7))
assert(limitCode == "UPLOAD_LIMIT" and limitText:find("FoxyMusic%+"), "two a day for free")
refused("TOO_BIG", "MUSIC_UPLOAD_BEGIN", { session_token = ana.token, title = "Huge",
    size = config.music_max_bytes + 1 })
refused("SIGN_IN", "MUSIC_UPLOAD_BEGIN", { title = "Nobody", size = 10 })
-- An upload that is someone else's cannot be finished by them.
local began = must("MUSIC_UPLOAD_BEGIN", { session_token = ana.token, title = "Mine",
    size = 10, genre = "Pop" })
refused("NOT_UPLOADING", "MUSIC_UPLOAD_DONE", { session_token = kit.token,
    upload_id = began.upload_id })

-- A Music Player --------------------------------------------------------------------------------

local PLAYER_ID = 40
local hello = must("MUSIC_HELLO", { session_token = kit.token, label = "Kit's Den" }, PLAYER_ID)
assert(hello.player.label == "Kit's Den" and hello.player.mode == "idle")
local token = hello.player_token
local function player(action, payload)
    payload = payload or {}
    payload.player_token = token
    return ask(action, payload, PLAYER_ID)
end
refused("NOT_A_PLAYER", "MUSIC_TICK", { player_token = "MP_nope" }, PLAYER_ID)

-- The Pocket sees it and tells it what to play.
local players = must("MUSIC_PLAYERS", { session_token = kit.token }).players
assert(#players == 1 and players[1].online and players[1].player_id == hello.player.player_id)
assert(#must("MUSIC_PLAYERS", { session_token = ana.token }).players == 0, "only your own")
refused("NOT_YOURS", "MUSIC_CONTROL", { session_token = ana.token,
    player_id = hello.player.player_id, command = "stop" })
local queue = { "T1", s2.track_id, s3.track_id }
local playing = must("MUSIC_CONTROL", { session_token = kit.token,
    player_id = hello.player.player_id, command = "play", track_id = s2.track_id,
    queue = queue }).player
assert(playing.mode == "library" and playing.now.track_id == s2.track_id and playing.index == 2)

-- FoxyOS 18: counted on the Music Server, which needs no Bank to do it.
local function plays(who)
    local usage = server.state.usage[who.id]
    return usage and usage.plays or 0
end
local stream = assert(player("MUSIC_STREAM"))
assert(stream.item.track_id == s2.track_id and stream.offset_ms == 0)
assert(as(PLAYER_ID, net.cloud.get, stream.plan, config.cloud_protocol) == audio(6000,
    #"Moon Howl"), "the player fetches the song itself")
assert(plays(kit) == 1, "counted when it starts")
assert(player("MUSIC_STREAM"), "asked again")
assert(plays(kit) == 1, "the same play is counted once")
-- Paused and resumed, from where it was.
assert(player("MUSIC_TICK", { position_ms = 4000, play_no = stream.play_no }))
must("MUSIC_CONTROL", { player_token = token, command = "pause" }, PLAYER_ID)
refused("PAUSED", "MUSIC_STREAM", { player_token = token }, PLAYER_ID)
must("MUSIC_CONTROL", { player_token = token, command = "resume" }, PLAYER_ID)
local resumed = assert(player("MUSIC_STREAM"))
assert(resumed.offset_ms == 4000 and plays(kit) == 1, "resuming is not another play")
-- The song ran out: the next one in the queue, and that one counts.
local after = assert(player("MUSIC_NEXT", { play_no = stream.play_no })).player
assert(after.now.track_id == s3.track_id)
assert(player("MUSIC_NEXT", { play_no = stream.play_no }).player.now.track_id == s3.track_id,
    "a second 'it ran out' for the same song moves nothing")
assert(player("MUSIC_STREAM") and plays(kit) == 2)

-- Ten a day free; then the player stops and says why.
server.state.usage[kit.id].plays = 10
must("MUSIC_CONTROL", { player_token = token, command = "next" }, PLAYER_ID)
assert(must("MUSIC_CONTROL", { player_token = token, command = "play",
    track_id = s4.track_id }, PLAYER_ID))
local _, stopped, stoppedCode = player("MUSIC_STREAM")
assert(stoppedCode == "MUSIC_LIMIT" and stopped:find("Radios are free"))
local quiet = assert(player("MUSIC_TICK")).player
assert(quiet.mode == "idle" and quiet.notice == stopped)

-- Radios ------------------------------------------------------------------------------------------

local r = as(MUSIC_ID, server.radio.create, "Foxy FM", "orange")
assert(r.radio_id == "R1" and r.number and r.number:match("^%d%d%d%-%d%d%d%d$"),
    "the Bank gives every radio a number")
r.songs = { "T1", s2.track_id, s3.track_id, s4.track_id }
r.hosts, r.ads, r.giveaways = { host.track_id }, { ad.track_id }, { give.track_id }

-- A fixed draw, so the timeline is known: no host, no special, no giveaway
-- by chance; ads every two songs.
r.host_chance, r.giveaway_chance, r.ads_every = 0, 0, 2
local realRandom = math.random
math.random = function(low, high) return low end
local function walk(count)
    local kinds = {}
    for _ = 1, count do
        local item = as(MUSIC_ID, server.radio.now, r)
        kinds[#kinds + 1] = item.kind
        bank.advanceMs(item.length_ms)
    end
    return table.concat(kinds, " ")
end
assert(walk(7) == "song song ad song song ad song", walk(0))
-- A song is never one of the last few again while others are waiting.
local seen = {}
for _ = 1, 4 do
    local item = as(MUSIC_ID, server.radio.now, r)
    if item.kind == "song" then
        assert(not seen[item.track_id], "no repeats among four songs")
        seen[item.track_id] = true
    end
    bank.advanceMs(item.length_ms)
end

-- Hosts between songs, and the specials they announce.
r.ads_every, r.host_chance = 99, 100
server.live[r.radio_id] = nil
local special = 0
math.random = function(low, high)
    special = special + 1
    if high == 3 then return 1 end -- which special: 20 Minute Non-Stop
    return low
end
assert(walk(2) == "song host", "a host after a song")
local live = server.live[r.radio_id]
assert(live.special and live.special.name == "20 MINUTE NON-STOP")
assert(walk(6) == "song song song song song song", "Non-Stop is songs and nothing else")
bank.advanceMs(20 * 60 * 1000)
assert(walk(2) == "song host", "and then it ends")

-- A giveaway, asked for at the Music Server. It opens at the Bank when its
-- clip starts, and the number is in Now Playing.
math.random = realRandom
-- (That host started another special: specials off for the rest.)
r.host_chance, r.specials, live.special = 0, false, nil
live.force_giveaway = true
local function untilKind(kind)
    for _ = 1, 10 do
        local item = as(MUSIC_ID, server.radio.now, r)
        if item.kind == kind then return item end
        bank.advanceMs(item.length_ms)
    end
    error("never a " .. kind)
end
-- (A giveaway is the Bank's: the Music Server plays its clip only while the
-- Bank has answered in the last two minutes. Its beat is that answer.)
as(MUSIC_ID, server.background.step)
untilKind("giveaway")
as(MUSIC_ID, server.radio.tick)
assert(live.giveaway and live.giveaway.number == r.number, "open at the Bank")
local tuned = must("MUSIC_CONTROL", { player_token = token, command = "radio",
    radio_id = r.radio_id }, PLAYER_ID).player
assert(tuned.radio.giveaway.number == r.number, "Now Playing shows the number to call")
local onAir = assert(player("MUSIC_STREAM"))
assert(onAir.mode == "radio" and onAir.item.kind == "giveaway" and onAir.offset_ms >= 0)
assert(plays(kit) == 10, "radios are free")
-- Listeners call in.
bank.fund(kit, 500)
for _ = 1, 2 do bank.request("PHONE_CALL", bank.as(kit, { number = r.number })) end
bank.advanceMs(config.giveaway_seconds * 1000 + 2000)
local kitBefore = bank.balanceOf(kit)
as(MUSIC_ID, server.radio.tick)
assert(not live.giveaway and live.winner and live.winner.name == "Kit Wolf",
    "the only caller wins")
assert(bank.balanceOf(kit) - kitBefore >= 100 and bank.balanceOf(kit) - kitBefore <= 500)
assert(must("MUSIC_RADIOS", {}).radios[1].winner.name == "Kit Wolf")

-- Skipping on the Music Server moves everybody on.
local before = as(MUSIC_ID, server.radio.now, r)
before.length_ms = 1
bank.advanceMs(5)
assert(as(MUSIC_ID, server.radio.now, r) ~= before)

-- A CCG Casino --------------------------------------------------------------------------------
-- Its owner picks a song or a radio and the casino is given a grant, never
-- the owner's session. FoxyCloud+ is needed, now and while it plays.

refused("NEEDS_PLUS", "MUSIC_GRANT", { session_token = kit.token, kind = "radio",
    id = r.radio_id })
bank.request("CLOUD_PLUS_JOIN", bank.as(ana, { pin = "1234" }))
local grant = must("MUSIC_GRANT", { session_token = ana.token, kind = "radio",
    id = r.radio_id, casino_id = "C1" })
assert(grant.label == "Foxy FM" and grant.grant)
local CASINO_ID = 50
local casino = assert(ask("MUSIC_STREAM", { grant = grant.grant }, CASINO_ID))
assert(casino.mode == "radio" and casino.radio.name == "Foxy FM")
local songGrant = must("MUSIC_GRANT", { session_token = ana.token, kind = "track",
    id = "T1", casino_id = "C1" })
refused("NO_GRANT", "MUSIC_STREAM", { grant = grant.grant }, CASINO_ID)
assert(must("MUSIC_STREAM", { grant = songGrant.grant }, CASINO_ID).item.track_id == "T1")
-- Her plan ends: within a minute, the casino goes quiet.
bank.state.accounts[ana.id].foxycloud = nil
bank.advanceMs(61000)
refused("NEEDS_PLUS", "MUSIC_STREAM", { grant = songGrant.grant }, CASINO_ID)

-- Deleting a track -----------------------------------------------------------------------------

local piecesBefore = heldTotal()
assert(as(MUSIC_ID, server.library.remove, "T1"))
for _, id in ipairs(r.songs) do assert(id ~= "T1", "gone from the radio") end
-- FoxyOS 18: the Music Server takes its pieces back itself, from the
-- background.
assert(#server.state.drops == 3)
as(MUSIC_ID, server.background.step)
assert(#server.state.drops == 0 and heldTotal() == piecesBefore - 3,
    "and its pieces from the Cloud Servers")
assert(must("MUSIC_LIBRARY", {}).total == 5)

-- Signing a player out ---------------------------------------------------------------------------
assert(player("MUSIC_BYE"))
refused("NOT_A_PLAYER", "MUSIC_TICK", { player_token = token }, PLAYER_ID)

io.write("host_music_server_test: OK\n")
