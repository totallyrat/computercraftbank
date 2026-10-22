-- Radio Broadcasters at the Music Server, FoxyOS 18.2, end to end: a real
-- Bank Core and Vault, five real Cloud Servers and the Music Server.
--
-- Fox FM's broadcaster sets it up on 98.4 for Ana's company. It is on no
-- list: a Music Player tuned there hears static until something is queued,
-- then what the broadcaster chose, item by item. Without Radio+ it goes off
-- the air when its broadcaster stops asking. An ad break earns Company Money
-- for each listener, a giveaway is paid out of it, and Radio+ -- bought out
-- of Company Money -- keeps it on the air by itself, takes Quick Uploads
-- that play once and are gone, can be saved and Featured, and is advertised
-- on the State Radios.

package.path = "../?.lua;../?/init.lua;" .. package.path
sleep = function() end
require("config").cloud_chunk_size = 6000
local harness = require("bank_pair_harness")
local bank = harness.pair()
local config = require("config")
local net = require("lib.net")
local music = require("lib.music")

local world = require("cloud_harness").start(harness, bank)
local as, beatAll = world.as, world.beatAll
local POCKET, MUSIC_ID, BROADCASTER, PLAYER_ID, NOA_PLAYER = world.pocket, 30, 50, 40, 41
beatAll()

local ana = bank.register("Ana Fox", "1234")
local kit = bank.register("Kit Wolf", "5678")
local noa = bank.register("Noa Hare", "4321")
bank.fund(ana, 5000)
bank.fund(kit, 1000)
bank.fund(noa, 1000)

local server = world.attach(MUSIC_ID, "music_server.lua", config.music_protocol, "music_server")
local registered = bank.request("MUSIC_SERVER_REGISTER", { code = "4040" })
server.state.server_token, server.state.server_id = registered.server_token,
    registered.server_id
as(MUSIC_ID, server.background.step)
beatAll()

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
local function audio(size, seed)
    local parts = {}
    for index = 1, size do parts[index] = string.char((index * 13 + seed) % 256) end
    return table.concat(parts)
