-- ComputerCraftGaming Bet Play console.
-- Runs on an Advanced Computer with an Ender/wireless modem and any-size
-- Advanced Monitor. Game outcomes and Survivor physics are Bank-authoritative.

local ROOT = fs.getDir(shell.getRunningProgram())
if ROOT == "" then ROOT = "." end
package.path = package.path .. ";" .. fs.combine(ROOT, "?.lua")
    .. ";" .. fs.combine(ROOT, "?/init.lua")

local config = require("config")
local util = require("lib.util")
local net = require("lib.net")
local ui = require("lib.ui")

local client = net.client(config)
local devicePath = fs.combine(ROOT, "ccg_device.dat")
local device = util.loadTable(devicePath, {
    console_id = nil,
    console_token = nil,
    name = "",
})
local running = true

ui.usePhoneStyle(false)

local gameColors = {
    red = colors.red,
    orange = colors.orange,
    yellow = colors.yellow,
    green = colors.lime,
    blue = colors.lightBlue,
    purple = colors.purple,
}

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

local function arcadeHeader(title, subtitle, accent)
    local width = target.getSize()
    ui.fill(target, 1, 1, width, 3, colors.black)
    ui.text(target, 2, 1, "CCG // " .. fitText(title, width - 9),
        colors.white, colors.black)
    ui.text(target, 2, 2, fitText(subtitle or "COMPUTERCRAFTGAMING", width - 3),
        colors.lightGray, colors.black)
    ui.fill(target, 1, 3, width, 1, accent or colors.magenta, "=")
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

local function drawLogo(frame)
    local width, height = target.getSize()
    ui.clear(target, colors.black)
    local accent = frame % 2 == 0 and colors.magenta or colors.cyan
    ui.fill(target, 2, 2, width - 2, 1, accent, "=")
    ui.center(target, math.max(5, math.floor(height / 2) - 2),
        "C C G", colors.white, colors.black)
    ui.center(target, math.max(7, math.floor(height / 2)),
        "COMPUTERCRAFTGAMING", accent, colors.black)
    ui.center(target, math.max(9, math.floor(height / 2) + 2),
        "BET PLAY", colors.lightGray, colors.black)
    ui.fill(target, 2, height - 1, width - 2, 1, accent, "=")
end

local function bootAnimation()
    for frame = 1, 8 do
        drawLogo(frame)
        sleep(0.07)
    end
end

local function gameMenu()
    while running do
        local width, height = target.getSize()
        ui.clear(target, colors.black)
        arcadeHeader("BET PLAY", device.name, colors.magenta)
        ui.center(target, 5, "SELECT A GAME", colors.white, colors.black)
        local scene = ui.scene(target)
        if width >= 45 then
            local gap, cardWidth = 2, math.floor((width - 6) / 3)
            scene:button("heads_tails", 2, 7, cardWidth, height - 9,
                "H/T\nHEADS OR TAILS\n2X", {
                    background = colors.blue,
                    foreground = colors.white,
                })
            scene:button("race", 3 + cardWidth, 7, cardWidth, height - 9,
                "RACE\n6 CARS\n3X", {
                    background = colors.orange,
                    foreground = colors.black,
                })
            scene:button("survivor", 4 + cardWidth * 2, 7,
                width - (5 + cardWidth * 2), height - 9,
                "SURVIVOR\nPUSH TO WIN\n3X", {
                    background = colors.purple,
                    foreground = colors.white,
                })
        else
            local buttonHeight = math.max(2, math.floor((height - 8) / 3))
            scene:button("heads_tails", 2, 6, width - 2, buttonHeight,
                "HEADS OR TAILS // 2X", { background = colors.blue })
            scene:button("race", 2, 7 + buttonHeight, width - 2, buttonHeight,
                "RACE // 6 CARS // 3X", {
                    background = colors.orange, foreground = colors.black,
                })
            scene:button("survivor", 2, 8 + buttonHeight * 2,
                width - 2, math.max(1, height - (9 + buttonHeight * 2)),
                "SURVIVOR // PUSH // 3X", { background = colors.purple })
        end
        scene:button("close", width - 7, 1, 6, 1, "CLOSE",
            { background = colors.red })
        local action = scene:wait({ tickRate = 1 })
        if action == "__tick" then
            net.autoUpdate(config, "ccg", ROOT)
        elseif action == "close" or action == "__terminate" then
            running = false
            return nil
        elseif action == "heads_tails" or action == "race"
            or action == "survivor" then
            return action
        end
    end
