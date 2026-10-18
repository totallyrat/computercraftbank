-- The FoxyCloud app, FoxyOS 17, on a 26x20 Pocket: the real app, with the
-- real api.cloud (net.cloud.api), against a real Bank Core and Vault and five
-- real Cloud Servers (cloud_harness.lua). Every draw is bounds-checked and
-- every tap lands only on something that is on the screen.
--
-- Ana writes a note, opens it again, changes a line, shares it, saves a copy
-- on her Pocket and joins FoxyCloud+. Kit opens her share code and keeps a
-- copy. Ana drops a MIDI file and a text file onto her Pocket's screen.

package.path = "../?.lua;../?/init.lua;" .. package.path
sleep = function() end
local harness = require("bank_pair_harness")
local bank = harness.pair()
local world = require("cloud_harness").start(harness, bank)
local phone = require("phone_app_harness")
local config = require("config")
local net = require("lib.net")
local util = require("lib.util")

world.beatAll()
local ana = bank.register("Ana Fox", "1234")
local kit = bank.register("Kit Wolf", "5678")
bank.fund(ana, 2000)

local function run(who, script, extra)
    extra = extra or {}
    local downloads = "/pocket" .. who.id .. "/downloads"
    return phone.run({ bank = bank, who = who, file = "../foxycloud.lua",
        app_id = "CLOUD", script = script, wanted = extra.wanted,
        width = extra.width, height = extra.height,
        api = { cloud = function(api)
            return net.cloud.api(function(action, payload)
                return api.request(action, payload)
            end, config.cloud_protocol, function() return false end, downloads)
        end } }), downloads
end
local function files(who)
    return bank.request("CLOUD_FILES", bank.as(who, { app_id = "CLOUD" })).files
end
local function body(who, file)
    return net.cloud.load(function(action, payload)
        payload.app_id = "CLOUD"
        return bank.request(action, bank.as(who, payload))
    end, file.file_id, config.cloud_protocol)
end

-- Ana: a note, written, opened, changed, shared, kept, and FoxyCloud+ ---------------------

local script = phone.script()
phone.push(script.actions, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "FoxyCloud") and phone.has(frame, "0 files"))
    assert(phone.has(frame, "0 B of 100 KB"), "the room, before anything is in it")
    return "add"
end, "note",
    "add", "add", "save",                          -- two lines, saved
    function(seen)
        assert(phone.has(phone.last(seen), "Shopping.txt"), "the note is listed")
        return "file:1"
    end,
    "open", "line:1", "save",                      -- milk becomes oat milk
    "share", "keep", "back",
    "tab:plus",
    function(seen)
        local frame = phone.last(seen)
        assert(phone.has(frame, "Billed every 5 days"))
        assert(phone.has(frame, "25 MB") and phone.has(frame, "50 MB"), "both tiers")
        assert(phone.has(frame, "0% fee on Foxy Cash"), "the perks are listed")
        assert(phone.has(frame, "500 messages a day"), "Tier 1's, to start with")
        return "join"
    end,
    function(seen)
        local frame = phone.last(seen)
        assert(phone.has(frame, "Ends day") == false)
        assert(phone.has(frame, "Cancel FoxyCloud+"))
        return "tier:2"
    end,
    function(seen)
        local frame = phone.last(seen)
        assert(phone.has(frame, "Unlimited messages"), "Tier 2's perks")
        assert(phone.has(frame, "Upgrade: $500 now"), "up costs the difference")
        return "join"
    end,
    function(seen)
        assert(phone.has(phone.last(seen), "Cancel FoxyCloud+"), "Tier 2 is yours")
        return "tier:1"
    end,
    function(seen)
        assert(phone.has(phone.last(seen), "Step down at renewal"))
        return "tab:account"
    end,
    function(seen)
        local frame = phone.last(seen)
        assert(phone.has(frame, "Ana Fox") and phone.has(frame, "FoxyCloud+ Tier 2"),
            "the account, on its new plan")
        return "home"
    end)
