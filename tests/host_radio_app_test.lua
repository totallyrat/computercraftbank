-- The Radio app, FoxyOS 18.2, on a 26x20 Pocket: the real app with the real
-- api.music, against a real Bank Core and Vault, five real Cloud Servers and
-- the Music Server. Every draw is bounds-checked and every tap lands only on
-- something that is on the screen.
--
-- Ana turns the dial: 98.4 is static. A tenth up is Fox FM, a Radio+
-- station, and her Music Player is on it at once; she saves it. The far end
-- of the slider is static again. Favorites has the State Radio, Fox FM as
-- today's Featured station and in her saved ones; a tap on either plays it,
-- and x forgets a saved one.

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
local olive = bank.register("Olive Owner", "9999")
bank.fund(olive, 1000)
local MUSIC_ID, PLAYER_ID, BROADCASTER = 30, 40, 50
local server = world.attach(MUSIC_ID, "music_server.lua", config.music_protocol, "music_server")
local registered = bank.core.actions.MUSIC_SERVER_REGISTER({ code = "4040" }, MUSIC_ID)
server.state.server_token, server.state.server_id = registered.server_token,
    registered.server_id
as(MUSIC_ID, server.background.step)
world.beatAll()
local trot = as(MUSIC_ID, server.library.import, { title = "Fox Trot", artist = "Ana",
    kind = "song", uploader_name = "Foxy Records" }, string.rep("t", 9000))
local state = as(MUSIC_ID, server.radio.create, "Foxy State", "lime")
state.songs = { trot.track_id }

-- Fox FM, Olive's company's station, with Radio+.
local company = bank.request("COMPANY_CREATE", bank.as(olive, { company_name = "Fox Media" }))
local companyId = company.company_id or company.company.company_id
bank.request("COMPANY_MONEY_ADD", bank.as(olive, { company_id = companyId, amount = 200,
    pin = "9999" }))
bank.request("RADIO_PLUS_START", bank.as(olive, { company_id = companyId }))
local made = as(BROADCASTER, net.ask, MUSIC_ID, config.music_protocol, "STATION_REGISTER",
    { session_token = olive.token, company_id = companyId, name = "Fox FM",
      frequency = 985 }, 3)
assert(made and server.state.stations[made.station_id].plus, "Fox FM, with Radio+")

-- Ana's Music Player.
local hello = as(PLAYER_ID, net.ask, MUSIC_ID, config.music_protocol, "MUSIC_HELLO",
    { session_token = ana.token, label = "Ana's Den" }, 3)
local playerId = hello.player.player_id
local function player() return server.state.players[playerId] end

local kept = {}
local function run(script, wanted)
    return phone.run({ bank = bank, who = ana, file = "../radio.lua", app_id = "RADIO",
        script = script, wanted = wanted, kept = kept,
        api = {
            music = function(api)
                return net.musicApi(config, function() return ana.token end,
                    function() return false end, function()
                        local where = api.request("MUSIC_WHERE", {})
                        return where and where.computer_id
                    end)
            end,
        } })
end

-- The dial ------------------------------------------------------------------------------------------

local script = phone.script()
phone.push(script.actions, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "~ static ~") and phone.has(frame, "Plays on Ana's Den"),
        "98.4: nothing there")
    return "up"
end, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "Fox FM  RADIO+") and phone.has(frame, "Fox Trot"),
        "a tenth up: Fox FM, shown clearly\n" .. table.concat(frame, "\n"))
    assert(player().mode == "station" and player().frequency == 985,
        "and the Music Player is on it")
    return "save"
end, function(seen)
    assert(phone.has(phone.last(seen), "SAVED"))
    return "dial:1080"
end, function(seen)
    assert(phone.has(phone.last(seen), "~ static ~") and player().frequency == 1080,
        "the far end of the slider")
    return "tab:favorites"
end, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "STATE RADIOS") and phone.has(frame, "Foxy State"))
    assert(phone.has(frame, "FEATURED TODAY") and phone.has(frame, "SAVED"))
    return "station:" .. made.station_id
end, function(seen)
    assert(phone.said(seen, "Playing") and player().frequency == 985,
        "a saved station, by its id")
    return "radio:" .. state.radio_id
end, function(seen)
    assert(player().mode == "radio" and player().radio_id == state.radio_id, "a State Radio")
    return "forget:" .. made.station_id
end, function(seen)
    assert(#kept.value.saved == 0, "forgotten")
    return "home"
end)
run(script)
assert(kept.value.frequency == 985, "the dial is kept where it was")

-- A station without Radio+ cannot be saved: it has to be found each time.
bank.request("RADIO_PLUS_CANCEL", bank.as(olive, { company_id = companyId }))
server.state.stations[made.station_id].plus = false
script = phone.script()
phone.push(script.actions, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "Fox FM") and not phone.has(frame, "SAVE"),
        table.concat(frame, "\n"))
    return "home"
end)
run(script)

io.write("host_radio_app_test: OK\n")
