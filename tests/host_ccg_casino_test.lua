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

print("host_ccg_casino_test: OK")