end
local function import(title, kind, size)
    return as(MUSIC_ID, server.library.import, { title = title, artist = "Foxy",
        kind = kind, uploader_name = "Foxy Records" }, audio(size or 12000, #title)).track_id
end
local songA, songB = import("Fox Trot", "song"), import("Den Beat", "song")
local host = import("Morning Hello", "host", 6000)
local ad1, ad2 = import("Buy Apples", "ad", 6000), import("Buy Pears", "ad", 6000)
local clip = import("Call Now", "giveaway", 6000)

-- Ana's company, with some money in it.
local company = bank.request("COMPANY_CREATE", bank.as(ana, { company_name = "Fox Media" }))
local companyId = company.company_id or company.company.company_id
bank.request("COMPANY_MONEY_ADD", bank.as(ana, { company_id = companyId, amount = 400,
    pin = "1234" }))
local function companyMoney()
    return bank.request("COMPANY_MONEY", bank.as(ana, { company_id = companyId }))
end

-- Setting it up ----------------------------------------------------------------------------------

local companies = must("STATION_COMPANIES", { session_token = ana.token }, BROADCASTER)
assert(companies.companies[1].company_id == companyId and not companies.companies[1].radio_plus)
refused("NOT_YOURS", "STATION_REGISTER", { session_token = kit.token, company_id = companyId,
    name = "Fox FM", frequency = 984 }, BROADCASTER)
refused("BAD_FREQUENCY", "STATION_REGISTER", { session_token = ana.token,
    company_id = companyId, name = "Fox FM", frequency = 1200 }, BROADCASTER)
local made = must("STATION_REGISTER", { session_token = ana.token, company_id = companyId,
    name = "Fox FM", frequency = 984, color = "orange" }, BROADCASTER)
assert(made.station.label == "98.4" and made.station.color == "orange")
refused("HAS_STATION", "STATION_REGISTER", { session_token = ana.token, company_id = companyId,
    name = "Fox FM 2", frequency = 990 }, BROADCASTER)
local auth = { station_id = made.station_id, station_token = made.station_token }
local function edit(extra)
    extra.station_id, extra.station_token = auth.station_id, auth.station_token
    return must("STATION_EDIT", extra, BROADCASTER).station
end
local s = server.state.stations[made.station_id]

-- On no list. Found on the dial.
for _, r in ipairs(must("MUSIC_RADIOS").radios) do assert(r.name ~= "Fox FM") end
assert(must("MUSIC_TUNE", { frequency = 984 }).station.name == "Fox FM")
assert(must("MUSIC_TUNE", { frequency = 985 }).station == nil, "nothing next to it")

-- A Music Player tuned to it ------------------------------------------------------------------------

local hello = must("MUSIC_HELLO", { session_token = kit.token, label = "Kit's Den" }, PLAYER_ID)
local function player(action, payload)
    payload = payload or {}
    payload.player_token = hello.player_token
    return must(action, payload, PLAYER_ID)
end
player("MUSIC_CONTROL", { command = "tune", frequency = 984 })
local stream = player("MUSIC_STREAM")
assert(stream.mode == "static" and stream.station.name == "Fox FM",
    "nothing queued and no Radio+: static")
assert(player("MUSIC_TICK").player.frequency_label == "98.4")

edit({ op = "add", type = "song", track_id = songA })
edit({ op = "add", type = "break", track_id = host })
stream = player("MUSIC_STREAM")
assert(stream.mode == "radio" and stream.item.title == "Fox Trot" and stream.plan.ticket,
    "what the broadcaster queued, straight away")
assert(#edit({ op = "loop", on = false }).playlist == 1, "Fox Trot is on; the break is next")
local songMs = stream.item.length_ms
bank.advanceMs(songMs + 100)
stream = player("MUSIC_STREAM")
assert(stream.item.kind == "host" and stream.item.label == "ON AIR")
-- Not a song: refused.
refused("NOT_FOUND", "STATION_EDIT", { station_id = auth.station_id,
    station_token = auth.station_token, op = "add", type = "song", track_id = host }, BROADCASTER)

-- No Radio+, and its broadcaster stops: off the air.
bank.advanceMs(61000)
stream = player("MUSIC_STREAM")
assert(stream.mode == "static" and not stream.station.on_air, "off the air")
must("STATION_VIEW", auth, BROADCASTER)
assert(player("MUSIC_STREAM").mode == "static" and player("MUSIC_STREAM").station.on_air,
    "back on, with nothing to play")

-- An ad break, paid per listener ------------------------------------------------------------------

local noaHello = must("MUSIC_HELLO", { session_token = noa.token, label = "Noa" }, NOA_PLAYER)
must("MUSIC_CONTROL", { player_token = noaHello.player_token, command = "tune",
    frequency = 984 }, NOA_PLAYER)
-- Pia is tuned in too, but paused: she is not listening, and is not paid for.
local pia = bank.register("Pia Lynx", "2468")
local piaHello = must("MUSIC_HELLO", { session_token = pia.token, label = "Pia" }, NOA_PLAYER + 1)
must("MUSIC_CONTROL", { player_token = piaHello.player_token, command = "tune",
    frequency = 984 }, NOA_PLAYER + 1)
must("MUSIC_CONTROL", { player_token = piaHello.player_token, command = "pause" }, NOA_PLAYER + 1)
bank.advanceMs(1000)
local before = companyMoney().balance
edit({ op = "add", type = "ads", track_ids = { ad1, ad2 } })
stream = player("MUSIC_STREAM")
assert(stream.item.kind == "ad" and stream.item.label == "ADVERTISEMENT")
must("MUSIC_TICK", { player_token = noaHello.player_token }, NOA_PLAYER)
must("MUSIC_TICK", { player_token = piaHello.player_token }, NOA_PLAYER + 1)
as(MUSIC_ID, server.station.tick)
assert(companyMoney().balance == before + 50, "two listeners, 25 each: "
    .. companyMoney().balance - before)
assert(s.last_ad.paid == 50 and s.last_ad.listeners == 2)
bank.advanceMs(stream.item.length_ms + 50)
assert(player("MUSIC_STREAM").item.title == "Buy Pears", "the break's second ad")

-- A giveaway, out of Company Money -----------------------------------------------------------------

bank.advanceMs(10000)
must("STATION_VIEW", auth, BROADCASTER)
before = companyMoney().balance
edit({ op = "add", type = "giveaway", track_id = clip, prize = 120 })
assert(player("MUSIC_STREAM").item.kind == "giveaway")
as(MUSIC_ID, server.station.tick)
local view = must("STATION_VIEW", auth, BROADCASTER).station
assert(view.giveaway and view.giveaway.number, "the lines are open")
assert(companyMoney().reserved == 120)
bank.request("PHONE_CALL", bank.as(noa, { number = view.giveaway.number }))
bank.advanceMs(200 * 1000)
must("STATION_VIEW", auth, BROADCASTER)
as(MUSIC_ID, server.station.tick)
view = must("STATION_VIEW", auth, BROADCASTER).station
assert(view.winner and view.winner.name == "Noa Hare" and view.winner.prize == 120)
assert(companyMoney().balance == before - 120 and companyMoney().reserved == 0)

-- Radio+ ----------------------------------------------------------------------------------------------

local began = ask("STATION_UPLOAD_BEGIN", { station_id = auth.station_id,
    station_token = auth.station_token, size = 6000, title = "Hello" }, BROADCASTER)
assert(not began, "Quick Upload is Radio+ only")
bank.request("RADIO_PLUS_START", bank.as(ana, { company_id = companyId }))
server.station.plus_at = 0
as(MUSIC_ID, server.station.tick)
assert(s.plus, "the Music Server hears of it")
-- On by itself: no playlist, no broadcaster, and still playing.
edit({ op = "clear" })
bank.advanceMs(5 * 60 * 1000)
stream = player("MUSIC_STREAM")
assert(stream.mode == "radio" and stream.station.on_air and stream.station.plus,
    "Radio+ plays round the clock")
-- Quick Upload: into the playlist, aired once, then gone.
began = must("STATION_UPLOAD_BEGIN", { station_id = auth.station_id,
    station_token = auth.station_token, size = 6000, title = "Hello Fox Town" }, BROADCASTER)
assert(as(BROADCASTER, music.upload, began.plan, audio(6000, 9), config.cloud_protocol))
view = must("STATION_UPLOAD_DONE", { station_id = auth.station_id,
    station_token = auth.station_token, upload_id = began.upload_id }, BROADCASTER).station
assert(view.playlist[1].type == "clip" and view.playlist[1].title == "Hello Fox Town")
edit({ op = "skip" })
stream = player("MUSIC_STREAM")
assert(stream.item.kind == "clip" and stream.item.title == "Hello Fox Town", "on air")
local clipId = stream.item.clip_id or next(server.state.clips)
assert(server.state.clips[clipId])
bank.advanceMs(stream.item.length_ms + 100)
player("MUSIC_STREAM")
assert(not server.state.clips[clipId], "and gone once it has played")

-- Saved, Featured, and advertised on a State Radio.
local favorites = must("MUSIC_FAVORITES", { saved = { auth.station_id } })
assert(favorites.saved[1].name == "Fox FM" and favorites.featured.name == "Fox FM")
local state = as(MUSIC_ID, server.radio.create, "Foxy State", "red")
state.songs = { songA, songB }
local promo = as(MUSIC_ID, server.radio.public, state)
assert(promo.promo and promo.promo.name == "Fox FM" and promo.promo.label == "98.4",
    "Fox FM, on the State Radio")

-- Moving and going off the air for good.
refused("BAD_FREQUENCY", "STATION_EDIT", { station_id = auth.station_id,
    station_token = auth.station_token, op = "frequency", frequency = 1200 }, BROADCASTER)
-- Kit's company has a station too, on 101.2: Fox FM cannot have that.
local kitCompany = bank.request("COMPANY_CREATE", bank.as(kit, { company_name = "Wolf Sound" }))
local wolf = must("STATION_REGISTER", { session_token = kit.token,
    company_id = kitCompany.company_id or kitCompany.company.company_id, name = "Wolf FM",
    frequency = 1012 }, BROADCASTER + 1)
refused("FREQUENCY_TAKEN", "STATION_EDIT", { station_id = auth.station_id,
    station_token = auth.station_token, op = "frequency", frequency = 1012 }, BROADCASTER)
must("STATION_UNLINK", { station_id = wolf.station_id, station_token = wolf.station_token },
    BROADCASTER + 1)
edit({ op = "frequency", frequency = 1012 })
assert(player("MUSIC_STREAM").mode == "static", "Kit's player is on 98.4, which is empty now")
player("MUSIC_CONTROL", { command = "station", station_id = auth.station_id })
assert(player("MUSIC_TICK").player.frequency_label == "101.2", "found again by its id")
must("STATION_UNLINK", auth, BROADCASTER)
refused("STATION_AUTH", "STATION_VIEW", auth, BROADCASTER)

io.write("host_radio_station_test: OK\n")
