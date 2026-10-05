local ROOT = fs.getDir(shell.getRunningProgram())
if ROOT == "" then ROOT = "." end
package.path = package.path .. ";" .. fs.combine(ROOT, "?.lua")
    .. ";" .. fs.combine(ROOT, "?/init.lua")

-- Stamped by tools/build_release_manifest.js. A program running beside a
-- config.lua from a different release means a partial install.
local PROGRAM_VERSION = "14.5.0"
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
    while #activity > 16 do table.remove(activity) end
end

local state = util.loadTable(dataFile, { apps = {}, order = {}, sequence = 0 })
state.apps = state.apps or {}
state.order = state.order or {}
state.sequence = state.sequence or 0

-- FoxyOS 14.1, for the App Browser's front page in 15: when each app first
-- appeared here ("added", a running number, so Latest is the newest apps
-- rather than whichever was updated last) and its downloads per in-game day
-- ("trending" is the last week of them). Apps that were already here get
-- numbered once, oldest first by the day they were last published.
local catalogueStats = { days = 7 }
state.added_seq = state.added_seq or 0
do
    local unnumbered = {}
    for index, appId in ipairs(state.order) do
        local app = state.apps[appId]
        if app and app.added == nil then
            unnumbered[#unnumbered + 1] = { app = app, index = index }
        end
    end
    table.sort(unnumbered, function(a, b)
        local dayA, dayB = a.app.published_day or 0, b.app.published_day or 0
        if dayA ~= dayB then return dayA < dayB end
        return a.index < b.index
    end)
    for _, entry in ipairs(unnumbered) do
        state.added_seq = state.added_seq + 1
        entry.app.added = state.added_seq
    end
end

function catalogueStats.stamp()
    state.added_seq = (state.added_seq or 0) + 1
    return state.added_seq
end

function catalogueStats.download(app)
    local today = util.ingameDay()
    app.daily = type(app.daily) == "table" and app.daily or {}
    app.daily[today] = (app.daily[today] or 0) + 1
    for day in pairs(app.daily) do
        if day <= today - catalogueStats.days then app.daily[day] = nil end
    end
end

function catalogueStats.trending(app)
    local today, total = util.ingameDay(), 0
    for day, count in pairs(type(app.daily) == "table" and app.daily or {}) do
        if day > today - catalogueStats.days then total = total + count end
    end
    return total
end

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
        -- 12.0 Final: an app is for the PUMPE, a game for a CCG in Home Mode.
        kind = app.kind or "app",
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
        added = app.added,
        trending = catalogueStats.trending(app),
    }
end

-- `kind` is "app" or "game". A PUMPE from before 12.0 Final asks for no
-- kind and is given apps, which is all it can run.
local function catalogue(banksOnly, kind)
    kind = kind == "game" and "game" or "app"
    local list = {}
    for _, appId in ipairs(state.order) do
        local app = state.apps[appId]
        if app and (app.kind or "app") == kind and (not banksOnly or app.bank_name) then
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
-- Every one of these has to be in this role's list of files in lib/update
-- as well, or the App Server never downloads it and has nothing to seed.
-- That is how FoxMail went missing from App Browsers in 11.0.
local SHIPPED = {
    { file = "foxy.lua", id = "FOXY", name = "Foxy",
      description = "Your Foxy Account and the bank behind it." },
    { file = "buckapp.lua", id = "BUCK", name = "BuckApp",
      description = "A bank of its own. Needs a 3rd Party Bank Server." },
    { file = "revolution.lua", id = "REVO", name = "Revolution",
      description = "0% fee proximity pay. One hour to clear." },
    -- The web, new in 10.0. Both ship here so a fresh world has
    -- something to publish with and something to read with.
    { file = "wc.lua", id = "WC", name = "Website Crafter",
      description = "Write a website and put it on the network." },
    { file = "internet.lua", id = "NET", name = "Internet",
      description = "Read the web. Type a domain and go." },
    -- New in 10.2: stores to order from, and the deliveries on the way.
    { file = "shop.lua", id = "SHOP", name = "Shop",
      description = "Order from stores. Home delivery or pickup." },
    -- 11.0. Every PUMPE fetches it on sign-in, like Foxy.
    { file = "foxmail.lua", id = "MAIL", name = "FoxMail",
      description = "Email for people, companies and apps." },
    -- 11.1. Starting and running companies, and Delivery Mode.
    { file = "company.lua", id = "COMPANY", name = "Company",
      description = "Start and run companies. Delivery Mode." },
    -- 12.0 Final: a game, for the CCG's Game Browser in Home Mode -- and the
    -- example for anybody writing one.
    { file = "brickbreaker.lua", id = "BRICKS", name = "Brick Breaker",
      description = "Bounce the ball, break the wall.", kind = "game" },
    -- FoxyOS 14: invitations and small events, made by Foxy.
    { file = "invt.lua", id = "INVT", name = "INVT", author = "Foxy",
      description = "Invite friends. Small events, one price, no queue." },
}

