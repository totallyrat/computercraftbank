-- The Music Server's own screen, FoxyOS 17: the real lib/ui on its 51x19
-- screen, on a network with a real Bank and five Cloud Servers. A song is
-- dropped on the Library tab and imported with its title, artist, kind and
-- credit; a giveaway clip too. A radio is made on the Radios tab, gets its
-- phone number from the Bank, has songs and the clip put in it, and a
-- giveaway asked for -- which opens at the Bank at the next break.

package.path = "../?.lua;../?/init.lua;" .. package.path
sleep = function() end
require("config").cloud_chunk_size = 6000
local harness = require("bank_pair_harness")
local bank = harness.pair()
local config = require("config")

local world = require("cloud_harness").start(harness, bank)
local as = world.as
world.beatAll()
local MUSIC_ID = 30

local screen = dofile("screen_harness.lua")
local computer = screen.terminal(51, 19)
term = { current = function() return computer end }
local steps = {}
local ui, screenState = screen.install({ display = computer, steps = steps,
    event = "mouse_click" })
package.loaded["lib.ui"] = ui
local server = world.attach(MUSIC_ID, "music_server.lua", config.music_protocol, "music_server")
local registered = bank.request("MUSIC_SERVER_REGISTER", { code = "4040" })
server.state.server_token, server.state.server_id = registered.server_token,
    registered.server_id

-- Files dragged onto the screen, the way ComputerCraft hands them over.
local function drop(name, body)
    local handle = { getName = function() return name end,
        readAll = function() return body end, close = function() end }
    return { raw = { "file_transfer", { getFiles = function() return { handle } end } } }
end

local function backspaces(count)
    local list = {}
    for index = 1, count do list[index] = { key = keys.backspace } end
    return list
end

local function stopHere()
    error("STOP_TEST", 0)
end

local function run(...)
    screen.push(steps, ...)
    local ok, err = pcall(as, MUSIC_ID, function()
        ui.serverTabs({
            target = computer, title = "MUSIC SERVER", files = true,
            pages = { server.admin.libraryPage(), server.admin.radiosPage() },
            activity = {}, running = function() return true end,
        })
    end)
    assert(not ok and tostring(err):find("STOP_TEST", 1, true), err)
    assert(#steps == 0, #steps .. " steps left")
end

-- The Library: empty, then a song dropped on it.
run("tab:library", function(state)
    assert(state.display.has("LIBRARY  0"), state.display.dump())
    assert(state.display.has("Drop .dfpwm files on this screen"))
    return drop("Fox_Trot.dfpwm", string.rep("f", 9000))
end, function(state)
    assert(state.display.has("TITLE") and state.display.has("Fox Trot"),
        "the title comes from the file's name\n" .. state.display.dump())
    return { key = keys.enter }
end, screen.typed("Ana"), "kind:song", function(state)
    assert(state.display.has("CREDIT") and state.display.has("Music Server"))
    return { key = keys.backspace }
end, backspaces(11), screen.typed("Foxy Records"), function(state)
    assert(state.display.has("Fox Trot") and state.display.has("Song"),
        "in the library\n" .. state.display.dump())
    return drop("contest.dfpwm", string.rep("g", 3000))
end, { key = keys.enter }, screen.typed("DJ Fox"), "kind:giveaway", { key = keys.enter },
function(state)
    assert(state.display.has("LIBRARY  2"), state.display.dump())
    assert(state.display.has("Giveaway"))
    return drop("notes.txt", "hello")
end, function(state)
    -- Said in a banner, and nothing added.
    assert(state.display.has("LIBRARY  2") and not server.state.tracks.T3,
        state.display.dump())
    stopHere()
end)
local trot, clip = server.state.tracks.T1, server.state.tracks.T2
assert(trot.title == "Fox Trot" and trot.artist == "Ana" and trot.kind == "song"
    and trot.uploader_name == "Foxy Records" and trot.size == 9000)
assert(clip.kind == "giveaway" and clip.title == "contest")

-- A radio, its songs, its clip and a giveaway.
run("tab:radios", function(state)
    assert(state.display.has("RADIOS  0"), state.display.dump())
    return "new"
end, screen.typed("Foxy FM"), function(state)
    local r = server.state.radios.R1
    assert(r and r.number, "the Bank gave it a number")
    assert(state.display.has("Foxy FM") and state.display.has("Call " .. r.number),
        state.display.dump())
    assert(state.display.has("Nothing to play: put songs in rotation"))
    return "giveaway"
end, function(state)
    -- No giveaway clip on it yet: said in a banner, and nothing asked for.
    assert(not server.radio.live(server.state.radios.R1).force_giveaway)
    return "list:song"
end, function(state)
    assert(state.display.has("[ ] Fox Trot"), state.display.dump())
    return "row:T1"
end, function(state)
    assert(state.display.has("[x] Fox Trot"))
    return "back"
end, "list:giveaway", "row:T2", "back", function(state)
    assert(state.display.has("Songs 1") and state.display.has("Giveaways 1"),
        state.display.dump())
    assert(state.display.has("NOW  Fox Trot - Ana"), state.display.dump())
    return "dial:ads_every"
end, function(state)
    assert(state.display.has("ADS EVERY") and state.display.has("5 songs"),
        state.display.dump())
    return "giveaway"
end, function(state)
    assert(state.display.has("Giveaway at the next break"), state.display.dump())
    stopHere()
end)
local r = server.state.radios.R1
assert(r.songs[1] == "T1" and r.giveaways[1] == "T2" and r.ads_every == 5)

-- The song plays out; the clip starts; the radio loop opens the giveaway.
local item = as(MUSIC_ID, server.radio.now, r)
bank.advanceMs(item.length_ms + 10)
assert(as(MUSIC_ID, server.radio.now, r).kind == "giveaway")
as(MUSIC_ID, server.radio.tick)
local opened
for _, giveaway in pairs(bank.state.giveaways) do opened = giveaway end
assert(opened and opened.status == "open" and opened.number == r.number
    and opened.radio_name == "Foxy FM", "open at the Bank")

io.write("host_music_server_screen_test: OK\n")
