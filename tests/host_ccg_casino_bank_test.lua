-- The CCG Casino's money, FoxyOS 16.1, on a real Bank Core and Vault -- ahead
-- of the FoxyOS 17 CCG Casino that uses it.
--
-- Roulette, Blackjack, Poker and the casino's Heads or Tails pay by the bet:
-- a stake is a list of bets, each of a kind the game has, and the CCG Server
-- says only how each one ended. What that pays is the Bank's own table, so a
-- server can call a bet the wrong way but cannot name a price, and nothing
-- here makes or loses money beyond what the table says. A tie is the stake
-- straight back; winnings are held for a day like any CCG win.
--
-- And whose a casino is: the CCG Server asks which companies the person
-- setting one up owns, with their own session.

package.path = "../?.lua;../?/init.lua;" .. package.path
sleep = function() end
local harness = require("bank_pair_harness")
local rejected = harness.rejected
local bank = harness.pair()

local ana = bank.register("Ana Fox", "1234")
local kit = bank.register("Kit Wolf", "5678")
local sam = bank.register("Sam Hare", "4321")
for _, who in ipairs({ ana, kit, sam }) do
    bank.request("BET_WALLET_DEPOSIT", bank.as(who, { pin = who.pin, amount = 200 }))
    who.bet = bank.request("BET_UNLOCK", bank.as(who, { pin = who.pin })).bet_token
end

local server = bank.request("CCG_SERVER_REGISTER", { code = "4040", name = "Casino" }).server_token
local function asServer(extra)
    extra = extra or {}
    extra.server_token = server
    return extra
end
local function stake(who, code, game, bets)
    return bank.request("CCG_ESCROW_SET", asServer({ bet_token = who.bet,
        lobby_code = code, game = game, bets = bets }))
end
local function wallet(who)
    return bank.request("BET_WALLET_SUMMARY", bank.as(who)).wallet
end
local function world()
    local total = bank.state.ccg_house_profit or 0
    for _, account in pairs(bank.state.accounts) do
        local purse = account.bet_wallet or {}
        total = total + (purse.balance or 0)
        for _, hold in pairs(purse.holds or {}) do
            if hold.status == "holding" then total = total + hold.amount end
        end
    end
    for _, escrow in pairs(bank.state.ccg_escrow or {}) do
        for _, amount in pairs(escrow.stakes) do total = total + amount end
    end
    return total
end
local start = world()
local function house() return bank.state.ccg_house_profit or 0 end
local houseBefore = house()

-- Roulette: three bets at once -------------------------------------------------------------

stake(ana, "ROUL01", "roulette", { { kind = "straight", amount = 10 },
    { kind = "even", amount = 5 }, { kind = "dozen", amount = 5 } })
assert(wallet(ana).available == 180, "three bets, twenty staked")
-- A bet the game does not have, too many bets, too much at once, a game
-- that pays by the bet staked as one wager: all refused, nothing taken.
rejected(bank.request, "INVALID_BET", "CCG_ESCROW_SET", asServer({ bet_token = kit.bet,
    lobby_code = "ROUL01", game = "roulette", bets = { { kind = "hand", amount = 5 } } }))
local many = {}
for index = 1, 9 do many[index] = { kind = "even", amount = 1 } end
rejected(bank.request, "INVALID_BETS", "CCG_ESCROW_SET", asServer({ bet_token = kit.bet,
    lobby_code = "ROUL01", game = "roulette", bets = many }))
rejected(bank.request, "INVALID_AMOUNT", "CCG_ESCROW_SET", asServer({ bet_token = kit.bet,
    lobby_code = "ROUL01", game = "roulette", bets = { { kind = "even", amount = 9000 },
    { kind = "even", amount = 9000 } } }))
rejected(bank.request, "INVALID_BETS", "CCG_ESCROW_SET", asServer({ bet_token = kit.bet,
    lobby_code = "ROUL01", game = "roulette", amount = 5 }))
assert(wallet(kit).available == 200)
stake(kit, "ROUL01", "roulette", { { kind = "even", amount = 10 } })

-- The server says Ana's straight and dozen won, her even bet lost; and it
-- tries to make Kit's even bet a blackjack, and to name its own payout.
local settled = bank.request("CCG_ESCROW_SETTLE", asServer({ lobby_code = "ROUL01",
    results = { [ana.id] = { "win", "lose", "win" }, [kit.id] = { "blackjack" } },
    payouts = { [kit.id] = 99999 } }))
assert(settled.stakes == 30 and settled.payouts == 375,
    "36x10 and 3x5 for Ana; nothing for an ending an even bet cannot have")
