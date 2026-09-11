local ROOT = fs.getDir(shell.getRunningProgram())
package.path = package.path .. ";" .. fs.combine(ROOT, "?.lua")

-- PUMPE CCG SERVER
--
-- ComputerCraftGaming: the lobbies, the games and the outcomes. It ran on
-- the Bank until 9.1, where it was a tenth of a file that had reached the
-- size a ComputerCraft computer can update itself through.
--
-- It holds no money. Every wager sits in escrow on the Bank, and this
-- server can only ever put money in or say who won -- the payout is the
-- Bank multiplying the stake it is already holding by its own copy of the
-- game's multiplier. So a CCG Server that is lying, broken or switched off
-- mid-round cannot invent money or strand anybody's: the Bank refunds
-- escrow nobody comes back for.
--
-- The Bank is still authoritative for money. This server is authoritative
-- for outcomes, which is what a modified PUMPE or console must not be.

local PROGRAM_VERSION = "9.3.1"
local config = require("config")
local util = require("lib.util")
local net = require("lib.net")
local ui = require("lib.ui")

local TEST_MODE = rawget(_G, "PUMPE_TEST_MODE") == true

local target = term.current()
local running = true
local dataFile = fs.combine(ROOT, "ccg_server_v1.dat")
local activity = {}
local BOOT_ID = util.token("CCG_BOOT")
local bank = net.client(config)

local function logActivity(text, color)
    table.insert(activity, 1, {
        time = util.formatClock(), text = tostring(text),
        color = color or colors.white,
    })
    while #activity > 40 do table.remove(activity) end
end

local state = util.loadTable(dataFile, {
    server_token = nil,
    consoles = {}, lobbies = {}, codes = {},
    sequence = { console = 0, lobby = 0 },
    house_note = 0,
})
state.consoles = state.consoles or {}
state.lobbies = state.lobbies or {}
state.codes = state.codes or {}
state.sequence = state.sequence or { console = 0, lobby = 0 }

local function save() pcall(util.saveTable, dataFile, state) end

local function reject(code, message)
    error({ pumpe = true, code = code, message = message }, 0)
end
local function need(condition, code, message)
    if not condition then reject(code, message) end
    return condition
end

local CCG_GAMES = {
    heads_tails = {
        name = "Heads or Tails",
        multiplier = 2,
        maximum_players = 24,
    },
    race = {
        name = "Race",
        multiplier = 3,
        maximum_players = 24,
    },
    survivor = {
        name = "Survivor",
        multiplier = 3,
        maximum_players = 8,
    },
}

local RACE_COLORS = {
    "red", "orange", "yellow", "green", "blue", "purple",
}

-- Talking to the Bank ----------------------------------------------------------
-- Everything to do with money is a question asked of the Bank, never a
-- decision made here.

local function askBank(action, payload, timeout)
    payload = payload or {}
    payload.server_token = state.server_token
    local result, err, code = bank:request(action, payload, timeout or 6)
    return result, err, code
end

-- A refusal from the Bank is the player's answer, not an internal fault, so
-- it is passed straight back with its own code.
local function bankOrFail(action, payload)
    local result, err, code = askBank(action, payload)
    if not result then
        reject(code or "BANK_OFFLINE", err or "The Bank is not answering")
    end
    return result
end

local function nextId(kind, prefix, width)
    state.sequence[kind] = (state.sequence[kind] or 0) + 1
    return prefix .. string.format("%0" .. width .. "d", state.sequence[kind])
end

-- Lobbies -----------------------------------------------------------------------

