-- Trivia in the Pocket, FoxyOS 18.1: the real pumpe.lua and lib/ui on a
-- Pocket's 26x20 screen, against a real CCG Server and a real Bank Core and
-- Vault, run the way ComputerCraft runs it.
--
-- Ana sits at a table in Trivia mode. The question and its four answers are
-- on her screen; she taps the right one and says how much, the answer is
-- shown, and her pot is 1.5x. The next question she takes it instead: held
-- for a day, like any CCG win. Then Olive, who owns the table, opens its
-- Trivia page in My Casino, turns Trivia mode off, and writes a question of
-- her own.

package.path = "../?.lua;../?/init.lua;" .. package.path
local harness = require("bank_pair_harness")
local bank = harness.pair()
local config = require("config")
local world = require("cloud_harness").start(harness, bank)
local as = world.as
local POCKET, CCG_ID = world.pocket, 40

-- The CCG Server, registered with the Bank by the operator code.
local ccg = world.attach(CCG_ID, "ccg_server.lua", config.ccg_protocol or "PUMPE_CCG_V1",
    "ccg", true)
ccg.state.server_token = bank.request("CCG_SERVER_REGISTER", { code = "4040",
    name = "Test CCG" }).server_token

-- Olive owns Lucky Fox, and its table is in Trivia mode, on Minecraft.
local olive = bank.register("Olive Owner", "9999")
bank.state.companies.COM9 = { company_id = "COM9", name = "Lucky Fox",
    owner_account_id = olive.id, status = "active" }
local made = as(CCG_ID, ccg.actions.CASINO_REGISTER, { session_token = olive.token,
    company_id = "COM9", name = "Quiz Night" })
as(CCG_ID, ccg.actions.CASINO_CONTROL, { session_token = olive.token,
    console_id = made.console_id, op = "trivia", mode = true, topic = "minecraft" })
local t = ccg.state.casinos[made.console_id]
assert(t.phase == "betting" and t.game == "trivia" and t.question)

local ana = bank.register("Ana Fox", "1234")
bank.fund(ana, 1000)
bank.request("BET_WALLET_DEPOSIT", { session_token = ana.token, pin = "1234", amount = 200 })

-- The Pocket ---------------------------------------------------------------------------------------

local screen = dofile("screen_harness.lua")
local display = screen.terminal(26, 20)
pocket = {}
window = nil
peripheral = { getNames = function() return { "back" } end,
    getType = function() return "modem" end, wrap = function() return nil end,
    isPresent = function() return true end }
