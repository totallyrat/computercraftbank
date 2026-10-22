-- CCG Home, FoxyOS 17.
-- Runs on an Advanced Computer with a wireless or Ender modem and any-size
-- Advanced Monitor. Until FoxyOS 17 this was half of the CCG console, beside
-- Bet Play; Bet Play is the CCG Casino now (ccg_casino.lua), and this is
-- Home Mode on its own, as it was: four free games for one player and the
-- Game Browser's, with a Pocket as the controller.

local ROOT = fs.getDir(shell.getRunningProgram())
if ROOT == "" then ROOT = "." end
package.path = package.path .. ";" .. fs.combine(ROOT, "?.lua")
    .. ";" .. fs.combine(ROOT, "?/init.lua")

-- Stamped by tools/build_release_manifest.js. A program running beside a
-- config.lua from a different release means a partial install.
local PROGRAM_VERSION = "18.2.0"
local config = require("config")
local util = require("lib.util")
local net = require("lib.net")
local ui = require("lib.ui")

-- Home Mode, 12.0 -----------------------------------------------------------
-- Four games for one player, free: no lobby, no wager, and no CCG Server --
-- this console runs them and a PUMPE is the controller. Each game is a small
-- engine: new() makes a game for a board of a given size, input() takes a
-- button (up, down, left, right, a), tick() moves time on, draw() paints it.
-- Nothing in an engine touches the network or the disk.
local HOME_PROTOCOL = "PUMPE_CCG_HOME"
local DIRECTIONS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 },
    right = { 1, 0 } }

local function sameCell(a, b) return a.x == b.x and a.y == b.y end

local snake = { id = "snake", label = "SNAKE", color = colors.lime,
    hint = "Eat, grow, and never bite yourself" }
function snake.new(width, height, random)
    local cx, cy = math.floor(width / 2), math.floor(height / 2)
    local game = { width = width, height = height, random = random, score = 0,
        body = { { x = cx, y = cy }, { x = cx - 1, y = cy }, { x = cx - 2, y = cy } },
        dir = { 1, 0 }, want = { 1, 0 } }
    snake.food(game)
    return game
