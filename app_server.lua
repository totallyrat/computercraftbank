local ROOT = fs.getDir(shell.getRunningProgram())
if ROOT == "" then ROOT = "." end
package.path = package.path .. ";" .. fs.combine(ROOT, "?.lua")
    .. ";" .. fs.combine(ROOT, "?/init.lua")

-- Stamped by tools/build_release_manifest.js. A program running beside a
-- config.lua from a different release means a partial install.
local PROGRAM_VERSION = "9.3.1"
local config = require("config")
local util = require("lib.util")
local net = require("lib.net")
local ui = require("lib.ui")

-- The App Server holds every optional PUMPE app and serves the downloads.
-- The Bank is asked one question, once, when something is published: is this
-- developer real. Every download after that never reaches the Bank at all,
-- which is the whole point of the machine.
local target = term.current()
local bank = net.client(config)
local running = true
local dataFile = fs.combine(ROOT, "app_server_v1.dat")
local appsDir = fs.combine(ROOT, "appstore")
local activity = {}

local function logActivity(text, color)
    table.insert(activity, 1, {
        text = util.safeText(text, 42),
        color = color or colors.lightGray,
        time = util.formatClock(),
    })
    while #activity > 8 do table.remove(activity) end
end

local state = util.loadTable(dataFile, { apps = {}, order = {}, sequence = 0 })
state.apps = state.apps or {}
state.order = state.order or {}
state.sequence = state.sequence or 0

local function save()
    util.saveTable(dataFile, state)
end

local function appPath(appId)
    return fs.combine(appsDir, appId .. ".lua")
end

local function appBody(appId)
    return util.readFile(appPath(appId))
end

local function reject(code, message)
    error({ pumpe = true, code = code, message = message }, 0)
end

local function need(condition, code, message)
    if not condition then reject(code, message) end
end

-- A bank app declares itself in its own header:
--
--     -- PUMPE BANK APP: BuckApp
--
-- That is the whole registration. A 3rd Party Bank Server lists the apps
-- that say this and hosts the one it is told to.
local function declaredBank(body)
    local name = tostring(body or ""):match(
        "%-%-%s*PUMPE BANK APP:%s*([^\r\n]+)")
    return name and util.safeText(util.trim(name), 20) or nil
end

-- A bank sets its own terms in the same header. Clearing is whole in-game
-- hours before money is spendable; the fee is a percentage of what is sent.
-- Saying nothing means nothing: no wait and no fee.
local function declaredTerms(body)
    body = tostring(body or "")
    return tonumber(body:match("%-%-%s*PUMPE BANK CLEARING:%s*([%d%.]+)")) or 0,
        (tonumber(body:match("%-%-%s*PUMPE BANK FEE:%s*([%d%.]+)")) or 0) / 100
end

local function publicApp(app)
    return {
        app_id = app.app_id,
        bank_name = app.bank_name,
        clearing_hours = app.clearing_hours,
        fee_rate = app.fee_rate,
        name = app.name,
        description = app.description,
        author = app.author,
        version = app.version,
        size = app.size,
        checksum = app.checksum,
        published_day = app.published_day,
        downloads = app.downloads or 0,
    }
end

