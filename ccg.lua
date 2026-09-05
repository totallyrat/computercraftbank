-- ComputerCraftGaming Bet Play console.
-- Runs on an Advanced Computer with an Ender/wireless modem and any-size
-- Advanced Monitor. Game outcomes and Survivor physics are Bank-authoritative.

local ROOT = fs.getDir(shell.getRunningProgram())
if ROOT == "" then ROOT = "." end
package.path = package.path .. ";" .. fs.combine(ROOT, "?.lua")
    .. ";" .. fs.combine(ROOT, "?/init.lua")

-- Stamped by tools/build_release_manifest.js. A program running beside a
-- config.lua from a different release means a partial install.
local PROGRAM_VERSION = "8.1.0"
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
    auto = nil,
})
local running = true

-- Auto Mode keeps opening the next lobby on its own. It is unlocked with the
-- code the operator typed when starting it, and it survives a reboot so an
-- automatic update never leaves the arena dark.
local auto = nil

ui.usePhoneStyle(false)

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
        arcadeHeader("BET PLAY", device.name, colors.magenta)
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
        scene:button("auto", 2, autoY, width - 2, 2,
            "AUTO MODE // NON-STOP", {
                background = colors.lime, foreground = colors.black,
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
        arcadeHeader(lobby.game_name, "LOBBY // PUMPE BET APP", colors.cyan)
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

-- Main loop ---------------------------------------------------------------

bootAnimation()
-- Check for a new release at every restart, straight from the public
-- manifest. The Bank Server no longer has to hold a copy for us.
net.autoUpdate(config, "ccg", ROOT, client,
    { force = true, programVersion = PROGRAM_VERSION })
if not registerConsole() then
    ui.clear(target, colors.black)
    ui.center(target, math.floor(select(2, target.getSize()) / 2),
        "CCG COULD NOT START", colors.red, colors.black)
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
    if game then
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