local function seedShippedApps()
    for _, shipped in ipairs(SHIPPED) do
        local body = util.readFile(fs.combine(ROOT, shipped.file))
        local existing = state.apps[shipped.id]
        local sum = body and util.checksum(body) or nil
        if body and (not existing or existing.checksum ~= sum) then
            if not fs.exists(appsDir) then fs.makeDir(appsDir) end
            util.writeFile(appPath(shipped.id), body)
            state.apps[shipped.id] = {
                app_id = shipped.id,
                kind = shipped.kind or "app",
                name = shipped.name,
                description = shipped.description,
                author = shipped.author or "FoxyOS",
                developer_id = "PUMPE",
                version = (existing and (existing.version or 0) or 0) + 1,
                size = #body,
                checksum = sum,
                published_day = util.ingameDay(),
                downloads = existing and existing.downloads or 0,
                added = existing and existing.added or catalogueStats.stamp(),
                daily = existing and existing.daily or nil,
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

-- Shop Apps, FoxyOS 14 ---------------------------------------------------------------
-- A store turns one on from its Store page in the Company app; the Bank keeps
-- the list. Each is built here from the Shop app, locked to its store, and
-- listed like any other app, under the company's name. It is rebuilt when
-- the Shop app or the store's app changes, so a store's app is never behind.
local shopApps = { every = 30 }

function shopApps.body(entry, shopBody)
    return "-- PUMPE APP: " .. entry.name .. "\n"
        .. "-- PUMPE APP ACTION: store | " .. entry.name .. " | Shop at "
        .. entry.company_name .. "\n"
        .. "-- A Shop App: " .. entry.company_name .. "'s store, built from Shop.\n"
        .. "local shop = (function()\n" .. shopBody .. "\nend)()\n"
        .. "return function(api)\n"
        .. "    api.shop_store = " .. string.format("%q", entry.company_id) .. "\n"
        .. "    return shop(api)\n"
        .. "end\n"
end

function shopApps.sync()
    local listed = bank:request("SHOP_APPS", {}, 4)
    local shopBody = util.readFile(fs.combine(ROOT, "shop.lua"))
    if not listed or not shopBody then return false end
    -- The Shop app's own header lines would make every store's app offer
    -- Shop's actions too.
    shopBody = shopBody:gsub("%-%-%s*PUMPE [^\n]*", "")
    local wanted = {}
    for _, entry in ipairs(listed.apps or {}) do
        local appId = "SA-" .. tostring(entry.company_id)
        wanted[appId] = true
        local body = shopApps.body(entry, shopBody)
        local sum = util.checksum(body)
        local existing = state.apps[appId]
        local description = entry.description ~= "" and entry.description
            or ("Shop at " .. entry.company_name)
        if not existing or existing.checksum ~= sum
            or existing.description ~= description then
            if not fs.exists(appsDir) then fs.makeDir(appsDir) end
            util.writeFile(appPath(appId), body)
            state.apps[appId] = {
                app_id = appId, kind = "app", name = entry.name,
                description = description, author = entry.company_name,
                developer_id = "SHOPAPP", shop_app = entry.company_id,
                version = (existing and (existing.version or 0) or 0) + 1,
                size = #body, checksum = sum, published_day = util.ingameDay(),
                downloads = existing and existing.downloads or 0,
                added = existing and existing.added or catalogueStats.stamp(),
                daily = existing and existing.daily or nil,
            }
            if not existing then table.insert(state.order, appId) end
            logActivity("Shop App " .. entry.name .. " v"
                .. state.apps[appId].version, colors.lime)
        end
    end
    -- A store that took its app down: gone from the catalogue.
    for index = #state.order, 1, -1 do
        local appId = state.order[index]
        local app = state.apps[appId]
        if app and app.shop_app and not wanted[appId] then
            state.apps[appId] = nil
            table.remove(state.order, index)
            if fs.exists(appPath(appId)) then fs.delete(appPath(appId)) end
            logActivity("Shop App taken down: " .. app.name, colors.orange)
        end
    end
    save()
    return true
end

local actions = {}

-- A 3rd Party Bank Server asks for this, so it can show which banks it
-- could host.
function actions.APP_BANKS()
    return { apps = catalogue(true, "app") }
end

function actions.APP_LIST(payload)
    local kind = payload and payload.kind
    return { apps = catalogue(false, kind), kind = kind == "game" and "game" or "app",
        server_version = config.version }
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
        catalogueStats.download(app)
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
    -- What it is is chosen once, when it is first published: an app does not
    -- turn into a game on the PUMPEs that already have it.
    local kind = existing and (existing.kind or "app")
        or (payload.kind == "game" and "game" or "app")
    state.apps[appId] = {
        app_id = appId,
        kind = kind,
        name = name,
        description = description,
        author = developer.name,
        developer_id = developer.developer_id,
        version = (existing and (existing.version or 0) or 0) + 1,
        size = #body,
        checksum = util.checksum(body),
        published_day = util.ingameDay(),
        downloads = existing and existing.downloads or 0,
        added = existing and existing.added or catalogueStats.stamp(),
        daily = existing and existing.daily or nil,
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
    logActivity((existing and "Updated " or "Published ") .. (kind == "game"
        and "game " or "") .. name .. " by " .. developer.name, colors.lime)
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
    local waited = 0
    while running do
        net.autoUpdate(config, "apps", ROOT, nil,
            { programVersion = PROGRAM_VERSION })
        -- FoxyOS 14: and which stores have an app of their own.
        if waited <= 0 then
            pcall(shopApps.sync)
            waited = shopApps.every
        end
        sleep(10)
        waited = waited - 10
    end
end

-- 12.0: Status, Activity and Server tabs, as on every server.
local function dashboardLoop()
    ui.serverTabs({
        target = target, title = "APP SERVER", subtitle = "v" .. config.version,
        cards = function()
            local downloads, games = 0, 0
            for _, app in pairs(state.apps) do
                downloads = downloads + (app.downloads or 0)
                if app.kind == "game" then games = games + 1 end
            end
            return { { "APPS", #state.order - games, ui.theme.accent },
                { "GAMES", games, colors.magenta },
                { "DOWNLOADS", downloads, ui.theme.success } }
        end,
        lines = function()
            local lines = { { "CATALOGUE", ui.theme.muted } }
            for _, appId in ipairs(state.order) do
                local app = state.apps[appId]
                if app then
                    lines[#lines + 1] = { (app.kind == "game" and "GAME  " or "")
                        .. app.name .. "  v" .. app.version .. "  by " .. app.author }
                end
            end
            if #state.order == 0 then
                lines[#lines + 1] = { "Nothing published yet", ui.theme.muted }
            end
            return lines
        end,
        activity = activity, root = ROOT, colorTitle = "Server colour",
        actions = { { id = "stop", label = "STOP", hint = "Pockets stop downloading apps",
            color = ui.theme.danger, run = function()
                if ui.confirm(target, "STOP APP SERVER",
                    "Pockets will not be able to download apps.", "STOP", "BACK") then
                    running = false
                    save()
                    return true
                end
            end } },
        running = function() return running end,
    })
end

if rawget(_G, "PUMPE_TEST_MODE") == true then
    return { actions = actions, state = state, shipped = SHIPPED,
        seed = seedShippedApps, sync_shop_apps = shopApps.sync,
        set_bank = function(client) bank = client end }
end

-- 12.0: this server's main colour, orange unless its owner chose one.
if type(ui.useMainColor) == "function" then ui.useMainColor(ROOT) end
ui.boot(target, "APP SERVER", (ui.osLabel and ui.osLabel(config) or "FoxyOS"))
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
print("App Server stopped.")