sleep = function() end
local timers = {}
os.startTimer = function()
    timers[#timers + 1] = #timers + 1
    return #timers
end
os.cancelTimer = function() end
os.queueEvent = function() end
os.pullEventRaw = coroutine.yield
os.pullEvent = function(filter)
    local event = table.pack(coroutine.yield(filter))
    if event[1] == "terminate" then error("Terminated", 0) end
    return table.unpack(event, 1, event.n)
end
term = { current = function() return display end, redirect = function() return display end }
shell = { getRunningProgram = function() return "/pumpe/pumpe.lua" end }

local ui = dofile("../lib/ui.lua")
package.loaded["lib.ui"] = ui
PUMPE_DESK_TEST = true
local phone = as(POCKET, assert(loadfile("../pumpe.lua")))
PUMPE_DESK_TEST = nil
assert(as(POCKET, phone.signIn, "Ana Fox", "1234"))
-- The apps wired to their screens, as the Home Screen does at start.
as(POCKET, phone.desk.startApps)

local driver
local function send(...)
    local ok, err = as(POCKET, coroutine.resume, driver, ...)
    assert(ok, err)
end
local function at(text)
    local x, y = display.find(text)
    if not x then error("not on the screen: " .. text .. "\n" .. display.dump(), 0) end
    return x, y
end
local function tap(text)
    local x, y = at(text)
    send("mouse_click", 1, x, y)
end
local function type_(text)
    for index = 1, #text do send("char", text:sub(index, index)) end
    send("key", keys.enter, false)
end
local function tick(count)
    for _ = 1, count or 1 do
        local due = timers
        timers = {}
        for _, id in ipairs(due) do send("timer", id) end
    end
end
-- Time going by at the table: the clock, and the Pocket looking at it.
local function later(ms)
    for _ = 1, math.ceil(ms / 500) do
        bank.advanceMs(500)
        tick(3)
    end
end
local function untilPhase(phase)
    for _ = 1, 80 do
        if t.phase == phase then return end
        later(500)
    end
    error("never " .. phase .. ": " .. tostring(t.phase) .. "\n" .. display.dump(), 0)
end
local function choice(index)
    return t.question.choices[index]
end

-- Ana sits down ------------------------------------------------------------------------------------

driver = coroutine.create(function() return phone.openApp("ccg", "bet") end)
send()
tap("Sit at a table")
type_("1234")                                        -- Unlock Bet
type_(made.code)                                     -- the table's code
send("key", keys.enter, false)                       -- her name, as it is
assert(display.has("Minecraft") and display.has("Pick an answer to play"), display.dump())
local right = t.question.answer
for index = 1, 4 do
    assert(display.has(({ "A", "B", "C", "D" })[index] .. " " .. ui.truncate(choice(index), 10)),
        "every answer is a button\n" .. display.dump())
end

-- The right answer, for 50.
tap(({ "A ", "B ", "C ", "D " })[right] .. ui.truncate(choice(right), 8))
type_("50")
local runs = bank.state.trivia_runs[made.code]
assert(runs and runs[ana.id] and runs[ana.id].stake == 50, "staked at the Bank")
assert(display.has("Pot $50") or display.has("Pot 50"), display.dump())
assert(display.has("> " .. ({ "A", "B", "C", "D" })[right]), "her answer, marked\n" .. display.dump())

untilPhase("result")
tick(3)
assert(display.has("Right! Your pot is"), display.dump())
assert(runs[ana.id].streak == 1)

-- The next question: an answer rides on the pot, with nothing more to pay;
-- then she thinks better of it and takes the 75.
untilPhase("betting")
tick(3)
local second = t.question.answer
tap(({ "A ", "B ", "C ", "D " })[second] .. ui.truncate(choice(second), 8))
assert(not display.has("how much"), "no second stake\n" .. display.dump())
assert(t.players[ana.id].bets[1].pick == second and runs[ana.id].stake == 50)
tap("TAKE")
assert(display.has("Taken") or not bank.state.trivia_runs[made.code], display.dump())
local held = 0
for _, hold in pairs(bank.state.accounts[ana.id].bet_wallet.holds) do held = held + hold.amount end
assert(held == 75, "75, held for a day: " .. held)
tick(2)
tap("LEAVE")

-- Olive's My Casino ---------------------------------------------------------------------------------

assert(as(POCKET, phone.signIn, "Olive Owner", "9999"))
driver = coroutine.create(function() return phone.openApp("ccg", "mine") end)
send()
tap("Quiz Night")
local music, trivia, rename = at("MUSIC"), at("TRIVIA"), at("RENAME")
assert(music < trivia and trivia + 6 < rename, "three whole words\n" .. display.dump())
tap("TRIVIA")
assert(display.has("TRIVIA MODE: ON") and display.has("Minecraft"), display.dump())
tap("TRIVIA MODE: ON")
assert(display.has("TRIVIA MODE: OFF") and not t.trivia.mode, display.dump())
tap("Our questions")
tap("+ New question")
send("key", keys.enter, false)                       -- the topic, as offered
type_("What is our river called?")
type_("Foxbrook")
type_("Wolfwater")
type_("Bearburn")
type_("Owlflow")
local mine = ccg.state.trivia_custom.COM9
assert(mine and #mine.questions == 1 and mine.questions[1].text == "What is our river called?"
    and mine.questions[1].choices[1] == "Foxbrook", "saved, the right answer first")
tick()
assert(display.has("What is our river ca"), "in the list\n" .. display.dump())
-- And gone again: opened, deleted.
tap("What is our river ca")
assert(display.has("+ Foxbrook") and display.has("- Owlflow"), display.dump())
tap("DELETE")
assert(#mine.questions == 0 and not display.has("What is our river"), display.dump())

io.write("host_ccg_trivia_pocket_test: OK\n")
