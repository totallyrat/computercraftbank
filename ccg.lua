-- ComputerCraftGaming Bet Play console.
-- Runs on an Advanced Computer with an Ender/wireless modem and any-size
-- Advanced Monitor. Game outcomes and Survivor physics are Bank-authoritative.

local ROOT = fs.getDir(shell.getRunningProgram())
if ROOT == "" then ROOT = "." end
package.path = package.path .. ";" .. fs.combine(ROOT, "?.lua")
    .. ";" .. fs.combine(ROOT, "?/init.lua")

-- Stamped by tools/build_release_manifest.js. A program running beside a
-- config.lua from a different release means a partial install.
local PROGRAM_VERSION = "11.9.1"
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

-- Since 9.1 the games live on their own computer. The console talks to the
-- CCG Server; the Bank is not in this path at all.
local client = net.client({
    protocol = config.ccg_protocol or "PUMPE_CCG_V1",
    hostname = config.ccg_hostname or "CCG_SERVER",
})
local devicePath = fs.combine(ROOT, "ccg_device.dat")
local device = util.loadTable(devicePath, {
    console_id = nil,
    console_token = nil,
    name = "",
    auto = nil,
    -- 12.0: the owner's PIN for Home Mode, and the best score at each game.
    home_pin = nil,
    home_best = {},
})
device.home_best = type(device.home_best) == "table" and device.home_best or {}
local running = true

-- Auto Mode keeps opening the next lobby on its own. It is unlocked with the
-- code the operator typed when starting it, and it survives a reboot so an
-- automatic update never leaves the arena dark.
local auto = nil

ui.usePhoneStyle(false)
-- 12.0: the owner's main colour, orange unless they chose one.
if type(ui.useMainColor) == "function" then ui.useMainColor(ROOT) end

local GAMES = {
    { id = "heads_tails", label = "HEADS OR TAILS", tag = "2X",
        color = colors.blue, ink = colors.white, minimum = 1 },
    { id = "race", label = "RACE", tag = "6 CARS // 3X",
        color = colors.orange, ink = colors.black, minimum = 1 },
    { id = "survivor", label = "SURVIVOR", tag = "PUSH // 3X",
        color = colors.purple, ink = colors.white, minimum = 2 },
}
local gameById = {}
for _, game in ipairs(GAMES) do gameById[game.id] = game end

local gameColors = {
    red = colors.red,
    orange = colors.orange,
    yellow = colors.yellow,
    green = colors.lime,
    blue = colors.lightBlue,
    purple = colors.purple,
}

-- Lobby scenes tick twice a second; result scenes tick once a second.
local AUTO_START_TICKS = math.max(2,
    math.floor((tonumber(config.ccg_auto_start_seconds) or 15) * 2))
local AUTO_NEXT_TICKS = math.max(1,
    math.floor(tonumber(config.ccg_auto_next_seconds) or 8))

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
if not target then
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.red)
    term.clear()
    term.setCursorPos(1, 2)
    if monitorName then
        print("CCG needs an Advanced Monitor.")
    else
        print("Attach an Advanced Monitor, then restart CCG.")
    end
    return
end

local function saveDevice()
    util.saveTable(devicePath, device)
end

local function request(action, payload, silent, timeout)
    payload = payload or {}
    if device.console_id and not payload.console_id then
        payload.console_id = device.console_id
        payload.console_token = device.console_token
    end
    local result, err = client:request(action, payload, timeout)
    if not result and not silent then ui.networkError(target, err) end
    return result, err
end

local function fitText(value, width)
    return ui.truncate(tostring(value or ""), math.max(1, width))
end

local function money(value)
    return util.money(value, config.currency)
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
    ui.text(target, 2, 2,
        fitText(subtitle or "COMPUTERCRAFTGAMING", width - (auto and 8 or 3)),
        colors.lightGray, colors.black)
    ui.fill(target, 1, 3, width, 1, accent or colors.magenta, "=")
    if auto then
        ui.text(target, math.max(1, width - 5), 2, "AUTO",
            colors.lime, colors.black)
    end
end