assert(wallet(ana).held == 375 and wallet(ana).available == 180, "Ana's win is held")
assert(wallet(kit).held == 0 and wallet(kit).available == 190, "Kit lost his ten")
assert(bank.state.ccg_escrow.ROUL01 == nil, "the round's escrow is closed")
assert(house() == houseBefore - 345, "the house paid 375 against 30 staked, and no more")
assert(world() == start, "money moved between the house and the players, none was made")
houseBefore = house()

-- Blackjack: a double, a blackjack, a push and a loss ---------------------------------------

stake(ana, "JACK01", "blackjack", { { kind = "hand", amount = 10 } })
stake(kit, "JACK01", "blackjack", { { kind = "hand", amount = 20 } })
stake(sam, "JACK01", "blackjack", { { kind = "hand", amount = 10 } })
-- Sam doubles: the same bet, staked again.
stake(sam, "JACK01", "blackjack", { { kind = "hand", amount = 20 } })
assert(wallet(sam).available == 180, "the double took ten more, not twenty")
local samHeld = wallet(sam).held
settled = bank.request("CCG_ESCROW_SETTLE", asServer({ lobby_code = "JACK01",
    results = { [ana.id] = "blackjack", [kit.id] = "push", [sam.id] = "win" } }))
assert(settled.stakes == 50 and settled.payouts == 85,
    "25 for Ana, 20 back to Kit, 40 for Sam: " .. tostring(settled.payouts))
assert(wallet(ana).held == 375 + 25, "a blackjack pays three to two")
assert(wallet(kit).available == 190 and wallet(kit).held == 0,
    "a push is the stake straight back, not held")
assert(wallet(sam).available == 180 and wallet(sam).held == samHeld + 40,
    "Sam's double won double: the doubled stake, once")
assert(house() == houseBefore - 35, "the house paid out 85 against 50")
assert(world() == start, "and none was made")

-- Poker and Heads or Tails, at the casino ------------------------------------------------------

stake(kit, "POKR01", "poker", { { kind = "hand", amount = 8 } })
settled = bank.request("CCG_ESCROW_SETTLE", asServer({ lobby_code = "POKR01",
    results = { [kit.id] = "win" } }))
assert(settled.payouts == 16, "poker pays even money")
stake(sam, "COIN01", "heads_tails", { { kind = "pick", amount = 6 } })
settled = bank.request("CCG_ESCROW_SETTLE", asServer({ lobby_code = "COIN01",
    results = { [sam.id] = "win" } }))
assert(settled.payouts == 12, "and Heads or Tails pays double, by the bet too")
-- Leaving before a round gives every bet back.
stake(ana, "ROUL02", "roulette", { { kind = "straight", amount = 4 }, { kind = "even", amount = 4 } })
local before = wallet(ana).available
bank.request("CCG_ESCROW_RELEASE", asServer({ lobby_code = "ROUL02", account_id = ana.id }))
assert(wallet(ana).available == before + 8, "both bets come back")
-- The old lobbies still pay by the game, one wager each.
rejected(bank.request, "BAD_GAME", "CCG_ESCROW_SET", asServer({ bet_token = kit.bet,
    lobby_code = "OLDRC1", game = "race", bets = { { kind = "pick", amount = 5 } } }))
bank.request("CCG_ESCROW_SET", asServer({ bet_token = kit.bet, lobby_code = "OLDRC1",
    game = "race", amount = 5 }))
settled = bank.request("CCG_ESCROW_SETTLE", asServer({ lobby_code = "OLDRC1",
    winners = { kit.id } }))
assert(settled.payouts == 15, "Race still pays three times the stake")
-- And a casino game cannot be settled the old way.
stake(sam, "ROUL03", "roulette", { { kind = "even", amount = 2 } })
rejected(bank.request, "BAD_GAME", "CCG_ESCROW_SETTLE", asServer({ lobby_code = "ROUL03",
    winners = { sam.id } }))

-- Whose a casino is -------------------------------------------------------------------------

bank.request("COMPANY_CREATE", bank.as(ana, { company_name = "Fox Casino", app_id = "COMPANY" }))
bank.request("COMPANY_CREATE", bank.as(ana, { company_name = "Ace Games", app_id = "COMPANY" }))
local mine = bank.request("CCG_COMPANIES", asServer({ session_token = ana.token }))
assert(mine.account_id == ana.id and mine.name == "Ana Fox", "who is asking")
assert(#mine.companies == 2 and mine.companies[1].name == "Ace Games"
    and mine.companies[2].name == "Fox Casino", "the companies Ana owns, A to Z")
assert(#bank.request("CCG_COMPANIES", asServer({ session_token = kit.token })).companies == 0)
rejected(bank.request, "CCG_AUTH", "CCG_COMPANIES", { server_token = "made up",
    session_token = ana.token })
rejected(bank.request, "SESSION_EXPIRED", "CCG_COMPANIES", asServer({ session_token = "nope" }))

print("host_ccg_casino_bank_test: OK")