local function catalogue(banksOnly)
    local list = {}
    for _, appId in ipairs(state.order) do
        local app = state.apps[appId]
        if app and (not banksOnly or app.bank_name) then
            list[#list + 1] = publicApp(app)
        end
    end
    return list
end

-- Anyone can read the catalogue and download; publishing and deleting need a
-- developer the Bank vouches for.
local function requireDeveloper(payload)
    local id = payload and payload.developer_id
    local token = payload and payload.developer_token
    need(type(id) == "string" and type(token) == "string",
        "DEV_REQUIRED", "Publishing needs a developer account")
    local verified, err = bank:request("DEV_VERIFY", {
        developer_id = id, developer_token = token,
    })
    need(verified, "DEV_UNKNOWN", err or "The Bank could not confirm you")
    return { developer_id = id, name = verified.name }
end

-- Foxy ships with this server, so a fresh world has something to download
-- before anybody has written an app. It is first party: no developer owns it,
-- so nobody can overwrite or delete it from a PUMPE.
local function seedShippedApps()
    for _, shipped in ipairs({
        { file = "foxy.lua", id = "FOXY", name = "Foxy",
          description = "Your Foxy Account and the bank behind it." },
        { file = "buckapp.lua", id = "BUCK", name = "BuckApp",
          description = "A bank of its own. Needs a 3rd Party Bank Server." },
        { file = "revolution.lua", id = "REVO", name = "Revolution",
          description = "0% fee proximity pay. One hour to clear." },
    }) do
        local body = util.readFile(fs.combine(ROOT, shipped.file))
        local existing = state.apps[shipped.id]
        local sum = body and util.checksum(body) or nil
        if body and (not existing or existing.checksum ~= sum) then
            if not fs.exists(appsDir) then fs.makeDir(appsDir) end
            util.writeFile(appPath(shipped.id), body)
            state.apps[shipped.id] = {
                app_id = shipped.id,
                name = shipped.name,
                description = shipped.description,
                author = "PUMPE",
                developer_id = "PUMPE",
                version = (existing and (existing.version or 0) or 0) + 1,
                size = #body,
                checksum = sum,
                published_day = util.ingameDay(),
                downloads = existing and existing.downloads or 0,
                bank_name = declaredBank(body),
                clearing_hours = select(1, declaredTerms(body)),
                fee_rate = select(2, declaredTerms(body)),
            }
            if not existing then
                table.insert(state.order, 1, shipped.id)
            end
            logActivity(shipped.name .. " v"
                .. state.apps[shipped.id].version .. " seeded", colors.cyan)
        end
    end
    save()
end

local actions = {}

-- A 3rd Party Bank Server asks for this, so it can show which banks it
-- could host.
function actions.APP_BANKS()
    return { apps = catalogue(true) }
end

function actions.APP_LIST()
    return { apps = catalogue(), server_version = config.version }
end

function actions.APP_INFO(payload)
    local app = state.apps[payload and payload.app_id]
    need(app, "NOT_FOUND", "That app is not here")
    return { app = publicApp(app) }
end

-- Downloads go out in chunks, the same shape Easy Deployment uses, so a big
-- app never blocks the loop.
function actions.APP_CHUNK(payload)
    local app = state.apps[payload and payload.app_id]
    need(app, "NOT_FOUND", "That app is not here")
    local body = appBody(app.app_id)
    need(body, "MISSING_FILE", "That app's file is missing")
    local offset = math.max(0, math.floor(tonumber(payload.offset) or 0))
    local limit = math.min(
        math.max(1, math.floor(tonumber(payload.limit) or 0)),
        tonumber(config.app_chunk_size) or 6000)
    local data = body:sub(offset + 1, offset + limit)
    if offset == 0 then
        app.downloads = (app.downloads or 0) + 1
        save()
    end
    return {
        app_id = app.app_id,
        offset = offset,
        data = data,
        next_offset = offset + #data,
        total_size = #body,
        done = offset + #data >= #body,
    }
end

function actions.APP_PUBLISH(payload)
    local developer = requireDeveloper(payload)
    local name = util.safeText(util.trim(payload.name or ""), 18)
    need(#name >= 2, "INVALID_NAME", "Give the app a name")
    local description = util.safeText(util.trim(payload.description or ""), 80)
    local body = payload.body
    need(type(body) == "string" and #body > 0, "EMPTY_APP",
        "That app file is empty")
    need(#body <= (tonumber(config.max_app_bytes) or 96 * 1024),
        "APP_TOO_BIG", "That app is larger than the network allows")
    -- Every app is a file returning one function. Refusing anything else here
    -- keeps a broken upload from reaching a PUMPE at all.
    local loader = load(body, "app")
    need(loader, "APP_INVALID", "That file is not valid Lua")

    local appId = payload.app_id and state.apps[payload.app_id]
        and payload.app_id or nil
    if appId then
        need(state.apps[appId].developer_id == developer.developer_id,
            "NOT_YOURS", "That app belongs to another developer")
    else
        state.sequence = state.sequence + 1
        appId = string.format("APP%05d", state.sequence)
        state.order[#state.order + 1] = appId
    end
    local existing = state.apps[appId]
    state.apps[appId] = {
        app_id = appId,
        name = name,
        description = description,
        author = developer.name,
        developer_id = developer.developer_id,
        version = (existing and (existing.version or 0) or 0) + 1,
        size = #body,
        checksum = util.checksum(body),
        published_day = util.ingameDay(),
        downloads = existing and existing.downloads or 0,
        bank_name = declaredBank(body),
        clearing_hours = select(1, declaredTerms(body)),
        fee_rate = select(2, declaredTerms(body)),
    }
    if not fs.exists(appsDir) then fs.makeDir(appsDir) end
    util.writeFile(appPath(appId), body)
    save()
    -- Publishing is the one moment anybody knows both the app id and the
    -- developer behind it, so it is where the Bank is told who to pay for
    -- anything the app sells.
    local linked = bank:request("APP_OWNER_SET", {
        app_id = appId, app_name = name,
        developer_id = payload.developer_id,
        developer_token = payload.developer_token,
    }, 5)
    if not linked then
        -- The app is published either way, but nobody can be paid for what
        -- it sells until this lands. Publishing again re-tries it.
        logActivity("Bank did not record who owns " .. name
            .. " -- publish again", colors.orange)
    end
    logActivity((existing and "Updated " or "Published ") .. name
        .. " by " .. developer.name, colors.lime)
    return { app = publicApp(state.apps[appId]) }
end

function actions.APP_DELETE(payload)
    local developer = requireDeveloper(payload)
    local app = state.apps[payload.app_id]
    need(app, "NOT_FOUND", "That app is not here")
    need(app.developer_id == developer.developer_id, "NOT_YOURS",
        "That app belongs to another developer")
    state.apps[app.app_id] = nil
    for index = #state.order, 1, -1 do
        if state.order[index] == app.app_id then
            table.remove(state.order, index)
        end
    end
    if fs.exists(appPath(app.app_id)) then pcall(fs.delete, appPath(app.app_id)) end
    save()
    logActivity("Removed " .. app.name, colors.orange)
    return { removed = app.app_id }
end

local function route(sender, message)
    if type(message) ~= "table" or message.kind ~= "request"
        or type(message.action) ~= "string" then return end
    local handler = actions[message.action]
    if not handler then
        net.reply(sender, config.app_protocol, message.request_id, false, nil,
            "Unknown app action", "UNKNOWN_ACTION")
        return
    end
    local ok, result = pcall(handler, message.payload or {}, sender)
    if ok then
        net.reply(sender, config.app_protocol, message.request_id, true, result)
    elseif type(result) == "table" and result.pumpe then
        net.reply(sender, config.app_protocol, message.request_id, false, nil,
            result.message, result.code)
    else
        logActivity("Error: " .. tostring(result), colors.red)
        net.reply(sender, config.app_protocol, message.request_id, false, nil,
            "App server error", "SERVER_ERROR")
    end
end

local function serverLoop()
    while running do
        local sender, message = rednet.receive(config.app_protocol, 2)
        if sender then route(sender, message) end
    end
end

local function updateLoop()
    while running do
        net.autoUpdate(config, "apps", ROOT, nil,
            { programVersion = PROGRAM_VERSION })
        sleep(10)
    end
end

local function dashboardLoop()
    local blink = true
    while running do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "PUMPE APP SERVER", "v" .. config.version,
            util.formatClock(blink))
        local downloads = 0
        for _, app in pairs(state.apps) do
            downloads = downloads + (app.downloads or 0)
        end
        local cardWidth = math.floor((width - 3) / 2)
        ui.card(target, 2, 5, cardWidth, 4, ui.theme.accent)
        ui.text(target, 4, 6, "APPS", ui.theme.muted, ui.theme.panel)
        ui.text(target, 4, 7, tostring(#state.order), ui.theme.ink,
            ui.theme.panel, cardWidth - 3)
        ui.card(target, 3 + cardWidth, 5, width - cardWidth - 3, 4,
            ui.theme.success)
        ui.text(target, 5 + cardWidth, 6, "DOWNLOADS", ui.theme.muted,
            ui.theme.panel)
        ui.text(target, 5 + cardWidth, 7, tostring(downloads), ui.theme.ink,
            ui.theme.panel, width - cardWidth - 6)

        ui.text(target, 2, 10, "CATALOGUE", ui.theme.muted)
        local row = 11
        for _, appId in ipairs(state.order) do
            local app = state.apps[appId]
            if app and row <= height - 6 then
                ui.text(target, 2, row,
                    ui.truncate(app.name .. "  v" .. app.version
                        .. "  by " .. app.author, width - 3), ui.theme.ink)
                row = row + 1
            end
        end
        if #state.order == 0 then
            ui.text(target, 2, 11, "Nothing published yet", ui.theme.muted)
        end
        ui.text(target, 2, height - 4, "ACTIVITY", ui.theme.muted)
        for index = 1, math.min(#activity, 2) do
            local item = activity[index]
            ui.text(target, 2, height - 4 + index,
                item.time .. "  " .. ui.truncate(item.text, width - 10),
                item.color)
        end
        local scene = ui.scene(target)
        scene:button("stop", width - 9, height, 8, 1, "STOP",
            { background = ui.theme.danger })
        local action = scene:wait({ tickRate = 0.5, flash = false })
        blink = not blink
        if action == "stop" or action == "__terminate" then
            if ui.confirm(target, "STOP APP SERVER",
                "PUMPEs will not be able to download apps.",
                "STOP", "BACK") then
                running = false
                save()
                return
            end
        end
    end
end

if rawget(_G, "PUMPE_TEST_MODE") == true then
    return { actions = actions, state = state }
end

ui.boot(target, "PUMPE APPS", "APP SERVER v" .. config.version)
net.autoUpdate(config, "apps", ROOT, nil,
    { force = true, programVersion = PROGRAM_VERSION })
net.host(config.app_protocol, config.app_hostname)
if not fs.exists(appsDir) then fs.makeDir(appsDir) end
seedShippedApps()
bank:discover()
logActivity("App Server online on #" .. os.getComputerID(), colors.lime)
save()

parallel.waitForAny(serverLoop, updateLoop, dashboardLoop)
pcall(rednet.unhost, config.app_protocol)
ui.clear(target)
print("PUMPE App Server stopped.")