local function registerConsole()
    if not client:discover() then
        ui.message(target, "error", "BANK OFFLINE",
            "CCG needs the PUMPE Bank Server", 1.5)
        return false
    end
    local result = request("CCG_REGISTER", {
        console_id = device.console_id,
        console_token = device.console_token,
        name = device.name ~= "" and device.name or nil,
    }, true)
    if not result then
        local name = ui.input(target, "NAME THIS CCG", {
            hint = "Shown on the lobby screen",
            maxLength = 24,
            minLength = 2,
            allowSpace = true,
            initial = device.name,
        })
        if not name then return false end
        result = request("CCG_REGISTER", { name = name })
    end
    if not result then return false end
    device.console_id = result.console_id
    device.console_token = result.console_token
    device.name = result.name
    saveDevice()
    return true
end

local function drawLogo(frameIndex)
    local width, height = target.getSize()
    ui.clear(target, colors.black)
    local accent = frameIndex % 2 == 0 and colors.magenta or colors.cyan
    ui.fill(target, 2, 2, width - 2, 1, accent, "=")
    local middle = math.max(5, math.floor(height / 2) - 2)
    ui.center(target, middle, "C C G", colors.white, colors.black)
    ui.center(target, middle + 2, "COMPUTERCRAFTGAMING", accent, colors.black)
    ui.center(target, middle + 4, "BET PLAY", colors.lightGray, colors.black)
    ui.fill(target, 2, height - 1, width - 2, 1, accent, "=")
end

local function bootAnimation()
    for frameIndex = 1, 8 do
        drawLogo(frameIndex)
        sleep(0.07)
    end
end

-- Auto Mode controls ------------------------------------------------------

local function codeHash(value)
    return util.checksum(string.upper(util.trim(tostring(value or ""))))
end

local function askCode(title, hint)
    return ui.input(target, title, {
        hint = hint,
        mode = "code",
        minLength = 3,
        maxLength = 12,
    })
end

local function startAuto()
    local choice
    while running and not choice do
        local width, _, top, bottom, footerY = frame()
        ui.clear(target, colors.black)
        arcadeHeader("AUTO MODE", "PICK WHAT KEEPS RUNNING", colors.lime)
        ui.center(target, top + 1, "AUTO MODE RUNS FOREVER",
            colors.white, colors.black)
        local scene = ui.scene(target)
        local rows = #GAMES + 1
        local step = math.min(4,
            math.max(2, math.floor((bottom - top - 2) / rows)))
        for index, game in ipairs(GAMES) do
            scene:button("game:" .. game.id, 2, top + 2 + (index - 1) * step,
                width - 2, math.min(step, 2), game.label .. " // " .. game.tag,
                { background = game.color, foreground = game.ink })
        end
        scene:button("game:rotate", 2, top + 2 + #GAMES * step, width - 2,
            math.min(step, 2), "ROTATE ALL GAMES",
            { background = colors.magenta })
        scene:button("cancel", 2, footerY, width - 2, 2, "BACK",
            { background = colors.gray })
        local action = scene:wait({ tickRate = 1 })
        if action == "cancel" or action == "__terminate" then
            if action == "__terminate" then running = false end
            return false
        elseif action ~= "__tick" then
            choice = action and action:match("^game:(.+)$")
        end
    end
    if not choice then return false end

    local code = askCode("AUTO MODE STOP CODE",
        "Needed again to stop Auto Mode")
    if not code then return false end
    local confirmation = askCode("REPEAT STOP CODE", "Type the same code")
    if not confirmation or codeHash(confirmation) ~= codeHash(code) then
        ui.message(target, "error", "CODES DID NOT MATCH",
            "Auto Mode was not started", 1.4)
        return false
    end

    auto = { game = choice, hash = codeHash(code), index = 0 }
    device.auto = auto
    saveDevice()
    ui.message(target, "success", "AUTO MODE ON",
        "Keep the stop code safe", 1.2)
    return true
end

local function stopAuto()
    if not auto then return true end
    local code = askCode("STOP AUTO MODE", "Enter the Auto Mode code")
    if not code then return false end
    if codeHash(code) ~= auto.hash then
        ui.message(target, "error", "WRONG CODE", "Auto Mode is still on", 1.4)
        return false
    end
    auto = nil
    device.auto = nil
    saveDevice()
    ui.message(target, "success", "AUTO MODE OFF", "Back to manual play", 1.1)
    return true
end

local function nextAutoGame()
    if auto.game ~= "rotate" then return auto.game end
    auto.index = (auto.index or 0) % #GAMES + 1
    device.auto = auto
    saveDevice()
    return GAMES[auto.index].id
