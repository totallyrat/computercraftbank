-- Trivia at a CCG Casino, FoxyOS 18.1: the CCG Server and a real Bank.
--
-- All or nothing. A player stakes once and answers question after question:
-- every right answer makes the pot 1.5 times bigger, one wrong answer loses
-- it, and they take it whenever they like between questions. At the longest
-- streak a table allows it is paid for them; leaving, or the table moving on
-- to another game, pays it too. The Bank holds the stake and works out every
-- amount; no money is made or lost on the way. Questions go round the topics
-- or stay on one, come from Open Trivia DB while there is HTTP and from the
-- built-in ones when there is not, and a company writes its own -- one at a
-- time, or a text file at once.

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
    getName = function(path) return tostring(path):match("([^/]*)$") end,
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
-- The CCG Server, once it is loaded: a client on its protocol (the table's
-- own computer, below) is answered by it rather than the Bank.
local servers = {}
package.loaded["lib.net"] = {
    openModems = function() return { "modem" } end,
    host = function() end,
    reply = function() end,
    locate = function() return nil end,
    autoUpdate = function() end,
    client = function(options)
        local toCcg = options and options.protocol == "PUMPE_CCG_V1"
        return {
            discover = function() return 1 end,
            isOnline = function() return true end,
            request = function(_, action, payload)
                if toCcg then
                    local ok, result = pcall(servers.ccg.actions[action], payload or {})
                    if ok then return result end
                    if type(result) == "table" and result.pumpe then
                        return nil, result.message, result.code
                    end
                    error(result, 0)
                end
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
servers.ccg = ccg

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

-- A table, three players --------------------------------------------------------------------------

local made = actions.CASINO_REGISTER(asOf(owner, { company_id = "COM9", name = "Quiz Night" }))
local console = { console_id = made.console_id, console_token = made.console_token }
local function tick()
    return actions.CASINO_TICK({ console_id = console.console_id,
        console_token = console.console_token }).table
end
local t = ccg.state.casinos[made.console_id]
local players = {}
for index = 1, 3 do
    local account = register("Quizzer " .. index, "1111")
    deposit(account, "1111", 500)
    players[index] = { account = account, bet = unlock(account, "1111") }
    actions.TABLE_JOIN({ bet_token = players[index].bet, code = made.code,
        display_name = "Quizzer " .. index })
end
-- Somebody who owns no company, made now: a new account starts with money.
local stranger = register("Not Olive", "2222")
local function conserved()
    local total = worldMoney() + (bank.state.ccg_house_profit or 0)
    for _, company in pairs(bank.state.companies) do
        total = total + (company.casino and company.casino.balance or 0)
    end
    for _, runs in pairs(bank.state.trivia_runs or {}) do
        for _, run in pairs(runs) do total = total + run.stake end
    end
    return util.roundMoney(total)
end
local start = conserved()
local function advance(ms)
    currentEpoch = currentEpoch + ms
    casino.tick(currentEpoch)
end
local function control(extra)
    extra.console_id = made.console_id
    return actions.CASINO_CONTROL(asOf(owner, extra))
end
local function status(index)
    return actions.TABLE_STATUS({ bet_token = players[index].bet, code = made.code })
end
-- The players' Pockets look at the table all the time, or they are gone.
local function untilPhase(phase, most)
    for step = 1, most or 80 do
        if t.phase == phase then return true end
        advance(500)
        if step % 20 == 0 then
            for index = 1, 3 do pcall(status, index) end
        end
    end
    return t.phase == phase
end
local function answer(index, pick, amount)
    return actions.TABLE_BET({ bet_token = players[index].bet, code = made.code,
        bets = { { kind = "answer", pick = pick, amount = amount } } })
end
local function cashout(index)
    return actions.TABLE_CASHOUT({ bet_token = players[index].bet, code = made.code })
end
local function wallet(index)
    return bank.state.accounts[players[index].account.account.account_id].bet_wallet
end
local function held(index)
    local total = 0
    for _, hold in pairs(bank.state.accounts[players[index].account.account.account_id]
        .bet_wallet.holds) do total = total + hold.amount end
    return util.roundMoney(total)
end
local function nextQuestion()
    untilPhase("result")
    untilPhase("betting")
end
local function company() return bank.state.companies.COM9.casino or { balance = 0 } end

-- No HTTP at all to start with: the built-in questions.
http = nil

-- Trivia mode -------------------------------------------------------------------------------------

local view = control({ op = "trivia", mode = true, topic = "minecraft" }).table
assert(view.trivia.mode and view.trivia.topic == "minecraft"
    and view.trivia.topic_name == "Minecraft")
assert(t.phase == "betting" and t.game == "trivia", "the first question, straight away")
local topics = {}
for _, topic in ipairs(view.trivia_topics) do topics[topic.id] = topic.name end
assert(topics.all and topics.science and topics.minecraft and not topics.ours,
    "every topic; no 'our questions' before there are any")

local seen = tick()
local q = seen.question
assert(q and q.topic == "Minecraft" and #q.choices == 4 and q.text ~= "", "a question")
assert(q.answer == nil, "and never its answer while bets are open")
local mine = status(1).table.question
assert(mine.answer == nil and mine.text == q.text, "a player sees the question, not the answer")

-- Three players stake 50 each: two right, one wrong.
local right = t.question.answer
local wrong = right % 4 + 1
assert(not pcall(answer, 1, 5, 50), "there is no fifth answer")
assert(not pcall(answer, 1, right, nil), "the first answer says how much")
local after = answer(1, right, 50)
assert(after.me.run.stake == 50 and after.me.run.pot == 50 and after.me.run.next_pot == 75,
    "staked: 50 now, 75 if right")
assert(wallet(1).balance == 450, "out of the Bet Wallet")
answer(2, wrong, 50)
answer(3, right, 50)
-- The Bank itself will not start a second run over the first, whoever asks.
rejected(bank.actions.CCG_TRIVIA_BUYIN, "IN_A_RUN", { server_token = ccg.state.server_token,
    bet_token = players[1].bet, lobby_code = made.code, amount = 10 })
for _, entry in ipairs(tick().players) do
    assert(entry.bets == nil, "nobody's answer is on the table's screen while bets are open")
end
-- Changing your mind is free: no stake, no money.
local calls = #bankCalls
answer(1, wrong, 999)
answer(1, right)
for index = calls + 1, #bankCalls do
    assert(bankCalls[index] ~= "CCG_TRIVIA_BUYIN", "a new answer, not a new stake")
end
assert(wallet(1).balance == 450 and t.players[players[1].account.account.account_id]
    .bets[1].pick == right)
assert(conserved() == start, "the stakes are held, not spent")

assert(untilPhase("playing") and t.step == "answer")
seen = tick()
assert(seen.question.answer == right, "the answer, shown")
assert(seen.question.counts[right] == 2 and seen.question.counts[wrong] == 1,
    "and how many chose each")
-- Nobody takes a pot while their answer is waiting to be shown.
local ok, err = pcall(cashout, 1)
assert(not ok and err.code == "GAME_STARTED", tostring(err and err.code))
assert(untilPhase("result"))
local one, two = status(1).me, status(2).me
assert(one.result.won and one.run.streak == 1 and one.run.pot == 75, "right: 1.5x, and on")
assert(not two.result.won and two.run == nil and two.taken.ended == "wrong",
    "wrong: all of it gone")
assert(wallet(2).balance == 450 and held(2) == 0)
assert(company().balance == 50, "the casino keeps a lost stake: " .. company().balance)
local inView = {}
for _, entry in ipairs(tick().players) do inView[entry.name] = entry end
assert(inView["Quizzer 1"].streak == 1 and inView["Quizzer 1"].pot == 75
    and inView["Quizzer 2"].pot == nil, "the room sees every streak")
assert(t.winners[1].payout == 75 and t.winners[1].streak == 1)
assert(conserved() == start, "no money made or lost")

-- The next question: Quizzer 1 answers it, Quizzer 3 sits it out and takes 75.
nextQuestion()
right = t.question.answer
answer(1, right)
local taken = cashout(3)
assert(taken.me.run == nil and taken.me.taken.payout == 75, "taken")
assert(held(3) == 75 and wallet(3).balance == 450, "75, held for a day like any CCG win")
assert(company().balance == 25, "the casino paid 25 over the stake")
assert(not pcall(cashout, 3), "nothing left to take")
nextQuestion()
one = status(1).me
assert(one.run.streak == 2 and one.run.pot == 112.5, "two right: " .. one.run.pot)
-- A question sat out leaves the pot where it is.
nextQuestion()
assert(status(1).me.run.pot == 112.5, "sat out, still 112.5")
cashout(1)
assert(held(1) == 112.5 and company().balance == -37.5, "a casino can borrow to pay")
assert(conserved() == start, "nothing made or lost")

-- Endless: nobody bets, and the answer still comes, then the next question.
nextQuestion()
local asked = t.trivia.asked
local first = t.question.text
assert(untilPhase("playing") and t.step == "answer", "answered with no bets")
nextQuestion()
assert(t.trivia.asked == asked + 1 and t.question.text ~= first, "and another, for ever")
for _ = 1, 6 do
    assert(t.question.topic == "Minecraft", "on its topic: " .. tostring(t.question.topic))
    nextQuestion()
end

-- The longest streak: paid without being asked.
local config = require("config")
config.ccg_trivia_max_streak = 3
answer(2, t.question.answer, 10)
for _ = 1, 2 do
    nextQuestion()
    answer(2, t.question.answer)
end
untilPhase("result")
two = status(2).me
assert(two.run == nil and two.result.ended == "top" and two.result.payout == 33.75,
    "three right at most: 10 x 1.5^3, paid " .. tostring(two.result.payout))
assert(held(2) == 33.75)
config.ccg_trivia_max_streak = 10

-- A table that cannot cover a pot does not take it.
config.ccg_casino_credit = 500
nextQuestion()
ok, err = pcall(answer, 3, 1, 50)
assert(not ok and err.code == "TABLE_LIMIT", "50 could become 2,883")
assert(wallet(3).balance == 450 and not (bank.state.trivia_runs or {})[made.code],
    "and nothing was taken")
config.ccg_casino_credit = 10000

-- Every topic, in turn.
control({ op = "trivia", topic = "all" })
local names = {}
for _ = 1, 4 do
    nextQuestion()
    names[#names + 1] = t.question.topic
end
assert(names[1] ~= names[2] and names[2] ~= names[3], "a different topic each time: "
    .. table.concat(names, ", "))

-- The dealer: REVEAL, with or without answers, and the next question.
control({ op = "take" })
assert(t.phase == "betting" and not t.phase_until, "bets wait for the dealer")
view = control({ op = "next" }).table
assert(t.phase == "playing" and t.step == "answer", "revealed by the dealer")
assert(untilPhase("result") and not t.phase_until, "and the result waits too")
view = control({ op = "next" }).table
assert(t.phase == "betting" and t.game == "trivia" and view.next_label == "REVEAL",
    tostring(view.next_label))
control({ op = "release" })

-- The table moves on to Roulette: every pot is paid what it has.
nextQuestion()
answer(1, t.question.answer, 20)
nextQuestion()
assert(status(1).me.run.pot == 30)
local before = held(1)
control({ op = "trivia", mode = false })
control({ op = "game", game = "roulette" })
assert(t.game == "roulette" and status(1).me.run == nil and held(1) == before + 30,
    "paid out when the questions stopped")
assert(status(1).me.taken.payout == 30, "and told so")
local inWheel = false
for _, game in ipairs(tick().games) do if game == "trivia" then inWheel = true end end
assert(inWheel, "Trivia is one of the wheel's games")

-- Leaving takes the pot; a pot nobody plays for is paid after a while.
control({ op = "trivia", mode = true })
answer(1, t.question.answer, 20)
nextQuestion()
before = held(1)
actions.TABLE_LEAVE({ bet_token = players[1].bet, code = made.code })
assert(held(1) == before + 30, "left with 30")
answer(3, 1, 20)
bank.state.trivia_runs[made.code][players[3].account.account.account_id].touched_at =
    currentEpoch - 3 * 60 * 60 * 1000
local balance = wallet(3).balance
bank.sweep_trivia_runs()
assert(wallet(3).balance == balance + 20 and not bank.state.trivia_runs[made.code],
    "a stake nobody played for comes back")
t.players[players[3].account.account.account_id].run = nil
assert(conserved() == start, "nothing made or lost")

-- Your own questions -------------------------------------------------------------------------------

rejected(actions.TRIVIA_QUESTIONS, "NOT_YOURS", asOf(stranger, { company_id = "COM9" }))
local list = actions.TRIVIA_SAVE(asOf(owner, { company_id = "COM9", topic = "Our town",
    text = "What is the name of our town's river?", answers = { "Foxbrook", "Wolfwater",
    "Bearburn", "Owlflow" } }))
assert(#list.questions == 1 and list.questions[1].id == "C1"
    and list.questions[1].choices[1] == "Foxbrook", "kept, right answer first")
rejected(actions.TRIVIA_SAVE, "INVALID_QUESTION", asOf(owner, { company_id = "COM9",
    text = "Two answers?", answers = { "Yes", "No" } }))
rejected(actions.TRIVIA_SAVE, "INVALID_QUESTION", asOf(owner, { company_id = "COM9",
    text = "Same?", answers = { "A", "a", "B", "C" } }))
-- A text file: a topic line, two questions, and two lines that are not.
local imported = actions.TRIVIA_IMPORT(asOf(owner, { console_id = made.console_id, text =
    "# Lucky Fox\nWho owns the Lucky Fox? | Olive | Kit | Ana | Noa\n"
    .. "This line has no answers\n\nHow many tables do we have? | 1 | 2 | 3 | 4\n"
    .. "Only two | a | b\n" }))
assert(imported.added == 2 and #imported.problems == 2 and #imported.questions == 3,
    "two added, and the two lines that were not, with why")
assert(imported.problems[1]:find("Line 3", 1, true), imported.problems[1])
assert(imported.questions[2].topic == "Lucky Fox", "under the file's topic")
list = actions.TRIVIA_DELETE(asOf(owner, { company_id = "COM9", id = "C2" }))
assert(#list.questions == 2)

view = control({ op = "trivia", mode = true, topic = "ours" }).table
assert(view.trivia.topic_name == "Our questions (2)")
local ours = {}
for _ = 1, 4 do
    nextQuestion()
    ours[t.question.text] = t.question.source
end
assert(ours["What is the name of our town's river?"] == "ours"
    and ours["How many tables do we have?"] == "ours", "only ours, and both")

-- Online -------------------------------------------------------------------------------------------
-- Open Trivia DB, as its documented API answers: a token, then ten at a time,
-- every field percent-encoded.

local requests = {}
local function encode(text)
    return (text:gsub("[^%w]", function(c) return string.format("%%%02X", c:byte()) end))
end
local tokenSpent = false
textutils = { unserializeJSON = function(body) return body end }
http = { get = function(url)
    requests[#requests + 1] = url
    local body
    if url:find("api_token.php", 1, true) then
        body = { response_code = 0, token = "TOKEN" .. #requests }
    elseif tokenSpent then
        tokenSpent = false
        body = { response_code = 4, results = {} }
    else
        local results = {}
        for index = 1, 10 do
            results[index] = { type = "multiple", difficulty = "easy",
                category = encode("Science & Nature"),
                question = encode("Online question " .. index .. " & more?"),
                correct_answer = encode("Right " .. index),
                incorrect_answers = { encode("Wrong A"), encode("Wrong B"), encode("Wrong C") } }
        end
        results[11] = { type = "boolean", question = "True%3F", correct_answer = "True",
            incorrect_answers = { "False" } }
        body = { response_code = 0, results = results }
    end
    return { readAll = function() return body end, close = function() end }
end }
control({ op = "trivia", topic = "science" })
assert(casino.triviaFetch(currentEpoch), "fetched")
assert(requests[1]:find("api_token.php?command=request", 1, true), "a token first")
assert(requests[2]:find("category=17", 1, true) and requests[2]:find("token=TOKEN1", 1, true)
    and requests[2]:find("encode=url3986", 1, true), requests[2])
assert(#casino.trivia.pool.science == 10, "ten, and never a true-or-false one")
assert(not casino.triviaFetch(currentEpoch + 1000), "not again within six seconds")
nextQuestion()
assert(t.question.source == "online" and t.question.text:match("^Online question %d+ & more%?$"),
    "decoded: " .. tostring(t.question.text))
-- The token is spent: a new one, and on.
for _ = 1, 9 do table.remove(casino.trivia.pool.science) end
tokenSpent = true
assert(not casino.triviaFetch(currentEpoch + 7000) and casino.trivia.token == nil,
    "a spent token is dropped")
assert(casino.triviaFetch(currentEpoch + 14000) and casino.trivia.token ~= nil, "and a new one asked for")
-- The internet goes: a minute's rest, the built-in questions meanwhile.
http = { get = function() return nil end }
casino.trivia.pool.science = {}
assert(not casino.triviaFetch(currentEpoch + 21000))
assert(casino.trivia.status:find("Offline", 1, true), casino.trivia.status)
nextQuestion()
assert(t.question.source == "built-in" and t.question.topic == "Science")
assert(conserved() == start, "nothing made or lost, all along")

-- The table's own computer ---------------------------------------------------------------------
-- The monitor: a question, its answers, the right one lit, at three sizes.
-- And the computer's screen: locked, the owner's PIN, the table's controls,
-- locked again after a minute untouched, and a .txt of questions dropped on it.

local screen = dofile("screen_harness.lua")
local display = screen.terminal(51, 19)
term.current = function() return display end
local ui, driven = screen.install({ display = display, event = "mouse_click" })
package.loaded["lib.ui"] = ui
peripheral = { getNames = function() return {} end }
PUMPE_TEST_MODE = "ccg_casino"
local table_ = assert(loadfile("../ccg_casino.lua"))()
PUMPE_TEST_MODE = nil
local device, console, show = table_.device, table_.console, table_.show
device.console_id, device.console_token = made.console_id, made.console_token
device.code, device.name, device.company_name = made.code, made.name, "Lucky Fox"

control({ op = "trivia", mode = true, topic = "minecraft" })
answer(2, 1, 20)
local drawn = {}
for _ = 1, 100 do
    local view = tick()
    show.table, show.at, show.online = view, currentEpoch, true
    for _, size in ipairs({ { 29, 19 }, { 51, 26 }, { 82, 40 } }) do
        local monitor = screen.terminal(size[1], size[2])
        local ok, err = pcall(show.render, monitor)
        assert(ok, tostring(view.phase) .. " at " .. size[1] .. "x" .. size[2] .. ": " .. tostring(err))
        if size[1] == 51 then
            local key = view.phase .. (view.phase == "playing" and (":" .. tostring(view.step)) or "")
            drawn[key] = drawn[key] or monitor
        end
    end
    if view.phase == "result" then break end
    advance(500)
end
local betting, reveal = drawn.betting, drawn["playing:answer"]
local q = t.question
assert(betting and betting.has(ui.wrap(q.text, 47)[1]) and betting.has("A " .. ui.truncate(q.choices[1], 8)),
    "the question and its answers\n" .. (betting and betting.dump() or ""))
assert(betting.has("Quizzer 2") and betting.has("IN"), "who is playing, not what they chose")
assert(reveal and reveal.has("> " .. ({ "A", "B", "C", "D" })[q.answer]),
    "the right one, lit\n" .. (reveal and reveal.dump() or ""))
assert(drawn.result and drawn.result.has("NEXT QUESTION IN"), "and the next one coming\n"
    .. (drawn.result and drawn.result.dump() or "none"))

-- Locked to start with. A tap, and the owner's PIN.
device.owner_name = "Olive Owner"
local function steps(list) for _, step in ipairs(list) do driven.steps[#driven.steps + 1] = step end end
-- The controls' own once-a-second tick, by its id: a tap restarts the idle
-- lock's timer, so "the first timer since the last step" is not always it.
local tickTimer
local startTimer = os.startTimer
os.startTimer = function(seconds)
    local id = startTimer(seconds)
    if seconds == 1 then tickTimer = id end
    return id
end
local function tickStep() return function() return { raw = { "timer", tickTimer } } end end
steps({ { raw = { "mouse_click", 1, 10, 10 } }, { char = "9" }, { char = "9" }, { char = "9" },
    { char = "9" } })
console.lockScreen()
assert(console.session and console.owner and console.owner.trivia.mode, "unlocked, and the table")
assert(display.has("PIN to unlock") == false)

-- The controls: Trivia mode off, the dealer taken.
steps({ "trivia" })
console.controls()
assert(not t.trivia.mode, "turned off")
steps({ tickStep() })
console.controls()
for _, words in ipairs({ "ROULETTE", "BLACKJACK", "COIN", "POKER", "TRIVIA", "BE THE DEALER",
    "TRIVIA MODE OFF", "Minecraft", "STOP MUSIC", "NEXT SONG", "UNLINK" }) do
    assert(display.has(words), "every control, in whole words: " .. words .. "\n" .. display.dump())
end
steps({ "dealer" })
console.controls()
assert(t.controller and t.controller.account_id == owner.account.account_id and console.mine,
    "the dealer, from the table's own computer")
steps({ tickStep() })
console.controls()
assert(display.has("RELEASE") and display.has("Dealer  you"), display.dump())

-- A .txt of questions, dropped on it while it is open.
local function file(name, text)
    return { getName = function() return name end, readAll = function() return text end,
        close = function() end }
end
local before = #ccg.state.trivia_custom.COM9.questions
local said = console.dropped_files({ file("quiz.txt", "# Lucky Fox\nWho deals here? | Olive"
    .. " | Kit | Ana | Noa\nBroken line\n") })
assert(#ccg.state.trivia_custom.COM9.questions == before + 1 and said:find("Added 1 questions", 1, true)
    and said:find("Line 3", 1, true), said)

-- Untouched for as long as it waits (30 seconds here, inside the dealer's
-- minute): locked, the dealer handed back, signed out.
config.ccg_console_lock_seconds = 30
console.opened(console.session)
currentEpoch = currentEpoch + 31000
steps({ tickStep() })
console.controls()
assert(console.session == nil and not casino.controlled(t, currentEpoch), "locked by itself")
assert(console.dropped_files({ file("more.txt", "Q? | a | b | c | d") }):find("Unlock", 1, true),
    "and takes no files while locked")
console.drawLock(true)
assert(display.has("PIN to unlock") and display.has("Quiz Night") and display.has(made.code),
    display.dump())

-- Somebody else's PIN opens nothing, even with no owner on record.
device.owner_name = nil
steps({ { raw = { "mouse_click", 1, 10, 10 } } })
for _, step in ipairs(screen.typed("Not Olive")) do steps({ step }) end
steps({ { char = "2" }, { char = "2" }, { char = "2" }, { char = "2" }, { terminate = true } })
pcall(console.lockScreen)
assert(console.session == nil and device.owner_name == nil, "still locked, and nobody remembered")

io.write("host_ccg_trivia_test: OK\n")