phone.push(script.inputs, "Shopping", "milk", "eggs", "oat milk")
phone.push(script.confirms, true)                  -- share it
phone.push(script.confirms, true, true)            -- join FoxyCloud+, then upgrade
phone.push(script.pins, "1234", "1234")
local balanceBefore = bank.balanceOf(ana)
local seen, downloads = run(ana, script)
assert(phone.said(seen, "Saved"), "the note went up")
assert(phone.said(seen, "Shared"), "and was shared")
assert(phone.said(seen, "On this Pocket"), "and kept on the Pocket")
assert(phone.said(seen, "FoxyCloud+ Tier 1") and phone.said(seen, "FoxyCloud+ Tier 2"))
assert(balanceBefore - bank.balanceOf(ana) == 1000, "500 to join, 500 more for Tier 2")

local mine = files(ana)
assert(#mine == 1 and mine[1].name == "Shopping.txt" and mine[1].version == 2)
assert(body(ana, mine[1]) == "oat milk\neggs", "the changed line, saved")
local code = mine[1].share
assert(code and #code == 6)
local kept = world.disks["pocket" .. ana.id].files["pocket" .. ana.id .. "/downloads/Shopping.txt"]
assert(kept == "oat milk\neggs", "the copy kept on the Pocket")
assert(bank.request("CLOUD_PLAN", bank.as(ana)).tier == 2)

-- Kit: a share code, read, and a copy kept ------------------------------------------------

script = phone.script()
phone.push(script.actions, "add", "code", function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "From Ana Fox") and phone.has(frame, "oat milk"),
        "Ana's note, read-only, on Kit's Pocket")
    return "back"
end, function(seen)
    assert(phone.has(phone.last(seen), "Shopping.txt"), "Kit's own copy is listed")
    return "home"
end)
phone.push(script.inputs, code)
phone.push(script.confirms, true)                  -- keep a copy
seen = run(kit, script)
local kits = files(kit)
assert(#kits == 1 and body(kit, kits[1]) == "oat milk\neggs")

-- Ana: files dropped onto the screen --------------------------------------------------------

local song = {}
for index = 1, 9000 do song[index] = string.char(index % 256) end
song = table.concat(song)
script = phone.script()
phone.push(script.actions, "add", "drop",
    { drop = { { name = "Song (1).mid", body = song },
        { name = "C:\\stuff\\notes.txt", body = "hello" } } },
    function(seen)
        local frame = phone.last(seen)
        assert(phone.has(frame, "Song _1_.mid") and phone.has(frame, "MIDI"),
            "the song, under a name FoxyCloud takes")
        assert(phone.has(frame, "notes.txt"), "and the note, without the folders")
        return "file:3"                            -- notes, Shopping, Song: by name
    end, "open", function(seen)
        assert(phone.has(phone.last(seen), "Play it on a CCG Casino"))
        return "back"
    end, "back", "home")
seen = run(ana, script)
local byName = {}
for _, file in ipairs(files(ana)) do byName[file.name] = file end
assert(byName["Song _1_.mid"] and byName["Song _1_.mid"].kind == "midi")
assert(body(ana, byName["Song _1_.mid"]) == song, "the MIDI file, byte for byte")
assert(body(ana, byName["notes.txt"]) == "hello")

-- The same name again offers to replace it.
script = phone.script()
phone.push(script.actions, "add", "pocket", "pick:1", "home")
phone.push(script.confirms, true)                  -- replace Shopping.txt
seen = run(ana, script)
assert(phone.said(seen, "Saved"), "replaced from the Pocket's Downloads")

-- A standing computer's screen: the same pages, wider and shorter.
script = phone.script()
phone.push(script.actions, "file:1", "back", "tab:plus", "tab:account", "tab:files", "add", "back", "home")
run(ana, script, { width = 51, height = 19 })

print("host_foxycloud_app_test: OK")