end

-- Screens -----------------------------------------------------------------

local function gameMenu()
    while running do
        local width, height, top, bottom, footerY = frame()
        ui.clear(target, colors.black)
        arcadeHeader("BET PLAY", device.name, ui.theme.accent)
        ui.center(target, top, "SELECT A GAME", colors.white, colors.black)
        local scene = ui.scene(target)
        local autoY = bottom - 1
        if width >= 45 then
            local cardWidth = math.floor((width - 4) / 3)
            local cardHeight = math.max(2, autoY - 2 - (top + 2) + 1)
            for index, game in ipairs(GAMES) do
                scene:button(game.id, 2 + (index - 1) * (cardWidth + 1),
                    top + 2, cardWidth, cardHeight,
                    game.label .. "\n" .. game.tag,
                    { background = game.color, foreground = game.ink })
            end
        else
            local step = math.min(4,
                math.max(2, math.floor((autoY - 1 - (top + 2)) / 3)))
            for index, game in ipairs(GAMES) do
                scene:button(game.id, 2, top + 2 + (index - 1) * step,
                    width - 2, math.min(step, 2),
                    game.label .. " // " .. game.tag,
                    { background = game.color, foreground = game.ink })
            end
        end
        -- 12.0: Home Mode beside Auto Mode. Free, one player, the owner's.
        local half = math.floor((width - 3) / 2)
        scene:button("auto", 2, autoY, half, 2,
            width >= 45 and "AUTO MODE // NON-STOP" or "AUTO MODE", {
                background = colors.lime, foreground = colors.black,
            })
        scene:button("home", 3 + half, autoY, width - 3 - half, 2,
            width >= 45 and "HOME MODE // FREE" or "HOME MODE", {
                background = ui.theme.accent, foreground = ui.inkOn(ui.theme.accent),
            })
        scene:button("close", width - 7, 1, 6, 1, "CLOSE",
            { background = colors.red })
        local action = scene:wait({ tickRate = 1 })
        if action == "__tick" then
            net.autoUpdate(config, "ccg", ROOT, client)
        elseif action == "close" or action == "__terminate" then
            running = false
            return nil
        elseif action == "auto" then
            if startAuto() then return nextAutoGame() end
        elseif action == "home" then
            return "home"
        elseif gameById[action] then
            return action
        end
    end
end