end

local function playerList(lobby, startY, maximumRows)
    local width = target.getSize()
    local players = lobby.players or {}
    for index = 1, math.min(#players, maximumRows) do
        local player = players[index]
        local marker = player.ready and "[READY]" or "[CHOOSING]"
        local line = string.format("%02d  %-14s  %s  %s",
            player.seat or index,
            fitText(player.display_name, 14),
            marker,
            player.ready and money(player.wager) or "")
        ui.text(target, 3, startY + index - 1,
            fitText(line, width - 5),
            player.ready and colors.lime or colors.lightGray,
            colors.black)
    end
    if #players > maximumRows then
        ui.text(target, 3, startY + maximumRows,
            "+" .. (#players - maximumRows) .. " MORE PLAYERS",
            colors.lightGray, colors.black)
    end
end

local function waitForLobby(game, existingLobby)
    local lobby = existingLobby
    if not lobby then
        local created = request("CCG_CREATE_LOBBY", { game = game })
        if not created then return nil end
        lobby = created.lobby
    end
    while running and lobby.status == "lobby" do
        local width, height = target.getSize()
        ui.clear(target, colors.black)
        arcadeHeader(lobby.game_name, "LOBBY // PUMPE BET APP", colors.cyan)
        ui.center(target, 5, "JOIN CODE", colors.lightGray, colors.black)
        ui.center(target, 7, lobby.code, colors.white, colors.black)
        ui.fill(target, 2, 9, width - 2, 1, colors.gray, "-")
        playerList(lobby, 10, math.max(1, height - 14))

        local scene = ui.scene(target)
        scene:button("cancel", 2, height - 2, math.max(8, math.floor(width / 3)),
            2, "CANCEL", { background = colors.red })
        scene:button("start", math.floor(width / 2), height - 2,
            width - math.floor(width / 2), 2,
            "START // " .. tostring(lobby.player_count or 0), {
                background = (lobby.player_count or 0) > 0
                    and colors.lime or colors.gray,
                foreground = colors.black,
                disabled = game == "survivor"
                    and (lobby.player_count or 0) < 2
                    or (lobby.player_count or 0) < 1,
            })
        local action = scene:wait({ tickRate = 0.5 })
        if action == "__tick" then
            local status = request("CCG_CONSOLE_STATUS", {
                code = lobby.code,
            }, true)
            if status then lobby = status.lobby end
            net.autoUpdate(config, "ccg", ROOT)
        elseif action == "start" then
            local started = request("CCG_START", { code = lobby.code })
            if started then return started.lobby end
        elseif action == "cancel" or action == "__terminate" then
            request("CCG_CANCEL_LOBBY", { code = lobby.code }, true)
            if action == "__terminate" then running = false end
            return nil
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
    for frame = 1, 34 do
        ui.clear(target, colors.black)
        arcadeHeader("HEADS OR TAILS", "LOCKED // 2X", colors.cyan)
        local face = frame % 2 == 0 and "H" or "T"
        if frame > 29 then face = string.upper(lobby.outcome:sub(1, 1)) end
        local boxWidth = math.min(15, width - 4)
        local boxX = math.floor((width - boxWidth) / 2) + 1
        local boxY = math.max(5, math.floor(height / 2) - 3)
        ui.card(target, boxX, boxY, boxWidth, 7,
            frame % 2 == 0 and colors.orange or colors.yellow)
        ui.center(target, boxY + 2, face, colors.black,
            frame % 2 == 0 and colors.orange or colors.yellow)
        ui.center(target, boxY + 5,
            frame > 29 and "RESULT LOCKED" or "FLIPPING", colors.white,
            colors.black)
        sleep(frame > 29 and 0.14 or 0.07)
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
    local laneHeight = math.max(1, math.floor((height - top - 1) / 6))
    for frame = 1, 44 do
        ui.clear(target, colors.black)
        arcadeHeader("RACE", "6 CARS // SERVER RANDOM // 3X", colors.orange)
        for lane, colorName in ipairs({
            "red", "orange", "yellow", "green", "blue", "purple",
        }) do
            local y = top + (lane - 1) * laneHeight
            local color = gameColors[colorName]
            ui.text(target, 1, y, fitText(string.upper(colorName), trackStart - 2),
                color, colors.black)
            ui.fill(target, trackStart, y, trackLength, 1, colors.gray, "-")
            local rank = orderIndex[colorName] or lane
            local progress = util.clamp(frame / 44
                + math.sin(frame * 0.63 + lane * 1.7) * 0.035
                - (rank - 1) * (frame / 44) * 0.022, 0, 1)
            if frame == 44 then progress = 1 - (rank - 1) * 0.045 end
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
    while running do
        local width, height = target.getSize()
        ui.clear(target, colors.black)
        arcadeHeader("RESULT", lobby.game_name, colors.lime)
        if lobby.game == "heads_tails" then
            ui.center(target, 6, "THE COIN LANDED", colors.lightGray, colors.black)
            ui.center(target, 8, string.upper(lobby.outcome or "?"),
                colors.yellow, colors.black)
        elseif lobby.game == "race" then
            ui.center(target, 6, "WINNING CAR", colors.lightGray, colors.black)
            local colorName = lobby.outcome or "unknown"
            ui.center(target, 8, string.upper(colorName),
                gameColors[colorName] or colors.white, colors.black)
        else
            ui.center(target, 6, "LAST PLAYER STANDING",
                colors.lightGray, colors.black)
            ui.center(target, 8, lobby.winner_name or "NO WINNER",
                colors.lime, colors.black)
        end
        ui.center(target, 11,
            fitText("WINNINGS MOVE TO 1-DAY HOLDING", width - 2),
            colors.magenta, colors.black)
        ui.center(target, 13,
            tostring(lobby.multiplier or 0) .. "X PAYOUT",
            colors.white, colors.black)
        local scene = ui.scene(target)
        scene:button("again", math.max(2, math.floor(width / 4)), height - 2,
            math.max(10, math.floor(width / 2)), 2, "NEXT GAME", {
                background = colors.lime,
                foreground = colors.black,
            })
        local action = scene:wait({ tickRate = 1 })
        if action == "again" then return end
        if action == "__terminate" then running = false return end
        if action == "__tick" then net.autoUpdate(config, "ccg", ROOT) end
    end
end

bootAnimation()
if not registerConsole() then
    ui.clear(target, colors.black)
    ui.center(target, math.floor(select(2, target.getSize()) / 2),
        "CCG COULD NOT START", colors.red, colors.black)
    return
end

local resume = request("CCG_CONSOLE_STATUS", {}, true)
local resumedLobby = resume and resume.lobby or nil
while running do
    local game = resumedLobby and resumedLobby.game or gameMenu()
    if game then
        local lobby = waitForLobby(game, resumedLobby)
        resumedLobby = nil
        if lobby and lobby.status == "running" then
            if game == "heads_tails" then
                lobby = coinAnimation(lobby)
            elseif game == "race" then
                lobby = raceAnimation(lobby)
            else
                lobby = survivorAnimation(lobby)
            end
            if lobby and lobby.status == "finished" then resultScreen(lobby) end
        elseif lobby and lobby.status == "finished" then
            resultScreen(lobby)
        end
    end
end

ui.clear(target, colors.black)
ui.center(target, math.floor(select(2, target.getSize()) / 2),
    "CCG OFFLINE", colors.lightGray, colors.black)