end
function snake.food(game)
    local free = {}
    for y = 1, game.height do
        for x = 1, game.width do
            local taken = false
            for _, cell in ipairs(game.body) do
                if cell.x == x and cell.y == y then taken = true break end
            end
            if not taken then free[#free + 1] = { x = x, y = y } end
        end
    end
    if #free == 0 then game.over, game.status = true, "The board is full!" return end
    game.food = free[game.random(1, #free)]
end
function snake.input(game, key)
    local dir = DIRECTIONS[key]
    -- Straight back into itself is not a turn.
    if dir and not (dir[1] == -game.dir[1] and dir[2] == -game.dir[2]) then
        game.want = dir
    end
end
function snake.tick(game)
    game.dir = game.want
    local head = { x = game.body[1].x + game.dir[1], y = game.body[1].y + game.dir[2] }
    local eats = game.food and sameCell(head, game.food)
    if head.x < 1 or head.y < 1 or head.x > game.width or head.y > game.height then
        game.over, game.status = true, "Hit the wall"
        return
    end
    -- The tail moves out of the way this tick, unless the snake is growing.
    for index = 1, #game.body - (eats and 0 or 1) do
        if sameCell(game.body[index], head) then
            game.over, game.status = true, "Bit itself"
            return
        end
    end
    table.insert(game.body, 1, head)
    if eats then
        game.score = game.score + 1
        snake.food(game)
    else
        table.remove(game.body)
    end
end
function snake.speed(game) return math.max(0.1, 0.3 - game.score * 0.008) end
function snake.draw(game, surface, left, top)
    ui.fill(surface, left, top, game.width, game.height, colors.black)
    if game.food then
        ui.fill(surface, left + game.food.x - 1, top + game.food.y - 1, 1, 1, colors.red)
    end
    for index, cell in ipairs(game.body) do
        ui.fill(surface, left + cell.x - 1, top + cell.y - 1, 1, 1,
            index == 1 and colors.yellow or colors.lime)
    end
end

local meteors = { id = "meteors", label = "METEORS", color = colors.orange,
    hint = "Dodge what falls. Left and right" }
function meteors.new(width, height, random)
    return { width = width, height = height, random = random, score = 0,
        x = math.max(1, math.ceil(width / 2)), rocks = {},
        step = math.max(1, math.floor(width / 16)) }
end
function meteors.hit(game)
    for _, rock in ipairs(game.rocks) do
        if rock.y == game.height and rock.x == game.x then
            game.over, game.status = true, "Hit by a meteor"
            return true
        end
    end
    return false
end
function meteors.input(game, key)
    if key == "left" then
        game.x = math.max(1, game.x - game.step)
    elseif key == "right" then
        game.x = math.min(game.width, game.x + game.step)
    end
    meteors.hit(game)
end
function meteors.tick(game)
    local kept = {}
    for _, rock in ipairs(game.rocks) do
        rock.y = rock.y + 1
        if rock.y > game.height then
            game.score = game.score + 1
        else
            kept[#kept + 1] = rock
        end
    end
    game.rocks = kept
    if meteors.hit(game) then return end
    -- More of them the longer it goes on.
    local count = 1 + math.floor(game.score / 40)
    for _ = 1, count do
        if game.random(1, 100) <= math.min(90, 35 + game.score) then
            game.rocks[#game.rocks + 1] = { x = game.random(1, game.width), y = 1 }
        end
    end
end
function meteors.speed(game) return math.max(0.08, 0.22 - game.score * 0.002) end
function meteors.draw(game, surface, left, top)
    ui.fill(surface, left, top, game.width, game.height, colors.black)
    for _, rock in ipairs(game.rocks) do
        ui.fill(surface, left + rock.x - 1, top + rock.y - 1, 1, 1, colors.orange)
    end
    ui.fill(surface, left + game.x - 1, top + game.height - 1, 1, 1, colors.cyan)
end

-- Simon: four pads, a longer tune every round, played back from memory.
local simon = { id = "simon", label = "SIMON", color = colors.purple,
    hint = "Watch the pads, then play them back",
    PADS = { "up", "right", "down", "left" },
    BRIGHT = { up = colors.lime, right = colors.red, down = colors.yellow,
        left = colors.lightBlue },
    DIM = { up = colors.green, right = colors.brown, down = colors.orange,
        left = colors.blue } }
function simon.grow(game)
    game.tune[#game.tune + 1] = simon.PADS[game.random(1, 4)]
    game.phase, game.shown, game.lit, game.rest = "show", 0, nil, 2
    game.status = "Watch"
end
function simon.new(width, height, random)
    local game = { width = width, height = height, random = random, score = 0,
        tune = {} }
    simon.grow(game)
    return game
end
function simon.tick(game)
    if game.phase ~= "show" then
        game.lit = nil
        return
    end
    if game.rest > 0 then
        game.rest, game.lit = game.rest - 1, nil
    elseif game.lit then
        game.lit = nil
    elseif game.shown < #game.tune then
        game.shown = game.shown + 1
        game.lit = game.tune[game.shown]
    else
        game.phase, game.at, game.status = "play", 1, "Your turn"
    end
end
function simon.input(game, key)
    if game.phase ~= "play" or not simon.BRIGHT[key] then return end
    game.lit = key
    if game.tune[game.at] ~= key then
        game.over, game.status = true, "That was " .. game.tune[game.at]
        return
    end
    game.at = game.at + 1
    if game.at > #game.tune then
        game.score = #game.tune
        simon.grow(game)
        -- The last pad of the round still lights while the next tune waits.
        game.lit = key
    end
end
function simon.speed(game) return math.max(0.25, 0.45 - #game.tune * 0.01) end
function simon.draw(game, surface, left, top)
    ui.fill(surface, left, top, game.width, game.height, colors.black)
    local padWidth = math.max(3, math.floor(game.width / 3))
    local padHeight = math.max(1, math.floor(game.height / 3))
    local middleX = left + math.floor((game.width - padWidth) / 2)
    local middleY = top + math.floor((game.height - padHeight) / 2)
    local places = {
        up = { middleX, top }, down = { middleX, top + game.height - padHeight },
        left = { left, middleY }, right = { left + game.width - padWidth, middleY },
    }
    for _, pad in ipairs(simon.PADS) do
        local place = places[pad]
        ui.fill(surface, place[1], place[2], padWidth, padHeight,
            game.lit == pad and simon.BRIGHT[pad] or simon.DIM[pad])
    end
    ui.text(surface, middleX, middleY + math.floor(padHeight / 2),
        ui.truncate(game.phase == "play" and "PLAY" or "WATCH", padWidth),
        colors.white, colors.black)
end

-- 2048: slide the tiles, equal ones join.
local tiles = { id = "2048", label = "2048", color = colors.yellow,
    hint = "Slide tiles. Equal ones join",
    COLORS = { [2] = colors.lightGray, [4] = colors.white, [8] = colors.orange,
        [16] = colors.red, [32] = colors.pink, [64] = colors.magenta,
        [128] = colors.yellow, [256] = colors.lime, [512] = colors.green,
        [1024] = colors.cyan, [2048] = colors.lightBlue } }
function tiles.spawn(game)
    local free = {}
    for row = 1, 4 do
        for column = 1, 4 do
            if game.grid[row][column] == 0 then free[#free + 1] = { row, column } end
        end
    end
    if #free == 0 then return end
    local cell = free[game.random(1, #free)]
    game.grid[cell[1]][cell[2]] = game.random(1, 10) == 1 and 4 or 2
end
function tiles.new(width, height, random)
    local game = { width = width, height = height, random = random, score = 0,
        grid = {} }
    for row = 1, 4 do game.grid[row] = { 0, 0, 0, 0 } end
    tiles.spawn(game)
    tiles.spawn(game)
    return game
end
-- One line, in the order it slides: numbers close up, equal neighbours
-- join once. Returns the new line and what the joins were worth.
function tiles.slide(line)
    local packed, out, gained = {}, {}, 0
    for _, value in ipairs(line) do
        if value ~= 0 then packed[#packed + 1] = value end
    end
    local index = 1
    while index <= #packed do
        if packed[index + 1] and packed[index] == packed[index + 1] then
            out[#out + 1] = packed[index] * 2
            gained = gained + packed[index] * 2
            index = index + 2
        else
            out[#out + 1] = packed[index]
            index = index + 1
        end
    end
    while #out < #line do out[#out + 1] = 0 end
    return out, gained
end
function tiles.canMove(game)
    for row = 1, 4 do
        for column = 1, 4 do
            local value = game.grid[row][column]
            if value == 0 then return true end
            if column < 4 and game.grid[row][column + 1] == value then return true end
            if row < 4 and game.grid[row + 1][column] == value then return true end
        end
    end
    return false
end
function tiles.input(game, key)
    local dir = DIRECTIONS[key]
    if not dir then return end
    local moved = false
    for lane = 1, 4 do
        -- The cells of one row or column, from the edge it slides towards.
        local cells = {}
        for step = 1, 4 do
            local position = (dir[1] + dir[2] > 0) and (5 - step) or step
            if dir[1] ~= 0 then
                cells[step] = { lane, position }
            else
                cells[step] = { position, lane }
            end
        end
        local line = {}
        for step, cell in ipairs(cells) do line[step] = game.grid[cell[1]][cell[2]] end
        local slid, gained = tiles.slide(line)
        for step, cell in ipairs(cells) do
            if game.grid[cell[1]][cell[2]] ~= slid[step] then moved = true end
            game.grid[cell[1]][cell[2]] = slid[step]
        end
        game.score = game.score + gained
        for _, value in ipairs(slid) do
            if value >= 2048 then game.status = "2048!" end
        end
    end
    if moved then tiles.spawn(game) end
    if not tiles.canMove(game) then game.over, game.status = true, "No moves left" end
end
function tiles.draw(game, surface, left, top)
    ui.fill(surface, left, top, game.width, game.height, colors.black)
    local cellWidth = math.max(1, math.floor((game.width - 3) / 4))
    local cellHeight = math.max(1, math.floor((game.height - 3) / 4))
    for row = 1, 4 do
        for column = 1, 4 do
            local value = game.grid[row][column]
            local x = left + (column - 1) * (cellWidth + 1)
            local y = top + (row - 1) * (cellHeight + 1)
            local tint = value == 0 and colors.gray or (tiles.COLORS[value] or colors.purple)
            ui.fill(surface, x, y, cellWidth, cellHeight, tint)
            if value > 0 then
                local text = ui.truncate(tostring(value), cellWidth)
                ui.text(surface, x + math.floor((cellWidth - #text) / 2),
                    y + math.floor((cellHeight - 1) / 2), text, colors.black, tint)
            end
        end
    end
end

local HOME_GAMES = { snake, meteors, simon, tiles }
local homeById = {}
for _, game in ipairs(HOME_GAMES) do homeById[game.id] = game end

if PUMPE_TEST_MODE == "ccg_home_games" then return homeById end

local devicePath = fs.combine(ROOT, "ccg_device.dat")
local device = util.loadTable(devicePath, {
    name = "",
    -- 12.0: the owner's PIN for Home Mode, and the best score at each game.
    home_pin = nil,
    home_best = {},
})
device.home_best = type(device.home_best) == "table" and device.home_best or {}
local running = true

ui.usePhoneStyle(false)
-- 12.0: the owner's main colour, orange unless they chose one.
if type(ui.useMainColor) == "function" then ui.useMainColor(ROOT) end

local function findAdvancedMonitor()
    local fallback
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "monitor" then
            local monitor = peripheral.wrap(name)
            if monitor and type(monitor.setTextScale) == "function" then
                pcall(monitor.setTextScale, 0.5)
                local colored = type(monitor.isColor) ~= "function"
                    or monitor.isColor()
                if colored then return monitor, name end
                fallback = fallback or name
            end
        end
    end
    return nil, fallback
end

local target, monitorName = findAdvancedMonitor()
-- FoxyOS 12: an update shows on the monitor, where the players are.
net.updateTarget = target
if not target then
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.red)
    term.clear()
    term.setCursorPos(1, 2)
    if monitorName then
        print("CCG Home needs an Advanced Monitor.")
    else
        print("Attach an Advanced Monitor, then restart CCG Home.")
    end
    return
end

local function saveDevice()
    util.saveTable(devicePath, device)
end

local function fitText(value, width)
    return ui.truncate(tostring(value or ""), math.max(1, width))
end

-- Every screen draws inside the same three-row header, content band, and
-- two-row footer, so the console looks identical on a 1x1 monitor and a wall.
local function frame()
    local width, height = target.getSize()
    return width, height, 4, math.max(5, height - 3), height - 1
end

local function arcadeHeader(title, subtitle, accent)
    local width = target.getSize()
    ui.fill(target, 1, 1, width, 3, colors.black)
    ui.text(target, 2, 1, "CCG // " .. fitText(title, width - 9),
        colors.white, colors.black)
    ui.text(target, 2, 2, fitText(subtitle or "COMPUTERCRAFTGAMING", width - 3),
        colors.lightGray, colors.black)
    ui.fill(target, 1, 3, width, 1, accent or colors.magenta, "=")
end

local function drawLogo(frameIndex)
    local width, height = target.getSize()
    ui.clear(target, colors.black)
    local accent = frameIndex % 2 == 0 and colors.magenta or colors.cyan
    ui.fill(target, 2, 2, width - 2, 1, accent, "=")
    local middle = math.max(5, math.floor(height / 2) - 2)
    ui.center(target, middle, "C C G", colors.white, colors.black)
    ui.center(target, middle + 2, "COMPUTERCRAFTGAMING", accent, colors.black)
    ui.center(target, middle + 4, "HOME", colors.lightGray, colors.black)
    ui.fill(target, 2, height - 1, width - 2, 1, accent, "=")
end

local function bootAnimation()
    for frameIndex = 1, 8 do
        drawLogo(frameIndex)
        sleep(0.07)
    end
end

-- Home Mode, the console's half ------------------------------------------------
-- HOME on the menu asks for the owner's PIN, then shows a six digit pairing
-- code. A PUMPE types it into the CCG app and becomes the controller: every
-- button it sends comes here, and this screen is where the game is played.
-- Nothing goes to the CCG Server, and nothing is paid for.

local function pinHash(pin)
    return util.checksum("CCGHOME:" .. tostring(device.console_id or "")
        .. ":" .. tostring(pin or ""))
end

-- Asked once: on the first start, and on the first start after this update
-- for a console that was already running. Cancelling asks again next time.
local function setHomePin()
    ui.message(target, "info", "SET A HOME PIN",
        "Home Mode is yours: this PIN opens it", 1.4)
    local pin = ui.pin(target, "NEW HOME PIN", true)
    if not pin then return false end
    local again = ui.pin(target, "SAME PIN AGAIN", true)
    if again ~= pin then
        ui.message(target, "error", "PINS DID NOT MATCH", "Nothing was set", 1.2)
        return false
    end
    device.home_pin = pinHash(pin)
    saveDevice()
    ui.message(target, "success", "HOME PIN SET", "Press HOME MODE to play", 1.2)
    return true
end

local function homeCode()
    local code = ""
    for _ = 1, 6 do code = code .. tostring(math.random(0, 9)) end
    return code
end

-- The board a game gets: the screen under the header, over the footer.
local function homeBoard()
    local width, height = target.getSize()
    return 2, 5, math.max(4, width - 2), math.max(4, height - 7)
end

local function homeRefuse(code, message)
    error({ ccg = true, code = code, message = message }, 0)
end

-- Games from the Game Browser, 12.0 Final ------------------------------------------
-- Home Mode plays the four built in and whatever the owner fetched from the
-- App Server's games. A fetched game is the same shape as the four -- new,
-- input, tick, speed, draw -- but it runs in a box: it is handed maths,
-- strings, tables and colours and a board to paint, and nothing that reaches
-- the disk, the network or the monitor itself. A game that fails ends its
-- round; the console carries on. See brickbreaker.lua for the whole of it.
local gamesDir = fs.combine(ROOT, "games")
local gamesFile = fs.combine(ROOT, "ccg_games.dat")
local gameShelf = util.loadTable(gamesFile, { list = {} })
gameShelf.list = type(gameShelf.list) == "table" and gameShelf.list or {}
local shelfGames = {}
local appStore = net.client({ protocol = config.app_protocol or "PUMPE_APPS_V1",
    hostname = config.app_hostname or "APP_SERVER" })
local MAX_GAMES = 12
local SHELF_COLORS = { colors.cyan, colors.pink, colors.lightBlue, colors.green,
    colors.magenta, colors.red }

local function shelved(appId)
    for index, entry in ipairs(gameShelf.list) do
        if entry.app_id == appId then return entry, index end
    end
    return nil
end

local function copyOf(source)
    local out = {}
    for key, value in pairs(source) do out[key] = value end
    return out
end

-- Everything a game is given. Copies, so a game cannot change the console's.
local function gameBox()
    local box = {
        math = copyOf(math), string = copyOf(string), table = copyOf(table),
        colors = copyOf(colors), pairs = pairs, ipairs = ipairs, next = next,
        select = select, tonumber = tonumber, tostring = tostring, type = type,
        pcall = pcall, error = error, assert = assert,
        setmetatable = setmetatable, unpack = table.unpack or unpack,
    }
    box.colours, box._G = box.colors, box
    return box
end

-- A game's file, run in its box. Its table, or nil and why.
local function loadGame(appId, body)
    body = body or util.readFile(fs.combine(gamesDir, appId .. ".lua"))
    if not body then return nil, "its file is missing" end
    local chunk, err = load(body, "=" .. appId, "t", gameBox())
    if not chunk then return nil, tostring(err) end
    local ok, engine = pcall(chunk)
    if not ok then return nil, type(engine) == "string" and engine or "it stopped as it loaded" end
    if type(engine) ~= "table" or type(rawget(engine, "new")) ~= "function"
        or type(rawget(engine, "draw")) ~= "function" then
        return nil, "a game returns a table with new and draw"
    end
    return engine
end

-- Only a game's words: an error that is a table could run its own code
-- the moment it is turned into text.
local function short(err)
    err = (type(err) == "string" or type(err) == "number") and tostring(err) or "?"
    return ui.truncate(err:gsub("^[^:]*:%d+: ", ""), 40)
end

-- The board, as a fetched game sees it: its own coordinates, clipped.
local function boardFor(surface, left, top, width, height)
    local function tint(value, fallback)
        value = tonumber(value)
        for _, known in pairs(colors) do
            if type(known) == "number" and known == value then return value end
        end
        return fallback
    end
    local board = { width = width, height = height }
    function board.fill(x, y, w, h, color)
        x, y = math.floor(tonumber(x) or 1), math.floor(tonumber(y) or 1)
        w, h = math.floor(tonumber(w) or 1), math.floor(tonumber(h) or 1)
        local x1, y1 = math.max(1, x), math.max(1, y)
        local x2, y2 = math.min(width, x + w - 1), math.min(height, y + h - 1)
        if x2 < x1 or y2 < y1 then return end
        ui.fill(surface, left + x1 - 1, top + y1 - 1, x2 - x1 + 1, y2 - y1 + 1,
            tint(color, colors.black))
    end
    function board.text(x, y, text, color, background)
        x, y = math.floor(tonumber(x) or 1), math.floor(tonumber(y) or 1)
        text = tostring(text or "")
        if y < 1 or y > height or x > width then return end
        if x < 1 then text, x = text:sub(2 - x), 1 end
        text = text:sub(1, width - x + 1)
        ui.text(surface, left + x - 1, top + y - 1, text,
            tint(color, colors.white), tint(background, colors.black))
    end
    return board
end

-- A fetched game, dressed as one of the four.
local function shelfGame(entry, index)
    local engine, why = loadGame(entry.app_id)
    local game = { id = entry.app_id, label = string.upper(tostring(entry.name or entry.app_id)),
        hint = entry.description or "", color = SHELF_COLORS[(index - 1) % #SHELF_COLORS + 1],
        fetched = true }
    local function call(name, ...)
        if not engine then return false, why end
        local fn = rawget(engine, name)
        if type(fn) ~= "function" then return true, nil end
        return pcall(fn, ...)
    end
    -- The game keeps its own state; the console keeps a plain copy of the
    -- three things it reads, so nothing of the game's runs outside the box.
    local function sync(play, err)
        if err then play.stopped = "The game stopped: " .. short(err) end
        if play.stopped then
            play.over, play.status = true, play.stopped
            return
        end
        local score = tonumber(rawget(play.inner, "score"))
        if not score or score ~= score or math.abs(score) == math.huge then score = 0 end
        local status = rawget(play.inner, "status")
        play.score = math.floor(score)
        play.over = rawget(play.inner, "over") and true or false
        play.status = type(status) == "string" and ui.truncate(status, 60) or nil
    end
    function game.new(width, height, random)
        local ok, state = call("new", width, height, random)
        if not ok or type(state) ~= "table" then
            local play = { inner = {}, stopped = "It did not start: "
                .. short(ok and "no game came back" or state) }
            sync(play)
            return play
        end
        local play = { inner = state }
        sync(play)
        return play
    end
    function game.input(play, key)
        local ok, err = call("input", play.inner, key)
        sync(play, not ok and (err or "?"))
    end
    function game.tick(play)
        local ok, err = call("tick", play.inner)
        sync(play, not ok and (err or "?"))
    end
    function game.speed(play)
        local ok, value = call("speed", play.inner)
        return math.max(0.05, math.min(2, ok and tonumber(value) or 0.25))
    end
    function game.draw(play, surface, left, top)
        local _, _, width, height = homeBoard()
        ui.fill(surface, left, top, width, height, colors.black)
        local ok, err = call("draw", play.inner, boardFor(surface, left, top, width, height))
        sync(play, not ok and (err or "?"))
    end
    return game
end

-- One of the four, or a fetched one.
local function homeGame(id)
    if homeById[id] then return homeById[id] end
    local entry, index = shelved(id)
    if not entry then return nil end
    shelfGames[id] = shelfGames[id] or shelfGame(entry, index)
    return shelfGames[id]
end

local function saveShelf()
    util.saveTable(gamesFile, gameShelf)
end

-- The Game Browser: the App Server's games, and which of them are here.
local function browseGames()
    local listed = appStore:request("APP_LIST", { kind = "game" }, 5)
    if not listed then
        homeRefuse("NO_APP_SERVER", "No App Server answers. Games come from one:"
            .. " a computer set up from Easy Deployment as APP SERVER")
    end
    local games = {}
    for _, app in ipairs(listed.apps or {}) do
        -- An App Server from before 12.0 Final lists apps and says nothing
        -- of kinds. None of those are games.
        if app.kind == "game" then
            local here = shelved(app.app_id)
            games[#games + 1] = { app_id = app.app_id, name = app.name,
                description = app.description, author = app.author,
                version = app.version, size = app.size, here = here ~= nil,
                update = here ~= nil and here.version ~= app.version }
        end
    end
    return games
end

-- Fetching one, in pieces, checked, tried in its box, then kept.
local function fetchGame(home, appId)
    local info = appStore:request("APP_INFO", { app_id = appId }, 5)
    local app = info and info.app
    if not app then homeRefuse("NO_APP_SERVER", "The App Server did not answer") end
    if app.kind ~= "game" then homeRefuse("NOT_A_GAME", "That is an app, not a game") end
    if not shelved(appId) and #gameShelf.list >= MAX_GAMES then
        homeRefuse("FULL", "This CCG holds " .. MAX_GAMES .. " games. Remove one first")
    end
    local chunks, offset = {}, 0
    while offset < (tonumber(app.size) or 0) do
        home.busy = "GETTING " .. string.upper(tostring(app.name)) .. " "
            .. math.floor(offset * 100 / math.max(1, app.size)) .. "%"
        os.queueEvent("ccg_home")
        local chunk = appStore:request("APP_CHUNK", { app_id = appId, offset = offset,
            limit = config.app_chunk_size }, 5)
        if not chunk or type(chunk.data) ~= "string" or #chunk.data == 0 then
            home.busy = nil
            homeRefuse("DOWNLOAD", "The download stopped")
        end
        chunks[#chunks + 1] = chunk.data
        offset = chunk.next_offset
    end
    home.busy = nil
    local body = table.concat(chunks)
    if #body ~= app.size or util.checksum(body) ~= app.checksum then
        homeRefuse("DAMAGED", "The download was damaged. Nothing changed")
    end
    local engine, why = loadGame(appId, body)
    if not engine then homeRefuse("BROKEN", "It does not run: " .. short(why)) end
    pcall(fs.makeDir, gamesDir)
    if not pcall(util.writeFile, fs.combine(gamesDir, appId .. ".lua"), body) then
        homeRefuse("NO_SPACE", "No room for it on this CCG")
    end
    local record = { app_id = appId, name = app.name, description = app.description,
        author = app.author, version = app.version, checksum = app.checksum }
    local _, index = shelved(appId)
    if index then gameShelf.list[index] = record
    else gameShelf.list[#gameShelf.list + 1] = record end
    shelfGames[appId] = nil
    saveShelf()
end

local function removeGame(appId)
    local _, index = shelved(appId)
    if not index then homeRefuse("NOT_HERE", "That game is not on this CCG") end
    table.remove(gameShelf.list, index)
    shelfGames[appId] = nil
    pcall(fs.delete, fs.combine(gamesDir, appId .. ".lua"))
    saveShelf()
end

local function homeState(home)
    local game = home.game and homeGame(home.game)
    local list = {}
    for _, entry in ipairs(HOME_GAMES) do
        list[#list + 1] = { id = entry.id, label = entry.label, hint = entry.hint,
            best = device.home_best[entry.id] or 0 }
    end
    for _, entry in ipairs(gameShelf.list) do
        list[#list + 1] = { id = entry.app_id, label = string.upper(tostring(entry.name)),
            hint = entry.description, best = device.home_best[entry.app_id] or 0,
            fetched = true }
    end
    return {
        console = device.name ~= "" and device.name or "CCG",
        screen = home.screen, game = home.game, label = game and game.label,
        score = home.play and home.play.score or 0,
        best = home.game and device.home_best[home.game] or 0,
        status = home.play and home.play.status or nil,
        record = home.record, games = list,
    }
end

local homeFinish

local function homeStart(home, id)
    local game = homeGame(id)
    if not game then return false end
    local _, _, width, height = homeBoard()
    home.game, home.play, home.screen, home.record = id, game.new(width, height,
        math.random), "game", nil
    -- A game that could not start is over before it began, and says why.
    homeFinish(home)
    return true
end

function homeFinish(home)
    if home.screen ~= "game" or not (home.play and home.play.over) then return end
    home.screen = "over"
    local best = device.home_best[home.game] or 0
    local score = tonumber(home.play.score) or 0
    if score > best then
        device.home_best[home.game] = score
        home.record = true
        saveDevice()
    end
end

-- Time passing in the game being played: what the screen's timer does.
local function homeTick(home)
    local game = home.screen == "game" and homeGame(home.game)
    if game and game.tick then
        game.tick(home.play)
        homeFinish(home)
    end
end

local function homeNewCode(home)
    if home.code then pcall(rednet.unhost, HOME_PROTOCOL) end
    home.code, home.misses = homeCode(), 0
    pcall(rednet.host, HOME_PROTOCOL, "CCGHOME_" .. home.code)
end

-- One request from the paired phone, or from a phone asking to pair.
local function homeHandle(home, action, payload, sender)
    local refuse = homeRefuse
    if action == "HOME_PAIR" then
        if home.peer then refuse("PAIRED", "This CCG already has a controller") end
        if tostring(payload.code or "") ~= home.code then
            home.misses = home.misses + 1
            -- Guessing gets a new code, and the screen shows it.
            if home.misses >= 5 then homeNewCode(home) end
            refuse("BAD_CODE", "That is not the code on the CCG")
        end
        home.peer, home.token = sender, util.token and util.token("HOME")
            or tostring(math.random(100000, 999999)) .. tostring(sender)
        home.player = ui.truncate(tostring(payload.name or "Player"), 14)
        home.screen = "menu"
        return { token = home.token, state = homeState(home) }
    end
    if sender ~= home.peer or payload.token ~= home.token then
        refuse("NOT_PAIRED", "Pair with the CCG again")
    end
    if action == "HOME_PLAY" then
        if not homeStart(home, tostring(payload.game or "")) then
            refuse("NO_SUCH_GAME", "That game is not on this CCG")
        end
    elseif action == "HOME_INPUT" then
        local key = tostring(payload.key or "")
        if home.screen == "game" then
            homeGame(home.game).input(home.play, key)
            homeFinish(home)
        elseif home.screen == "over" and key == "a" then
            homeStart(home, home.game)
        end
    elseif action == "HOME_MENU" then
        home.screen, home.play, home.game, home.record = "menu", nil, nil, nil
    -- 12.0 Final: the Game Browser. Only here, in Home Mode.
    elseif action == "HOME_BROWSE" then
        return { games = browseGames(), state = homeState(home) }
    elseif action == "HOME_GET" then
        fetchGame(home, tostring(payload.app_id or ""))
    elseif action == "HOME_REMOVE" then
        if home.game == payload.app_id then
            home.screen, home.play, home.game = "menu", nil, nil
        end
        removeGame(tostring(payload.app_id or ""))
    elseif action == "HOME_LEAVE" then
        home.peer, home.token, home.player = nil, nil, nil
        home.screen, home.play, home.game = "pair", nil, nil
        homeNewCode(home)
        return { left = true }
    elseif action ~= "HOME_STATE" then
        refuse("UNKNOWN", "Unknown Home Mode request")
    end
    return homeState(home)
end

local function homeDraw(home)
    local width, height = target.getSize()
    ui.clear(target, colors.black)
    local accent = ui.theme.accent
    if home.screen == "pair" then
        arcadeHeader("HOME MODE", "PAIR A POCKET", accent)
        local top = 5
        ui.center(target, top, "OPEN CCG ON YOUR POCKET", colors.white, colors.black)
        ui.center(target, top + 1, "HOME > TYPE THIS CODE", colors.lightGray, colors.black)
        if not ui.wordmark(target, top + 3, home.code, nil, accent) then
            ui.center(target, top + 4, home.code, accent, colors.black)
        end
        ui.center(target, math.min(height - 3, top + 10), "FREE // NO BETS // ONE PLAYER",
            colors.lightGray, colors.black)
    elseif home.screen == "menu" then
        arcadeHeader("HOME MODE", ui.truncate(tostring(home.player), width - 4)
            .. " IS PLAYING", accent)
        ui.center(target, 5, ui.truncate(home.busy or "PICK A GAME ON YOUR POCKET",
            width), home.busy and colors.yellow or colors.white, colors.black)
        -- The four, then what was fetched, as many as fit.
        local games = {}
        for _, game in ipairs(HOME_GAMES) do games[#games + 1] = game end
        for _, entry in ipairs(gameShelf.list) do
            local game = homeGame(entry.app_id)
            if game then games[#games + 1] = game end
        end
        local room = math.max(1, math.floor((height - 9) / 2) + 1)
        for index, game in ipairs(games) do
            local y = 5 + index * 2
            if index == room and #games > room then
                ui.text(target, 3, y, "+" .. (#games - room + 1) .. " MORE",
                    colors.lightGray, colors.black)
                break
            end
            ui.fill(target, 2, y, width - 2, 1, game.color)
            ui.text(target, 3, y, ui.truncate(game.label .. "  BEST "
                .. (device.home_best[game.id] or 0), width - 4),
                ui.inkOn(game.color), game.color)
        end
    else
        local game = homeGame(home.game)
        local score = tonumber(home.play.score) or 0
        arcadeHeader(game.label, "SCORE " .. score .. "  BEST "
            .. math.max(score, device.home_best[game.id] or 0), game.color)
        local left, top = homeBoard()
        game.draw(home.play, target, left, top)
        if home.screen == "over" then
            local middle = math.floor(height / 2)
            ui.fill(target, 2, middle - 1, width - 2, 3, colors.gray)
            ui.center(target, middle - 1, home.record and "NEW BEST!" or "GAME OVER",
                home.record and colors.yellow or colors.white, colors.gray)
            ui.center(target, middle, ui.truncate(tostring(home.play.status or ""),
                width - 4), colors.lightGray, colors.gray)
            ui.center(target, middle + 1, "A TO PLAY AGAIN", colors.white, colors.gray)
        end
    end
    ui.fill(target, 1, height, width, 1, colors.black)
    ui.text(target, width - 6, height, "EXIT", colors.white, colors.red)
    if home.screen == "pair" then
        ui.text(target, 2, height, "COLOR", ui.inkOn(accent), accent)
        ui.text(target, 8, height, "PIN", colors.white, colors.gray)
        -- FoxyOS 15.1: Beta Updates, the owner's like the rest of this row.
        local betaOn = util.betaJoined(ROOT)
        ui.text(target, 12, height, "BETA", betaOn and colors.black or colors.white,
            betaOn and colors.lime or colors.gray)
    end
end

local function homeMode()
    if not device.home_pin and not setHomePin() then return end
    local pin = ui.pin(target, "HOME PIN", true)
    if not pin then return end
    if pinHash(pin) ~= device.home_pin then
        ui.message(target, "error", "WRONG PIN", "Home Mode stays shut", 1.2)
        return
    end
    local home = { screen = "pair", active = true }
    net.openModems()
    homeNewCode(home)
    local function listen()
        while home.active do
            local sender, message = rednet.receive(HOME_PROTOCOL, 1)
            if sender and type(message) == "table" and message.kind == "request"
                and type(message.action) == "string" then
                local ok, result = pcall(homeHandle, home, message.action,
                    type(message.payload) == "table" and message.payload or {}, sender)
                if ok then
                    net.reply(sender, HOME_PROTOCOL, message.request_id, true, result)
                elseif type(result) == "table" and result.ccg then
                    net.reply(sender, HOME_PROTOCOL, message.request_id, false, nil,
                        result.message, result.code)
                else
                    net.reply(sender, HOME_PROTOCOL, message.request_id, false, nil,
                        "The CCG could not do that", "HOME_ERROR")
                end
                os.queueEvent("ccg_home")
            end
        end
    end
    local function play()
        local timer
        while home.active do
            homeDraw(home)
            local game = home.screen == "game" and homeGame(home.game)
            if not timer then
                timer = os.startTimer(game and game.speed and game.speed(home.play) or 1)
            end
            local event, a, b, c = os.pullEvent()
            if event == "timer" and a == timer then
                timer = nil
                homeTick(home)
            elseif event == "monitor_touch" or event == "mouse_click" then
                local width, height = target.getSize()
                if c == height and b >= width - 6 and b <= width - 3 then
                    home.active = false
                elseif c == height and b >= 2 and b <= 6 and home.screen == "pair"
                    and type(ui.pickMainColor) == "function" then
                    -- The owner's setting, behind the owner's PIN.
                    ui.pickMainColor(target, ROOT, "CCG COLOUR")
                elseif c == height and b >= 8 and b <= 10 and home.screen == "pair" then
                    -- A new Home PIN; the old one opened this screen.
                    setHomePin()
                elseif c == height and b >= 12 and b <= 15 and home.screen == "pair"
                    and type(ui.betaUpdates) == "function" then
                    ui.betaUpdates(target, ROOT, { kind = "console", version = config.version })
                end
            elseif event == "terminate" then
                running, home.active = false, false
            end
        end
    end
    parallel.waitForAny(listen, play)
    pcall(rednet.unhost, HOME_PROTOCOL)
    if home.peer then
        -- The phone finds out on its next button: NOT_PAIRED.
        home.peer = nil
    end
end

if PUMPE_TEST_MODE == "ccg_home" then
    return { handle = homeHandle, state = homeState, draw = homeDraw, tick = homeTick,
        new_code = homeNewCode, device = device, set_pin = setHomePin,
        pin_hash = pinHash, home_mode = homeMode, games = homeById }
end

-- The menu ------------------------------------------------------------------------
-- Home Mode, and the way out. Nothing here needs a server.

local function mainMenu()
    while running do
        local width, _, top, bottom, footerY = frame()
        ui.clear(target, colors.black)
        arcadeHeader(device.name ~= "" and device.name or "CCG HOME", "FREE // ONE PLAYER",
            ui.theme.accent)
        local scene = ui.scene(target)
        local tall = math.max(2, math.min(6, bottom - top - 1))
        scene:button("home", 2, top + 1, width - 2, tall,
            "HOME MODE\nFREE // ONE PLAYER", {
                background = ui.theme.accent, foreground = ui.inkOn(ui.theme.accent) })
        scene:button("close", 2, footerY, width - 2, 2, "CLOSE",
            { background = colors.red })
        local action = scene:wait({ tickRate = 1 })
        if action == "__tick" then
            net.autoUpdate(config, "ccghome", ROOT, nil)
        elseif action == "home" then
            homeMode()
        elseif action == "close" or action == "__terminate" then
            running = false
        end
    end
end

-- Starting ---------------------------------------------------------------

bootAnimation()
net.autoUpdate(config, "ccghome", ROOT, nil,
    { force = true, programVersion = PROGRAM_VERSION })
-- A new console: its colour, and the owner's Home PIN.
if type(ui.hasMainColor) == "function" and not ui.hasMainColor(ROOT) then
    ui.pickMainColor(target, ROOT, "CCG COLOUR")
end
if not device.home_pin then setHomePin() end
-- Straight into Home Mode: it is what this console is for.
homeMode()
mainMenu()

ui.clear(target, colors.black)
ui.center(target, math.floor(select(2, target.getSize()) / 2),
    "CCG HOME OFF", colors.lightGray, colors.black)
