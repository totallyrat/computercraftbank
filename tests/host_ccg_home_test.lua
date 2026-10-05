-- CCG Home Mode, 12.0: four games for one player, and the console's side of
-- pairing with a PUMPE.
--
-- The games are engines with no screen of their own, so their rules are
-- tested as rules: a snake that eats grows, a meteor that lands on you ends
-- it, Simon wants the tune back, 2048 joins what is equal once. Then the
-- console: a pairing code, one controller at a time, a PIN in front of it,
-- and a best score that is kept -- drawn on the smallest monitor CCG runs on
-- and on a wall.

local WIDTH, HEIGHT = 29, 19

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}
local monitor = {
    getSize = function() return WIDTH, HEIGHT end,
    setTextScale = function() end,
    isColor = function() return true end,
}
term = { current = function() return monitor end, setBackgroundColor = function() end,
    setTextColor = function() end, clear = function() end, setCursorPos = function() end }
peripheral = {
    getNames = function() return { "top" } end,
    getType = function() return "monitor" end,
    wrap = function() return monitor end,
}
fs = {
    getDir = function() return "/pumpe" end,
    combine = function(left, right)
        return tostring(left):gsub("/+$", "") .. "/" .. tostring(right):gsub("^/+", "")
    end,
}
shell = { getRunningProgram = function() return "/pumpe/ccg.lua" end }
sleep = function() end

local hosted = {}
rednet = {
    host = function(protocol, name) hosted[protocol] = name end,
    unhost = function(protocol) hosted[protocol] = nil end,
}

