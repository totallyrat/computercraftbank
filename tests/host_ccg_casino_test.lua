-- The CCG Casino, FoxyOS 17: tables on the CCG Server, against a real Bank.
-- (The harness is host_ccg_server_test's.)
--
-- ComputerCraftGaming, split across two computers.
--
-- The games moved to their own server in 9.1 and the money stayed on the
-- Bank, so this loads both and wires a table between them. Every wager here
-- makes a real round trip: the CCG Server asks the Bank who the player is
-- and to hold their stake, and the Bank decides every amount.
--
-- What the test is really watching is that the split cannot lose or invent
-- money -- including when the CCG Server lies about a payout, or walks away
-- from a lobby with wagers in it.

package.path = "../?.lua;../?/init.lua;" .. package.path

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

local currentDay, currentTime, currentEpoch = 300, 12, 1000000
os.day = function() return currentDay end
os.time = function() return currentTime end
os.epoch = function() return currentEpoch end
os.getComputerID = function() return 1 end

fs = {
    getDir = function() return "/pumpe" end,
    combine = function(left, right)
        return tostring(left):gsub("/+$", "") .. "/"
            .. tostring(right):gsub("^/+", "")
    end,
    exists = function() return false end,
    isDir = function() return false end,
}
shell = { getRunningProgram = function() return "/pumpe/bank_server.lua" end }
term = { current = function()
    return { getSize = function() return 51, 19 end }
end }

local util = require("lib.util")
util.loadTable = function(_, fallback) return util.copy(fallback) end
util.saveTable = function() end
package.loaded["lib.util"] = util

PUMPE_TEST_MODE = true
local bank = assert(loadfile("../bank_server.lua"))()
PUMPE_TEST_MODE = nil

-- The CCG Server's only route to the Bank. Every call it makes goes through
-- here, so the test can watch or interfere with all of it.
local bankCalls = {}
local bankOffline = false
package.loaded["lib.net"] = {
    openModems = function() return { "modem" } end,
    host = function() end,
    reply = function() end,
    locate = function() return nil end,
    autoUpdate = function() end,
    client = function()
        return {
            discover = function() return 1 end,
            isOnline = function() return true end,
            request = function(_, action, payload)
                bankCalls[#bankCalls + 1] = action
                if bankOffline then
                    return nil, "Bank server timed out"
                end
                local handler = bank.actions[action]
                if not handler then
                    return nil, "Unknown bank action", "UNKNOWN_ACTION"
                end
                local ok, result = pcall(handler, payload or {})
                if ok then return result end
                if type(result) == "table" and result.pumpe then
                    return nil, result.message, result.code
                end
                return nil, tostring(result), "SERVER_ERROR"
            end,
        }
    end,
}
package.loaded["lib.ui"] = setmetatable({ theme = {} }, {
    __index = function() return function() end end,
})

PUMPE_TEST_MODE = true
local ccg = assert(loadfile("../ccg_server.lua"))()
PUMPE_TEST_MODE = nil

-- The CCG Server proves itself to the Bank with the operator code, once.
ccg.state.server_token = bank.actions.CCG_SERVER_REGISTER({
    code = "4040", name = "Test CCG",
}).server_token

-- One table the test can call either server through, so a route moving
-- between them does not rewrite the test.
local actions = setmetatable({}, {
    __index = function(_, name)
        return ccg.actions[name] or bank.actions[name]
    end,
})

-- Easy Deployment must still offer both halves.
local seen = {}
for _, role in ipairs({ "ccg", "ccgserver" }) do
    for _, file in ipairs(bank.deployment_files(role)) do
        seen[file.path] = true
    end
end
assert(seen["ccg.lua"], "the CCG console is installable")
assert(seen["ccg_server.lua"], "and so is the CCG Server")

local function rejected(action, expectedCode, payload)
    local ok, result = pcall(action, payload)
    assert(not ok, "request should have been rejected")
    assert(type(result) == "table" and result.code == expectedCode,
        "expected " .. expectedCode .. ", got " .. tostring(
            type(result) == "table" and result.code or result))
end

local function register(name, pin)
    return bank.actions.REGISTER({ name = name, pin = pin,
        gender = "Not set" })
end

local function unlock(account, pin)
    return bank.actions.BET_UNLOCK({
        session_token = account.session_token, pin = pin,
    }).bet_token
end

local function deposit(account, pin, amount)
    return bank.actions.BET_WALLET_DEPOSIT({
        session_token = account.session_token, pin = pin, amount = amount,
    })
end

-- Money in the world: wallets plus whatever the Bank is holding in escrow.
-- Nothing this test does may change it except a deposit or a payout.
local function worldMoney()
    local total = 0
    for _, account in pairs(bank.state.accounts) do
        total = total + (account.balance or 0)
        local wallet = account.bet_wallet or {}
        total = total + (wallet.balance or 0)
        for _, hold in pairs(wallet.holds or {}) do
            if hold.status == "holding" then
                total = total + (hold.amount or 0)
            end
        end
    end
    for _, escrow in pairs(bank.state.ccg_escrow or {}) do
        for _, amount in pairs(escrow.stakes) do total = total + amount end
    end
    return util.roundMoney(total)
end


local casino = ccg.casino
local function asOf(account, extra)
    extra = extra or {}
    extra.session_token = account.session_token
    return extra
end
local owner = register("Olive Owner", "9999")
-- A company Olive owns, as the Bank keeps one.
bank.state.companies.COM9 = { company_id = "COM9", name = "Lucky Fox",
    owner_account_id = owner.account.account_id, status = "active" }

-- Setting up a table ----------------------------------------------------------------------------
local companies = actions.CASINO_COMPANIES(asOf(owner))
assert(#companies.companies == 1 and companies.companies[1].name == "Lucky Fox")
rejected(actions.CASINO_REGISTER, "NOT_YOURS", asOf(owner, { company_id = "NOPE", name = "Table 1" }))
local made = actions.CASINO_REGISTER(asOf(owner, { company_id = "COM9", name = "Table 1" }))
local console = { console_id = made.console_id, console_token = made.console_token }
local function tick(extra)
    extra = extra or {}
    extra.console_id, extra.console_token = console.console_id, console.console_token
    return actions.CASINO_TICK(extra).table
end
local t = ccg.state.casinos[made.console_id]
assert(tick({ library = { "theme.mid" } }).phase == "wheel", "a new table spins the wheel")

local players = {}
for index = 1, 3 do
    local account = register("Player " .. index, "1111")
    deposit(account, "1111", 500)
    players[index] = { account = account, bet = unlock(account, "1111") }
    actions.TABLE_JOIN({ bet_token = players[index].bet, code = made.code,
        display_name = "Player " .. index })
end
-- Since Beta 2 a table's rounds are its company's: counted here too.
local function conserved()
    local total = worldMoney() + (bank.state.ccg_house_profit or 0)
    for _, company in pairs(bank.state.companies) do
        total = total + (company.casino and company.casino.balance or 0)
    end
    return total
end
local start = conserved()
assert(t.bank_linked and bank.state.ccg_casino_codes[made.code] == "COM9",
    "the table is linked to its company at the Bank")
local function advance(ms)
    currentEpoch = currentEpoch + ms
    casino.tick(currentEpoch)
end
local function status(index)
    return actions.TABLE_STATUS({ bet_token = players[index].bet, code = made.code })
end
local function playGame(game, bet, act)
    actions.CASINO_CONTROL(asOf(owner, { console_id = made.console_id, op = "game", game = game }))
    for _ = 1, 20 do
        if t.phase == "betting" and t.game == game then break end
        advance(1000)
    end
    assert(t.phase == "betting" and t.game == game, game .. ": open for bets, " .. tostring(t.phase))
    for index = 1, 3 do
        actions.TABLE_BET({ bet_token = players[index].bet, code = made.code, bets = bet(index) })
    end
    for _ = 1, 120 do
        if t.phase == "result" then break end
        if t.phase == "playing" and act then
            for index = 1, 3 do
                local mine = status(index).me
                if mine.options and #mine.options > 0 then
                    actions.TABLE_ACT({ bet_token = players[index].bet, code = made.code,
                        action = act(index, mine) })
                end
            end
        end
        tick()
        advance(700)
    end
    assert(t.phase == "result", game .. " reached a result: " .. tostring(t.phase) .. "/" .. tostring(t.step))
    assert(conserved() == start, game .. ": no money made or lost")
    local seen = status(1)
    assert(seen.me.result, game .. ": the player has a result")
    return seen
end

playGame("roulette", function(index)
    return { { kind = "straight", pick = index, amount = 5 }, { kind = "even", pick = "red", amount = 5 },
        { kind = "dozen", pick = 1, amount = 2 } }
end)
playGame("heads_tails", function(index)
    return { { kind = "pick", pick = index % 2 == 0 and "heads" or "tails", amount = 4 } }
end)
playGame("blackjack", function() return { { kind = "hand", amount = 10 } } end,
    function(index, mine)
        if index == 1 and mine.options[3] == "double" then return "double" end
        return index == 2 and "hit" or "stand"
    end)
local poker = playGame("poker", function() return { { kind = "hand", amount = 6 } } end,
    function(index) return ({ "raise", "check", "fold" })[index] end)
assert(poker.table.dealer and #poker.table.dealer.cards == 2 and poker.table.dealer.cards[1] ~= 0,
    "the dealer's cards are shown at the showdown")

-- The owner takes the dealer: the wheel waits for a pick, NEXT deals.
actions.CASINO_CONTROL(asOf(owner, { console_id = made.console_id, op = "take" }))
local view = actions.CASINO_CONTROL(asOf(owner, { console_id = made.console_id, op = "next" }))
assert(view.table.phase == "wheel" and not view.table.left_ms, "the wheel waits for a pick")
advance(30000)
assert(t.phase == "wheel", "still waiting")
actions.CASINO_CONTROL(asOf(owner, { console_id = made.console_id, op = "game", game = "roulette" }))
advance(2000)
assert(t.phase == "betting" and not t.phase_until, "bets open, no clock")
actions.TABLE_BET({ bet_token = players[1].bet, code = made.code,
    bets = { { kind = "even", pick = "black", amount = 3 } } })
actions.CASINO_CONTROL(asOf(owner, { console_id = made.console_id, op = "next" }))
assert(t.phase == "playing", "SPIN")
-- Control lapses: the computer finishes the round.
advance(61000)
advance(10000)
assert(t.phase == "result" or t.phase == "wheel" or t.phase == "betting", tostring(t.phase))
assert(conserved() == start)
assert(bank.state.companies.COM9.casino.rounds >= 5, "the company's casino booked the rounds")
-- A table from Beta 1, set up before tables earned for their company, is
-- linked the next time its owner looks at My Casino, between rounds.
while t.phase == "playing" or t.phase == "settling" do advance(1000) end
actions.CASINO_CONTROL(asOf(owner, { console_id = made.console_id, op = "release" }))
for _ = 1, 40 do if t.phase ~= "playing" and t.phase ~= "settling" and #casino.bettors(t) == 0 then break end advance(1000) end
bank.actions.CCG_CASINO_UNLINK({ server_token = ccg.state.server_token, code = made.code })
t.bank_linked, t.link_tried_at = nil, nil
local list = actions.CASINO_LIST(asOf(owner))
assert(t.bank_linked and bank.state.ccg_casino_codes[made.code] == "COM9", "linked again")
assert(#list.casinos == 1 and list.casinos[1].name == "Table 1")
rejected(actions.CASINO_VIEW, "NOT_YOURS", asOf(players[1].account, { console_id = made.console_id }))
actions.CASINO_CONTROL(asOf(owner, { console_id = made.console_id, op = "music", action = "play",
    track = "theme.mid" }))
assert(tick().music.playing, "music, for the console")
-- FoxyOS 17: a song from the owner's FoxyCloud. The console is handed where
-- its pieces are and a ticket to read them -- checked for shape here, and
-- for whether it may be read at the Bank.
rejected(actions.CASINO_CONTROL, "BAD_SONG", asOf(owner, { console_id = made.console_id,
    op = "music", action = "cloud", name = "Theme.mid", cloud = { ticket = "CT_X" } }))
actions.CASINO_CONTROL(asOf(owner, { console_id = made.console_id, op = "music",
    action = "cloud", name = "Theme.mid", cloud = { ticket = "CT_X",
        chunks = { { id = "F9.1.1", size = 5000, servers = { "CS1", "CS2" } } },
        hosts = { CS1 = 11, CS2 = "12", CS9 = 99 } } }))
local cloudMusic = tick().music
assert(cloudMusic.playing and cloudMusic.track == "Theme.mid")
assert(cloudMusic.cloud and cloudMusic.cloud.ticket == "CT_X"
    and cloudMusic.cloud.hosts.CS1 == 11 and cloudMusic.cloud.hosts.CS2 == 12
    and cloudMusic.cloud.hosts.CS9 == nil, "only the servers its pieces are on")
actions.CASINO_CONTROL(asOf(owner, { console_id = made.console_id, op = "music",
    action = "volume", volume = 7 }))
assert(tick().music.cloud, "turning it up keeps the song")
assert(casino.view(t, {}).music == nil, "players are never handed the ticket")
actions.CASINO_CONTROL(asOf(owner, { console_id = made.console_id, op = "music", action = "play",
    track = "theme.mid" }))
assert(tick().music.cloud == nil, "a song on the console replaces it")
-- FoxyOS 17: DFPWM from the Music Library, a song or a radio, by a grant
-- the Music Server gave the owner. Never shown to players.
rejected(actions.CASINO_CONTROL, "BAD_SONG", asOf(owner, { console_id = made.console_id,
    op = "music", action = "stream", name = "Foxy FM" }))
actions.CASINO_CONTROL(asOf(owner, { console_id = made.console_id, op = "music",
    action = "stream", grant = "MG_1", kind = "radio", name = "Foxy FM" }))
local streamed = tick().music
assert(streamed.playing and streamed.mode == "dfpwm" and streamed.track == "Foxy FM"
    and streamed.stream.grant == "MG_1" and streamed.stream.kind == "radio")
assert(casino.view(t, {}).music == nil, "players are never handed the grant")
-- What the console says it can do, and how its music is going, is the
-- owner's to see: an old console says nothing, and My Casino says so.
assert(not actions.CASINO_VIEW(asOf(owner, { console_id = made.console_id })).table.features.dfpwm)
actions.CASINO_TICK({ console_id = made.console_id, console_token = made.console_token,
    version = "17.0.0", features = { cloud_midi = true, dfpwm = true },
    music_status = "Cannot play: Music on a CCG Casino needs FoxyCloud+" })
local owned = actions.CASINO_VIEW(asOf(owner, { console_id = made.console_id })).table
assert(owned.features.dfpwm and owned.features.cloud_midi and owned.version == "17.0.0")
assert(owned.music_status:find("needs FoxyCloud+", 1, true))
assert(tick().music_status == nil, "the console's own view does not echo it back")

-- Render smoke: the console's display, every phase, three sizes.
local screen = dofile("screen_harness.lua")
package.loaded["lib.ui"] = dofile("../lib/ui.lua")
peripheral = { getNames = function() return {} end }
PUMPE_TEST_MODE = "ccg_casino"
local console = assert(loadfile("../ccg_casino.lua"))()
PUMPE_TEST_MODE = nil
console.device.console_id = made.console_id
local sizes = { { 29, 19 }, { 51, 26 }, { 82, 40 } }
local rendered, phases = 0, {}
actions.CASINO_CONTROL(asOf(owner, { console_id = made.console_id, op = "release" }))
actions.CASINO_CONTROL(asOf(owner, { console_id = made.console_id, op = "auto", on = true }))
for _, game in ipairs({ "roulette", "heads_tails", "blackjack", "poker" }) do
    actions.CASINO_CONTROL(asOf(owner, { console_id = made.console_id, op = "game", game = game }))
    for step = 1, 140 do
        local view = tick()
        if view.phase == "betting" and view.game == game and #casino.bettors(t) == 0 then
            for index = 1, 3 do
                local bets = game == "roulette" and { { kind = "even", pick = "red", amount = 1 } }
                    or game == "heads_tails" and { { kind = "pick", pick = "heads", amount = 1 } }
                    or { { kind = "hand", amount = 1 } }
                pcall(actions.TABLE_BET, { bet_token = players[index].bet, code = made.code, bets = bets })
            end
        end
        console.show.table, console.show.at, console.show.online = view, currentEpoch, true
        for _, size in ipairs(sizes) do
            local display = screen.terminal(size[1], size[2])
            local ok, err = pcall(console.show.render, display)
            assert(ok, game .. " " .. tostring(view.phase) .. "/" .. tostring(view.step) .. " at "
                .. size[1] .. "x" .. size[2] .. ": " .. tostring(err))
            rendered = rendered + 1

        end
        phases[tostring(view.game) .. ":" .. tostring(view.phase) .. ":" .. tostring(view.step)] = true
        if view.phase == "result" and view.game == game then break end
        advance(400)
    end
end
local seen = {}
for key in pairs(phases) do seen[#seen + 1] = key end
table.sort(seen)
assert(#seen >= 20, "every phase of every game was drawn: " .. table.concat(seen, " "))
-- A MIDI file: one track, a tempo, three notes and a drum.
local function vl(n) return string.char(n) end
local track = vl(0) .. string.char(0xFF, 0x51, 3, 0x07, 0xA1, 0x20)
    .. vl(0) .. string.char(0xC0, 24)
    .. vl(0) .. string.char(0x90, 60, 100) .. vl(48) .. string.char(0x80, 60, 0)
    .. vl(0) .. string.char(0x90, 64, 90) .. vl(48) .. string.char(64, 0)
    .. vl(0) .. string.char(0x99, 36, 120)
    .. vl(0) .. string.char(0xFF, 0x2F, 0)
local function u32(n) return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256,
    math.floor(n / 256) % 256, n % 256) end
local file = "MThd" .. u32(6) .. string.char(0, 0, 0, 1, 0, 96) .. "MTrk" .. u32(#track) .. track
local notes = console.midi.parse(file)
assert(#notes == 3, "three notes: " .. #notes)
assert(notes[1].instrument == "guitar" and notes[3].instrument == "basedrum", notes[1].instrument)
assert(math.abs(notes[2].t - 0.25) < 0.001, "48 ticks at 96 a beat and 120 bpm is a quarter second: "
    .. notes[2].t)
-- FoxyOS 17: the same song from FoxyCloud, fetched with its plan and played
-- from memory: nothing is written to the console's disk.
local net = require("lib.net")
net.cloud = net.cloud or {}
-- A long song yields while it is read; here there is nothing to yield to.
os.queueEvent = os.queueEvent or function() end
os.pullEvent = os.pullEvent or function() end
local realGet, askedFor = net.cloud.get, nil
net.cloud.get = function(plan, protocol)
    askedFor = { plan = plan, protocol = protocol }
    return file
end
local fromCloud = console.midi.fromCloud({ ticket = "CT_X", chunks = {}, hosts = {} })
net.cloud.get = function() return nil, "A Cloud Server is not answering" end
local missing, why = console.midi.fromCloud({ ticket = "CT_Y", chunks = {}, hosts = {} })
net.cloud.get = realGet
assert(fromCloud and #fromCloud == 3, "the cloud song plays like one on the disk")
assert(askedFor.plan.ticket == "CT_X" and askedFor.protocol == require("config").cloud_protocol)
assert(not missing and why == "A Cloud Server is not answering", "and says why when it cannot")

-- FoxyOS 17: DFPWM on the console. It asks the Music Server with the grant,
-- plays what it is told through the speakers, and says what is on.
parallel = parallel or { waitForAny = function(first) first() end }
local musiclib = require("lib.music")
local realPlay, played = musiclib.play, nil
musiclib.play = function(plan, speakers, options)
    played = { plan = plan, offset = options.offset_ms, volume = options.volume() }
    return true
end
local streamAnswer = { mode = "track", item = { title = "Fox Trot", length_ms = 1000 },
    offset_ms = 0, plan = { ticket = "CT_M" } }
local asked = {}
console.console.musicClient = { request = function(_, action, payload)
    asked[#asked + 1] = action .. ":" .. tostring(payload.grant)
    if streamAnswer.code then return nil, streamAnswer.err, streamAnswer.code end
    return streamAnswer
end }
console.console.music = { playing = true, track = "Fox Trot", volume = 10,
    stream = { grant = "MG_2", kind = "track" } }
console.console.musicSeq = 7
assert(console.console.stream(console.console.music, 7))
assert(asked[1] == "MUSIC_STREAM:MG_2", "the grant, never a session")
assert(played.plan.ticket == "CT_M" and played.offset == 0)
assert(console.console.musicStatus == "Fox Trot")
-- A Cloud Server out of reach: tried again a little later, still playing.
os.startTimer = function() return 99 end
os.pullEvent = function() return "timer", 99 end
streamAnswer = { code = "CLOUD_OFFLINE", err = "A Cloud Server is not answering" }
local ok, err, code = console.console.stream(console.console.music, 7)
assert(not ok and code == "CLOUD_OFFLINE")
console.console.failed(console.console.music, 7, err, code)
assert(console.console.music.playing, "one failure is tried again")
assert(console.console.musicStatus == "Cannot play: A Cloud Server is not answering")
-- No FoxyCloud+: it stops, and says why.
streamAnswer = { code = "NEEDS_PLUS", err = "Music on a CCG Casino needs FoxyCloud+" }
ok, err, code = console.console.stream(console.console.music, 7)
console.console.failed(console.console.music, 7, err, code)
assert(not console.console.music.playing and console.console.musicStatus:find("FoxyCloud+", 1, true))
-- Quieter while a game is on.
console.console.music = { playing = true, volume = 10 }
console.show.table = { phase = "playing" }
assert(math.abs(console.console.level() - 3 * 0.35) < 0.001)
musiclib.play = realPlay

print("host_ccg_casino_test: OK")
