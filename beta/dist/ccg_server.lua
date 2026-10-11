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

local PROGRAM_VERSION = "16.5.1"
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

-- FoxyOS 16: a lobby is not one round any more. It keeps its code and its
-- players from game to game, so a player who has not wagered yet is only
-- dropped once their Pocket has gone quiet for this long.
local PRESENCE_MS = 120000
local function lobbyTtl()
    return tonumber(config.ccg_lobby_ttl_ms) or 5 * 60 * 1000
end

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
    until not state.codes[code] and not (state.casino_codes or {})[code]
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
        -- In this round, rather than sitting it out until the next.
        playing = (player.wager or 0) > 0,
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
        -- FoxyOS 16: the round this is, and whether the lobby is over for
        -- good (the console closed it, or nobody started it in time).
        round = lobby.round or 1,
        closed = lobby.closed == true,
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

local function refundLobby(lobby, reason, close)
    if close then lobby.closed = true end
    if lobby.escrow_closed then return false end
    -- The code is used again for the next round, so a refund the Bank never
    -- heard has to be sent again before anybody stakes under it.
    if not askBank("CCG_ESCROW_REFUND", { lobby_code = lobby.code, reason = reason }) then
        lobby.refund_pending = reason or "Lobby cancelled"
    end
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

local function retryRefund(lobby)
    if not lobby.refund_pending then return true end
    lobby.refund_tried_at = util.nowMs()
    if not askBank("CCG_ESCROW_REFUND", { lobby_code = lobby.code,
        reason = lobby.refund_pending }) then
        return false
    end
    lobby.refund_pending = nil
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
        if lobby.refund_pending and now - (lobby.refund_tried_at or 0) > 10000 then
            changed = retryRefund(lobby) or changed
        end
        if lobby.status == "lobby" and lobby.expires_at <= now then
            changed = refundLobby(lobby, "Lobby expired", true) or changed
        elseif lobby.status == "lobby" then
            -- Somebody who never wagered and whose Pocket went quiet left
            -- without saying so. A wager keeps its player: that money is
            -- in this round.
            for index = #lobby.player_order, 1, -1 do
                local accountId = lobby.player_order[index]
                local player = lobby.players[accountId]
                if player and (player.wager or 0) <= 0
                    and now - (player.seen_at or player.joined_at or now) > PRESENCE_MS then
                    lobby.players[accountId] = nil
                    table.remove(lobby.player_order, index)
                    changed = true
                end
            end
            for seat, accountId in ipairs(lobby.player_order) do
                lobby.players[accountId].seat = seat
            end
        elseif lobby.status == "running" then
            if lobby.game == "survivor" then
                if lobby.boot_id ~= BOOT_ID then
                    changed = refundLobby(lobby,
                        "CCG Server restarted during Survivor", false) or changed
                else
                    changed = advanceSurvivor(lobby, now) or changed
                end
            elseif lobby.reveal_at and now >= lobby.reveal_at then
                changed = settleChanceLobby(lobby) or changed
            end
        elseif (lobby.status == "finished" or lobby.status == "cancelled")
            and not lobby.refund_pending
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
    -- FoxyOS 16: a console keeps its code from lobby to lobby, as long as
    -- its last lobby is over and nothing of it is left with the Bank.
    local code = console.code
    local previous = code and state.codes[code] and state.lobbies[state.codes[code]]
    if not code or (state.codes[code] and not (previous
        and previous.console_id == console.console_id and previous.escrow_closed
        and retryRefund(previous))) then
        code = uniqueCode()
    end
    console.code = code
    local lobby = {
        lobby_id = lobbyId,
        code = code,
        console_id = console.console_id,
        game = game,
        status = "lobby",
        round = 1,
        players = {},
        player_order = {},
        created_day = util.ingameDay(),
        created_at = util.nowMs(),
        expires_at = util.nowMs() + lobbyTtl(),
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
    need(lobby.status ~= "running", "GAME_STARTED",
        "A running game cannot be cancelled")
    if lobby.status == "lobby" then
        refundLobby(lobby, "Cancelled by console", true)
    else
        lobby.closed = true
    end
    save()
    return { lobby = publicLobby(lobby, false) }
end

-- FoxyOS 16: the next round, in the same lobby. Same code, same players --
-- every wager cleared -- and the game can change. The round before is kept
-- so a Pocket that looked away still finds out how it went.
function actions.CCG_NEXT_ROUND(payload)
    local console = requireConsole(payload)
    local lobby = lobbyByCode(payload.code)
    need(lobby and lobby.console_id == console.console_id,
        "LOBBY_NOT_FOUND", "CCG lobby not found")
    need(not lobby.closed, "LOBBY_CLOSED", "That lobby is closed")
    need(lobby.status == "finished" or lobby.status == "cancelled",
        "GAME_STARTED", "Finish this round first")
    local game = string.lower(util.trim(payload.game or lobby.game))
    need(CCG_GAMES[game], "INVALID_GAME", "Choose a supported CCG game")
    need(#lobby.player_order <= CCG_GAMES[game].maximum_players, "LOBBY_FULL",
        CCG_GAMES[game].name .. " takes " .. CCG_GAMES[game].maximum_players
            .. " players")
    need(lobby.escrow_closed and retryRefund(lobby), "BANK_OFFLINE",
        "The Bank has not returned the last round's wagers yet")
    local results = {}
    for accountId, player in pairs(lobby.players) do
        if (player.wager or 0) > 0 then
            -- They were in the game a moment ago: present, for now.
            player.seen_at = util.nowMs()
            results[accountId] = { won = player.won == true, payout = player.payout,
                hold_id = player.hold_id, wager = player.wager,
                selection = player.selection }
        end
    end
    lobby.last_round = { round = lobby.round or 1, game = lobby.game,
        status = lobby.status, outcome = lobby.outcome,
        winner_name = lobby.winner_name, cancelled_reason = lobby.cancelled_reason,
        results = results }
    for _, player in pairs(lobby.players) do
        for _, key in ipairs({ "wager", "selection", "ready_at", "alive", "x", "y",
            "vx", "vy", "input_x", "input_y", "input_until", "push_requested",
            "push_cooldown_until", "last_push_hit", "eliminated_at", "color",
            "won", "payout", "hold_id", "settled", "refunded" }) do
            player[key] = nil
        end
        player.wager = 0
    end
    for _, key in ipairs({ "outcome", "race_order", "reveal_at", "started_at",
        "finished_at", "winner_account_id", "winner_name", "cancelled_reason",
        "escrow_closed", "platform_radius", "last_sim_at", "last_eliminated",
        "boot_id" }) do
        lobby[key] = nil
    end
    lobby.game = game
    lobby.round = (lobby.round or 1) + 1
    lobby.status = "lobby"
    lobby.expires_at = util.nowMs() + lobbyTtl()
    console.active_lobby_id = lobby.lobby_id
    save()
    logActivity("Round " .. lobby.round .. " in " .. lobby.code .. " / "
        .. CCG_GAMES[game].name, colors.cyan)
    return { lobby = publicLobby(lobby, false) }
end

function actions.BET_JOIN(payload)
    local who = requirePlayer(payload)
    processGames()
    local lobby = lobbyByCode(payload.code)
    -- FoxyOS 16: a lobby mid-round can be joined too, for the next one.
    need(lobby and not lobby.closed and (lobby.status ~= "lobby"
        or lobby.expires_at > util.nowMs()),
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
    player.seen_at = util.nowMs()
    if lobby.status == "lobby" then lobby.expires_at = util.nowMs() + lobbyTtl() end
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
    need(lobby and lobby.status == "lobby" and not lobby.closed,
        "LOBBY_CLOSED", "Betting is closed for this lobby")
    -- Before the Bank takes anything: money staked by somebody who is not
    -- in the lobby would sit in its escrow with nobody to settle it.
    local who = requirePlayer(payload)
    need(lobby.players[who.account_id], "NOT_JOINED",
        "Join the lobby before placing a wager")
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
    player.seen_at = util.nowMs()
    lobby.expires_at = util.nowMs() + lobbyTtl()
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
    need(lobby, "LOBBY_NOT_FOUND", "CCG lobby not found")
    local player = lobby.players[who.account_id]
    need(player, "NOT_JOINED", "You are not in this lobby")
    -- Between rounds, or sitting this one out, anybody can go. Not in the
    -- middle of a round they have money in.
    need(lobby.status ~= "running" or (player.wager or 0) <= 0,
        "GAME_STARTED", "You cannot leave after the game starts")
    local released
    if lobby.status == "lobby" and (player.wager or 0) > 0 then
        -- A stake the Bank did not give back would be settled as a loss
        -- with the round, so leaving waits for it.
        released = bankOrFail("CCG_ESCROW_RELEASE", {
            lobby_code = lobby.code, account_id = who.account_id,
        })
    end
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
    player.seen_at = util.nowMs()
    local last
    if lobby.last_round then
        local mine = lobby.last_round.results[who.account_id]
        local game = CCG_GAMES[lobby.last_round.game]
        last = { round = lobby.last_round.round, game = lobby.last_round.game,
            game_name = game and game.name or lobby.last_round.game,
            multiplier = game and game.multiplier or 0,
            status = lobby.last_round.status, outcome = lobby.last_round.outcome,
            winner_name = lobby.last_round.winner_name,
            cancelled_reason = lobby.last_round.cancelled_reason,
            played = mine ~= nil, won = mine and mine.won or false,
            payout = mine and mine.payout or nil, hold_id = mine and mine.hold_id,
            wager = mine and mine.wager or 0, selection = mine and mine.selection }
    end
    return {
        lobby = publicLobby(lobby, false),
        player = publicPlayer(player),
        wallet = who.wallet,
        last = last,
    }
end

function actions.BET_CONTROL(payload)
    local who = requirePlayer(payload)
    local lobby = lobbyByCode(payload.code)
    need(lobby and lobby.status == "running" and lobby.game == "survivor",
        "NOT_INTERACTIVE", "Survivor is not running")
    local player = lobby.players[who.account_id]
    need(player and player.alive, "ELIMINATED", "You are out of this round")
    player.seen_at = util.nowMs()
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
    -- FoxyOS 16: whoever has wagered plays; anybody still choosing sits
    -- this round out and stays for the next.
    local playing = {}
    for _, accountId in ipairs(lobby.player_order) do
        if (lobby.players[accountId].wager or 0) > 0 then
            playing[#playing + 1] = accountId
        end
    end
    need(#playing >= minimumPlayers, "NOT_ENOUGH_PLAYERS",
        lobby.game == "survivor" and "Survivor needs two players with a wager"
            or "At least one player must place a wager")
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
        local count = #playing
        for index, accountId in ipairs(playing) do
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

-- The CCG Casino, FoxyOS 17 ------------------------------------------------------------
-- A CCG Casino console is a table: one each, belonging to a company, with a
-- code on its screen that never changes. It deals Roulette, Blackjack, Heads
-- or Tails and Poker, a round at a time:
--
--   wheel    the games spin and stop on the next one (Auto), or wait for
--            whoever controls the table to pick
--   betting  players at the table place their bets from the CCG app
--   playing  the game itself, dealt by this server
--   settling the Bank pays out, by the bet (FoxyOS 16.1)
--   result   who won, for a few seconds, and the next round
--
-- The console is a display. Everything is decided here, and everything a
-- person decides comes from the CCG app: players bet and play their hands,
-- and the owner of the table's company can switch Auto, choose the game,
-- take the dealer (pacing the round: close bets, spin, the next card) and
-- play music. Nobody controlling it, the table runs itself. The dealer's own
-- play is never anybody's choice: Blackjack's dealer stands on 17, Poker's
-- shows its cards at the showdown.
--
-- Money is the Bank's, as it always was: a bet is staked in escrow under the
-- table's code, and the round is settled by saying how each bet ended. What
-- that pays is the Bank's own table.

local casino = {
    GAMES = { "roulette", "blackjack", "heads_tails", "poker" },
    NAMES = { roulette = "Roulette", blackjack = "Blackjack",
        heads_tails = "Heads or Tails", poker = "Poker" },
    SEATS = 8,
    WHEEL_MS = 5000,       -- Auto: the games spin this long, then stop on one
    PICKED_MS = 1800,      -- a game picked from the app: the wheel lands on it
    BETTING_MS = 25000,    -- Auto: how long bets are open
    LAST_CALL_MS = 5000,   -- everybody seated has bet: not long now
    DECIDE_MS = 20000,     -- Blackjack and Poker: how long a player has to act
    FLIP_MS = 5000,
    SPIN_MS = 8000,
    CARD_MS = 550,         -- one card dealt
    REVEAL_MS = 2600,      -- Poker: the next cards on the board, in Auto
    RESULT_MS = 9000,
    LEASE_MS = 60000,      -- control lapses when the controller goes quiet
    OWNER_MS = 20000,      -- who owns what, remembered this long
    ONLINE_MS = 10000,
    owners = {},
    RED = {},
    HANDS = { [0] = "High card", "Pair", "Two pair", "Three of a kind", "Straight",
        "Flush", "Full house", "Four of a kind", "Straight flush" },
}
for _, number in ipairs({ 1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32,
    34, 36 }) do casino.RED[number] = true end
state.casinos = state.casinos or {}
state.casino_codes = state.casino_codes or {}
state.sequence.casino = state.sequence.casino or 0

-- Cards ---------------------------------------------------------------------------------------
-- A card is 1..52: rank 2..14 (11 Jack, 12 Queen, 13 King, 14 Ace), suit 1..4.

function casino.rank(card) return (card - 1) % 13 + 2 end
function casino.suit(card) return math.floor((card - 1) / 13) + 1 end

function casino.deck()
    util.randomString(1)
    local deck = {}
    for card = 1, 52 do deck[card] = card end
    for index = #deck, 2, -1 do
        local other = math.random(1, index)
        deck[index], deck[other] = deck[other], deck[index]
    end
    return deck
end

-- Blackjack: the best total, and whether an ace is still counting 11.
function casino.total(cards)
    local total, aces = 0, 0
    for _, card in ipairs(cards) do
        local rank = casino.rank(card)
        if rank == 14 then
            total, aces = total + 11, aces + 1
        else
            total = total + math.min(10, rank)
        end
    end
    while total > 21 and aces > 0 do total, aces = total - 10, aces - 1 end
    return total, aces > 0
end

function casino.natural(cards)
    return #cards == 2 and casino.total(cards) == 21
end

-- Poker: five cards scored so that a bigger list is a better hand.
function casino.score5(cards)
    local counts, suits, ranks = {}, {}, {}
    for _, card in ipairs(cards) do
        local rank, suit = casino.rank(card), casino.suit(card)
        counts[rank] = (counts[rank] or 0) + 1
        suits[suit] = (suits[suit] or 0) + 1
        ranks[#ranks + 1] = rank
    end
    table.sort(ranks, function(a, b) return a > b end)
    local flush = false
    for _, count in pairs(suits) do if count == 5 then flush = true end end
    local groups = {}
    for rank, count in pairs(counts) do groups[#groups + 1] = { rank = rank, count = count } end
    table.sort(groups, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.rank > b.rank
    end)
    local high
    if #groups == 5 then
        if ranks[1] - ranks[5] == 4 then high = ranks[1]
        elseif ranks[1] == 14 and ranks[2] == 5 then high = 5 end
    end
    local order = {}
    for _, group in ipairs(groups) do order[#order + 1] = group.rank end
    local function with(category, list)
        local out = { category }
        for _, value in ipairs(list) do out[#out + 1] = value end
        return out
    end
    if high and flush then return { 8, high } end
    if groups[1].count == 4 then return with(7, order) end
    if groups[1].count == 3 and groups[2].count == 2 then return with(6, order) end
    if flush then return with(5, ranks) end
    if high then return { 4, high } end
    if groups[1].count == 3 then return with(3, order) end
    if groups[1].count == 2 and groups[2].count == 2 then return with(2, order) end
    if groups[1].count == 2 then return with(1, order) end
    return with(0, ranks)
end

function casino.compare(a, b)
    for index = 1, math.max(#a, #b) do
        local x, y = a[index] or 0, b[index] or 0
        if x ~= y then return x > y and 1 or -1 end
    end
    return 0
end

-- The best five of seven.
function casino.bestHand(cards)
    local best
    local n = #cards
    for a = 1, n - 4 do for b = a + 1, n - 3 do for c = b + 1, n - 2 do
        for d = c + 1, n - 1 do for e = d + 1, n do
            local score = casino.score5({ cards[a], cards[b], cards[c], cards[d], cards[e] })
            if not best or casino.compare(score, best) > 0 then best = score end
        end end
    end end end
    return best, casino.HANDS[best[1]]
end

-- Bets ------------------------------------------------------------------------------------------
-- What a player may stake on each game, as the Bank's kinds of bet: Roulette
-- has four (a number, an even-money pick, a dozen, a column), the rest one.

function casino.readBet(game, bet)
    if type(bet) ~= "table" then return nil end
    local kind, pick = tostring(bet.kind or ""), bet.pick
    if game == "roulette" then
        if kind == "straight" then
            pick = tonumber(pick)
            if pick and pick >= 0 and pick <= 36 and pick % 1 == 0 then return kind, pick end
        elseif kind == "even" then
            pick = tostring(pick or "")
            for _, name in ipairs({ "red", "black", "odd", "even", "low", "high" }) do
                if pick == name then return kind, pick end
            end
        elseif kind == "dozen" or kind == "column" then
            pick = tonumber(pick)
            if pick == 1 or pick == 2 or pick == 3 then return kind, pick end
        end
    elseif game == "heads_tails" then
        if kind == "pick" and (pick == "heads" or pick == "tails") then return kind, pick end
    elseif kind == "hand" then
        return kind, nil
    end
    return nil
end

function casino.rouletteWins(bet, number)
    if bet.kind == "straight" then return bet.pick == number end
    if number == 0 then return false end
    if bet.kind == "dozen" then return math.ceil(number / 12) == bet.pick end
    if bet.kind == "column" then return (number - 1) % 3 + 1 == bet.pick end
    local pick = bet.pick
    if pick == "red" then return casino.RED[number] == true end
    if pick == "black" then return not casino.RED[number] end
    if pick == "odd" then return number % 2 == 1 end
    if pick == "even" then return number % 2 == 0 end
    if pick == "low" then return number <= 18 end
    return number >= 19
end

-- Tables ---------------------------------------------------------------------------------------

function casino.event(t, kind, extra)
    t.seq = (t.seq or 0) + 1
    local entry = { seq = t.seq, kind = kind, at = util.nowMs() }
    for key, value in pairs(extra or {}) do entry[key] = value end
    t.events = t.events or {}
    t.events[#t.events + 1] = entry
    while #t.events > 30 do table.remove(t.events, 1) end
    t.dirty = true
end

function casino.controlled(t, now)
    return t.controller ~= nil and (t.controller.until_at or 0) > (now or util.nowMs())
end

function casino.phase(t, phase, ms, now)
    now = now or util.nowMs()
    t.phase, t.phase_at = phase, now
    t.phase_until = ms and (now + ms) or nil
    t.step, t.step_at, t.step_until = nil, now, nil
    t.dirty = true
end

function casino.step(t, step, ms, now)
    now = now or util.nowMs()
    t.step, t.step_at = step, now
    t.step_until = ms and (now + ms) or nil
    t.dirty = true
end

function casino.byCode(code)
    code = string.upper(util.trim(tostring(code or "")))
    local id = state.casino_codes[code]
    return id and state.casinos[id] or nil
end

function casino.console(payload)
    local t = state.casinos[payload and payload.console_id]
    need(t and t.auth_token == payload.console_token, "CCG_AUTH",
        "This CCG Casino is not registered")
    t.last_seen = util.nowMs()
    return t
end

-- Who is asking, as the Bank knows them, and the companies they own.
function casino.owner(payload)
    local token = tostring(payload and payload.session_token or "")
    need(token ~= "", "SESSION_REQUIRED", "Sign in first")
    local cached = casino.owners[token]
    if cached and util.nowMs() - cached.at < casino.OWNER_MS then return cached.who end
    local who = bankOrFail("CCG_COMPANIES", { session_token = token })
    casino.owners[token] = { at = util.nowMs(), who = who }
    return who
end

function casino.owns(who, t)
    for _, company in ipairs(who.companies or {}) do
        if company.company_id == t.company_id then return true end
    end
    return false
end

function casino.ownedTable(payload)
    local who = casino.owner(payload)
    local t = state.casinos[payload.console_id]
    need(t and casino.owns(who, t), "NOT_YOURS",
        "That CCG Casino is not one of your company's")
    casino.link(t, payload.session_token)
    return t, who
end

-- A table set up before Beta 2 earns for the Bank until its owner next
-- opens it in My Casino: then, between rounds, it is linked to its company.
function casino.link(t, session)
    if t.bank_linked or t.phase == "playing" or t.phase == "settling"
        or #casino.bettors(t) > 0 then return end
    if t.link_tried_at and util.nowMs() - t.link_tried_at < 30000 then return end
    t.link_tried_at = util.nowMs()
    if askBank("CCG_CASINO_LINK", { session_token = session, company_id = t.company_id,
        code = t.code }) then
        t.bank_linked = true
        t.dirty = true
        logActivity(t.name .. " now earns for " .. tostring(t.company_name), colors.lime)
    end
end

function casino.seated(t)
    local list = {}
    for _, accountId in ipairs(t.order or {}) do
        if t.players[accountId] then list[#list + 1] = t.players[accountId] end
    end
    return list
end

function casino.bettors(t)
    local list = {}
    for _, player in ipairs(casino.seated(t)) do
        if (player.total or 0) > 0 then list[#list + 1] = player end
    end
    return list
end

-- The next game: the one somebody asked for, the wheel's, or the same again.
function casino.pickNext(t)
    if t.next_game then
        local game = t.next_game
        t.next_game = nil
        return game
    end
    return casino.GAMES[math.random(1, #casino.GAMES)]
end

-- Opening a round: the wheel, unless the table is simply playing its game
-- again (Auto off, nobody controlling, nothing asked for).
function casino.newRound(t, now)
    for _, player in ipairs(casino.seated(t)) do
        player.bets, player.total, player.hand, player.status = nil, 0, nil, nil
        player.result, player.done, player.decision = nil, nil, nil
    end
    t.dealer, t.board, t.outcome, t.deck, t.deal_order = nil, nil, nil, nil, nil
    t.results, t.payouts = nil, nil
    if casino.controlled(t, now) then
        t.wheel_target = nil
        casino.phase(t, "wheel", nil, now)
        casino.event(t, "wheel")
    elseif t.auto or t.next_game then
        local picked = t.next_game ~= nil
        t.wheel_target = casino.pickNext(t)
        casino.phase(t, "wheel", picked and casino.PICKED_MS or casino.WHEEL_MS, now)
        casino.event(t, "wheel")
    else
        casino.openBets(t, t.game or "roulette", now)
    end
end

function casino.openBets(t, game, now)
    t.game = game
    t.round = (t.round or 0) + 1
    casino.phase(t, "betting", (not casino.controlled(t, now)) and casino.BETTING_MS or nil, now)
    casino.event(t, "bets_open", { game = game })
end

-- Playing a round -------------------------------------------------------------------------------

function casino.draw(t)
    if not t.deck or #t.deck == 0 then t.deck = casino.deck() end
    return table.remove(t.deck)
end

-- Bets are closed: deal. Only the players who bet are in the round.
function casino.deal(t, now)
    local bettors = casino.bettors(t)
    casino.phase(t, "playing", nil, now)
    t.deck = casino.deck()
    if t.game == "roulette" then
        t.outcome = math.random(0, 36)
        casino.step(t, "spin", casino.SPIN_MS, now)
        casino.event(t, "spin")
    elseif t.game == "heads_tails" then
        t.outcome = math.random(1, 2) == 1 and "heads" or "tails"
        casino.step(t, "flip", casino.FLIP_MS, now)
        casino.event(t, "flip")
    else
        -- Two cards each, the dealer last, one round of the table at a time.
        t.dealer = { cards = {} }
        t.deal_order = {}
        for _ = 1, 2 do
            for _, player in ipairs(bettors) do
                player.hand = player.hand or {}
                player.hand[#player.hand + 1] = casino.draw(t)
                t.deal_order[#t.deal_order + 1] = player.account_id
            end
            t.dealer.cards[#t.dealer.cards + 1] = casino.draw(t)
            t.deal_order[#t.deal_order + 1] = "dealer"
        end
        for _, player in ipairs(bettors) do player.status = "playing" end
        if t.game == "poker" then
            t.board = { cards = {}, shown = 0 }
            for index = 1, 5 do t.board.cards[index] = casino.draw(t) end
        end
        casino.step(t, "deal", casino.CARD_MS * #t.deal_order, now)
        casino.event(t, "deal")
    end
end

function casino.allDone(t)
    for _, player in ipairs(casino.bettors(t)) do
        if not player.done then return false end
    end
    return true
end

-- Blackjack: the dealer turns the hidden card over and draws to 17.
function casino.dealerPlays(t, now)
    local anyStanding = false
    for _, player in ipairs(casino.bettors(t)) do
        if player.status ~= "bust" then anyStanding = true end
    end
    if anyStanding then
        while casino.total(t.dealer.cards) < 17 do
            t.dealer.cards[#t.dealer.cards + 1] = casino.draw(t)
        end
    end
    t.dealer.open = true
    casino.step(t, "dealer", casino.CARD_MS * 2 * (#t.dealer.cards - 1), now)
    casino.event(t, "reveal")
end

-- How each bet ended, as the Bank's words: win, blackjack, push or lose.
function casino.outcomes(t)
    local results = {}
    if t.game == "roulette" then
        for _, player in ipairs(casino.bettors(t)) do
            local list = {}
            for index, bet in ipairs(player.bets) do
                list[index] = casino.rouletteWins(bet, t.outcome) and "win" or "lose"
            end
            results[player.account_id] = list
        end
    elseif t.game == "heads_tails" then
        for _, player in ipairs(casino.bettors(t)) do
            results[player.account_id] = player.bets[1].pick == t.outcome and "win" or "lose"
        end
    elseif t.game == "blackjack" then
        local dealer = casino.total(t.dealer.cards)
        local dealerNatural = casino.natural(t.dealer.cards)
        for _, player in ipairs(casino.bettors(t)) do
            local mine = casino.total(player.hand)
            local natural = casino.natural(player.hand) and not player.doubled
            local said
            if mine > 21 then said = "lose"
            elseif natural and dealerNatural then said = "push"
            elseif natural then said = "blackjack"
            elseif dealerNatural then said = "lose"
            elseif dealer > 21 or mine > dealer then said = "win"
            elseif mine == dealer then said = "push"
            else said = "lose" end
            results[player.account_id] = said
        end
    else
        local dealerCards = { t.dealer.cards[1], t.dealer.cards[2] }
        for _, card in ipairs(t.board.cards) do dealerCards[#dealerCards + 1] = card end
        local dealerBest, dealerName = casino.bestHand(dealerCards)
        t.dealer.hand_name = dealerName
        for _, player in ipairs(casino.bettors(t)) do
            local said = "lose"
            if player.status ~= "folded" then
                local cards = { player.hand[1], player.hand[2] }
                for _, card in ipairs(t.board.cards) do cards[#cards + 1] = card end
                local best, name = casino.bestHand(cards)
                player.hand_name = name
                -- Ties go to the dealer: the house's edge, said on the table.
                said = casino.compare(best, dealerBest) > 0 and "win" or "lose"
            end
            results[player.account_id] = said
        end
    end
    return results
end

-- The Bank pays out. If it does not answer, the round waits and asks again:
-- the money is still in escrow, so calling it settled would lose it.
function casino.settle(t, now)
    if not t.results then
        t.results = casino.outcomes(t)
        casino.phase(t, "settling", nil, now)
    end
    if next(t.results) == nil then
        casino.finish(t, {}, now)
        return true
    end
    if t.settle_tried_at and now - t.settle_tried_at < 2000 then return false end
    t.settle_tried_at = now
    local paid = askBank("CCG_ESCROW_SETTLE", { lobby_code = t.code, results = t.results }, 8)
    if not paid then
        logActivity("Bank did not settle " .. t.name .. ", will retry", colors.orange)
        return false
    end
    casino.finish(t, paid.settled or {}, now)
    return true
end

function casino.finish(t, settled, now)
    t.settle_tried_at = nil
    local winners = {}
    for _, entry in ipairs(settled) do
        local player = t.players[entry.account_id]
        if player then
            player.result = { won = entry.won, payout = entry.payout or 0,
                pushed = entry.pushed or 0, results = entry.results,
                said = t.results[entry.account_id] }
            if entry.won then
                winners[#winners + 1] = { name = player.name, payout = entry.payout }
            end
        end
    end
    table.sort(winners, function(a, b) return (a.payout or 0) > (b.payout or 0) end)
    t.winners = winners
    -- Kept for a player who looked away while the next round opened.
    local kept = {}
    for _, player in ipairs(casino.bettors(t)) do
        kept[player.account_id] = player.result
    end
    t.last = { round = t.round, game = t.game, outcome = t.outcome, results = kept,
        dealer_total = t.dealer and casino.total(t.dealer.cards) or nil,
        dealer_hand = t.dealer and t.dealer.hand_name or nil }
    t.results = nil
    casino.phase(t, "result", (not casino.controlled(t, now)) and casino.RESULT_MS or nil, now)
    casino.event(t, #winners > 0 and "win" or "lose")
    logActivity(t.name .. ": " .. casino.NAMES[t.game] .. " round " .. t.round
        .. ", " .. #winners .. " won", colors.magenta)
end

-- Moving a table on. Called every tick for every table, and straight after
-- anybody does anything to one.
function casino.advance(t, now)
    now = now or util.nowMs()
    if t.controller and not casino.controlled(t, now) then
        t.controller = nil
        t.dirty = true
        -- Back to the computer: anything that was waiting on the controller
        -- gets its clock again.
        if t.phase == "wheel" and not t.phase_until then
            t.wheel_target = casino.pickNext(t)
            t.phase_until = now + casino.WHEEL_MS
        elseif t.phase == "betting" and not t.phase_until then
            t.phase_until = now + casino.BETTING_MS
        elseif t.phase == "result" and not t.phase_until then
            t.phase_until = now + 2000
        elseif t.phase == "playing" and not t.step_until then
            t.step_until = now + casino.REVEAL_MS
        end
    end
    local phase = t.phase
    if phase == nil then
        casino.newRound(t, now)
    elseif phase == "wheel" then
        if t.phase_until and now >= t.phase_until and t.wheel_target then
            casino.event(t, "stop", { game = t.wheel_target })
            casino.openBets(t, t.wheel_target, now)
        end
    elseif phase == "betting" then
        local bettors, seated = casino.bettors(t), casino.seated(t)
        if t.phase_until and #bettors > 0 and #bettors == #seated
            and t.phase_until - now > casino.LAST_CALL_MS then
            t.phase_until = now + casino.LAST_CALL_MS
            t.dirty = true
        end
        if t.phase_until and now >= t.phase_until then
            if #bettors > 0 then
                casino.deal(t, now)
            elseif t.auto then
                casino.newRound(t, now)
            else
                t.phase_until = now + casino.BETTING_MS
            end
        end
    elseif phase == "playing" then
        casino.play(t, now)
    elseif phase == "settling" then
        casino.settle(t, now)
    elseif phase == "result" then
        if t.phase_until and now >= t.phase_until then casino.newRound(t, now) end
    end
end

function casino.play(t, now)
    local step, due = t.step, t.step_until and now >= t.step_until
    if (step == "spin" or step == "flip") and due then
        casino.settle(t, now)
    elseif step == "deal" and due then
        if t.game == "blackjack" then
            local dealerNatural = casino.natural(t.dealer.cards)
            for _, player in ipairs(casino.bettors(t)) do
                if casino.natural(player.hand) or dealerNatural then
                    player.done = true
                    player.status = casino.natural(player.hand) and "blackjack" or "stood"
                end
            end
            if dealerNatural or casino.allDone(t) then
                casino.dealerPlays(t, now)
            else
                casino.step(t, "turns", casino.DECIDE_MS, now)
            end
        else
            casino.step(t, "decide", casino.DECIDE_MS, now)
        end
    elseif (step == "turns" or step == "decide") and (due or casino.allDone(t)) then
        -- Whoever has not acted stands, or checks.
        for _, player in ipairs(casino.bettors(t)) do
            if not player.done then
                player.done = true
                player.status = step == "turns" and "stood" or "checked"
            end
        end
        if step == "turns" then
            casino.dealerPlays(t, now)
        else
            t.board.shown = 3
            casino.step(t, "flop", (not casino.controlled(t, now)) and casino.REVEAL_MS or nil, now)
            casino.event(t, "reveal")
        end
    elseif step == "dealer" and due then
        casino.settle(t, now)
    elseif (step == "flop" or step == "turn") and due then
        t.board.shown = step == "flop" and 4 or 5
        casino.step(t, step == "flop" and "turn" or "river",
            (not casino.controlled(t, now)) and casino.REVEAL_MS or nil, now)
        casino.event(t, "reveal")
    elseif step == "river" and due then
        t.dealer.open = true
        casino.step(t, "showdown", casino.REVEAL_MS, now)
        casino.event(t, "reveal")
    elseif step == "showdown" and due then
        casino.settle(t, now)
    end
end

-- What a table looks like ---------------------------------------------------------------------
-- To the console, which is the casino's screen and is shown everything it
-- shows the room (and where the ball will stop, so it can land it there);
-- to a player, who also sees their own cards; to the owner, who also sees
-- every bet and the music. Cards face down are 0. During the deal, cards
-- appear one at a time in the order they were dealt, on every screen alike.

function casino.nextLabel(t)
    if t.phase == "wheel" then return nil end
    if t.phase == "betting" then
        return t.game == "roulette" and "SPIN" or t.game == "heads_tails" and "FLIP" or "DEAL"
    end
    if t.phase == "result" then return "NEXT GAME" end
    local labels = { turns = "DEALER'S TURN", decide = "FLOP", flop = "TURN",
        turn = "RIVER", river = "SHOWDOWN" }
    return t.phase == "playing" and labels[t.step] or nil
end

function casino.view(t, how)
    how = how or {}
    local now = util.nowMs()
    local shownSoFar
    if t.step == "deal" and t.deal_order then
        shownSoFar = {}
        local count = math.floor((now - (t.step_at or now)) / casino.CARD_MS) + 1
        for index = 1, math.min(count, #t.deal_order) do
            local who = t.deal_order[index]
            shownSoFar[who] = (shownSoFar[who] or 0) + 1
        end
    end
    local showdown = t.phase == "settling" or t.phase == "result"
        or t.step == "showdown"
    local function cardsOf(id, cards, faceDown)
        if not cards then return nil end
        local limit = shownSoFar and (shownSoFar[id] or 0) or #cards
        local out = {}
        for index = 1, math.min(limit, #cards) do
            out[index] = faceDown and 0 or cards[index]
        end
        return out
    end
    local players = {}
    for _, player in ipairs(casino.seated(t)) do
        local mine = how.account == player.account_id
        local hidden = t.game == "poker" and not mine and not showdown
        local entry = { seat = player.seat, name = player.name,
            total = player.total or 0, playing = (player.total or 0) > 0,
            status = player.status, result = player.result, me = mine or nil,
            hand_name = (showdown or mine) and player.hand_name or nil }
        if how.display or how.owner or mine or t.phase ~= "betting" then
            entry.bets = player.bets
        end
        entry.cards = cardsOf(player.account_id, player.hand, hidden)
        if entry.cards and t.game == "blackjack" and #entry.cards > 0 then
            entry.hand_total = casino.total(entry.cards)
        end
        players[#players + 1] = entry
    end
    local view = {
        console_id = t.console_id, name = t.name, company_name = t.company_name,
        code = t.code, game = t.game, game_name = casino.NAMES[t.game or ""],
        auto = t.auto == true, controlled = casino.controlled(t, now),
        controller_name = casino.controlled(t, now) and t.controller.name or nil,
        phase = t.phase, step = t.step, round = t.round or 0,
        left_ms = t.phase_until and math.max(0, t.phase_until - now) or nil,
        phase_ms = t.phase_until and t.phase_at and (t.phase_until - t.phase_at) or nil,
        step_left_ms = t.step_until and math.max(0, t.step_until - now) or nil,
        step_ms = t.step_until and t.step_at and (t.step_until - t.step_at) or nil,
        wheel_target = t.wheel_target, games = casino.GAMES, names = casino.NAMES,
        players = players, seats = casino.SEATS, winners = t.phase == "result" and t.winners or nil,
        seq = t.seq or 0,
    }
    if t.dealer then
        local cards = cardsOf("dealer", t.dealer.cards, false)
        if t.game == "blackjack" and t.dealer.open then
            -- The dealer's draws, one every two card-times.
            if t.step == "dealer" then
                local count = 2 + math.floor((now - (t.step_at or now)) / (casino.CARD_MS * 2))
                while #cards > math.max(2, count) do table.remove(cards) end
            end
        elseif t.game == "blackjack" then
            if cards[2] then cards[2] = 0 end
        elseif not t.dealer.open then
            for index in ipairs(cards) do cards[index] = 0 end
        end
        local visible = {}
        for _, card in ipairs(cards) do if card ~= 0 then visible[#visible + 1] = card end end
        view.dealer = { cards = cards,
            total = t.game == "blackjack" and #visible > 0 and casino.total(visible) or nil,
            hand_name = showdown and t.dealer.hand_name or nil }
    end
    if t.board then
        local shown = {}
        for index = 1, t.board.shown or 0 do shown[index] = t.board.cards[index] end
        view.board = { cards = shown }
    end
    if t.outcome ~= nil and (how.display or showdown) then view.outcome = t.outcome end
    if how.display then view.events = t.events end
    if how.display or how.owner then
        view.music, view.library = t.music, t.library or {}
    end
    if how.owner then view.next_label = casino.nextLabel(t) end
    return view
end

-- The player asking, their seat, and what they can do now.
function casino.mine(t, accountId)
    local player = t.players[accountId]
    if not player then return nil end
    local options = {}
    if t.phase == "playing" and not player.done and (player.total or 0) > 0 then
        if t.step == "turns" then
            options = { "hit", "stand" }
            if #(player.hand or {}) == 2 and not player.doubled then options[3] = "double" end
        elseif t.step == "decide" then
            options = { "raise", "check", "fold" }
        end
    end
    -- Poker: what your cards make so far, with the board as it is.
    local handName = player.hand_name
    if t.game == "poker" and player.hand and not handName then
        local cards = { player.hand[1], player.hand[2] }
        for index = 1, (t.board and t.board.shown or 0) do cards[#cards + 1] = t.board.cards[index] end
        if #cards >= 5 then
            handName = select(2, casino.bestHand(cards))
        elseif #cards == 2 then
            handName = casino.rank(cards[1]) == casino.rank(cards[2]) and "Pair" or "High card"
        end
    end
    return { seat = player.seat, name = player.name, bets = player.bets,
        total = player.total or 0, status = player.status, options = options,
        result = player.result, hand_name = handName }
end

-- Actions: the console ---------------------------------------------------------------------------

function actions.CASINO_COMPANIES(payload)
    local who = casino.owner(payload)
    return { name = who.name, companies = who.companies or {} }
end

function actions.CASINO_REGISTER(payload)
    local who = casino.owner(payload)
    local company
    for _, owned in ipairs(who.companies or {}) do
        if owned.company_id == payload.company_id then company = owned end
    end
    need(company, "NOT_YOURS", "Choose a company you own")
    local name = util.safeText(util.trim(payload.name), 16)
    need(#name >= 2, "INVALID_NAME", "Give this CCG Casino a name")
    local code = uniqueCode()
    -- FoxyOS 17 Beta 2: the table earns for its company. The Bank links the
    -- code to the company with the owner's own session, or there is no table.
    bankOrFail("CCG_CASINO_LINK", { session_token = payload.session_token,
        company_id = company.company_id, code = code })
    local consoleId = nextId("casino", "CAS", 5)
    local t = {
        console_id = consoleId, auth_token = util.token("CCG_CASINO"),
        name = name, company_id = company.company_id, company_name = company.name,
        owner_account_id = who.account_id, code = code, auto = true, bank_linked = true,
        players = {}, order = {}, round = 0, seq = 0, events = {},
        music = { playing = false, volume = 5, seq = 0 }, library = {},
        created_at = util.nowMs(), last_seen = util.nowMs(),
    }
    state.casinos[consoleId] = t
    state.casino_codes[code] = consoleId
    casino.advance(t)
    save()
    logActivity("CCG Casino " .. name .. " for " .. company.name, colors.magenta)
    return { console_id = consoleId, console_token = t.auth_token, code = code,
        name = name, company_name = company.name }
end

-- The console asks what to show, a few times a second, and says which music
-- files it has.
function actions.CASINO_TICK(payload)
    local t = casino.console(payload)
    if type(payload.library) == "table" then
        local library = {}
        for index, name in ipairs(payload.library) do
            if index > 60 then break end
            library[#library + 1] = util.safeText(tostring(name), 32)
        end
        t.library = library
    end
    casino.advance(t)
    return { table = casino.view(t, { display = true }) }
end

function actions.CASINO_UNLINK(payload)
    local t = casino.console(payload)
    need(t.phase ~= "playing" and t.phase ~= "settling", "GAME_STARTED",
        "Finish this round first")
    if #casino.bettors(t) > 0 then
        bankOrFail("CCG_ESCROW_REFUND", { lobby_code = t.code, reason = "Table closed" })
    end
    if t.bank_linked then bankOrFail("CCG_CASINO_UNLINK", { code = t.code }) end
    state.casino_codes[t.code] = nil
    state.casinos[t.console_id] = nil
    save()
    return { unlinked = true }
end

-- Actions: the owner, from My Casino -------------------------------------------------------------

function actions.CASINO_LIST(payload)
    local who = casino.owner(payload)
    local now, list = util.nowMs(), {}
    for _, t in pairs(state.casinos) do
        if casino.owns(who, t) then
            casino.link(t, payload.session_token)
            list[#list + 1] = { console_id = t.console_id, name = t.name,
                company_name = t.company_name, code = t.code, game = t.game,
                game_name = casino.NAMES[t.game or ""], phase = t.phase,
                players = #casino.seated(t), betting = #casino.bettors(t),
                auto = t.auto == true, controlled = casino.controlled(t, now),
                controller_name = casino.controlled(t, now) and t.controller.name or nil,
                online = now - (t.last_seen or 0) < casino.ONLINE_MS,
                linked = t.bank_linked == true,
                music = t.music and t.music.playing and t.music.track or nil }
        end
    end
    table.sort(list, function(a, b)
        if a.company_name ~= b.company_name then return a.company_name < b.company_name end
        return a.name < b.name
    end)
    return { casinos = list, companies = who.companies or {} }
end

function actions.CASINO_VIEW(payload)
    local t, who = casino.ownedTable(payload)
    local now = util.nowMs()
    local mine = casino.controlled(t, now) and t.controller.account_id == who.account_id
    -- Watching the controls is controlling: the lease runs while you look.
    if mine then t.controller.until_at = now + casino.LEASE_MS end
    casino.advance(t, now)
    return { table = casino.view(t, { owner = true }), you_control = mine }
end

function actions.CASINO_CONTROL(payload)
    local t, who = casino.ownedTable(payload)
    local now = util.nowMs()
    local op = tostring(payload.op or "")
    local mine = casino.controlled(t, now) and t.controller.account_id == who.account_id
    if op == "take" then
        t.controller = { account_id = who.account_id, name = who.name,
            until_at = now + casino.LEASE_MS }
        -- What was running on a clock now waits for the controller.
        if t.phase == "wheel" then t.wheel_target, t.phase_until = nil, nil end
        if t.phase == "betting" or t.phase == "result" then t.phase_until = nil end
        if t.phase == "playing" and (t.step == "flop" or t.step == "turn"
            or t.step == "river") then t.step_until = nil end
        casino.event(t, "control")
        mine = true
    elseif op == "release" then
        if t.controller then t.controller.until_at = 0 end
    elseif op == "auto" then
        t.auto = payload.on == true
        t.dirty = true
    elseif op == "game" then
        local game = tostring(payload.game or "")
        need(casino.NAMES[game], "INVALID_GAME", "Choose Roulette, Blackjack, Heads or Tails or Poker")
        if t.phase == "wheel" then
            t.wheel_target, t.phase_until = game, now + casino.PICKED_MS
        elseif t.phase == "betting" and #casino.bettors(t) == 0 then
            casino.openBets(t, game, now)
        else
            t.next_game = game
        end
        t.dirty = true
    elseif op == "next" then
        need(mine, "NOT_CONTROLLING", "Take the dealer first")
        if t.phase == "betting" then
            need(#casino.bettors(t) > 0, "NO_BETS", "Nobody has bet yet")
            casino.deal(t, now)
        elseif t.phase == "result" then
            casino.newRound(t, now)
        elseif t.phase == "playing" then
            if t.step == "turns" or t.step == "decide" then
                for _, player in ipairs(casino.bettors(t)) do
                    if not player.done then player.done = true
                        player.status = t.step == "turns" and "stood" or "checked" end
                end
            end
            if t.step ~= "deal" and t.step ~= "spin" and t.step ~= "flip"
                and t.step ~= "dealer" and t.step ~= "showdown" then
                t.step_until = now
            end
        end
    elseif op == "music" then
        local music = t.music
        local action = tostring(payload.action or "")
        if action == "play" then
            music.track = util.safeText(tostring(payload.track or ""), 32)
            music.playing = music.track ~= ""
        elseif action == "stop" then
            music.playing = false
        elseif action == "volume" then
            music.volume = util.clamp(math.floor(tonumber(payload.volume) or 5), 0, 10)
        elseif action == "next" then
            local library = t.library or {}
            local at = 0
            for index, name in ipairs(library) do if name == music.track then at = index end end
            music.track = library[at % math.max(1, #library) + 1]
            music.playing = music.track ~= nil
        end
        music.seq = (music.seq or 0) + 1
        t.dirty = true
    elseif op == "rename" then
        local name = util.safeText(util.trim(payload.name), 16)
        need(#name >= 2, "INVALID_NAME", "Give it a name")
        t.name = name
        t.dirty = true
    else
        reject("UNKNOWN_OP", "The CCG cannot do that")
    end
    if mine and t.controller then t.controller.until_at = math.max(t.controller.until_at, now
        + (op == "release" and 0 or casino.LEASE_MS)) end
    if op == "release" and t.controller then t.controller.until_at = 0 end
    casino.advance(t, now)
    save()
    return { table = casino.view(t, { owner = true }),
        you_control = casino.controlled(t, now) and t.controller.account_id == who.account_id }
end

-- Actions: players, from the CCG app's Bet tab ---------------------------------------------------

function casino.status(t, who)
    local last
    if t.last and t.last.results and t.last.results[who.account_id]
        and t.last.round ~= (t.phase == "result" and t.round or -1) then
        last = { round = t.last.round, game = t.last.game,
            game_name = casino.NAMES[t.last.game], outcome = t.last.outcome,
            result = t.last.results[who.account_id], dealer_total = t.last.dealer_total,
            dealer_hand = t.last.dealer_hand }
    end
    return { table = casino.view(t, { account = who.account_id }),
        me = casino.mine(t, who.account_id), last = last, wallet = who.wallet }
end

function casino.seat(t, who)
    local player = t.players[who.account_id]
    need(player, "NOT_JOINED", "Sit down at the table first")
    player.seen_at = util.nowMs()
    return player
end

function actions.TABLE_JOIN(payload)
    local who = requirePlayer(payload)
    local t = casino.byCode(payload.code)
    need(t, "TABLE_NOT_FOUND", "No CCG Casino has that code")
    local name = util.safeText(util.trim(payload.display_name), 14)
    need(#name >= 2 and name:match("^[%w_ %-]+$"), "INVALID_NAME",
        "Use 2-14 letters, numbers, spaces, _ or -")
    for otherId, other in pairs(t.players) do
        need(otherId == who.account_id or util.normalName(other.name) ~= util.normalName(name),
            "NAME_TAKEN", "Somebody at this table already has that name")
    end
    local player = t.players[who.account_id]
    if not player then
        need(#t.order < casino.SEATS, "TABLE_FULL", "Every seat at this table is taken")
        player = { account_id = who.account_id, seat = #t.order + 1, total = 0,
            joined_at = util.nowMs() }
        t.players[who.account_id] = player
        t.order[#t.order + 1] = who.account_id
        casino.event(t, "sit")
    end
    if (player.total or 0) == 0 then player.name = name end
    player.seen_at = util.nowMs()
    save()
    return casino.status(t, who)
end

function actions.TABLE_STATUS(payload)
    local who = requirePlayer(payload)
    local t = casino.byCode(payload.code)
    need(t, "TABLE_NOT_FOUND", "That table has closed")
    casino.seat(t, who)
    casino.advance(t)
    return casino.status(t, who)
end

-- Bets for this round: a list of { kind, pick, amount }. Up to eight at
-- Roulette, one at the rest. Placing again replaces them.
function actions.TABLE_BET(payload)
    local t = casino.byCode(payload.code)
    need(t and t.phase == "betting", "BETS_CLOSED", "Bets are closed")
    local who = requirePlayer(payload)
    local player = casino.seat(t, who)
    local list = type(payload.bets) == "table" and payload.bets or {}
    need(#list >= 1 and #list <= (t.game == "roulette" and 8 or 1), "INVALID_BETS",
        t.game == "roulette" and "Place one to eight bets" or "Place one bet")
    local bets, staked = {}, {}
    for index, entry in ipairs(list) do
        local kind, pick = casino.readBet(t.game, entry)
        need(kind, "INVALID_BET", "That is not a bet at " .. casino.NAMES[t.game])
        local amount = tonumber(entry.amount)
        need(amount and amount > 0, "INVALID_AMOUNT", "Say how much")
        bets[index] = { kind = kind, pick = pick, amount = amount }
        staked[index] = { kind = kind, amount = amount }
    end
    -- The Bank takes the money, or says why not; the player is checked as
    -- seated before it is asked.
    local done = bankOrFail("CCG_ESCROW_SET", { bet_token = payload.bet_token,
        session_token = payload.session_token, lobby_code = t.code, game = t.game,
        bets = staked })
    if t.phase ~= "betting" then
        -- The round started while the Bank was taking it: this player is not
        -- in it, so their stake goes straight back rather than being settled
        -- as a bet that lost.
        askBank("CCG_ESCROW_RELEASE", { lobby_code = t.code, account_id = who.account_id })
        reject("BETS_CLOSED", "Bets closed while that went through")
    end
    player.bets, player.total = bets, done.staked
    casino.event(t, "chip")
    save()
    local status = casino.status(t, who)
    status.wallet = done.wallet or status.wallet
    return status
end

-- Blackjack: hit, stand, double. Poker: raise, check, fold.
function actions.TABLE_ACT(payload)
    local who = requirePlayer(payload)
    local t = casino.byCode(payload.code)
    need(t and t.phase == "playing", "NOT_NOW", "There is nothing to do right now")
    local player = casino.seat(t, who)
    local action = tostring(payload.action or "")
    local allowed = false
    for _, option in ipairs((casino.mine(t, who.account_id) or {}).options or {}) do
        if option == action then allowed = true end
    end
    need(allowed, "NOT_NOW", "You cannot do that now")
    local function restake()
        -- The same bet, staked again: a double, or a raise.
        local done = bankOrFail("CCG_ESCROW_SET", { bet_token = payload.bet_token,
            session_token = payload.session_token, lobby_code = t.code, game = t.game,
            bets = { { kind = "hand", amount = player.total * 2 } } })
        player.bets[1].amount = done.staked
        player.total = done.staked
    end
    if action == "hit" then
        player.hand[#player.hand + 1] = casino.draw(t)
        local total = casino.total(player.hand)
        if total > 21 then player.status, player.done = "bust", true
        elseif total == 21 then player.status, player.done = "stood", true end
        casino.event(t, total > 21 and "bust" or "card")
    elseif action == "stand" then
        player.status, player.done = "stood", true
    elseif action == "double" then
        restake()
        player.doubled = true
        player.hand[#player.hand + 1] = casino.draw(t)
        player.status = casino.total(player.hand) > 21 and "bust" or "doubled"
        player.done = true
        casino.event(t, "chip")
    elseif action == "raise" then
        restake()
        player.status, player.done = "raised", true
        casino.event(t, "chip")
    elseif action == "check" then
        player.status, player.done = "checked", true
    elseif action == "fold" then
        player.status, player.done = "folded", true
    end
    t.dirty = true
    casino.advance(t)
    save()
    return casino.status(t, who)
end

function actions.TABLE_LEAVE(payload)
    local who = requirePlayer(payload)
    local t = casino.byCode(payload.code)
    need(t, "TABLE_NOT_FOUND", "That table has closed")
    local player = t.players[who.account_id]
    need(player, "NOT_JOINED", "You are not at this table")
    local staked = (player.total or 0) > 0
    need(not staked or t.phase == "betting" or t.phase == "result" or t.phase == "wheel",
        "GAME_STARTED", "Finish this round first")
    if staked and t.phase == "betting" then
        bankOrFail("CCG_ESCROW_RELEASE", { lobby_code = t.code, account_id = who.account_id })
    end
    t.players[who.account_id] = nil
    for index, accountId in ipairs(t.order) do
        if accountId == who.account_id then table.remove(t.order, index) break end
    end
    for seat, accountId in ipairs(t.order) do t.players[accountId].seat = seat end
    save()
    return { left = true, wallet = who.wallet }
end

-- Every table, every tick: the clock, and anybody who left without saying.
function casino.tick(now)
    local changed = false
    for _, t in pairs(state.casinos) do
        local ok, err = pcall(casino.advance, t, now)
        if not ok then logActivity("Casino " .. tostring(t.name) .. ": " .. tostring(err),
            colors.red) end
        if t.phase ~= "playing" and t.phase ~= "settling" then
            for index = #t.order, 1, -1 do
                local player = t.players[t.order[index]]
                if player and (player.total or 0) <= 0
                    and now - (player.seen_at or player.joined_at or now) > PRESENCE_MS then
                    t.players[t.order[index]] = nil
                    table.remove(t.order, index)
                    t.dirty = true
                end
            end
            for seat, accountId in ipairs(t.order) do t.players[accountId].seat = seat end
        end
        if t.dirty then t.dirty, changed = nil, true end
    end
    if changed then save() end
    return changed
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
        -- FoxyOS 17: every CCG Casino table.
        pcall(casino.tick, util.nowMs())
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

-- 12.0: Status, Activity and Server tabs, as on every server.
local function dashboardLoop()
    ui.serverTabs({
        version = config.version,
        target = target, title = "CCG SERVER", subtitle = "v" .. PROGRAM_VERSION,
        cards = function()
            local open, running_count, players = 0, 0, 0
            for _, lobby in pairs(state.lobbies) do
                if lobby.status == "lobby" then open = open + 1 end
                if lobby.status == "running" then running_count = running_count + 1 end
                if lobby.status == "lobby" or lobby.status == "running" then
                    players = players + #(lobby.player_order or {})
                end
            end
            -- FoxyOS 17: the CCG Casino tables, and who is at them.
            local tables = 0
            for _, t in pairs(state.casinos) do
                tables = tables + 1
                players = players + #(t.order or {})
            end
            return { { "TABLES", tables, colors.cyan }, { "LOBBIES", open + running_count,
                colors.lime }, { "PLAYERS", players, colors.magenta } }
        end,
        lines = function()
            return { { "BANK  " .. (bank:isOnline() and "CONNECTED" or "SEARCHING"),
                bank:isOnline() and colors.lime or colors.orange } }
        end,
        activity = activity, root = ROOT, colorTitle = "Server colour",
        actions = { { id = "stop", label = "STOP", hint = "Open lobbies are refunded",
            color = colors.red, run = function(terminated)
                if terminated or ui.confirm(target, "STOP CCG SERVER",
                    "Open lobbies will be refunded.", "STOP", "BACK") then
                    for _, lobby in pairs(state.lobbies) do
                        if lobby.status == "lobby" or lobby.status == "running" then
                            pcall(refundLobby, lobby, "CCG Server stopped")
                        end
                    end
                    running = false
                    save()
                    return true
                end
            end } },
        running = function() return running end,
    })
end

if TEST_MODE then
    return {
        actions = actions, state = state, games = CCG_GAMES,
        process_games = processGames, advance_survivor = advanceSurvivor,
        refund_lobby = refundLobby, boot_id = BOOT_ID, casino = casino,
    }
end

ui.usePhoneStyle(false)
ui.boot(target, "CCG SERVER", (ui.osLabel and ui.osLabel(config) or "FoxyOS"))
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
print("CCG Server stopped safely.")
