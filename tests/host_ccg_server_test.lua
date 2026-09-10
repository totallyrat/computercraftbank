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

local console = actions.CCG_REGISTER({ name = "Neon Arena" })
local consoleAuth = {
    console_id = console.console_id,
    console_token = console.console_token,
}

local first = register("Heads Player", "1111")
local second = register("Tails Player", "2222")
rejected(actions.BET_UNLOCK, "BAD_PIN", {
    session_token = first.session_token,
    pin = "9999",
})
deposit(first, "1111", 100)
deposit(second, "2222", 100)
local firstBet = unlock(first, "1111")
local secondBet = unlock(second, "2222")

local chance = actions.CCG_CREATE_LOBBY({
    console_id = consoleAuth.console_id,
    console_token = consoleAuth.console_token,
    game = "heads_tails",
}).lobby
actions.BET_JOIN({
    bet_token = firstBet,
    code = chance.code,
    display_name = "Heads Hero",
})
actions.BET_JOIN({
    bet_token = secondBet,
    code = chance.code,
    display_name = "Tails Hero",
})
actions.BET_PLACE_WAGER({
    bet_token = firstBet, code = chance.code,
    selection = "heads", amount = 10,
})
actions.BET_PLACE_WAGER({
    bet_token = secondBet, code = chance.code,
    selection = "tails", amount = 10,
})
local started = actions.CCG_START({
    console_id = consoleAuth.console_id,
    console_token = consoleAuth.console_token,
    code = chance.code,
    outcome = "client-cannot-choose-this",
}).lobby
assert(started.outcome == "heads" or started.outcome == "tails")

currentEpoch = currentEpoch + 7000
ccg.process_games()
local firstResult = actions.BET_LOBBY_STATUS({
    bet_token = firstBet, code = chance.code,
})
local secondResult = actions.BET_LOBBY_STATUS({
    bet_token = secondBet, code = chance.code,
})
assert(firstResult.lobby.status == "finished")
assert(firstResult.player.won ~= secondResult.player.won)
local winner = firstResult.player.won and first or second
local winnerPin = firstResult.player.won and "1111" or "2222"
local winnerResult = firstResult.player.won and firstResult or secondResult
local loserResult = firstResult.player.won and secondResult or firstResult
assert(winnerResult.player.payout == 20)
assert(winnerResult.wallet.available == 90)
assert(winnerResult.wallet.held == 20)
assert(loserResult.wallet.available == 90)
assert(loserResult.wallet.held == 0)

-- A next-day number alone is not enough if a full 24 in-game hours have not
-- passed since settlement.
currentDay, currentTime = 301, 11.9
bank.process_bet_holds()
local beforeRelease = actions.BET_WALLET_SUMMARY({
    session_token = winner.session_token,
}).wallet
assert(beforeRelease.available == 90 and beforeRelease.held == 20)
currentTime = 12
bank.process_bet_holds()
local afterRelease = actions.BET_WALLET_SUMMARY({
    session_token = winner.session_token,
}).wallet
assert(afterRelease.available == 110 and afterRelease.held == 0)

local cashed = actions.BET_WALLET_WITHDRAW({
    session_token = winner.session_token,
    pin = winnerPin,
    amount = 50,
})
assert(cashed.wallet.available == 60)
assert(cashed.account_balance == 450)

-- Cover every race color so exactly one server-random winner receives 3X.
local raceColors = { "red", "orange", "yellow", "green", "blue", "purple" }
local raceAccounts, raceTokens = {}, {}
local race = actions.CCG_CREATE_LOBBY({
    console_id = consoleAuth.console_id,
    console_token = consoleAuth.console_token,
    game = "race",
}).lobby
for index, colorName in ipairs(raceColors) do
    local account = register("Race Player " .. index, "3333")
    deposit(account, "3333", 10)
    local token = unlock(account, "3333")
    raceAccounts[index], raceTokens[index] = account, token
    actions.BET_JOIN({
        bet_token = token,
        code = race.code,
        display_name = "Racer " .. index,
    })
    actions.BET_PLACE_WAGER({
        bet_token = token,
        code = race.code,
        selection = colorName,
        amount = 2,
    })
