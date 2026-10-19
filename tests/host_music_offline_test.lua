-- Offline Listening, FoxyOS 18: songs kept on a Music Player.
--
-- First lib/music on its own: a song kept in a file plays exactly like one on
-- the Cloud Servers, from wherever it is asked to start, and a file that is
-- short or gone says so.
--
-- Then a Music Player for real -- its real screens on a 51x19 computer -- on
-- a network with a real Bank, five Cloud Servers and a Music Server. Ana is on
-- the free plan: nothing to download. She joins FoxyMusic+, keeps two songs
-- from the Library tab, and a kept song plays from the player's own disk with
-- the Cloud Servers gone. The Music Server goes off, and the Bank with it: the
-- Library shows what is kept and plays it from this screen, with pause and
-- next. The Music Server comes back and the Music app takes over. Kept songs
-- stop playing ten days after FoxyMusic+ was last confirmed, and go the
-- moment the Music Server says it has ended.

package.path = "../?.lua;../?/init.lua;" .. package.path
sleep = function() end
require("config").cloud_chunk_size = 6000
local harness = require("bank_pair_harness")
local bank = harness.pair()
local config = require("config")
local util = require("lib.util")
local net = require("lib.net")
local music = require("lib.music")

-- A DFPWM decoder that only says which bytes it was given.
local decoded = {}
package.loaded["cc.audio.dfpwm"] = { make_decoder = function()
    return function(data)
        decoded[#decoded + 1] = data
        local samples = {}
        for index = 1, #data * 8 do samples[index] = data:byte(math.floor((index - 1) / 8) + 1) end
        return samples
    end
end }

local function speaker()
    local heard = { samples = 0 }
    heard.playAudio = function(samples)
        heard.samples = heard.samples + #samples
        heard.first = heard.first or samples[1]
        return true
    end
    heard.stop = function() heard.stopped = true end
    return heard
end

local world = require("cloud_harness").start(harness, bank)
local as = world.as
world.beatAll()

-- 1. lib/music: a song in a file ---------------------------------------------------------------

do
    local body = string.rep("a", 6000) .. string.rep("b", 6000) .. string.rep("c", 100)
    local file = fs.open("/scratch/kept.dfpwm", "wb")
    file.write(body)
    file.close()
    local plan = music.keptPlan("/scratch/kept.dfpwm", #body, 6000)
    assert(#plan.chunks == 3 and plan.chunks[3].size == 100 and plan.chunks[2].at == 6000)
    local heard = speaker()
    assert(music.play(plan, { heard }))
    assert(heard.samples == #body * 8, "all of it")
    decoded = {}
    assert(music.play(plan, { speaker() }, { offset_ms = 1500 }))
    assert(#decoded[1] == 3000 and decoded[1]:sub(1, 1) == "b", "from a second and a half in")
    local ok, err, code = music.play(music.keptPlan("/scratch/kept.dfpwm", #body + 50, 6000),
        { speaker() })
    assert(ok == nil and code == "DAMAGED" and err)
    assert(select(3, music.play(music.keptPlan("/scratch/none.dfpwm", 10), { speaker() }))
        == "MISSING")
end

-- 2. The network ---------------------------------------------------------------------------------

local ana = bank.register("Ana Fox", "1234")
bank.fund(ana, 1000)
local MUSIC_ID, PLAYER_ID = 30, 40
local server, musicNode = world.attach(MUSIC_ID, "music_server.lua", config.music_protocol,
    "music_server")
local registered = bank.core.actions.MUSIC_SERVER_REGISTER({ code = "4040" }, MUSIC_ID)
server.state.server_token, server.state.server_id = registered.server_token,
    registered.server_id
as(MUSIC_ID, server.background.step)
world.beatAll()
local function import(title, size)
    return assert(as(MUSIC_ID, server.library.import, { title = title, artist = "Foxy",
        kind = "song", uploader_name = "Foxy Records" }, string.rep(title:sub(1, 1), size)))
end
local trot, howl, jive = import("Trot", 9000), import("Howl", 7000), import("Jive", 6000)
local r = as(MUSIC_ID, server.radio.create, "Foxy FM", "lime")
r.songs, r.host_chance, r.giveaway_chance = { jive.track_id }, 0, 0

-- Ana's Music Player: a 51x19 screen and a speaker on the left.
local screen = dofile("screen_harness.lua")
local computer = screen.terminal(51, 19)
local box = speaker()
peripheral = {
    getNames = function() return { "back", "left" } end,
    getType = function(name) return ({ back = "modem", left = "speaker" })[name] end,
    wrap = function(name) return ({ left = box })[name] end,
}
term = { current = function() return computer end }
parallel = { waitForAny = function(first) first() end }
os.queueEvent = function() end
local steps = {}
local ui = screen.install({ display = computer, steps = steps, event = "mouse_click" })
package.loaded["lib.ui"] = ui
local player = world.attach(PLAYER_ID, "music_player.lua", "PLAYER_ONLY", "music_player")
local root = "music_player" .. PLAYER_ID

-- Signed in the way its screen does it.
local hello = assert(as(PLAYER_ID, net.ask, MUSIC_ID, config.music_protocol, "MUSIC_HELLO",
    { session_token = ana.token, label = "Ana's Den" }, 3))
player.state.player_token, player.state.owner_name = hello.player_token, "Ana Fox"
as(PLAYER_ID, player.tickOnce)
assert(player.state.music_server == MUSIC_ID, "it remembers which computer the Bank named")

local function runScreen(...)
    screen.push(steps, ...)
    local ok, err = pcall(as, PLAYER_ID, player.screenLoop)
    assert(ok or tostring(err):find("STOP_TEST", 1, true), err)
    assert(#steps == 0, #steps .. " steps never used")
end
local function stop() error("STOP_TEST", 0) end

-- Free: nothing to download, and nothing downloaded.
assert(player.shared.player.offline == false)
runScreen("tab:library", function(state)
    assert(state.display.has("Trot") and not state.display.has("Downloaded"),
        state.display.dump())
    stop()
end)
local _, _, needsPlus = as(PLAYER_ID, net.ask, MUSIC_ID, config.music_protocol,
    "MUSIC_DOWNLOAD", { player_token = hello.player_token, track_id = trot.track_id }, 3)
assert(needsPlus == "NEEDS_MUSIC_PLUS")

-- 3. FoxyMusic+: two songs kept --------------------------------------------------------------------

bank.request("MUSIC_PLUS_JOIN", bank.as(ana, { pin = "1234", app_id = "MUSIC" }))
-- The Music app asks the Music Server who she is now; the player hears at its next tick.
assert(as(world.pocket, net.ask, MUSIC_ID, config.music_protocol, "MUSIC_ME",
    { session_token = ana.token }, 3).offline)
as(PLAYER_ID, player.tickOnce)
assert(player.shared.player.offline and player.state.offline_day == util.ingameDay())

runScreen("tab:library", "keep:" .. trot.track_id, function(state)
    assert(state.display.has("Downloaded"), "a list of what is kept\n" .. state.display.dump())
    return "keep:" .. howl.track_id
end, "sort:kept", function(state)
    assert(state.display.has("Downloaded  2 songs") and state.display.has("Trot")
        and state.display.has("Howl") and not state.display.has("Jive"), state.display.dump())
    stop()
end)
local disk = world.disks["music_player" .. PLAYER_ID]
assert(disk.files[root .. "/offline/" .. trot.track_id .. ".dfpwm"] == string.rep("T", 9000),
    "the whole song, on the player's own disk")
assert(not disk.files[root .. "/offline/" .. trot.track_id .. ".dfpwm.part"])
assert(player.state.offline[howl.track_id].title == "Howl")
assert(player.kept.bytes() == 16000)

-- A kept song plays from the disk, counted all the same: the Cloud Servers can be gone.
for _, id in ipairs(world.ids) do world.servers[id].up = false end
as(PLAYER_ID, player.tickOnce)
assert(as(world.pocket, net.ask, MUSIC_ID, config.music_protocol, "MUSIC_CONTROL",
    { session_token = ana.token, player_id = hello.player.player_id, command = "play",
        track_id = trot.track_id }, 3))
as(PLAYER_ID, player.tickOnce)
box.samples = 0
as(PLAYER_ID, player.audioStep)
assert(box.samples == 9000 * 8, "Trot, from the disk: " .. box.samples)
assert(server.state.usage[ana.id].plays == 1, "counted by the Music Server")
for _, id in ipairs(world.ids) do world.servers[id].up = true end

-- 4. The Music Server goes off, and the Bank with it ---------------------------------------------

musicNode.up = false
world.lose[bank.core_id] = 1e9
for _ = 1, 3 do as(PLAYER_ID, player.tickOnce) end
assert(player.shared.server_down, "three ticks unanswered")

runScreen("tab:library", function(state)
    assert(state.display.has("The Music Server is off: songs kept here")
        and state.display.has("Downloaded  2 songs"), state.display.dump())
    assert(not state.display.has("SEARCH"), "only what is kept")
    return "play:" .. howl.track_id
end, function(state)
    assert(state.display.has("OFFLINE") and state.display.has("Howl"), state.display.dump())
    stop()
end)
local here = player.shared.here
assert(here and #here.queue == 2 and here.queue[here.index] == howl.track_id,
    "Howl, then the rest of what is kept")

box.samples = 0
as(PLAYER_ID, player.audioStep)
assert(box.samples == 7000 * 8, "Howl, from this computer alone")
assert(player.shared.here.queue[player.shared.here.index] == trot.track_id, "then Trot")

-- Pause and next are this screen's own while the Music Server is off.
runScreen("pause", function(state)
    assert(player.shared.here.paused and state.display.has("PLAY"), state.display.dump())
    return "resume"
end, "next", function(state)
    assert(player.shared.here == nil, "past the end: nothing playing")
    stop()
end)

-- Found again without the Bank: the computer it named last time.
musicNode.up = true
as(PLAYER_ID, player.tickOnce)
assert(not player.shared.server_down, "the Music Server, with the Bank still away")

-- The Music app on a Pocket the same way (net.musicApi's `remember`).
local function pocketMusic(kept)
    return net.musicApi(config, function() return ana.token end, function() return false end,
        function()
            local where = net.ask(bank.core_id, config.protocol, "MUSIC_WHERE", {}, 2)
            return where and where.computer_id
        end, function(id)
            if id then kept.id = id end
            return kept.id
        end)
end
local remembered = {}
assert(not as(world.pocket, pocketMusic({}).ask, "MUSIC_ME"), "never told: nowhere to go")
world.lose[bank.core_id] = 0
assert(as(world.pocket, pocketMusic(remembered).ask, "MUSIC_ME"))
assert(remembered.id == MUSIC_ID)
world.lose[bank.core_id] = 1e9
assert(as(world.pocket, pocketMusic(remembered).ask, "MUSIC_ME").music_plus,
    "a Pocket that signed in is believed, at the computer the Bank named")

-- Playing here, then told otherwise from the Music app: the Music app wins.
musicNode.up = false
for _ = 1, 3 do as(PLAYER_ID, player.tickOnce) end
as(PLAYER_ID, player.kept.play, trot.track_id)
musicNode.up = true
as(PLAYER_ID, player.tickOnce)
assert(player.shared.here, "the same as before: still playing here")
assert(as(world.pocket, net.ask, MUSIC_ID, config.music_protocol, "MUSIC_CONTROL",
    { session_token = ana.token, player_id = hello.player.player_id, command = "radio",
        radio_id = r.radio_id }, 3))
as(PLAYER_ID, player.tickOnce)
assert(player.shared.here == nil and player.shared.player.mode == "radio")

-- 5. How long kept songs last ----------------------------------------------------------------------

-- Ten days after FoxyMusic+ was last confirmed, they stop playing.
musicNode.up = false
for _ = 1, 3 do as(PLAYER_ID, player.tickOnce) end
player.state.offline_day = util.ingameDay() - 11
runScreen("tab:library", "play:" .. trot.track_id, function(state)
    assert(player.shared.here == nil, "not played")
    stop()
end)
player.state.offline_day = util.ingameDay()

-- Full: config.music_offline_bytes.
musicNode.up = true
world.lose[bank.core_id] = 0
as(PLAYER_ID, player.tickOnce)
config.music_offline_bytes = 20000
local _, full, fullCode = as(PLAYER_ID, player.kept.download, jive.track_id)
assert(fullCode == "FULL" and full:find("Remove some", 1, true))
config.music_offline_bytes = nil
-- Removed from the Library tab.
runScreen("tab:library", "sort:kept", "keep:" .. howl.track_id, function(state)
    assert(state.display.has("REMOVE DOWNLOAD"), state.display.dump())
    return "yes"
end, function(state)
    assert(state.display.has("Downloaded  1 songs"), state.display.dump())
    stop()
end)
assert(not disk.files[root .. "/offline/" .. howl.track_id .. ".dfpwm"])

-- FoxyMusic+ ends: the Music Server says so, and the songs go.
bank.request("MUSIC_PLUS_CANCEL", bank.as(ana, { app_id = "MUSIC" }))
bank.advanceDays(5)
bank.process_subscriptions()
ana.token = bank.request("LOGIN", { name = "Ana Fox", pin = "1234" }).session_token
bank.advanceMs(6 * 60 * 1000)
as(PLAYER_ID, player.tickOnce)
assert(player.shared.player.offline == false)
assert(next(player.state.offline) == nil and player.state.offline_day == nil)
assert(not disk.files[root .. "/offline/" .. trot.track_id .. ".dfpwm"], "gone from the disk")

io.write("host_music_offline_test: OK\n")