local function uniqueCode()
    local code
    repeat code = util.randomString(6, "ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    until not state.codes[code]
    return code
end

local function lobbyByCode(code)
    code = string.upper(util.trim(tostring(code or "")))
    local lobbyId = state.codes[code]
    return lobbyId and state.lobbies[lobbyId] or nil
end

local function requireConsole(payload)
    local console = state.consoles[payload and payload.console_id]
    need(console and console.auth_token == payload.console_token,
        "CCG_AUTH", "CCG console is not registered")
    need(console.status == "active", "CCG_INACTIVE", "CCG console is inactive")
    console.last_seen = util.nowMs()
    return console
end

-- The player, as the Bank knows them. The bet session is the player's own
-- PIN-unlocked token, so this cannot look up somebody who has not sat down.
local function requirePlayer(payload)
    local who = bankOrFail("CCG_WHO", {
        session_token = payload.session_token,
        bet_token = payload.bet_token,
    })
    return who
end

local function publicPlayer(player)
    return {
        player_id = player.account_id,
        seat = player.seat,
        display_name = player.display_name,
        wager = player.wager or 0,
        selection = player.selection,
        ready = (player.wager or 0) > 0,
        alive = player.alive,
        x = player.x,
        y = player.y,
        color = player.color,
        won = player.won,
        payout = player.payout,
        hold_id = player.hold_id,
    }
end

local function publicLobby(lobby, revealOutcome)
    local players = {}
    for _, accountId in ipairs(lobby.player_order or {}) do
        local player = lobby.players[accountId]
        if player then players[#players + 1] = publicPlayer(player) end
    end
    local output = {
        lobby_id = lobby.lobby_id,
        code = lobby.code,
        game = lobby.game,
        game_name = CCG_GAMES[lobby.game] and CCG_GAMES[lobby.game].name
            or lobby.game,
        multiplier = CCG_GAMES[lobby.game]
            and CCG_GAMES[lobby.game].multiplier or 0,
        status = lobby.status,
        player_count = #players,
        players = players,
        created_day = lobby.created_day,
        expires_in_ms = math.max(0,
            (lobby.expires_at or util.nowMs()) - util.nowMs()),
        started_at = lobby.started_at,
        finished_at = lobby.finished_at,
        winner_player_id = lobby.winner_account_id,
        winner_name = lobby.winner_name,
        cancelled_reason = lobby.cancelled_reason,
    }
    if lobby.status == "finished" or revealOutcome then
        output.outcome = lobby.outcome
        output.race_order = util.copy(lobby.race_order)
    end
    if lobby.game == "survivor" and lobby.status == "running" then
        output.platform_radius = lobby.platform_radius
        output.elapsed_ms = math.max(0,
            util.nowMs() - (lobby.started_at or util.nowMs()))
        output.maximum_ms = (tonumber(config.ccg_survivor_max_seconds) or 75)
            * 1000
    end
    return output
end

-- Settling ------------------------------------------------------------------------
-- Both of these are the Bank's decision to carry out. This server says which
-- lobby and, at most, who won.

local function refundLobby(lobby, reason)
    if lobby.escrow_closed then return false end
    askBank("CCG_ESCROW_REFUND", { lobby_code = lobby.code, reason = reason })
    for _, player in pairs(lobby.players or {}) do
        player.settled = true
        player.refunded = true
    end
    lobby.escrow_closed = true
    lobby.status = "cancelled"
    lobby.cancelled_reason = reason or "Lobby cancelled"
    lobby.finished_at = util.nowMs()
    return true
end

local function finishLobbySettlement(lobby, winnerIds)
    if lobby.escrow_closed then return false end
    winnerIds = winnerIds or {}
    local winners = {}
    for accountId in pairs(winnerIds) do winners[#winners + 1] = accountId end
    local result = askBank("CCG_ESCROW_SETTLE", {
        lobby_code = lobby.code, winners = winners,
    }, 8)
    if not result then
        -- The Bank did not answer. Leave the lobby open rather than marking
        -- it settled: the escrow is still there, and this is retried on the
        -- next tick. Saying "settled" here would lose the money.
        logActivity("Bank did not settle " .. lobby.code .. ", will retry",
            colors.orange)
        return false
    end
    for _, entry in ipairs(result.settled or {}) do
        local player = lobby.players[entry.account_id]
        if player then
            player.won = entry.won
            player.payout = entry.payout
            player.settled = true
        end
    end
    lobby.escrow_closed = true
    lobby.status = "finished"
    lobby.finished_at = util.nowMs()
    logActivity("Settled " .. lobby.code .. " / "
        .. CCG_GAMES[lobby.game].name, colors.magenta)
    return true
end

local function settleChanceLobby(lobby)
    local winners = {}
    for accountId, player in pairs(lobby.players) do
        if player.selection == lobby.outcome then winners[accountId] = true end
    end
    return finishLobbySettlement(lobby, winners)
end

local function settleSurvivorLobby(lobby, winnerId)
    local winners = {}
    if winnerId then winners[winnerId] = true end
    lobby.winner_account_id = winnerId
    local player = winnerId and lobby.players[winnerId]
    lobby.winner_name = player and player.display_name or "No winner"
    lobby.outcome = lobby.winner_name
    return finishLobbySettlement(lobby, winners)
end

-- Survivor ------------------------------------------------------------------------

local function aliveSurvivors(lobby)
    local alive = {}
    for _, accountId in ipairs(lobby.player_order) do
        local player = lobby.players[accountId]
        if player and player.alive then alive[#alive + 1] = player end
    end
    return alive
end

local function advanceSurvivor(lobby, now)
    if lobby.status ~= "running" or lobby.game ~= "survivor" then return false end
    now = now or util.nowMs()
    local last = lobby.last_sim_at or now
    local remaining = math.max(0, math.min(1, (now - last) / 1000))
    lobby.last_sim_at = now
    local maxSeconds = tonumber(config.ccg_survivor_max_seconds) or 75
    local elapsed = math.max(0, (now - lobby.started_at) / 1000)
    local shrink = util.clamp((elapsed - 18) / math.max(1, maxSeconds - 18), 0, 1)
    lobby.platform_radius = 850 - shrink * 540

    while remaining > 0 do
        local step = math.min(0.1, remaining)
        remaining = remaining - step
        for _, player in ipairs(aliveSurvivors(lobby)) do
            local inputActive = (player.input_until or 0) >= now
            local inputX = inputActive and (player.input_x or 0) or 0
            local inputY = inputActive and (player.input_y or 0) or 0
            player.x = player.x + inputX * 315 * step
                + (player.vx or 0) * step
            player.y = player.y + inputY * 315 * step
                + (player.vy or 0) * step
            local damping = 0.72 ^ (step * 10)
            player.vx = (player.vx or 0) * damping
            player.vy = (player.vy or 0) * damping
        end

        local alive = aliveSurvivors(lobby)
        for _, player in ipairs(alive) do
            if player.push_requested then
                player.push_requested = false
                local nearest, nearestDistance
                for _, targetPlayer in ipairs(alive) do
                    if targetPlayer.account_id ~= player.account_id then
                        local dx = targetPlayer.x - player.x
                        local dy = targetPlayer.y - player.y
                        local distance = math.sqrt(dx * dx + dy * dy)
                        if not nearestDistance or distance < nearestDistance then
                            nearest = targetPlayer
                            nearestDistance = distance
                        end
                    end
                end
                if nearest and nearestDistance <= 260 then
                    local divisor = math.max(1, nearestDistance)
                    nearest.vx = (nearest.vx or 0)
                        + (nearest.x - player.x) / divisor * 610
                    nearest.vy = (nearest.vy or 0)
                        + (nearest.y - player.y) / divisor * 610
                    player.last_push_hit = nearest.account_id
                end
            end
        end

        alive = aliveSurvivors(lobby)
        for first = 1, #alive do
            for second = first + 1, #alive do
                local a, b = alive[first], alive[second]
                local dx, dy = b.x - a.x, b.y - a.y
                local distance = math.sqrt(dx * dx + dy * dy)
                if distance < 85 then
                    local divisor = math.max(1, distance)
                    local separation = (85 - distance) * 0.52
                    local nx, ny = dx / divisor, dy / divisor
                    a.x, a.y = a.x - nx * separation, a.y - ny * separation
                    b.x, b.y = b.x + nx * separation, b.y + ny * separation
                end
            end
        end

        for _, player in ipairs(aliveSurvivors(lobby)) do
            local distance = math.sqrt(player.x * player.x + player.y * player.y)
            if distance > lobby.platform_radius + 24 then
                player.alive = false
                player.eliminated_at = now
                lobby.last_eliminated = player.account_id
            end
        end
    end

    local alive = aliveSurvivors(lobby)
    if #alive <= 1 then
        local winnerId = alive[1] and alive[1].account_id
            or lobby.last_eliminated
        return settleSurvivorLobby(lobby, winnerId)
    end
    if elapsed >= maxSeconds then
        local winner, nearest
        for _, player in ipairs(alive) do
            local distance = player.x * player.x + player.y * player.y
            if not nearest or distance < nearest then
                winner, nearest = player, distance
            end
        end
        for _, player in ipairs(alive) do
            if player ~= winner then player.alive = false end
        end
        return settleSurvivorLobby(lobby, winner and winner.account_id)
    end
    return false
end

local function processGames()
    local now, changed = util.nowMs(), false
    for lobbyId, lobby in pairs(state.lobbies) do
        if lobby.status == "lobby" and lobby.expires_at <= now then
            changed = refundLobby(lobby, "Lobby expired") or changed
        elseif lobby.status == "running" then
            if lobby.game == "survivor" then
                if lobby.boot_id ~= BOOT_ID then
                    changed = refundLobby(lobby,
                        "CCG Server restarted during Survivor") or changed
                else
                    changed = advanceSurvivor(lobby, now) or changed
                end
            elseif lobby.reveal_at and now >= lobby.reveal_at then
                changed = settleChanceLobby(lobby) or changed
            end
        elseif (lobby.status == "finished" or lobby.status == "cancelled")
            and lobby.finished_at and lobby.finished_at + 30 * 60 * 1000 < now then
            if state.codes[lobby.code] == lobbyId then
                state.codes[lobby.code] = nil
            end
            state.lobbies[lobbyId] = nil
            changed = true
        end
    end
    if changed then save() end
    return changed
end

-- Routes -----------------------------------------------------------------------

local actions = {}

function actions.CCG_REGISTER(payload)
    if payload.console_id and payload.console_token then
        local existing = state.consoles[payload.console_id]
        if existing and existing.auth_token == payload.console_token then
            existing.last_seen = util.nowMs()
            return {
                console_id = existing.console_id,
                console_token = existing.auth_token,
                name = existing.name,
            }
        end
    end
    local consoleId = nextId("console", "CCGC", 5)
    local console = {
        console_id = consoleId,
        auth_token = util.token("CCG_CONSOLE"),
        name = util.safeText(payload.name or ("CCG " .. consoleId), 24),
        status = "active",
        created_day = util.ingameDay(),
        last_seen = util.nowMs(),
    }
    state.consoles[consoleId] = console
    save()
    logActivity("Registered " .. console.name, colors.magenta)
    return {
        console_id = console.console_id,
        console_token = console.auth_token,
        name = console.name,
    }
end

function actions.CCG_CREATE_LOBBY(payload)
    local console = requireConsole(payload)
    processGames()
    local game = string.lower(util.trim(payload.game))
    need(CCG_GAMES[game], "INVALID_GAME", "Choose a supported CCG game")
    for _, lobby in pairs(state.lobbies) do
        need(lobby.console_id ~= console.console_id
            or (lobby.status ~= "lobby" and lobby.status ~= "running"),
            "LOBBY_ACTIVE", "Finish or cancel the current lobby first")
    end
    local lobbyId = nextId("lobby", "CCGL", 6)
    local code = uniqueCode()
    local lobby = {
        lobby_id = lobbyId,
        code = code,
        console_id = console.console_id,
        game = game,
        status = "lobby",
        players = {},
        player_order = {},
        created_day = util.ingameDay(),
        created_at = util.nowMs(),
        expires_at = util.nowMs()
            + (tonumber(config.ccg_lobby_ttl_ms) or 5 * 60 * 1000),
    }
    state.lobbies[lobbyId] = lobby
    state.codes[code] = lobbyId
    console.active_lobby_id = lobbyId
    save()
    return { lobby = publicLobby(lobby, false) }
end

function actions.CCG_CONSOLE_STATUS(payload)
    local console = requireConsole(payload)
    processGames()
    local lobby = payload.code and lobbyByCode(payload.code)
        or (console.active_lobby_id and state.lobbies[console.active_lobby_id])
    need(lobby and lobby.console_id == console.console_id,
        "LOBBY_NOT_FOUND", "CCG lobby not found")
    return { lobby = publicLobby(lobby, true) }
end

function actions.CCG_CANCEL_LOBBY(payload)
    local console = requireConsole(payload)
    local lobby = lobbyByCode(payload.code)
    need(lobby and lobby.console_id == console.console_id,
        "LOBBY_NOT_FOUND", "CCG lobby not found")
    need(lobby.status == "lobby", "GAME_STARTED",
        "A running game cannot be cancelled")
    refundLobby(lobby, "Cancelled by console")
    save()
    return { lobby = publicLobby(lobby, false) }
end

function actions.BET_JOIN(payload)
    local who = requirePlayer(payload)
    processGames()
    local lobby = lobbyByCode(payload.code)
    need(lobby and lobby.status == "lobby"
        and lobby.expires_at > util.nowMs(),
        "LOBBY_NOT_FOUND", "Lobby code is invalid or closed")
    local displayName = util.safeText(util.trim(payload.display_name), 14)
    need(#displayName >= 2 and displayName:match("^[%w_ %-]+$"),
        "INVALID_NAME", "Use 2-14 letters, numbers, spaces, _ or -")
    for otherId, other in pairs(lobby.players) do
        need(otherId == who.account_id
            or util.normalName(other.display_name)
                ~= util.normalName(displayName),
            "NAME_TAKEN", "That player name is already in this lobby")
    end
    local player = lobby.players[who.account_id]
    if not player then
        need(#lobby.player_order < CCG_GAMES[lobby.game].maximum_players,
            "LOBBY_FULL", "This lobby is full")
        player = {
            account_id = who.account_id,
            seat = #lobby.player_order + 1,
            display_name = displayName,
            wager = 0,
            joined_at = util.nowMs(),
        }
        lobby.players[who.account_id] = player
        lobby.player_order[#lobby.player_order + 1] = who.account_id
    elseif (player.wager or 0) == 0 then
        player.display_name = displayName
    end
    save()
    return {
        lobby = publicLobby(lobby, false),
        player = publicPlayer(player),
    }
end

local function validRaceSelection(selection)
    for _, value in ipairs(RACE_COLORS) do
        if selection == value then return true end
    end
    return false
end

function actions.BET_PLACE_WAGER(payload)
    local lobby = lobbyByCode(payload.code)
    need(lobby and lobby.status == "lobby",
        "LOBBY_CLOSED", "Betting is closed for this lobby")
    local selection = string.lower(util.trim(payload.selection))
    if lobby.game == "heads_tails" then
        need(selection == "heads" or selection == "tails",
            "INVALID_SELECTION", "Choose Heads or Tails")
    elseif lobby.game == "race" then
        need(validRaceSelection(selection), "INVALID_SELECTION",
            "Choose one of the six race cars")
    else
        selection = "survivor"
    end
    -- The Bank takes the money and tells us who it took it from, so the
    -- amount is checked against the wallet by the only thing that can.
    local staked = bankOrFail("CCG_ESCROW_SET", {
        session_token = payload.session_token,
        bet_token = payload.bet_token,
        lobby_code = lobby.code,
        game = lobby.game,
        amount = payload.amount,
    })
    local player = lobby.players[staked.account_id]
    need(player, "NOT_JOINED", "Join the lobby before placing a wager")
    player.wager = staked.staked
    player.selection = selection
    player.ready_at = util.nowMs()
    save()
    return {
        lobby = publicLobby(lobby, false),
        player = publicPlayer(player),
        wallet = staked.wallet,
    }
end

function actions.BET_LEAVE(payload)
    local who = requirePlayer(payload)
    local lobby = lobbyByCode(payload.code)
    need(lobby and lobby.status == "lobby",
        "GAME_STARTED", "You cannot leave after the game starts")
    local player = lobby.players[who.account_id]
    need(player, "NOT_JOINED", "You are not in this lobby")
    local released = askBank("CCG_ESCROW_RELEASE", {
        lobby_code = lobby.code, account_id = who.account_id,
    })
    lobby.players[who.account_id] = nil
    for index, accountId in ipairs(lobby.player_order) do
        if accountId == who.account_id then
            table.remove(lobby.player_order, index)
            break
        end
    end
    for index, accountId in ipairs(lobby.player_order) do
        lobby.players[accountId].seat = index
    end
    save()
    return {
        wallet = released and released.wallet or who.wallet,
        left = true,
    }
end

function actions.BET_LOBBY_STATUS(payload)
    local who = requirePlayer(payload)
    processGames()
    local lobby = lobbyByCode(payload.code)
    need(lobby, "LOBBY_NOT_FOUND", "CCG lobby not found")
    local player = lobby.players[who.account_id]
    need(player, "NOT_JOINED", "You are not in this lobby")
    return {
        lobby = publicLobby(lobby, false),
        player = publicPlayer(player),
        wallet = who.wallet,
    }
end

function actions.BET_CONTROL(payload)
    local who = requirePlayer(payload)
    local lobby = lobbyByCode(payload.code)
    need(lobby and lobby.status == "running" and lobby.game == "survivor",
        "NOT_INTERACTIVE", "Survivor is not running")
    local player = lobby.players[who.account_id]
    need(player and player.alive, "ELIMINATED", "You are out of this round")
    local dx = util.clamp(tonumber(payload.dx) or 0, -1, 1)
    local dy = util.clamp(tonumber(payload.dy) or 0, -1, 1)
    local length = math.sqrt(dx * dx + dy * dy)
    if length > 1 then dx, dy = dx / length, dy / length end
    player.input_x, player.input_y = dx, dy
    player.input_until = util.nowMs() + 650
    local pushed = false
    if payload.push == true
        and util.nowMs() >= (player.push_cooldown_until or 0) then
        player.push_requested = true
        player.push_cooldown_until = util.nowMs() + 1200
        pushed = true
    end
    return {
        accepted = true,
        pushed = pushed,
        push_cooldown_ms = math.max(0,
            (player.push_cooldown_until or 0) - util.nowMs()),
    }
end

local function shuffledRaceOrder()
    local output = util.copy(RACE_COLORS)
    for index = #output, 2, -1 do
        local other = math.random(1, index)
        output[index], output[other] = output[other], output[index]
    end
    return output
end

function actions.CCG_START(payload)
    local console = requireConsole(payload)
    local lobby = lobbyByCode(payload.code)
    need(lobby and lobby.console_id == console.console_id,
        "LOBBY_NOT_FOUND", "CCG lobby not found")
    need(lobby.status == "lobby", "GAME_STARTED", "Game has already started")
    local minimumPlayers = lobby.game == "survivor" and 2 or 1
    need(#lobby.player_order >= minimumPlayers, "NOT_ENOUGH_PLAYERS",
        lobby.game == "survivor" and "Survivor needs at least two players"
            or "At least one player must join")
    for _, accountId in ipairs(lobby.player_order) do
        need((lobby.players[accountId].wager or 0) > 0,
            "PLAYER_NOT_READY", "Every player must place a wager")
    end
    -- Seed the RNG even when nothing has generated a token since this server
    -- started.
    util.randomString(1)
    lobby.status = "running"
    lobby.started_at = util.nowMs()
    lobby.boot_id = BOOT_ID
    lobby.expires_at = lobby.started_at + 30 * 60 * 1000
    if lobby.game == "heads_tails" then
        lobby.outcome = math.random(1, 2) == 1 and "heads" or "tails"
        lobby.reveal_at = lobby.started_at
            + (tonumber(config.ccg_result_delay_ms) or 6000)
    elseif lobby.game == "race" then
        lobby.race_order = shuffledRaceOrder()
        lobby.outcome = lobby.race_order[1]
        lobby.reveal_at = lobby.started_at
            + (tonumber(config.ccg_result_delay_ms) or 6000)
    else
        local count = #lobby.player_order
        for index, accountId in ipairs(lobby.player_order) do
            local player = lobby.players[accountId]
            local angle = (index - 1) / count * math.pi * 2
            player.x = math.cos(angle) * 360
            player.y = math.sin(angle) * 360
            player.vx, player.vy = 0, 0
            player.input_x, player.input_y = 0, 0
            player.alive = true
            player.color = RACE_COLORS[(index - 1) % #RACE_COLORS + 1]
        end
        lobby.platform_radius = 850
        lobby.last_sim_at = lobby.started_at
    end
    save()
    logActivity("Started " .. lobby.code .. " / "
        .. CCG_GAMES[lobby.game].name, colors.cyan)
    return { lobby = publicLobby(lobby, true) }
end

function actions.CCG_TICK(payload)
    local console = requireConsole(payload)
    local lobby = lobbyByCode(payload.code)
    need(lobby and lobby.console_id == console.console_id,
        "LOBBY_NOT_FOUND", "CCG lobby not found")
    local settled = false
    if lobby.game == "survivor" then
        settled = advanceSurvivor(lobby, util.nowMs())
    elseif lobby.status == "running" and lobby.reveal_at
        and util.nowMs() >= lobby.reveal_at then
        settled = settleChanceLobby(lobby)
    end
    if settled then save() end
    return { lobby = publicLobby(lobby, true) }
end

function actions.CCG_PING()
    return { version = config.version, games = CCG_GAMES,
        registered = state.server_token ~= nil }
end

-- Serving ---------------------------------------------------------------------

local function route(sender, message)
    if type(message) ~= "table" or message.kind ~= "request"
        or type(message.action) ~= "string" then return end
    local protocol = config.ccg_protocol or "PUMPE_CCG_V1"
    local handler = actions[message.action]
    if not handler then
        net.reply(sender, protocol, message.request_id, false, nil,
            "Unknown CCG action", "UNKNOWN_ACTION")
        return
    end
    local ok, result = pcall(handler, message.payload or {}, sender)
    if ok then
        net.reply(sender, protocol, message.request_id, true, result)
    elseif type(result) == "table" and result.pumpe then
        net.reply(sender, protocol, message.request_id, false, nil,
            result.message, result.code)
    else
        logActivity("Error: " .. tostring(result), colors.red)
        net.reply(sender, protocol, message.request_id, false, nil,
            "CCG server failed", "SERVER_ERROR")
    end
end

local function serverLoop()
    local protocol = config.ccg_protocol or "PUMPE_CCG_V1"
    while running do
        local sender, message = rednet.receive(protocol, 1)
        if sender then route(sender, message) end
    end
end

local function gameLoop()
    while running do
        pcall(processGames)
        sleep(0.15)
    end
end

local function updateLoop()
    while running do
        net.autoUpdate(config, "ccgserver", ROOT, nil,
            { programVersion = PROGRAM_VERSION })
        sleep(10)
    end
end

local function dashboardLoop()
    local blink = true
    while running do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "PUMPE CCG SERVER", "v" .. PROGRAM_VERSION,
            util.formatClock(blink))
        local open, running_count, players = 0, 0, 0
        for _, lobby in pairs(state.lobbies) do
            if lobby.status == "lobby" then open = open + 1 end
            if lobby.status == "running" then
                running_count = running_count + 1
            end
            if lobby.status == "lobby" or lobby.status == "running" then
                players = players + #(lobby.player_order or {})
            end
        end
        local cardWidth = math.floor((width - 4) / 3)
        local cards = {
            { "LOBBIES", open, colors.cyan },
            { "RUNNING", running_count, colors.lime },
            { "PLAYERS", players, colors.magenta },
        }
        for index, card in ipairs(cards) do
            local x = 2 + (index - 1) * (cardWidth + 1)
            local panelWidth = index == #cards and width - 1 - x or cardWidth
            ui.card(target, x, 5, panelWidth, 4, card[3])
            ui.text(target, x + 2, 6, card[1], colors.lightGray, colors.gray)
            ui.text(target, x + 2, 7, tostring(card[2]), colors.white,
                colors.gray, panelWidth - 3)
        end
        ui.text(target, 2, 10, ui.truncate("BANK  " .. (bank:isOnline()
            and "CONNECTED" or "SEARCHING"), width - 2),
            bank:isOnline() and colors.lime or colors.orange)
        ui.text(target, 2, 12, "ACTIVITY", colors.lightGray)
        local maxFeed = math.max(1, height - 14)
        for index = 1, math.min(#activity, maxFeed) do
            local item = activity[index]
            ui.text(target, 2, 12 + index,
                item.time .. "  " .. ui.truncate(item.text, width - 10),
                item.color)
        end
        local scene = ui.scene(target)
        scene:button("stop", width - 10, height, 9, 1, "STOP",
            { background = colors.red })
        local action = scene:wait({ tickRate = 0.5, flash = false })
        blink = not blink
        if action == "stop" or action == "__terminate" then
            if action == "__terminate"
                or ui.confirm(target, "STOP CCG SERVER",
                    "Open lobbies will be refunded.", "STOP", "BACK") then
                for _, lobby in pairs(state.lobbies) do
                    if lobby.status == "lobby" or lobby.status == "running" then
                        pcall(refundLobby, lobby, "CCG Server stopped")
                    end
                end
                running = false
                save()
                return
            end
        end
    end
end

if TEST_MODE then
    return {
        actions = actions, state = state, games = CCG_GAMES,
        process_games = processGames, advance_survivor = advanceSurvivor,
        refund_lobby = refundLobby, boot_id = BOOT_ID,
    }
end

ui.usePhoneStyle(false)
ui.boot(target, "PUMPE CCG", "COMPUTERCRAFTGAMING")
net.openModems()

-- Registering with the Bank once. A CCG Server pays out of the Bank's
-- escrow, so the Bank has to know it -- and the operator code is what
-- proves this is the operator's own machine rather than anybody's.
while running and not state.server_token do
    if not bank:discover() then
        ui.message(target, "error", "BANK OFFLINE",
            "Start the Bank Server and check the modem", 2)
    else
        local code = ui.input(target, "OPERATOR CODE", {
            hint = "The same code that installs a Bank Server",
            mode = "number", maxLength = 8,
        })
        if not code then
            ui.clear(target)
            print("CCG Server not registered.")
            return
        end
        local registered, err = bank:request("CCG_SERVER_REGISTER",
            { code = code, name = "CCG " .. os.getComputerID() }, 6)
        if registered then
            state.server_token = registered.server_token
            save()
            logActivity("Registered with the Bank", colors.lime)
        else
            ui.message(target, "error", "NOT REGISTERED", err, 2)
        end
    end
end

net.host(config.ccg_protocol or "PUMPE_CCG_V1",
    config.ccg_hostname or "CCG_SERVER")
logActivity("CCG Server online on computer #" .. os.getComputerID(),
    colors.lime)

parallel.waitForAny(serverLoop, gameLoop, updateLoop, dashboardLoop)
pcall(rednet.unhost, config.ccg_protocol or "PUMPE_CCG_V1")
save()
ui.clear(target)
print("PUMPE CCG Server stopped safely.")