end
local raceStart = actions.CCG_START({
    console_id = consoleAuth.console_id,
    console_token = consoleAuth.console_token,
    code = race.code,
}).lobby
assert(#raceStart.race_order == 6)
currentEpoch = currentEpoch + 7000
ccg.process_games()
local raceWinners = 0
for index, token in ipairs(raceTokens) do
    local result = actions.BET_LOBBY_STATUS({
        bet_token = token,
        code = race.code,
    })
    if result.player.won then
        raceWinners = raceWinners + 1
        assert(result.player.selection == raceStart.outcome)
        assert(result.player.payout == 6)
        assert(result.wallet.held == 6)
    end
end
assert(raceWinners == 1)

-- Survivor is settled from server-owned positions, never a client-supplied
-- winner. Force one player beyond the shrinking ring and tick the simulation.
local survivor = actions.CCG_CREATE_LOBBY({
    console_id = consoleAuth.console_id,
    console_token = consoleAuth.console_token,
    game = "survivor",
}).lobby
actions.BET_JOIN({
    bet_token = firstBet, code = survivor.code, display_name = "Pusher",
})
actions.BET_JOIN({
    bet_token = secondBet, code = survivor.code, display_name = "Faller",
})
actions.BET_PLACE_WAGER({
    bet_token = firstBet, code = survivor.code,
    selection = "ignored", amount = 5,
})
actions.BET_PLACE_WAGER({
    bet_token = secondBet, code = survivor.code,
    selection = "ignored", amount = 5,
})
actions.CCG_START({
    console_id = consoleAuth.console_id,
    console_token = consoleAuth.console_token,
    code = survivor.code,
})
local control = actions.BET_CONTROL({
    bet_token = firstBet,
    code = survivor.code,
    dx = 1,
    dy = 0,
    push = true,
})
assert(control.accepted and control.pushed)
local cooldown = actions.BET_CONTROL({
    bet_token = firstBet,
    code = survivor.code,
    dx = 0,
    dy = -1,
    push = true,
})
assert(cooldown.accepted and not cooldown.pushed)
local live = ccg.state.lobbies[survivor.lobby_id]
live.players[first.account.account_id].x = 0
live.players[first.account.account_id].y = 0
live.players[second.account.account_id].x = 1200
live.players[second.account.account_id].y = 0
currentEpoch = currentEpoch + 200
local survivorResult = actions.CCG_TICK({
    console_id = consoleAuth.console_id,
    console_token = consoleAuth.console_token,
    code = survivor.code,
}).lobby
assert(survivorResult.status == "finished")
assert(survivorResult.winner_player_id == first.account.account_id)
local pusherResult = actions.BET_LOBBY_STATUS({
    bet_token = firstBet, code = survivor.code,
})
assert(pusherResult.player.won)
assert(pusherResult.player.payout == 15)

local interrupted = actions.CCG_CREATE_LOBBY({
    console_id = consoleAuth.console_id,
    console_token = consoleAuth.console_token,
    game = "survivor",
}).lobby
actions.BET_JOIN({
    bet_token = firstBet, code = interrupted.code, display_name = "Safe One",
})
actions.BET_JOIN({
    bet_token = secondBet, code = interrupted.code, display_name = "Safe Two",
})
local firstBefore = actions.BET_WALLET_SUMMARY({
    session_token = first.session_token,
}).wallet.available
actions.BET_PLACE_WAGER({
    bet_token = firstBet, code = interrupted.code,
    selection = "survivor", amount = 3,
})
actions.BET_PLACE_WAGER({
    bet_token = secondBet, code = interrupted.code,
    selection = "survivor", amount = 3,
})
actions.CCG_START({
    console_id = consoleAuth.console_id,
    console_token = consoleAuth.console_token,
    code = interrupted.code,
})
ccg.state.lobbies[interrupted.lobby_id].boot_id = "OLD_BOOT"
ccg.process_games()
local interruptedResult = actions.BET_LOBBY_STATUS({
    bet_token = firstBet, code = interrupted.code,
})
assert(interruptedResult.lobby.status == "cancelled")
assert(interruptedResult.wallet.available == firstBefore)



-- The split itself ---------------------------------------------------------------
-- Everything above is the games behaving as they always did. What follows is
-- what is new: two computers, and a Bank that does not take the CCG Server's
-- word for anything to do with money.

-- Every wager really did cross the wire.
local askedBank = {}
for _, call in ipairs(bankCalls) do askedBank[call] = true end
assert(askedBank.CCG_WHO, "the CCG Server has no accounts: it asks the Bank")
assert(askedBank.CCG_ESCROW_SET, "and the Bank is what takes a wager")
assert(askedBank.CCG_ESCROW_SETTLE, "and what pays one out")

-- A CCG Server nobody registered gets nothing, whatever it asks for.
local realToken = ccg.state.server_token
ccg.state.server_token = "made up"
rejected(bank.actions.CCG_WHO, "CCG_AUTH",
    { server_token = "made up", bet_token = "anything" })
rejected(bank.actions.CCG_ESCROW_SETTLE, "CCG_AUTH",
    { server_token = "made up", lobby_code = "ABCDEF" })
ccg.state.server_token = realToken
rejected(bank.actions.CCG_SERVER_REGISTER, "BAD_CODE", { code = "1234" })

-- It cannot invent money either. The Bank multiplies the stake it is
-- already holding, so naming a winner is the whole of what a settle can do.
local rich = register("Rich Player", "3333")
deposit(rich, "3333", 500)
local richBet = unlock(rich, "3333")
local greedy = actions.CCG_CREATE_LOBBY({
    console_id = consoleAuth.console_id,
    console_token = consoleAuth.console_token,
    game = "heads_tails",
}).lobby
actions.BET_JOIN({ bet_token = richBet, code = greedy.code,
    display_name = "Rich" })
actions.BET_PLACE_WAGER({ bet_token = richBet, code = greedy.code,
    selection = "heads", amount = 10 })

local before = worldMoney()
-- A payout the server would rather have. The Bank ignores it entirely.
local settled = bank.actions.CCG_ESCROW_SETTLE({
    server_token = ccg.state.server_token,
    lobby_code = greedy.code,
    winners = { rich.account.account_id },
    payout = 999999,
    payouts = { [rich.account.account_id] = 999999 },
})
assert(settled.payouts == 20,
    "the payout is the stake times the game's multiplier, not what the CCG"
        .. " Server asked for: got " .. tostring(settled.payouts))
assert(worldMoney() == before + 10,
    "and the world gained exactly the house's share of one 10 stake")

-- A lobby the CCG Server walks away from comes back on its own -------------------
-- This is what makes it safe to put wagers on a computer somebody might
-- switch off in the middle of a round.

-- A second console, because the first one still thinks its lobby is open:
-- the settle above went straight to the Bank, which is the point of it.
local other = actions.CCG_REGISTER({ name = "Second Arena" })
local otherAuth = { console_id = other.console_id,
    console_token = other.console_token }

local abandoned = actions.CCG_CREATE_LOBBY({
    console_id = otherAuth.console_id,
    console_token = otherAuth.console_token,
    game = "race",
}).lobby
actions.BET_JOIN({ bet_token = richBet, code = abandoned.code,
    display_name = "Rich" })
actions.BET_PLACE_WAGER({ bet_token = richBet, code = abandoned.code,
    selection = "red", amount = 25 })
local walletBefore = bank.actions.BET_WALLET_SUMMARY({
    session_token = rich.session_token }).wallet.available
local totalBefore = worldMoney()

-- The CCG Server is gone. Nobody settles, nobody refunds.
ccg.state.lobbies = {}
ccg.state.codes = {}
bank.sweep_ccg_escrow()
assert(worldMoney() == totalBefore, "a sweep creates and destroys nothing")
assert(bank.actions.BET_WALLET_SUMMARY({
    session_token = rich.session_token }).wallet.available == walletBefore,
    "and nothing comes back before the escrow is actually old")

currentEpoch = currentEpoch + 3 * 60 * 60 * 1000
bank.sweep_ccg_escrow()
assert(bank.actions.BET_WALLET_SUMMARY({
    session_token = rich.session_token }).wallet.available
    == walletBefore + 25,
    "an abandoned wager is given back by the Bank, without the CCG Server")
assert(worldMoney() == totalBefore, "and still nothing was made or lost")

-- Three hours passed above, so the bet session has to be re-unlocked with
-- the PIN, exactly as it would on a real phone.
richBet = unlock(rich, "3333")

-- Leaving a lobby returns the stake, across the wire.
local leaver = actions.CCG_CREATE_LOBBY({
    console_id = otherAuth.console_id,
    console_token = otherAuth.console_token,
    game = "race",
}).lobby
actions.BET_JOIN({ bet_token = richBet, code = leaver.code,
    display_name = "Rich" })
actions.BET_PLACE_WAGER({ bet_token = richBet, code = leaver.code,
    selection = "blue", amount = 30 })
local held = worldMoney()
local left = actions.BET_LEAVE({ bet_token = richBet, code = leaver.code })
assert(left.left and left.wallet.available == walletBefore + 25,
    "the stake is back in the wallet")
assert(worldMoney() == held, "and the total is unchanged by leaving")

-- A settle the Bank never answered ------------------------------------------------
-- If the CCG Server called a lobby settled without hearing back, the escrow
-- would still be sitting on the Bank and the winner would never be paid.
-- It has to stay open and try again.

-- A third console: the second one's lobby was left open above on purpose.
local third = actions.CCG_REGISTER({ name = "Third Arena" })
local thirdAuth = { console_id = third.console_id,
    console_token = third.console_token }

local dropped = actions.CCG_CREATE_LOBBY({
    console_id = thirdAuth.console_id,
    console_token = thirdAuth.console_token,
    game = "heads_tails",
}).lobby
actions.BET_JOIN({ bet_token = richBet, code = dropped.code,
    display_name = "Rich" })
actions.BET_PLACE_WAGER({ bet_token = richBet, code = dropped.code,
    selection = "heads", amount = 40 })
actions.CCG_START({
    console_id = thirdAuth.console_id,
    console_token = thirdAuth.console_token,
    code = dropped.code,
})

local beforeDrop = worldMoney()
bankOffline = true
currentEpoch = currentEpoch + 7000
ccg.process_games()
bankOffline = false

local stillOpen = ccg.state.lobbies[dropped.lobby_id]
assert(stillOpen.status == "running" and not stillOpen.escrow_closed,
    "a settle the Bank did not answer leaves the lobby open, because the"
        .. " money is still in escrow there")
assert(worldMoney() == beforeDrop,
    "and nothing was made or lost while it was unreachable")

-- The Bank is back, and the next tick finishes what it started.
ccg.process_games()
assert(ccg.state.lobbies[dropped.lobby_id].status == "finished",
    "the retry settles it")
local paid = bank.actions.BET_WALLET_SUMMARY({
    session_token = rich.session_token }).wallet
local won = stillOpen.outcome == "heads"
assert((paid.held > 0) == won,
    won and "the winner is paid on the retry"
        or "and a loser is not")

print("host_ccg_server_test: OK")
