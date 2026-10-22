-- The Radio Broadcaster, FoxyOS 18.2: the real radio_broadcaster.lua and
-- lib/ui on a 51x19 computer, against a real Bank Core and Vault, five
-- Cloud Servers and the Music Server.
--
-- It starts with its tower: three rings, RADIO with the tower as its A, a
-- ring that takes the whole screen, and the colour gone top to bottom. Ana
-- sets it up for her company on 98.5 -- 98.4 is turning the dial past it --
-- and queues a song from the ADD page, which goes on the air. Radio+ comes
-- out of Company Money with her PIN, and then a .dfpwm dropped on the screen
-- goes straight into the playlist.

package.path = "../?.lua;../?/init.lua;" .. package.path
require("config").cloud_chunk_size = 6000
local harness = require("bank_pair_harness")
local bank = harness.pair()
local config = require("config")
local net = require("lib.net")

local world = require("cloud_harness").start(harness, bank)
local as = world.as
local MUSIC_ID, BROADCASTER = 30, 50
world.beatAll()

local ana = bank.register("Ana Fox", "1234")
bank.fund(ana, 2000)
local server = world.attach(MUSIC_ID, "music_server.lua", config.music_protocol, "music_server")
local registered = bank.request("MUSIC_SERVER_REGISTER", { code = "4040" })
server.state.server_token, server.state.server_id = registered.server_token,
    registered.server_id
as(MUSIC_ID, server.background.step)
world.beatAll()
local song = as(MUSIC_ID, server.library.import, { title = "Fox Trot", artist = "Ana",
    kind = "song", uploader_name = "Foxy Records" }, string.rep("t", 12000)).track_id
local company = bank.request("COMPANY_CREATE", bank.as(ana, { company_name = "Fox Media" }))
local companyId = company.company_id or company.company.company_id
bank.request("COMPANY_MONEY_ADD", bank.as(ana, { company_id = companyId, amount = 300,
    pin = "1234" }))

-- The computer --------------------------------------------------------------------------------

local screen = dofile("screen_harness.lua")
local display = screen.terminal(51, 19)
term = { current = function() return display end, redirect = function() return display end }
shell = { getRunningProgram = function() return "/radio50/radio_broadcaster.lua" end }
local ui, driven = screen.install({ display = display, event = "mouse_click" })
package.loaded["lib.ui"] = ui
PUMPE_TEST_MODE = "radio_broadcaster"
local radio = as(BROADCASTER, assert(loadfile("../radio_broadcaster.lua")))
PUMPE_TEST_MODE = nil
local function steps(list)
    for _, step in ipairs(list) do
        if type(step) == "table" and step[1] then
            for _, inner in ipairs(step) do driven.steps[#driven.steps + 1] = inner end
        else
            driven.steps[#driven.steps + 1] = step
        end
    end
end
local function pin(digits)
    local list = {}
    for index = 1, #digits do list[index] = { char = digits:sub(index, index) } end
    return list
end
local function run(fn, ...) return as(BROADCASTER, fn, ...) end

-- The start ------------------------------------------------------------------------------------

local at = radio.intro.layout(display)
assert(at.scale == 2, "RADIO twice the size on a computer")
radio.intro.frame(display, at, colors.orange, {}, 4)
assert(display.backAt(at.towerX, at.top - 1) == colors.orange, "the tower's light")
assert(display.backAt(at.towerX, at.top + at.letterH - 1) == nil
    or display.backAt(at.towerX - math.floor(at.towerW / 2), at.top + at.letterH - 1)
        == colors.lightGray, "its legs, as wide as an A")
assert(display.backAt(at.x, at.top) == colors.white, "R, beside it")
local afterTower = at.towerX + math.floor(at.towerW / 2) + 1 + at.scale
assert(display.backAt(afterTower, at.top) == colors.white, "and DIO after it")
-- A ring in the colour, and then the whole screen.
radio.intro.frame(display, at, colors.orange, { 6 }, 0)
local ringed = 0
for y = 1, 19 do ringed = ringed + display.count(y, colors.orange) end
assert(ringed > 10, "a ring")
run(radio.intro.play, display, "orange")
for y = 1, 19 do
    assert(display.count(y, colors.orange) == 0, "the colour gone, top to bottom")
end

-- Setting it up --------------------------------------------------------------------------------

steps({ "start", screen.typed("Ana Fox"), pin("1234"), "company:1",
    { key = keys.enter },                -- the station's name, as offered: the company's
    "color:orange", "up", "pick" })
run(radio.setup.run)
local device = radio.device()
assert(device.station_id and device.owner_name == "Ana Fox" and device.company_id == companyId)
local s = server.state.stations[device.station_id]
assert(s and s.frequency == 985 and s.name == "Fox Media" and s.color == "orange",
    "on 98.5, past 98.4 on the dial")
assert(#driven.steps == 0, "every step taken")

-- On the air -------------------------------------------------------------------------------------

run(radio.shared.refresh)
local function screenOnce(list)
    steps(list)
    steps({ { raw = { "terminate" } } })
    radio.go()
    run(radio.loops.screen)
end
radio.shared.page = "add"
screenOnce({ "track:" .. song })
-- Nothing was on, so it went straight on the air rather than waiting in the playlist.
local item = server.station.now(s)
assert(item.kind == "song" and item.title == "Fox Trot" and #s.playlist == 0,
    "queued from ADD, and on the air")
radio.shared.page = "air"
assert(radio.shared.view.label == "98.5")

-- Radio+, out of Company Money, with Ana's PIN -----------------------------------------------------

run(radio.shared.refresh)
radio.shared.page = "station"
screenOnce({ "plus", "yes", pin("1234") })
local money = bank.request("COMPANY_MONEY", bank.as(ana, { company_id = companyId }))
assert(money.radio_plus and money.radio_plus.active and money.balance == 200,
    "100 from Company Money")
server.station.plus_at = 0
as(MUSIC_ID, server.station.tick)
run(radio.shared.refresh)
assert(radio.shared.view.plus)

-- Quick Upload.
local dropped = { getName = function() return "Hello Fox Town.dfpwm" end,
    readAll = function() return string.rep("h", 6000) end, close = function() end }
local said = run(radio.act.dropped, { dropped })
assert(said == "Queued Hello Fox Town", said)
assert(s.playlist[#s.playlist].type == "clip")
local wrong = { getName = function() return "notes.txt" end, readAll = function() return "" end,
    close = function() end }
assert(run(radio.act.dropped, { wrong }):find("not a .dfpwm", 1, true))

-- The playlist: the upload waiting its turn, with its buttons.
radio.shared.page = "list"
screenOnce({})
assert(display.has("UPLOAD  Hello Fox Town") and display.has("CLEAR"), display.dump())
screenOnce({ "remove:" .. s.playlist[#s.playlist].entry_id })
assert(#s.playlist == 0 and next(server.state.clips) == nil, "removed, and its pieces with it")

-- What the On Air page shows.
radio.shared.page = "air"
screenOnce({})
assert(display.has("ON AIR") and display.has("RADIO+") and display.has("SKIP"), display.dump())

io.write("host_radio_broadcaster_test: OK\n")