local saved = {}
package.loaded.config = { version = "12.0.0", currency = "$" }
package.loaded["lib.util"] = {
    -- FoxyOS 15.1: Beta Updates, not signed up here.
    betaJoined = function() return false end,
    isBetaVersion = function() return false end,
    loadTable = function(_, fallback) return fallback end,
    saveTable = function(_, value) saved[#saved + 1] = value end,
    truncate = function(value, maximum) return tostring(value or ""):sub(1, maximum) end,
    money = function(value, symbol) return (symbol or "$") .. tostring(value) end,
    formatClock = function() return "12:00" end,
    trim = function(value) return (tostring(value):gsub("^%s+", ""):gsub("%s+$", "")) end,
    checksum = function(value)
        local hash = 5381
        for index = 1, #value do hash = (hash * 33 + value:byte(index)) % 4294967296 end
        return string.format("%x", hash)
    end,
    token = function(prefix) return prefix .. "TOKEN" .. math.random(1000, 9999) end,
}
package.loaded["lib.net"] = {
    client = function() return { discover = function() return true end } end,
    autoUpdate = function() end, openModems = function() end,
}

-- Drawing is bounds checked: nothing a game or a screen paints may leave the
-- monitor.
local drawn = {}
local function inside(label, x, y, width, height)
    assert(x >= 1 and y >= 1 and width >= 1 and height >= 1, label .. " has no room")
    assert(x + width - 1 <= WIDTH and y + height - 1 <= HEIGHT,
        label .. " leaves a " .. WIDTH .. "x" .. HEIGHT .. " monitor at "
            .. x .. "," .. y .. " size " .. width .. "x" .. height)
end
local pins = {}
local ui = { theme = { accent = colors.orange, background = colors.black,
    panel = colors.gray, ink = colors.white, muted = colors.lightGray } }
function ui.usePhoneStyle() end
function ui.clear() drawn = {} end
function ui.fill(_, x, y, width, height) inside("fill", x, y, width, height) end
function ui.text(_, x, y, value)
    value = tostring(value)
    inside("text " .. value, x, y, math.max(1, #value), 1)
    drawn[#drawn + 1] = value
end
function ui.center(_, y, value)
    value = tostring(value)
    assert(#value <= WIDTH, "centred text too wide: " .. value)
    inside("centre " .. value, 1, y, 1, 1)
    drawn[#drawn + 1] = value
end
function ui.truncate(value, maximum) return tostring(value or ""):sub(1, math.max(0, maximum)) end
function ui.inkOn() return colors.black end
function ui.wordmark(_, y, word)
    local span = #word * 4 - 1
    if span > WIDTH then return false end
    inside("wordmark", 1, y, span, 5)
    drawn[#drawn + 1] = "BIG:" .. word
    return true
end
local messages = {}
function ui.message(_, kind, title) messages[#messages + 1] = title end
function ui.pin(_, title)
    local entry = table.remove(pins, 1)
    assert(entry ~= nil, "unexpected PIN pad: " .. title)
    if entry == false then return nil end
    return entry
end
function ui.useMainColor() return "orange" end
package.loaded["lib.ui"] = ui

local function has(wanted)
    for _, value in ipairs(drawn) do
        if value:find(wanted, 1, true) then return true end
    end
    return false
end

-- Rolls that are always the lowest: the first free cell, the first pad.
local function low(a) return a end

-- The games --------------------------------------------------------------------------

PUMPE_TEST_MODE = "ccg_home_games"
local games = assert(loadfile("../ccg.lua"))()
PUMPE_TEST_MODE = nil
assert(games.snake and games.meteors and games.simon and games["2048"], "four games")

-- Snake. Starts in the middle heading right; food lands on the first free cell.
local snake = games.snake.new(10, 6, low)
assert(#snake.body == 3 and snake.body[1].x == 5 and snake.food.x == 1 and snake.food.y == 1)
games.snake.input(snake, "left")
games.snake.tick(snake)
assert(snake.body[1].x == 6, "turning straight back is ignored")
snake.food = { x = 7, y = 3 }
games.snake.tick(snake)
assert(snake.score == 1 and #snake.body == 4, "eating grows it and scores")
assert(not (snake.food.x == 7 and snake.food.y == 3), "and new food is put down")
for _ = 1, 3 do games.snake.tick(snake) end
assert(not snake.over and snake.body[1].x == 10)
games.snake.tick(snake)
assert(snake.over and snake.status == "Hit the wall", "the wall ends it")

-- Biting itself: a long snake turning back into its own body.
snake = games.snake.new(10, 6, low)
snake.body = { { x = 5, y = 3 }, { x = 4, y = 3 }, { x = 4, y = 4 }, { x = 5, y = 4 },
    { x = 6, y = 4 }, { x = 6, y = 3 } }
snake.dir, snake.want, snake.food = { -1, 0 }, { -1, 0 }, { x = 1, y = 1 }
games.snake.input(snake, "down")
games.snake.tick(snake)
assert(snake.over and snake.status == "Bit itself")
-- Moving into the cell the tail is leaving is not a bite.
snake = games.snake.new(10, 6, low)
snake.body = { { x = 5, y = 3 }, { x = 5, y = 4 }, { x = 4, y = 4 }, { x = 4, y = 3 } }
snake.dir, snake.want, snake.food = { 0, -1 }, { -1, 0 }, { x = 1, y = 1 }
games.snake.tick(snake)
assert(not snake.over, "the tail moves out of the way")
assert(games.snake.speed({ score = 0 }) > games.snake.speed({ score = 20 }),
    "and it speeds up as it grows")

-- Meteors. Rocks fall a row a tick; one that passes scores, one that lands
-- on the ship ends it.
local rocks = games.meteors.new(20, 8, function(a, b) return b end)
rocks.rocks = { { x = 3, y = 8 } }
local noRolls = function() return 100 end
rocks.random = noRolls
games.meteors.tick(rocks)
assert(rocks.score == 1 and #rocks.rocks == 0, "a rock off the bottom is dodged")
rocks.rocks = { { x = rocks.x, y = 7 } }
games.meteors.tick(rocks)
assert(rocks.over and rocks.status == "Hit by a meteor")
rocks = games.meteors.new(20, 8, noRolls)
rocks.rocks = { { x = rocks.x - 1, y = 8 } }
games.meteors.input(rocks, "left")
assert(rocks.over, "steering into a rock ends it too")
rocks = games.meteors.new(20, 8, noRolls)
for _ = 1, 30 do games.meteors.input(rocks, "right") end
assert(rocks.x == 20, "the ship stays on the screen")

-- Simon. The tune is shown, then wanted back; a longer one each round.
local simon = games.simon.new(20, 10, function() return 2 end)
assert(#simon.tune == 1 and simon.tune[1] == "right" and simon.phase == "show")
games.simon.input(simon, "right")
assert(simon.score == 0, "nothing counts while the tune is being shown")
games.simon.tick(simon)
games.simon.tick(simon)
games.simon.tick(simon)
assert(simon.lit == "right", "the pad lights")
games.simon.tick(simon)
assert(simon.lit == nil, "and goes dark again")
games.simon.tick(simon)
assert(simon.phase == "play" and simon.status == "Your turn")
games.simon.input(simon, "right")
assert(simon.score == 1 and #simon.tune == 2 and simon.phase == "show",
    "right, so the tune grows and is shown again")
for _ = 1, 8 do games.simon.tick(simon) end
assert(simon.phase == "play")
games.simon.input(simon, "left")
assert(simon.over and simon.status == "That was right", "a wrong pad ends it, and says which")

-- 2048. Equal tiles join once, towards the side it slides to.
local function same(a, b) return table.concat(a, ",") == table.concat(b, ",") end
local line, gained = games["2048"].slide({ 2, 2, 2, 2 })
assert(same(line, { 4, 4, 0, 0 }) and gained == 8, "two pairs, two joins")
line, gained = games["2048"].slide({ 2, 0, 2, 4 })
assert(same(line, { 4, 4, 0, 0 }) and gained == 4, "a new 4 does not join the old one")
line = games["2048"].slide({ 4, 4, 8, 0 })
assert(same(line, { 8, 8, 0, 0 }))
local board = games["2048"].new(20, 10, low)
board.grid = { { 2, 2, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 4 }, { 0, 0, 0, 4 } }
games["2048"].input(board, "right")
assert(board.grid[1][4] == 4 and board.score == 4, "slid right and joined")
local count = 0
for row = 1, 4 do for column = 1, 4 do
    if board.grid[row][column] ~= 0 then count = count + 1 end
end end
assert(count == 4, "and one new tile came in after the move")
games["2048"].input(board, "down")
assert(board.grid[4][4] == 8, "down joins the column")
board.grid = { { 2, 0, 0, 0 }, { 4, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 } }
games["2048"].input(board, "left")
assert(board.grid[3][1] == 0 and board.grid[1][2] == 0 and board.grid[4][1] == 0,
    "a slide that moves nothing brings no new tile")
local stuck = games["2048"].new(20, 10, low)
stuck.grid = { { 2, 4, 2, 4 }, { 4, 2, 4, 2 }, { 2, 4, 2, 4 }, { 4, 2, 4, 2 } }
games["2048"].input(stuck, "left")
assert(stuck.over and stuck.status == "No moves left")
stuck.grid = { { 2, 4, 2, 4 }, { 4, 2, 4, 2 }, { 2, 4, 2, 4 }, { 4, 2, 4, 4 } }
stuck.over = nil
games["2048"].input(stuck, "up")
assert(not stuck.over, "a board with a join left in it is not over")

-- Every game draws inside its board.
for _, id in ipairs({ "snake", "meteors", "simon", "2048" }) do
    local game = games[id].new(27, 12, low)
    games[id].draw(game, monitor, 2, 5)
end

-- The console ----------------------------------------------------------------------

PUMPE_TEST_MODE = "ccg_home"
local console = assert(loadfile("../ccg.lua"))()
PUMPE_TEST_MODE = nil
local device = console.device
local function refused(code, ...)
    local ok, err = pcall(console.handle, ...)
    assert(not ok and type(err) == "table" and err.code == code,
        "expected " .. code .. ", got " .. tostring(ok and "success"
            or (type(err) == "table" and err.code or err)))
end

-- The PIN: set twice, the same both times.
pins = { "4321", "9999" }
assert(console.set_pin() == false and not device.home_pin, "PINs that differ set nothing")
pins = { "4321", "4321" }
assert(console.set_pin() == true and device.home_pin == console.pin_hash("4321"))
assert(device.home_pin ~= "4321", "and only a hash of it is kept")

local home = { screen = "pair", active = true }
console.new_code(home)
assert(#home.code == 6 and home.code:match("^%d+$"), "six digits")
assert(hosted.PUMPE_CCG_HOME == "CCGHOME_" .. home.code, "found on the network by its code")
console.draw(home)
assert(has("BIG:" .. home.code), "the code is on the screen, big")

-- Pairing. A wrong code is refused; five of them and the code changes.
local first = home.code
refused("BAD_CODE", home, "HOME_PAIR", { code = "000000" }, 7)
for _ = 1, 4 do pcall(console.handle, home, "HOME_PAIR", { code = "000000" }, 7) end
assert(home.code ~= first and hosted.PUMPE_CCG_HOME == "CCGHOME_" .. home.code,
    "guessing gets a new code")
local paired = console.handle(home, "HOME_PAIR", { code = home.code, name = "Kit Wolf" }, 7)
assert(paired.token and paired.state.screen == "menu" and #paired.state.games == 4,
    "paired: the four games come back")
refused("PAIRED", home, "HOME_PAIR", { code = home.code, name = "Rob" }, 8)
refused("NOT_PAIRED", home, "HOME_STATE", { token = paired.token }, 8)
refused("NOT_PAIRED", home, "HOME_STATE", { token = "guess" }, 7)
console.draw(home)
assert(has("Kit Wolf IS PLAYING"), "the screen says who has it")

-- Playing. Buttons go to the game; the screen's timer moves it on.
local token = paired.token
refused("NO_SUCH_GAME", home, "HOME_PLAY", { token = token, game = "poker" }, 7)
local state = console.handle(home, "HOME_PLAY", { token = token, game = "snake" }, 7)
assert(state.screen == "game" and state.label == "SNAKE" and state.score == 0)
console.handle(home, "HOME_INPUT", { token = token, key = "up" }, 7)
console.draw(home)
local ticks = 0
while home.screen == "game" and ticks < 100 do
    console.tick(home)
    ticks = ticks + 1
end
assert(home.screen == "over", "up into the wall, and it is over")
state = console.handle(home, "HOME_STATE", { token = token }, 7)
assert(state.screen == "over" and state.status == "Hit the wall")
console.draw(home)
assert(has("GAME OVER"))

-- A best score is kept on the console, and said when it is beaten.
home.play.score = 12
home.screen = "game"
console.tick(home)
assert(device.home_best.snake == 12 and home.record, "a new best is kept")
assert(saved[#saved].home_best.snake == 12, "on the console's disk")
console.draw(home)
assert(has("NEW BEST!"))
state = console.handle(home, "HOME_STATE", { token = token }, 7)
assert(state.best == 12 and state.record)
for _, game in ipairs(state.games) do
    if game.id == "snake" then assert(game.best == 12) end
end

-- A to play again; the menu; leaving frees the console with a new code.
state = console.handle(home, "HOME_INPUT", { token = token, key = "a" }, 7)
assert(state.screen == "game" and state.score == 0 and not state.record)
state = console.handle(home, "HOME_MENU", { token = token }, 7)
assert(state.screen == "menu" and state.game == nil)
local before = home.code
assert(console.handle(home, "HOME_LEAVE", { token = token }, 7).left)
assert(home.screen == "pair" and home.peer == nil and home.code ~= before,
    "the CCG goes back to showing a new code")
refused("NOT_PAIRED", home, "HOME_STATE", { token = token }, 7)

-- Every screen, on a small monitor and on a wall.
for _, size in ipairs({ { 29, 19 }, { 82, 38 } }) do
    WIDTH, HEIGHT = size[1], size[2]
    local fresh = { screen = "pair", active = true }
    console.new_code(fresh)
    console.draw(fresh)
    local again = console.handle(fresh, "HOME_PAIR", { code = fresh.code, name = "Kit" }, 3)
    console.draw(fresh)
    for _, id in ipairs({ "snake", "meteors", "simon", "2048" }) do
        console.handle(fresh, "HOME_PLAY", { token = again.token, game = id }, 3)
        for _ = 1, 6 do console.tick(fresh) end
        console.draw(fresh)
        fresh.play.over = true
        fresh.screen = "game"
        console.tick(fresh)
        console.draw(fresh)
    end
end
WIDTH, HEIGHT = 29, 19

-- Home Mode is behind the PIN: the wrong one opens nothing.
hosted = {}
pins = { "0000" }
console.home_mode()
assert(messages[#messages] == "WRONG PIN" and hosted.PUMPE_CCG_HOME == nil,
    "a wrong PIN hosts nothing")
pins = { false }
console.home_mode()
assert(hosted.PUMPE_CCG_HOME == nil, "and nor does cancelling")

print("host_ccg_home_test: OK")
