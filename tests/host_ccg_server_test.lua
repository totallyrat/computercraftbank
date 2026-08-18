-- Bank-authoritative ComputerCraftGaming wallets, holds, chance games, and
-- Survivor settlement.

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
shell = {
    getRunningProgram = function() return "/pumpe/bank_server.lua" end,
}

local util = require("lib.util")
util.loadTable = function(_, fallback) return util.copy(fallback) end
util.saveTable = function() end
package.loaded["lib.util"] = util

PUMPE_TEST_MODE = true
local bank = assert(loadfile("../bank_server.lua"))()
PUMPE_TEST_MODE = nil
local actions = bank.actions

local ccgDeployment = bank.deployment_files("ccg")
local deployedCCG = false
for _, file in ipairs(ccgDeployment) do
    if file.path == "ccg.lua" and file.source == "ccg.lua" then
        deployedCCG = true
    end
end
assert(deployedCCG, "CCG must be available through Easy Deployment")

local function rejected(action, expectedCode, payload)
    local ok, result = pcall(action, payload)
    assert(not ok, "request should have been rejected")
    assert(type(result) == "table" and result.code == expectedCode,
        "expected " .. expectedCode .. ", got " .. tostring(result.code))
end

local function register(name, pin)
    return actions.REGISTER({ name = name, pin = pin, gender = "Not set" })
end

local function unlock(account, pin)
    return actions.BET_UNLOCK({
        session_token = account.session_token,
        pin = pin,
    }).bet_token
end

local function deposit(account, pin, amount)
    return actions.BET_WALLET_DEPOSIT({
        session_token = account.session_token,
        pin = pin,
        amount = amount,
    })
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
bank.process_ccg_games()
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
bank.process_ccg_games()
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
local live = bank.state.ccg_lobbies[survivor.lobby_id]
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
bank.state.ccg_lobbies[interrupted.lobby_id].bank_boot_id = "OLD_BOOT"
bank.process_ccg_games()
local interruptedResult = actions.BET_LOBBY_STATUS({
    bet_token = firstBet, code = interrupted.code,
})
assert(interruptedResult.lobby.status == "cancelled")
assert(interruptedResult.wallet.available == firstBefore)

print("host_ccg_server_test: OK")