local function playerList(lobby, startY, maximumRows)
    local width = target.getSize()
    local players = lobby.players or {}
    local shown = math.min(#players, maximumRows)
    if #players > maximumRows then shown = math.max(0, maximumRows - 1) end
    for index = 1, shown do
        local player = players[index]
        local line = string.format("%02d %-12s %s %s",
            player.seat or index,
            fitText(player.display_name, 12),
            player.ready and "READY" or "PICKING",
            player.ready and money(player.wager) or "")
        ui.text(target, 3, startY + index - 1, fitText(line, width - 4),
            player.ready and colors.lime or colors.lightGray, colors.black)
    end
    if #players > shown then
        ui.text(target, 3, startY + shown,
            "+" .. (#players - shown) .. " MORE PLAYERS",
            colors.lightGray, colors.black)
    elseif #players == 0 then
        ui.text(target, 3, startY, "WAITING FOR PLAYERS...",
            colors.lightGray, colors.black)
    end
end

local function readyCount(lobby)
    local ready = 0
    for _, player in ipairs(lobby.players or {}) do
        if player.ready then ready = ready + 1 end
    end
    return ready
end

local function waitForLobby(game, existingLobby)
    local definition = gameById[game] or GAMES[1]
    local lobby = existingLobby
    if not lobby then
        local created = request("CCG_CREATE_LOBBY", { game = game }, auto ~= nil)
        if not created then return nil, "offline" end
        lobby = created.lobby
    end
    local countdown
    while running and lobby.status == "lobby" do
        local width, height, top, bottom, footerY = frame()
        local ready = readyCount(lobby)
        local startable = ready >= definition.minimum
            and ready == (lobby.player_count or 0)
        ui.clear(target, colors.black)
        arcadeHeader(lobby.game_name, "LOBBY // CCG APP > BET", colors.cyan)
        ui.center(target, top, "JOIN CODE", colors.lightGray, colors.black)
        ui.center(target, top + 2, lobby.code, colors.white, colors.black)
        ui.fill(target, 2, top + 4, width - 2, 1, colors.gray, "-")
        playerList(lobby, top + 5, math.max(1, bottom - (top + 5)))

        local statusText
        if auto and countdown then
            statusText = "AUTO START IN " .. math.ceil(countdown / 2) .. "s"
        elseif auto then
            statusText = "AUTO WAITING FOR " .. definition.minimum .. "+ READY"
        else
            statusText = ready .. "/" .. (lobby.player_count or 0) .. " READY"
        end
        ui.text(target, 2, bottom, fitText(statusText, width - 2),
            startable and colors.lime or colors.orange, colors.black)

        local scene = ui.scene(target)
        local half = math.max(8, math.floor((width - 3) / 2))
        scene:button("cancel", 2, footerY, half, 2,
            auto and "STOP AUTO" or "CANCEL", { background = colors.red })
        scene:button("start", 2 + half + 1, footerY, width - 3 - half, 2,
            "START // " .. tostring(lobby.player_count or 0), {
                background = startable and colors.lime or colors.gray,
                foreground = colors.black,
                disabled = not startable,
            })
        local action = scene:wait({ tickRate = 0.5 })
        if action == "__tick" then
            local refreshed = request("CCG_CONSOLE_STATUS", {
                code = lobby.code,
            }, true)
            if refreshed then lobby = refreshed.lobby end
            if auto and lobby.status == "lobby" then
                local waiting = readyCount(lobby)
                if waiting >= definition.minimum
                    and waiting == (lobby.player_count or 0) then
                    countdown = (countdown or AUTO_START_TICKS) - 1
                    if countdown <= 0 then
                        local started = request("CCG_START",
                            { code = lobby.code }, true)
                        if started then return started.lobby end
                        countdown = AUTO_START_TICKS
                    end
                else
                    countdown = nil
                end
            end
            net.autoUpdate(config, "ccg", ROOT, client)
        elseif action == "start" then
            local started = request("CCG_START", { code = lobby.code })
            if started then return started.lobby end
        elseif action == "cancel" or action == "__terminate" then
            if action == "__terminate" then
                request("CCG_CANCEL_LOBBY", { code = lobby.code }, true)
                running = false
                return nil
            end
            if auto then
                if stopAuto() then
                    request("CCG_CANCEL_LOBBY", { code = lobby.code }, true)
                    return nil
                end
            else
                request("CCG_CANCEL_LOBBY", { code = lobby.code }, true)
                return nil
            end
        end
    end
    return lobby
end

local function waitForFinished(lobby)
    while running and lobby and lobby.status == "running" do
        local status = request("CCG_TICK", { code = lobby.code }, true, 2)
        if status then lobby = status.lobby end
        if lobby and lobby.status == "running" then sleep(0.15) end
    end
    return lobby
end

local function coinAnimation(lobby)
    local width, height = target.getSize()
    local boxWidth = math.min(15, width - 4)
    local boxX = math.floor((width - boxWidth) / 2) + 1
    local boxY = math.max(5, math.floor((height - 7) / 2) + 1)
    for frameIndex = 1, 34 do
        ui.clear(target, colors.black)
        arcadeHeader("HEADS OR TAILS", "LOCKED // 2X", colors.cyan)
        local face = frameIndex % 2 == 0 and "H" or "T"
        if frameIndex > 29 then face = string.upper(lobby.outcome:sub(1, 1)) end
        local shade = frameIndex % 2 == 0 and colors.orange or colors.yellow
        ui.card(target, boxX, boxY, boxWidth, math.min(7, height - boxY), shade)
        ui.center(target, boxY + 2, face, colors.black, shade)
        ui.center(target, math.min(height, boxY + 5),
            frameIndex > 29 and "RESULT LOCKED" or "FLIPPING",
            colors.white, colors.black)
        sleep(frameIndex > 29 and 0.14 or 0.07)
    end
    return waitForFinished(lobby)
end

local function raceAnimation(lobby)
    local width, height = target.getSize()
    local orderIndex = {}
    for index, colorName in ipairs(lobby.race_order or {}) do
        orderIndex[colorName] = index
    end
    local trackStart = math.max(8, math.floor(width * 0.17))
    local trackLength = math.max(8, width - trackStart - 2)
    local top = 4
    local laneHeight = math.max(1, math.floor((height - top) / 6))
    for frameIndex = 1, 44 do
        ui.clear(target, colors.black)
        arcadeHeader("RACE", "6 CARS // SERVER RANDOM // 3X", colors.orange)
        for lane, colorName in ipairs({
            "red", "orange", "yellow", "green", "blue", "purple",
        }) do
            local y = top + (lane - 1) * laneHeight
            local color = gameColors[colorName]
            ui.text(target, 1, y,
                fitText(string.upper(colorName), trackStart - 2),
                color, colors.black)
            ui.fill(target, trackStart, y, trackLength, 1, colors.gray, "-")
            local rank = orderIndex[colorName] or lane
            local progress = util.clamp(frameIndex / 44
                + math.sin(frameIndex * 0.63 + lane * 1.7) * 0.035
                - (rank - 1) * (frameIndex / 44) * 0.022, 0, 1)
            if frameIndex == 44 then progress = 1 - (rank - 1) * 0.045 end
            local x = trackStart + math.floor(progress * (trackLength - 1))
            ui.text(target, x, y, ">", colors.black, color)
        end
        sleep(0.09)
    end
    return waitForFinished(lobby)
end

local function drawSurvivor(lobby)
    local width, height = target.getSize()
    ui.clear(target, colors.black)
    arcadeHeader("SURVIVOR", "MOVE // PUSH // LAST ONE STANDING", colors.purple)
    local centerX = math.floor(width / 2)
    local centerY = math.floor((height + 3) / 2)
    local radiusY = math.max(3, math.floor((height - 6) / 2))
    local radiusX = math.max(6, math.min(math.floor((width - 4) / 2), radiusY * 2))
    for y = -radiusY, radiusY do
        for x = -radiusX, radiusX do
            local normalized = (x / radiusX) ^ 2 + (y / radiusY) ^ 2
            if normalized <= 1 then
                local background = normalized > 0.82
                    and colors.lightGray or colors.gray
                ui.text(target, centerX + x, centerY + y, " ",
                    colors.white, background)
            end
        end
    end
    local scale = math.max(1, tonumber(lobby.platform_radius) or 850)
    for _, player in ipairs(lobby.players or {}) do
        if player.alive then
            local px = centerX + math.floor((player.x or 0) / scale * radiusX)
            local py = centerY + math.floor((player.y or 0) / scale * radiusY)
            px = util.clamp(px, 1, width)
            py = util.clamp(py, 4, height)
            ui.text(target, px, py, tostring((player.seat or 0) % 10),
                colors.black, gameColors[player.color] or colors.white)
        end
    end
    local alive = 0
    for _, player in ipairs(lobby.players or {}) do
        if player.alive then alive = alive + 1 end
    end
    ui.text(target, 2, height, "ALIVE " .. alive, colors.lime, colors.black)
    ui.text(target, math.max(1, width - 13), height,
        "RING " .. math.floor(scale), colors.orange, colors.black)
end

local function survivorAnimation(lobby)
    while running and lobby.status == "running" do
        drawSurvivor(lobby)
        local status = request("CCG_TICK", { code = lobby.code }, true, 2)
        if status then lobby = status.lobby end
        if lobby.status == "running" then sleep(0.12) end
    end
    return lobby
end

local function resultScreen(lobby)
    if not lobby then return end
    local countdown = auto and AUTO_NEXT_TICKS or nil
    while running do
        local width, height, top, bottom, footerY = frame()
        ui.clear(target, colors.black)
        arcadeHeader("RESULT", lobby.game_name, colors.lime)
        local caption, headline, tint
        if lobby.game == "heads_tails" then
            caption, headline = "THE COIN LANDED",
                string.upper(lobby.outcome or "?")
            tint = colors.yellow
        elseif lobby.game == "race" then
            caption = "WINNING CAR"
            headline = string.upper(lobby.outcome or "UNKNOWN")
            tint = gameColors[lobby.outcome or ""] or colors.white
        else
            caption, headline = "LAST PLAYER STANDING",
                lobby.winner_name or "NO WINNER"
            tint = colors.lime
        end
        local middle = math.max(top, math.floor((top + bottom) / 2) - 2)
        ui.center(target, middle, caption, colors.lightGray, colors.black)
        ui.center(target, middle + 2, fitText(headline, width - 2),
            tint, colors.black)
        ui.center(target, middle + 4,
            tostring(lobby.multiplier or 0) .. "X PAYOUT",
            colors.white, colors.black)
        ui.center(target, bottom, fitText("WINNINGS MOVE TO 1-DAY HOLDING",
            width - 2), colors.magenta, colors.black)

        local scene = ui.scene(target)
        if auto then
            local half = math.max(8, math.floor((width - 3) / 2))
            scene:button("stop", 2, footerY, half, 2, "STOP AUTO",
                { background = colors.red })
            scene:button("again", 2 + half + 1, footerY, width - 3 - half, 2,
                "NEXT GAME " .. tostring(countdown) .. "s",
                { background = colors.lime, foreground = colors.black })
        else
            scene:button("again", math.max(2, math.floor(width / 4)), footerY,
                math.max(10, math.floor(width / 2)), 2, "NEXT GAME",
                { background = colors.lime, foreground = colors.black })
        end
        local action = scene:wait({ tickRate = 1 })
        if action == "again" then return end
        if action == "stop" then
            if stopAuto() then return end
            countdown = AUTO_NEXT_TICKS
        elseif action == "__terminate" then
            running = false
            return
        elseif action == "__tick" then
            net.autoUpdate(config, "ccg", ROOT, client)
            if countdown then
                countdown = countdown - 1
                if countdown <= 0 then return end
            end
        end
    end
end

-- Auto Mode has no game menu to fall back to, so a Bank outage parks the
-- console on a visible standby screen that still offers STOP AUTO.
local function autoStandby()
    local width, _, top, bottom, footerY = frame()
    ui.clear(target, colors.black)
    arcadeHeader("AUTO MODE", "WAITING FOR THE BANK SERVER", colors.orange)
    ui.center(target, math.floor((top + bottom) / 2), "BANK OFFLINE",
        colors.red, colors.black)
    ui.center(target, math.floor((top + bottom) / 2) + 2,
        "RETRYING AUTOMATICALLY", colors.lightGray, colors.black)
    local scene = ui.scene(target)
    scene:button("stop", 2, footerY, width - 2, 2, "STOP AUTO",
        { background = colors.red })
    local action = scene:wait({ tickRate = 3 })
    if action == "stop" then
        stopAuto()
    elseif action == "__terminate" then
        running = false
    else
        net.autoUpdate(config, "ccg", ROOT, client)
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

local function homeState(home)
    local game = home.game and homeById[home.game]
    local list = {}
    for _, entry in ipairs(HOME_GAMES) do
        list[#list + 1] = { id = entry.id, label = entry.label, hint = entry.hint,
            best = device.home_best[entry.id] or 0 }
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

local function homeStart(home, id)
    local game = homeById[id]
    if not game then return false end
    local _, _, width, height = homeBoard()
    home.game, home.play, home.screen, home.record = id, game.new(width, height,
        math.random), "game", nil
    return true
end

local function homeFinish(home)
    if home.screen ~= "game" or not (home.play and home.play.over) then return end
    home.screen = "over"
    local best = device.home_best[home.game] or 0
    if home.play.score > best then
        device.home_best[home.game] = home.play.score
        home.record = true
        saveDevice()
    end
end

-- Time passing in the game being played: what the screen's timer does.
local function homeTick(home)
    local game = home.screen == "game" and homeById[home.game]
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
    local function refuse(code, message) error({ ccg = true, code = code,
        message = message }, 0) end
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
            homeById[home.game].input(home.play, key)
            homeFinish(home)
        elseif home.screen == "over" and key == "a" then
            homeStart(home, home.game)
        end
    elseif action == "HOME_MENU" then
        home.screen, home.play, home.game, home.record = "menu", nil, nil, nil
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
        arcadeHeader("HOME MODE", "PAIR A PUMPE", accent)
        local top = 5
        ui.center(target, top, "OPEN CCG ON YOUR PUMPE", colors.white, colors.black)
        ui.center(target, top + 1, "HOME > TYPE THIS CODE", colors.lightGray, colors.black)
        if not ui.wordmark(target, top + 3, home.code, nil, accent) then
            ui.center(target, top + 4, home.code, accent, colors.black)
        end
        ui.center(target, math.min(height - 3, top + 10), "FREE // NO BETS // ONE PLAYER",
            colors.lightGray, colors.black)
    elseif home.screen == "menu" then
        arcadeHeader("HOME MODE", ui.truncate(tostring(home.player), width - 4)
            .. " IS PLAYING", accent)
        ui.center(target, 5, "PICK A GAME ON YOUR PUMPE", colors.white, colors.black)
        for index, game in ipairs(HOME_GAMES) do
            local y = 5 + index * 2
            if y <= height - 3 then
                ui.fill(target, 2, y, width - 2, 1, game.color)
                ui.text(target, 3, y, ui.truncate(game.label .. "  BEST "
                    .. (device.home_best[game.id] or 0), width - 4),
                    ui.inkOn(game.color), game.color)
            end
        end
    else
        local game = homeById[home.game]
        arcadeHeader(game.label, "SCORE " .. home.play.score .. "  BEST "
            .. math.max(home.play.score, device.home_best[game.id] or 0), game.color)
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
            local game = home.screen == "game" and homeById[home.game]
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

-- Main loop ---------------------------------------------------------------

bootAnimation()
-- Check for a new release at every restart, straight from the public
-- manifest. The Bank Server no longer has to hold a copy for us.
net.autoUpdate(config, "ccg", ROOT, client,
    { force = true, programVersion = PROGRAM_VERSION })
local firstStart = not device.console_id
local online = registerConsole()
if firstStart and type(ui.hasMainColor) == "function" and not ui.hasMainColor(ROOT) then
    ui.pickMainColor(target, ROOT, "CCG COLOUR")
end
-- 12.0: the Home Mode PIN, asked on the first start after updating too --
-- but never over an arena in Auto Mode, which must come back by itself.
if not device.home_pin and not (type(device.auto) == "table" and device.auto.hash) then
    setHomePin()
end
-- Bet Play needs the CCG Server; Home Mode does not, so a console that
-- cannot reach it still offers that.
while running and not online do
    local width, _, top, bottom, footerY = frame()
    ui.clear(target, colors.black)
    arcadeHeader("OFFLINE", "NO CCG SERVER", colors.red)
    ui.center(target, top + 1, "BET PLAY NEEDS THE CCG SERVER", colors.white, colors.black)
    ui.center(target, top + 3, "HOME MODE DOES NOT", colors.lightGray, colors.black)
    local scene = ui.scene(target)
    local half = math.floor((width - 3) / 2)
    scene:button("home", 2, bottom - 2, width - 2, 2, "HOME MODE",
        { background = ui.theme.accent, foreground = ui.inkOn(ui.theme.accent) })
    scene:button("retry", 2, footerY, half, 2, "TRY AGAIN", { background = colors.gray })
    scene:button("close", 3 + half, footerY, width - 3 - half, 2, "CLOSE",
        { background = colors.red })
    local action = scene:wait()
    if action == "home" then
        homeMode()
    elseif action == "retry" then
        online = registerConsole()
    elseif action == "close" or action == "__terminate" then
        running = false
    end
end
if not running then
    ui.clear(target, colors.black)
    ui.center(target, math.floor(select(2, target.getSize()) / 2),
        "CCG OFFLINE", colors.lightGray, colors.black)
    return
end

if type(device.auto) == "table" and device.auto.hash then auto = device.auto end

local resume = request("CCG_CONSOLE_STATUS", {}, true)
local resumedLobby = resume and resume.lobby or nil
while running do
    local game
    if resumedLobby then
        game = resumedLobby.game
    elseif auto then
        game = nextAutoGame()
    else
        game = gameMenu()
    end
    if game == "home" then
        homeMode()
    elseif game then
        local lobby, failure = waitForLobby(game, resumedLobby)
        resumedLobby = nil
        if not lobby and auto and failure == "offline" then autoStandby() end
        if lobby and lobby.status == "running" then
            if game == "heads_tails" then
                lobby = coinAnimation(lobby)
            elseif game == "race" then
                lobby = raceAnimation(lobby)
            else
                lobby = survivorAnimation(lobby)
            end
        end
        if lobby and lobby.status == "finished" then
            resultScreen(lobby)
        elseif lobby and lobby.status == "cancelled" and not auto then
            ui.message(target, "warning", "LOBBY CLOSED",
                lobby.cancelled_reason or "Every wager was returned", 1.2)
        end
    end
end

ui.clear(target, colors.black)
ui.center(target, math.floor(select(2, target.getSize()) / 2),
    "CCG OFFLINE", colors.lightGray, colors.black)
