-- The Music Player, FoxyOS 17, and the streaming under it.
--
-- First lib/music on its own: a song is played piece by piece from where it
-- was asked to start, every speaker gets every piece in order, a speaker that
-- is full is waited for, and a piece that does not come stops it with why.
--
-- Then the Music Player for real -- its real screens on a 51x19 computer --
-- on a network with a real Bank, five Cloud Servers and a Music Server:
-- signing in with a Foxy name and PIN, playing a song from the Library tab
-- through its speaker, tuning in on the Radio tab, Now Playing showing the
-- number to call in a giveaway (and the monitor beside it too), and signing
-- out.

package.path = "../?.lua;../?/init.lua;" .. package.path
sleep = function() end
require("config").cloud_chunk_size = 6000
local harness = require("bank_pair_harness")
local bank = harness.pair()
local config = require("config")
local util = require("lib.util")
local net = require("lib.net")
local music = require("lib.music")

-- A DFPWM decoder that only says which bytes it was given: sample n is the
-- n-th byte, eight times over.
local decoded = {}
local fakeDfpwm = { make_decoder = function()
    return function(data)
        decoded[#decoded + 1] = data
        local samples = {}
        for index = 1, #data * 8 do samples[index] = data:byte(math.floor((index - 1) / 8) + 1) end
        return samples
    end
end }
package.loaded["cc.audio.dfpwm"] = fakeDfpwm

local function speaker(fullTimes)
    local heard = { calls = 0, samples = 0, full = fullTimes or 0 }
    heard.playAudio = function(samples, volume)
        heard.calls = heard.calls + 1
        if heard.full > 0 then
            heard.full = heard.full - 1
            return false
        end
        heard.samples, heard.volume = heard.samples + #samples, volume
        heard.last = samples
        return true
    end
    heard.stop = function() heard.stopped = true end
    return heard
end

-- 1. lib/music on its own ------------------------------------------------------------------

do
    local pieces = { ["F1.1.1"] = string.rep("a", 6000), ["F1.1.2"] = string.rep("b", 6000),
        ["F1.1.3"] = string.rep("c", 500) }
    local plan = { ticket = "T", hosts = { CS1 = 11 }, chunks = {
        { id = "F1.1.1", size = 6000, servers = { "CS1" } },
        { id = "F1.1.2", size = 6000, servers = { "CS1" } },
        { id = "F1.1.3", size = 500, servers = { "CS1" } } } }
    local realAsk = net.cloud.ask
    local asked = {}
    net.cloud.ask = function(_, serverId, action, payload)
        asked[#asked + 1] = payload.chunk_id
        assert(action == "CHUNK_GET" and payload.ticket == "T" and serverId == "CS1")
        return { data = pieces[payload.chunk_id] }
    end
    local waited = 0
    local realPull, realTimer = os.pullEvent, os.startTimer
    os.startTimer = function() return 7 end
    os.pullEvent = function()
        waited = waited + 1
        return "speaker_audio_empty", "left"
    end
    local left, right = speaker(), speaker(1)
    assert(music.play(plan, { left, right }, { volume = function() return 1.5 end }))
    assert(table.concat(asked, " ") == "F1.1.1 F1.1.2 F1.1.3", "every piece, in order")
    assert(left.samples == 12500 * 8 and right.samples == 12500 * 8, "both speakers, all of it")
    assert(left.volume == 1.5, "at the player's volume")
    assert(waited == 1 and right.calls == 4, "a full speaker is waited for, then given it")

    -- From a second in: 6000 bytes, so the second piece, whole. The first is
    -- never fetched.
    asked, decoded = {}, {}
    local late = speaker()
    assert(music.play(plan, { late }, { offset_ms = 1000 }))
    assert(table.concat(asked, " ") == "F1.1.2 F1.1.3", table.concat(asked, " "))
    assert(#decoded[1] == 6000, "a second is exactly the second piece")
    asked, decoded = {}, {}
    assert(music.play(plan, { speaker() }, { offset_ms = 1500 }))
    assert(#decoded[1] == 3000 and decoded[1]:sub(1, 1) == "b", "half way into it")
    assert(music.play(plan, { speaker() }, { offset_ms = 99999 }), "past the end is the end")

    -- A piece too big for one speaker call goes in turns.
    pieces["F1.1.1"] = string.rep("z", 20000)
    plan.chunks[1].size = 20000
    local big = speaker()
    assert(music.play(plan, { big }))
    assert(big.calls == 4 and big.samples == 26500 * 8, "131072 samples at most at once")

    -- A Cloud Server that does not answer.
    net.cloud.ask = function() return nil, "A Cloud Server is not answering", "CLOUD_OFFLINE" end
    local ok, err, code = music.play(plan, { speaker() })
    assert(ok == nil and code == "CLOUD_OFFLINE" and err)
    net.cloud.ask = realAsk
    os.pullEvent, os.startTimer = realPull, realTimer

    assert(music.clock(185000) == "3:05" and music.clock(3723000) == "1:02:03")
    assert(music.lengthMs(6000) == 1000)
    assert(music.titleFrom("/disk/Fox_Trot.DFPWM") == "Fox Trot")
    assert(music.isAudio("a.dfpwm") and not music.isAudio("a.mid"))
end

-- 2. The Music Player ------------------------------------------------------------------------

local world = require("cloud_harness").start(harness, bank)
local as = world.as
world.beatAll()
local kit = bank.register("Kit Wolf", "5678")
local MUSIC_ID, PLAYER_ID = 30, 40
local server = world.attach(MUSIC_ID, "music_server.lua", config.music_protocol, "music_server")
local registered = bank.request("MUSIC_SERVER_REGISTER", { code = "4040" })
server.state.server_token, server.state.server_id = registered.server_token,
    registered.server_id
as(MUSIC_ID, server.background.step)
world.beatAll()
local function import(title, kind, size)
    return as(MUSIC_ID, server.library.import, { title = title, artist = "Foxy",
        kind = kind, uploader_name = "Foxy Records" }, string.rep(title:sub(1, 1), size or 9000))
end
local trot = import("Trot", "song")
import("Howl", "song")
local give = import("Giveaway", "giveaway", 3000)
local r = as(MUSIC_ID, server.radio.create, "Foxy FM", "lime")
r.songs, r.giveaways, r.host_chance, r.giveaway_chance = { trot.track_id }, { give.track_id }, 0, 0

-- Its computer: a 51x19 screen, a speaker on the left and a monitor on top.
local screen = dofile("screen_harness.lua")
local computer = screen.terminal(51, 19)
local wall = screen.terminal(29, 12)
local box = speaker()
peripheral = {
    getNames = function() return { "back", "left", "top" } end,
    getType = function(name)
        return ({ back = "modem", left = "speaker", top = "monitor" })[name]
    end,
    wrap = function(name) return ({ left = box, top = wall })[name] end,
}
term = { current = function() return computer end }
parallel = { waitForAny = function(first) first() end }
-- Told to change what it plays: the audio half hears it as an event.
local queued = {}
os.queueEvent = function(name) queued[#queued + 1] = name end
local steps = {}
local ui, screenState = screen.install({ display = computer, steps = steps,
    event = "mouse_click" })
package.loaded["lib.ui"] = ui
local player = world.attach(PLAYER_ID, "music_player.lua", "PLAYER_ONLY", "music_player")
-- Another computer has taken the Music Server's name. A Music Player about
-- to hand over a session asks the Bank which computer it really is.
local realLookup = rednet.lookup
rednet.lookup = function(protocol, name)
    if protocol == config.music_protocol then return 666 end
    return realLookup(protocol, name)
end

-- Signing in: name, PIN, and what to call it.
screen.push(steps, function(state)
    assert(state.display.has("YOUR NAME"), "it asks who is signing in\n" .. state.display.dump())
    return { char = "K" }
end, screen.typed("it Wolf"), { char = "5" }, { char = "6" }, { char = "7" }, { char = "8" },
    function(state)
        assert(state.display.has("NAME THIS PLAYER") and state.display.has("Kit Wolf's Player"))
        return { key = keys.backspace }
    end)
for _ = 1, 16 do screen.push(steps, { key = keys.backspace }) end
screen.push(steps, screen.typed("Kit's Den"))
assert(as(PLAYER_ID, player.signIn))
assert(player.state.player_token and player.state.owner_name == "Kit Wolf")
assert(server.state.players.P1.label == "Kit's Den" and server.state.players.P1.computer_id
    == PLAYER_ID, "the Music Server knows it, and which computer it is")
as(PLAYER_ID, player.tickOnce)
assert(player.shared.player.mode == "idle")

-- FoxyOS 18.4: the Music tab, as on a Pocket. Tap a song; what is playing
-- is along the top, and a tap there is Now Playing.
local function runScreen(...)
    screen.push(steps, ...)
    local ok, err = pcall(as, PLAYER_ID, player.screenLoop)
    assert(ok or tostring(err):find("STOP_TEST", 1, true), err)
end
local function stop() error("STOP_TEST", 0) end
runScreen(function(state)
    assert(state.display.has("Nothing playing") and state.display.has("NEW MUSIC")
        and state.display.has("Search") and state.display.has("Radio"), "\n" .. state.display.dump())
    return "now"
end, function(state)
    assert(state.display.has("Volume"), state.display.dump())
    return "back"
end, function(state)
    assert(state.display.has("Trot") and state.display.has("Howl"), state.display.dump())
    return "tile:new:2"
end, function(state)
    assert(state.display.has("> Trot - Foxy"), "playing, along the top\n" .. state.display.dump())
    return "now"
end, function(state)
    assert(state.display.has("Trot") and state.display.has("PAUSE")
        and state.display.has("(by Foxy Records)"), state.display.dump())
    stop()
end)
assert(player.shared.player.mode == "library")

-- Its speaker plays it, fetched from the Cloud Servers, and then it is over.
as(PLAYER_ID, player.audioStep)
assert(box.samples == 9000 * 8, "the whole song through the speaker: " .. box.samples)
assert(server.state.usage[kit.id].plays == 1, "one of Kit's ten today, counted on the Music Server")
assert(player.shared.player.mode == "idle", "nothing queued after it")

-- The Radio tab: tune in. A giveaway is on, and Now Playing says the number.
local live = server.radio.live(r)
live.giveaway = { giveaway_id = "G", number = r.number, closes_at = util.nowMs() + 90000 }
runScreen(function(state) return "tab:radio" end, function(state)
    -- FoxyOS 18.2: the dial on top, the State Radios under it.
    assert(state.display.has("98.4") and state.display.has("STATE RADIOS"), state.display.dump())
    assert(state.display.has("Foxy FM  GIVEAWAY " .. r.number), state.display.dump())
    return "radio:" .. r.radio_id
end, "now", function(state)
    assert(state.display.has("GIVEAWAY! Call " .. r.number .. " now"), state.display.dump())
    assert(state.display.has("Foxy FM") and state.display.has("LIVE"))
    stop()
end)
as(PLAYER_ID, player.tickOnce)
as(PLAYER_ID, player.drawMonitor)
assert(wall.has("GIVEAWAY! CALL " .. r.number) and wall.has("Foxy FM"),
    "the monitor shows it across the room\n" .. wall.dump())

-- Radios are live: no skipping, and no play counted.
local before = box.samples
-- The radio waits for the speaker to finish before asking what is next.
screenState.timers = {}
screen.push(steps, { tick = true })
as(PLAYER_ID, player.audioStep)
assert(box.samples > before, "the radio plays")
assert(server.state.usage[kit.id].plays == 1, "radios are free")

-- FoxyOS 18.2: the dial. Between stations, static out of the speaker --
-- made here, quiet, nothing fetched.
runScreen(function(state) return "tab:radio" end, function(state)
    return "up"
end, function(state)
    assert(state.display.has("98.5  ~ static ~"), state.display.dump())
    stop()
end)
assert(server.state.players[player.shared.player.player_id].frequency == 985)
as(PLAYER_ID, player.tickOnce)
before = box.samples
local loudest = 0
local realPlay = box.playAudio
box.playAudio = function(samples, volume)
    for _, sample in ipairs(samples) do loudest = math.max(loudest, math.abs(sample)) end
    return realPlay(samples, volume)
end
as(PLAYER_ID, player.audioStep)
box.playAudio = realPlay
assert(box.samples > before and loudest <= 24, "static, quietly: " .. loudest)

-- Uploading, from Me; and signing out.
runScreen(function() return "tab:me" end, function(state)
    assert(state.display.has("Kit Wolf") and state.display.has("YOUR PLAYLISTS"), state.display.dump())
    return "upload"
end, function(state)
    assert(state.display.has("Drop a .dfpwm file"), state.display.dump())
    assert(state.display.has("Today: 0 of 2 uploads"))
    return "back"
end, "signout", "yes")
assert(player.state.player_token == nil and next(server.state.players) == nil)
assert(#steps == 0, #steps .. " scripted steps never used")

-- FoxyOS 18.4.1: a Music Player updated by an older updater had no
-- lib/musicui.lua and could not start. Now it starts, says so, and the update
-- check fetches the file.
package.loaded["lib.musicui"] = nil
package.preload["lib.musicui"] = function() error("module 'lib.musicui' not found", 0) end
local broken = world.attach(PLAYER_ID + 1, "music_player.lua", "PLAYER_ONLY", "music_player")
package.preload["lib.musicui"] = nil
local realSleep = sleep
sleep = function() broken.stop() end
as(PLAYER_ID + 1, broken.screenLoop)
sleep = realSleep
assert(computer.has("Finishing the update"), "it starts, and says what it is waiting for\n"
    .. computer.dump())

io.write("host_music_player_test: OK\n")
