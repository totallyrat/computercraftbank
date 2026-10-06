-- FoxyOS 16: a CCG lobby lasts from game to game. The code stays, the
-- players stay, every wager is cleared between rounds, and the game can
-- change. Whoever has wagered when the round starts plays; anybody still
-- choosing sits it out. Run against a real Bank and CCG Server, watching
-- that no round, leave, close or Bank outage makes or loses money.
--
-- (The harness below is host_ccg_server_test's.)
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
                if bankOffline == true or (type(bankOffline) == "table"
                    and bankOffline[action]) then
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


local console = actions.CCG_REGISTER({ name = "Neon Arena" })
local auth = { console_id = console.console_id, console_token = console.console_token }
local function asConsole(extra)
    local payload = { console_id = auth.console_id, console_token = auth.console_token }
    for key, value in pairs(extra or {}) do payload[key] = value end
    return payload
end
local function player(name, pin, money)
    local account = register(name, pin)
    deposit(account, pin, money)
    return { account = account, bet = unlock(account, pin), pin = pin }
end
local function as(who, extra)
    local payload = { bet_token = who.bet }
    for key, value in pairs(extra or {}) do payload[key] = value end
    return payload
end
local function wallet(who)
    return bank.actions.BET_WALLET_SUMMARY({
        session_token = who.account.session_token }).wallet.available
end
local function finishRound()
    currentEpoch = currentEpoch + 7000
    ccg.process_games()
end

local ana, kit, sam = player("Ana Fox", "1111", 100), player("Kit Wolf", "2222", 100),
    player("Sam Hare", "3333", 100)
-- What a round can move but never make or lose: every wallet and escrow,
-- plus what the house has kept of the stakes nobody won.
local function conserved()
    return util.roundMoney(worldMoney() + (bank.state.ccg_house_profit or 0))
end
local start = conserved()

-- Round one ---------------------------------------------------------------------

local lobby = actions.CCG_CREATE_LOBBY(asConsole({ game = "heads_tails" })).lobby
local code = lobby.code
assert(lobby.round == 1 and not lobby.closed)
actions.BET_JOIN(as(ana, { code = code, display_name = "Ana" }))
actions.BET_JOIN(as(kit, { code = code, display_name = "Kit" }))
actions.BET_PLACE_WAGER(as(ana, { code = code, selection = "heads", amount = 10 }))
actions.BET_PLACE_WAGER(as(kit, { code = code, selection = "tails", amount = 10 }))
actions.CCG_START(asConsole({ code = code }))

-- Joining mid-round is joining the next one. Wagering now is refused before
-- the Bank takes anything.
local joined = actions.BET_JOIN(as(sam, { code = code, display_name = "Sam" }))
assert(joined.lobby.status == "running" and not joined.player.playing,
    "a running lobby can be joined, for the next round")
rejected(actions.BET_PLACE_WAGER, "LOBBY_CLOSED",
    as(sam, { code = code, selection = "heads", amount = 5 }))
assert(wallet(sam) == 100, "a refused wager takes nothing")
-- Nobody leaves a round they have money in.
rejected(actions.BET_LEAVE, "GAME_STARTED", as(ana, { code = code }))
-- A round in progress cannot be skipped past.
rejected(actions.CCG_NEXT_ROUND, "GAME_STARTED", asConsole({ code = code }))

finishRound()
local after = actions.BET_LOBBY_STATUS(as(ana, { code = code }))
assert(after.lobby.status == "finished")
local anaWon = after.player.won
assert(conserved() == start, "a settled round moves money, it does not make it")

-- Round two: same code, same people, wagers cleared ------------------------------

local reopened = actions.CCG_NEXT_ROUND(asConsole({ code = code })).lobby
assert(reopened.code == code and reopened.round == 2 and reopened.status == "lobby",
    "the next round is the same lobby, under the same code")
assert(reopened.player_count == 3, "everybody stayed, and Sam is in now")
for _, seat in ipairs(reopened.players) do
    assert(seat.wager == 0 and not seat.ready, "every wager is cleared")
end
assert(bank.state.ccg_escrow[code] == nil, "and nothing of round one is left in escrow")
-- A Pocket that looked away still finds out how round one went.
local last = actions.BET_LOBBY_STATUS(as(ana, { code = code })).last
assert(last and last.round == 1 and last.played and last.won == anaWon
    and last.outcome == after.lobby.outcome, "round one, as Ana played it")
assert(not actions.BET_LOBBY_STATUS(as(sam, { code = code })).last.played,
    "Sam was not in round one")

-- Only Ana wagers. Kit and Sam sit this round out rather than holding it up.
actions.BET_PLACE_WAGER(as(ana, { code = code, selection = "heads", amount = 5 }))
local second = actions.CCG_START(asConsole({ code = code })).lobby
assert(second.status == "running", "one wager is enough to start")
local kitSeat = actions.BET_LOBBY_STATUS(as(kit, { code = code })).player
assert(not kitSeat.playing, "Kit sits it out")
-- Sitting out, Kit could go mid-round: no money of theirs is in it.
finishRound()
local stakes = 0
for _, escrow in pairs(bank.state.ccg_escrow or {}) do
    for _, amount in pairs(escrow.stakes) do stakes = stakes + amount end
end
assert(stakes == 0, "settled: nothing held")
local kitResult = actions.BET_LOBBY_STATUS(as(kit, { code = code }))
-- (A win is held for a day, so round one left Kit 90 available either way.)
assert(not kitResult.player.won and kitResult.wallet.available == 90,
    "Kit's wallet is only touched by round one")

-- Round three, another game, and leaving between rounds ----------------------------

actions.CCG_NEXT_ROUND(asConsole({ code = code, game = "race" }))
local raceLobby = actions.BET_LOBBY_STATUS(as(sam, { code = code })).lobby
assert(raceLobby.game == "race" and raceLobby.code == code and raceLobby.round == 3,
    "the game changes; the lobby and its code do not")
local outsider = player("Lee Owl", "5555", 50)
rejected(actions.BET_PLACE_WAGER, "NOT_JOINED",
    as(outsider, { code = code, selection = "red", amount = 5 }))
assert(wallet(outsider) == 50 and not (bank.state.ccg_escrow[code]
    and bank.state.ccg_escrow[code].stakes[outsider.account.account.account_id]),
    "a wager from outside the lobby is refused before the Bank takes it")
start = conserved()
local samBefore = wallet(sam)
actions.BET_PLACE_WAGER(as(sam, { code = code, selection = "red", amount = 8 }))
-- The Bank is down: leaving with a stake waits for it rather than leaving
-- the money in escrow to be settled as a loss.
bankOffline = { CCG_ESCROW_RELEASE = true }
local ok = pcall(actions.BET_LEAVE, as(sam, { code = code }))
bankOffline = false
assert(not ok, "leaving fails while the Bank cannot give the stake back")
assert(ccg.state.lobbies[ccg.state.codes[code]].players[sam.account.account.account_id],
    "and Sam is still in, with the stake")
assert(actions.BET_LEAVE(as(sam, { code = code })).left)
assert(wallet(sam) == samBefore, "the stake comes back on leaving")
-- Kit goes between rounds: allowed, nothing to give back.
actions.BET_PLACE_WAGER(as(ana, { code = code, selection = "blue", amount = 4 }))
actions.CCG_START(asConsole({ code = code }))
finishRound()
assert(actions.BET_LEAVE(as(kit, { code = code })).left, "leaving after a round")
rejected(actions.BET_LOBBY_STATUS, "NOT_JOINED", as(kit, { code = code }))
assert(conserved() == start, "three rounds and two leaves, and nothing made or lost")

-- Somebody who walked off -----------------------------------------------------------

actions.CCG_NEXT_ROUND(asConsole({ code = code, game = "heads_tails" }))
actions.BET_JOIN(as(kit, { code = code, display_name = "Kit" }))
actions.BET_PLACE_WAGER(as(ana, { code = code, selection = "tails", amount = 3 }))
currentEpoch = currentEpoch + 125000
ccg.process_games()
local seats = ccg.state.lobbies[ccg.state.codes[code]].players
assert(seats[ana.account.account.account_id], "a wager keeps its player however long")
assert(not seats[kit.account.account.account_id],
    "somebody who never wagered and went quiet is dropped")
actions.CCG_START(asConsole({ code = code }))
finishRound()

-- Survivor, with somebody sitting out ---------------------------------------------

actions.CCG_NEXT_ROUND(asConsole({ code = code, game = "survivor" }))
actions.BET_JOIN(as(sam, { code = code, display_name = "Sam" }))
actions.BET_JOIN(as(kit, { code = code, display_name = "Kit" }))
actions.BET_PLACE_WAGER(as(ana, { code = code, amount = 2 }))
rejected(actions.CCG_START, "NOT_ENOUGH_PLAYERS", asConsole({ code = code }))
actions.BET_PLACE_WAGER(as(sam, { code = code, amount = 2 }))
local arena = actions.CCG_START(asConsole({ code = code })).lobby
local onRing = 0
for _, seat in ipairs(arena.players) do
    if seat.alive then onRing = onRing + 1 end
    if seat.display_name == "Kit" then
        assert(not seat.alive and seat.x == nil, "Kit is not on the ring")
    end
end
assert(onRing == 2, "the two with a wager are")
local ring = ccg.state.lobbies[ccg.state.codes[code]]
ring.players[sam.account.account.account_id].x = 1200
currentEpoch = currentEpoch + 200
ccg.process_games()
assert(ring.status == "finished" and ring.winner_account_id == ana.account.account.account_id,
    "and Survivor is settled between them")
assert(conserved() == start, "nothing made or lost by Survivor either")
actions.BET_LEAVE(as(kit, { code = code }))
actions.BET_LEAVE(as(sam, { code = code }))

-- Survivor takes eight -------------------------------------------------------------

actions.CCG_NEXT_ROUND(asConsole({ code = code, game = "heads_tails" }))
local crowd = {}
for index = 1, 8 do
    crowd[index] = player("Crowd " .. index, "4444", 10)
    actions.BET_JOIN(as(crowd[index], { code = code, display_name = "Crowd " .. index }))
end
actions.BET_PLACE_WAGER(as(ana, { code = code, selection = "heads", amount = 1 }))
actions.CCG_START(asConsole({ code = code }))
finishRound()
rejected(actions.CCG_NEXT_ROUND, "LOBBY_FULL", asConsole({ code = code, game = "survivor" }))
-- Eight new accounts brought money of their own into the world.
start = conserved()

-- Closing, and the code the console keeps -------------------------------------------

local closed = actions.CCG_CANCEL_LOBBY(asConsole({ code = code })).lobby
assert(closed.closed, "CLOSE ends the lobby")
rejected(actions.CCG_NEXT_ROUND, "LOBBY_CLOSED", asConsole({ code = code }))
rejected(actions.BET_JOIN, "LOBBY_NOT_FOUND", as(sam, { code = code, display_name = "Sam" }))
local fresh = actions.CCG_CREATE_LOBBY(asConsole({ game = "race" })).lobby
assert(fresh.code == code and fresh.round == 1,
    "a console's next lobby keeps its code")
rejected(actions.BET_LOBBY_STATUS, "NOT_JOINED", as(ana, { code = code }))

-- A refund the Bank never heard ------------------------------------------------------

actions.BET_JOIN(as(ana, { code = code, display_name = "Ana" }))
local anaBefore = wallet(ana)
actions.BET_PLACE_WAGER(as(ana, { code = code, selection = "red", amount = 6 }))
bankOffline = true
currentEpoch = currentEpoch + 6 * 60 * 1000
ccg.process_games()
local expired = ccg.state.lobbies[ccg.state.codes[code]]
assert(expired.status == "cancelled" and expired.closed and expired.refund_pending,
    "an expired lobby whose refund went unanswered remembers it")
-- Its code cannot be reused while the Bank still holds money under it.
local meanwhile = actions.CCG_CREATE_LOBBY(asConsole({ game = "race" })).lobby
assert(meanwhile.code ~= code, "a new code while the old one has money in escrow")
actions.CCG_CANCEL_LOBBY(asConsole({ code = meanwhile.code }))
bankOffline = false
currentEpoch = currentEpoch + 11000
ccg.process_games()
assert(not expired.refund_pending and wallet(ana) == anaBefore,
    "the refund is sent again, and the stake is back")
assert(conserved() == start, "and at the end, nothing was made or lost")

print("host_ccg_rounds_test: OK")
