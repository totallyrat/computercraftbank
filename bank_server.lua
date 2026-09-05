local ROOT = fs.getDir(shell.getRunningProgram())
if ROOT == "" then ROOT = "." end
package.path = package.path .. ";" .. fs.combine(ROOT, "?.lua")
    .. ";" .. fs.combine(ROOT, "?/init.lua")

-- Stamped by tools/build_release_manifest.js. A program running beside a
-- config.lua from a different release means a partial install.
local PROGRAM_VERSION = "8.1.2"
local config = require("config")
local util = require("lib.util")
local net = require("lib.net")
local ui = require("lib.ui")
local onlineUpdate = require("lib.update")
local TEST_MODE = rawget(_G, "PUMPE_TEST_MODE") == true

local UPDATES_DIR = "/updates"

-- Grouped rather than declared one by one. Lua allows 200 locals per
-- function and this file's top level is one function; 8.0.0 crossed the line
-- and the Bank would not load at all. tests/host_bank_restart_test.lua now
-- fails long before that happens again.
local DEPLOY = {
    protocol = "PUMPE_DEPLOY_V5",
    hostname = "PUMPE_UPDATES",
    code = "4040",
    chunk = 6000,
    restart_marker = fs.combine(ROOT, ".bank_auto_restart"),
    legacy_installer = fs.combine(ROOT, ".easy_deployment_source.lua"),
    role_marker = "-- PUMPE ROLE STARTUP",
    installer_marker = "-- PUMPE EASY DEPLOYMENT",
    cache_stamp = fs.combine("/updates", ".cache_version"),
}
local RELEASE = {}
RELEASE.local_files = {
    "bank_server.lua",
    "pumpe.lua",
    "service_kiosk.lua",
    "event_kiosk.lua",
    "tax_controller.lua",
    "admin_terminal.lua",
    "border_controller.lua",
    "ccg.lua",
    "gps_anchor.lua",
    "startup.lua",
    "config.lua",
    "lib/net.lua",
    "lib/ui.lua",
    "lib/update.lua",
    "lib/util.lua",
}

-- Only role-specific programs need physical copies in /updates. The Bank's
-- own program, installer, configuration, and shared libraries are served
-- directly from ROOT, avoiding a second copy of the largest runtime files.
RELEASE.depot_files = {
    "pumpe.lua",
    "service_kiosk.lua",
    "event_kiosk.lua",
    "tax_controller.lua",
    "admin_terminal.lua",
    "border_controller.lua",
    "ccg.lua",
    "gps_anchor.lua",
}
RELEASE.depot_set = {}
for _, path in ipairs(RELEASE.depot_files) do RELEASE.depot_set[path] = true end

-- Keep this list compatible with v5.2.1, whose updater rejects unknown
-- entries in the manifest's `files` array. Everything added since then is
-- published in `extra_files`, which older updaters simply ignore.
-- Written out rather than read from lib/update.lua. A Bank whose updater is
-- older than its program would otherwise get nil here, and a Bank that
-- cannot name what it expects is a Bank that cannot update itself out of the
-- skew. host_update_test.lua checks the two lists still agree.
RELEASE.published = {
    "bank_server.lua",
    "pumpe.lua",
    "service_kiosk.lua",
    "event_kiosk.lua",
    "tax_controller.lua",
    "startup.lua",
    "launcher.lua",
    "config.lua",
    "lib/net.lua",
    "lib/ui.lua",
    "lib/update.lua",
    "lib/util.lua",
}

RELEASE.optional = {
    "border_controller.lua",
    "ccg.lua",
    "gps_anchor.lua",
    "admin_terminal.lua",
}

RELEASE.programs = {
    bank = "bank_server.lua",
    pumpe = "pumpe.lua",
    service = "service_kiosk.lua",
    event = "event_kiosk.lua",
    tax = "tax_controller.lua",
    admin = "admin_terminal.lua",
    border = "border_controller.lua",
    ccg = "ccg.lua",
    anchor = "gps_anchor.lua",
}

-- lib/update.lua is included for every role: without it a client cannot load
-- the self-updater and is stuck on the Bank fallback forever.
RELEASE.common = {
    { path = "installer.lua", source = "startup.lua" },
    { path = "lib/net.lua", source = "lib/net.lua" },
    { path = "lib/ui.lua", source = "lib/ui.lua" },
    { path = "lib/update.lua", source = "lib/update.lua" },
    { path = "lib/util.lua", source = "lib/util.lua" },
}

local function protectedDeployRole(role)
    return role == "bank" or role == "tax" or role == "admin"
end

local function deploymentFilesForRole(role)
    local mainFile = RELEASE.programs[role]
    if not mainFile then return nil end
    local files = {
        {
            path = "config.lua",
            source = protectedDeployRole(role)
                and "config.lua" or "public/config.lua",
        },
    }
    for _, file in ipairs(RELEASE.common) do
        files[#files + 1] = { path = file.path, source = file.source }
    end
    files[#files + 1] = { path = mainFile, source = mainFile }
    return files
end

-- The dashboard feed. Declared up here because the depot bootstrap runs at
-- load time and logs to it: a Bank whose cached programs went stale used to
-- reach a logActivity that had not been defined yet and die on the spot.
local activity = {}

local function logActivity(text, color)
    table.insert(activity, 1, {
        text = util.safeText(text, 42),
        color = color or colors.lightGray,
        time = util.formatClock(),
    })
    while #activity > 8 do table.remove(activity) end
end

-- /updates holds cached role programs. They belong to whichever release the
-- Bank was running when it fetched them, so a version change makes every one
-- of them stale: serving one beside the new config.lua hands a client a new
-- program next to an old library, or an old program next to a new config.
local function dropStaleDepotCache()
    if util.readFile(DEPLOY.cache_stamp) == tostring(config.version) then return 0 end
    local dropped = 0
    for _, path in ipairs(RELEASE.depot_files) do
        local cached = fs.combine(UPDATES_DIR, path)
        if fs.exists(cached) and not fs.isDir(cached) then
            pcall(fs.delete, cached)
            dropped = dropped + 1
        end
    end
    pcall(util.writeFile, DEPLOY.cache_stamp, tostring(config.version))
    return dropped
end

local function writePublicDeployConfig()
    local publicConfig = util.copy(config)
    publicConfig.government_key = "CLIENT-NO-GOVERNMENT-ACCESS"
    local path = fs.combine(UPDATES_DIR, "public/config.lua")
    local directory = fs.getDir(path)
    if not fs.exists(directory) then fs.makeDir(directory) end
    util.writeFile(path, "-- Generated by the PUMPE Bank Server.\nreturn "
        .. textutils.serialize(publicConfig, { compact = false }) .. "\n")
end

local function localUpdateBody(path)
    if path == "public/config.lua" then
        return util.readFile(fs.combine(UPDATES_DIR, path))
    end
    if path == "startup.lua" then
        local candidates = {
            fs.combine(ROOT, "installer.lua"),
            fs.combine(ROOT, "startup.lua"),
            DEPLOY.legacy_installer,
        }
        for _, candidate in ipairs(candidates) do
            local body = util.readFile(candidate)
            if body and body:find("This file is intentionally standalone", 1, true) then
                return body
            end
        end
        return nil
    end

    local candidates = RELEASE.depot_set[path] and {
        fs.combine(UPDATES_DIR, path),
        fs.combine(ROOT, path),
    } or {
        fs.combine(ROOT, path),
    }
    for _, candidate in ipairs(candidates) do
        local body = util.readFile(candidate)
        if body then return body end
    end
    return nil
end

local function cacheInstaller(body)
    body = body or localUpdateBody("startup.lua")
    if body and body:find("This file is intentionally standalone", 1, true) then
        util.writeFile(fs.combine(ROOT, "installer.lua"), body)
        if fs.exists(DEPLOY.legacy_installer) then
            pcall(fs.delete, DEPLOY.legacy_installer)
        end
        return body
    end
    return nil
end

local function absoluteRootFile(path)
    local combined = fs.combine(ROOT, path)
    combined = combined:gsub("^%./", "")
    if combined:sub(1, 1) ~= "/" then combined = "/" .. combined end
    return combined
end

local function ensureBankStartup(installerBody)
    installerBody = cacheInstaller(installerBody)
    local startupPath = "/startup.lua"
    local existing = util.readFile(startupPath)
    local owned = not existing
        or existing:find(DEPLOY.installer_marker, 1, true)
        or existing:find(DEPLOY.role_marker, 1, true)
        or existing:find("This file is intentionally standalone", 1, true)
    if not owned then
        return false, "Existing non-PUMPE /startup.lua was preserved"
    end
    local body = DEPLOY.role_marker .. "\n"
        .. "shell.run(" .. string.format("%q", absoluteRootFile("installer.lua"))
        .. ", \"--boot\", \"bank\")\n"
    util.writeFile(startupPath, body)
    return true
end

local function ensureParent(path)
    local directory = fs.getDir(path)
    if directory ~= "" and not fs.exists(directory) then fs.makeDir(directory) end
end

local function replaceWithMove(source, destination, body)
    ensureParent(destination)
    if fs.exists(destination) then fs.delete(destination) end
    local moved = pcall(fs.move, source, destination)
    if moved then return true end
    local ok = pcall(util.writeFile, destination, body)
    if ok and util.readFile(destination) == body then
        pcall(fs.delete, source)
        return true
    end
    return false
end

local function compactBankStorage()
    if not fs.exists(UPDATES_DIR) then fs.makeDir(UPDATES_DIR) end
    local available = 0

    -- Newer role programs replace the depot copy by moving, not copying.
    -- Legacy Banks with identical copies simply discard the ROOT duplicate.
    for _, path in ipairs(RELEASE.depot_files) do
        local rootPath = fs.combine(ROOT, path)
        local depotPath = fs.combine(UPDATES_DIR, path)
        local rootBody = util.readFile(rootPath)
        if rootBody then
            if util.readFile(depotPath) == rootBody then
                pcall(fs.delete, rootPath)
            else
                replaceWithMove(rootPath, depotPath, rootBody)
            end
        end
        if localUpdateBody(path) then available = available + 1 end
    end

    -- Remove the v6.0 duplicate depot copies now served from the live runtime.
    for _, path in ipairs(RELEASE.local_files) do
        if not RELEASE.depot_set[path] and localUpdateBody(path) then
            local duplicate = fs.combine(UPDATES_DIR, path)
            if fs.exists(duplicate) then pcall(fs.delete, duplicate) end
            available = available + 1
        end
    end
    local duplicateInstaller = fs.combine(UPDATES_DIR, "installer.lua")
    if fs.exists(duplicateInstaller) then pcall(fs.delete, duplicateInstaller) end
    local legacyLauncher = fs.combine(ROOT, "launcher.lua")
    if fs.exists(legacyLauncher) then pcall(fs.delete, legacyLauncher) end

    local redundantStartup = absoluteRootFile("startup.lua")
    if redundantStartup ~= "/startup.lua" and fs.exists(redundantStartup)
        and localUpdateBody("startup.lua") then
        pcall(fs.delete, redundantStartup)
    end
    if fs.exists(DEPLOY.legacy_installer) then
        pcall(fs.delete, DEPLOY.legacy_installer)
    end

    -- A power loss during an older update must not reserve disk forever.
    for _, stale in ipairs({
        fs.combine(ROOT, ".online_update_stage"),
        fs.combine(ROOT, ".online_update_backup"),
    }) do
        if fs.exists(stale) then pcall(fs.delete, stale) end
    end
    return available
end

-- Only the Bank's own runtime has to be present. Role programs are fetched
-- from the public manifest the first time a client installs one.
local function updateDepotMissingFiles()
    local missing = {}
    for _, path in ipairs(RELEASE.local_files) do
        if not RELEASE.depot_set[path] and not localUpdateBody(path) then
            missing[#missing + 1] = path .. " (local source)"
        end
    end
    local publicConfig = fs.combine(UPDATES_DIR, "public/config.lua")
    if not fs.exists(publicConfig) or fs.isDir(publicConfig) then
        missing[#missing + 1] = "public/config.lua"
    end
    return missing
end

local function renderUpdateBootstrap(created, staged, missing)
    local target = term.current()
    local width, height = target.getSize()
    ui.clear(target)
    ui.header(target, "EASY DEPLOYMENT SETUP", "/updates/")
    ui.text(target, 2, 5, created and "UPDATE DEPOT CREATED" or "UPDATE DEPOT CHECK",
        created and ui.theme.success or ui.theme.accent)
    ui.text(target, 2, 7, "Synced locally: " .. staged .. "/" .. #RELEASE.local_files,
        ui.theme.ink)
    if #missing == 0 then
        ui.text(target, 2, 9, "All deployment files are ready.", ui.theme.success)
        ui.text(target, 2, 11, "Restart once to enable installer downloads.",
            ui.theme.muted)
    else
        ui.text(target, 2, 9, "Missing " .. #missing .. " required file(s):",
            ui.theme.danger)
        local visible = math.max(1, height - 14)
        for index = 1, math.min(#missing, visible) do
            ui.text(target, 4, 10 + index, ui.truncate(missing[index], width - 6),
                ui.theme.warning)
        end
        ui.text(target, 2, height - 3,
            "Add them beside bank_server.lua, then rescan.", ui.theme.muted)
    end
    local scene = ui.scene(target)
    if #missing == 0 then
        scene:button("restart", 2, height - 1, 15, 1, "RESTART NOW",
            { background = ui.theme.success, foreground = colors.black })
    else
        scene:button("rescan", 2, height - 1, 12, 1, "RESCAN",
            { background = ui.theme.accentDark })
    end
    scene:button("shutdown", width - 11, height - 1, 10, 1, "SHUTDOWN",
        { background = ui.theme.danger })
    return scene
end

local function bootstrapUpdateDepot()
    if fs.exists(UPDATES_DIR) and not fs.isDir(UPDATES_DIR) then
        ui.clear(term.current())
        ui.header(term.current(), "DEPLOYMENT BLOCKED", "/updates is not a folder")
        ui.text(term.current(), 2, 6, "Rename or remove the /updates file.", ui.theme.danger)
        ui.text(term.current(), 2, 8, "The Bank Server needs /updates/ as a directory.",
            ui.theme.muted)
        sleep(3)
        error("/updates must be a directory")
    end

    local automaticRestart = fs.exists(DEPLOY.restart_marker)
    local created = not fs.exists(UPDATES_DIR)
    if created then
        fs.makeDir(UPDATES_DIR)
    end

    local staged = compactBankStorage()
    local dropped = dropStaleDepotCache()
    if dropped > 0 then
        logActivity("Dropped " .. dropped .. " stale cached program(s)",
            colors.orange)
    end
    writePublicDeployConfig()
    local missing = updateDepotMissingFiles()
    if automaticRestart then
        fs.delete(DEPLOY.restart_marker)
        ensureBankStartup()
        return
    end
    if #missing == 0 then
        ensureBankStartup()
        return
    end

    while true do
        local scene = renderUpdateBootstrap(created, staged, missing)
        local bootstrapKeys = {}
        if type(keys) == "table" and type(keys.enter) == "number" then
            bootstrapKeys[keys.enter] = #missing == 0 and "restart" or "rescan"
        end
        local action = scene:wait({
            keys = bootstrapKeys,
        })
        if action == "restart" and #missing == 0 then
            ensureBankStartup()
            os.reboot()
        elseif action == "rescan" then
            staged = compactBankStorage()
            writePublicDeployConfig()
            missing = updateDepotMissingFiles()
        elseif action == "shutdown" or action == "__terminate" then
            os.shutdown()
        end
    end
end

if not TEST_MODE then bootstrapUpdateDepot() end

local DATA_FILE = fs.combine(ROOT, config.data_file)
local sessions = {}
local governmentSessions = {}
local betSessions = {}
local running = true
local BANK_BOOT_ID = util.token("BANK_BOOT")

local function blankState()
    return {
        schema = 8,
        created_at = util.nowMs(),
        sequence = {
            account = 0, company = 0, terminal = 0, event = 0,
            ticket_type = 0, ticket = 0, transaction = 0,
            period = 0, notification = 0, subscription = 0,
            territory = 0, visa = 0,
            visa_application = 0, visit = 0, border = 0,
            bet_hold = 0, bet_activity = 0,
            ccg_console = 0, ccg_lobby = 0,
            conversation = 0, proximity = 0, announcement = 0,
        },
        accounts = {},
        account_names = {},
        companies = {},
        terminals = {},
        events = {},
        ticket_types = {},
        tickets = {},
        transactions = {},
        declaration_periods = {},
        declarations = {},
        active_pay_codes = {},
        territories = {},
        territory_names = {},
        visas = {},
        visa_codes = {},
        visa_applications = {},
        visits = {},
        border_controllers = {},
        ccg_consoles = {},
        ccg_lobbies = {},
        ccg_codes = {},
        ccg_house_profit = 0,
        conversations = {},
        direct_conversations = {},
        proximity_offers = {},
        announcements = {},
        settings = { account_approval = false },
        tax_revenue = 0,
        processing_fee_revenue = 0,
        last_subscription_day = -1,
    }
end

local state = util.loadTable(DATA_FILE, blankState())

local function ensureState()
    local defaults = blankState()
    for key, value in pairs(defaults) do
        if state[key] == nil then state[key] = util.copy(value) end
    end
    for key, value in pairs(defaults.sequence) do
        if state.sequence[key] == nil then state.sequence[key] = value end
    end
    -- Proximity Pay was removed in v5.4; erase its legacy transient state.
    state.payment_requests = nil
    state.gps_devices = nil
    state.sequence.request = nil
    state.account_names = state.account_names or {}
    for _, account in pairs(state.accounts) do
        account.notifications = account.notifications or {}
        account.subscriptions = account.subscriptions or {}
        account.daily_spent = account.daily_spent or 0
        account.daily_sent = account.daily_sent or 0
        account.last_spent_day = account.last_spent_day or util.ingameDay()
        account.bet_wallet = account.bet_wallet or {
            balance = 0,
            holds = {},
            activity = {},
        }
        account.bet_wallet.balance = util.roundMoney(
            account.bet_wallet.balance or 0) or 0
        account.bet_wallet.holds = account.bet_wallet.holds or {}
        account.bet_wallet.activity = account.bet_wallet.activity or {}
        account.friends = account.friends or {}
        account.friend_requests_in = account.friend_requests_in or {}
        account.friend_requests_out = account.friend_requests_out or {}
        account.conversation_ids = account.conversation_ids or {}
        if account.name then
            state.account_names[util.normalName(account.name)] = account.account_id
        end
    end
    for _, terminal in pairs(state.terminals) do
        terminal.balance = terminal.balance or 0
        terminal.sales_total = terminal.sales_total or 0
        terminal.quick_items = terminal.quick_items or {}
        for _, item in ipairs(terminal.quick_items) do
            item.kind = item.kind == "subscription"
                and "subscription" or "one_time"
            item.favorite = item.favorite == true
        end
        terminal.status = terminal.status or "active"
    end
    for _, company in pairs(state.companies) do
        company.quick_items = company.quick_items or {}
        for _, item in ipairs(company.quick_items) do
            item.kind = item.kind == "subscription"
                and "subscription" or "one_time"
            item.favorite = item.favorite == true
        end
        company.linked_terminal_ids = company.linked_terminal_ids or {}
        company.status = company.status or "active"
    end
    for _, event in pairs(state.events) do
        event.ticket_type_ids = event.ticket_type_ids or {}
        event.status = event.status or "active"
    end
    state.schema = 8
    state.territory_names = {}
    for territoryId, territory in pairs(state.territories) do
        territory.territory_id = territory.territory_id or territoryId
        territory.citizen_account_ids = territory.citizen_account_ids or {}
        territory.free_roam_territory_ids =
            territory.free_roam_territory_ids or {}
        territory.status = territory.status or "active"
        if territory.name then
            state.territory_names[util.normalName(territory.name)] =
                territory.territory_id
        end
    end
    state.visa_codes = {}
    for visaId, document in pairs(state.visas) do
        document.visa_id = document.visa_id or visaId
        document.status = document.status or
            (document.kind == "citizenship" and "active" or "issued")
        if document.code then
            document.code = string.upper(util.trim(document.code))
            state.visa_codes[document.code] = document.visa_id
        end
    end
    for applicationId, application in pairs(state.visa_applications) do
        application.application_id =
            application.application_id or applicationId
        application.status = application.status or "pending"
    end
    for visitId, visit in pairs(state.visits) do
        visit.visit_id = visit.visit_id or visitId
        visit.status = visit.status or "visiting"
        local document = visit.visa_id and state.visas[visit.visa_id]
        if document and document.kind == "visa"
            and (visit.status == "visiting" or visit.status == "overdue") then
            document.status = visit.status
        end
    end
    for controllerId, controller in pairs(state.border_controllers) do
        controller.controller_id = controller.controller_id or controllerId
        controller.status = controller.status or "active"
    end
    state.ccg_codes = {}
    for consoleId, console in pairs(state.ccg_consoles) do
        console.console_id = console.console_id or consoleId
        console.status = console.status or "active"
    end
    for lobbyId, lobby in pairs(state.ccg_lobbies) do
        lobby.lobby_id = lobby.lobby_id or lobbyId
        lobby.players = lobby.players or {}
        lobby.player_order = lobby.player_order or {}
        if lobby.code and (lobby.status == "lobby"
            or lobby.status == "running") then
            state.ccg_codes[string.upper(lobby.code)] = lobby.lobby_id
        end
    end
end

ensureState()

local function save()
    util.saveTable(DATA_FILE, state)
end

local function reject(code, message)
    error({ pumpe = true, code = code, message = message }, 0)
end

local function need(condition, code, message)
    if not condition then reject(code, message) end
end

local prefixes = {
    account = { "ACC", 6 },
    company = { "CMP", 6 },
    terminal = { "TERM", 5 },
    event = { "EVT", 6 },
    ticket_type = { "TT", 6 },
    ticket = { "TICK", 10 },
    transaction = { "TX", 10 },
    period = { "PER", 6 },
    notification = { "NOT", 8 },
    subscription = { "SUB", 8 },
    request = { "REQ", 8 },
    territory = { "TER", 6 },
    visa = { "VISA", 8 },
    visa_application = { "VAPP", 8 },
    visit = { "VISIT", 8 },
    border = { "BORDER", 6 },
    bet_hold = { "HOLD", 10 },
    bet_activity = { "BACT", 10 },
    ccg_console = { "CCG", 6 },
    ccg_lobby = { "GAME", 8 },
    conversation = { "CHAT", 8 },
    proximity = { "NEAR", 8 },
    announcement = { "ANN", 8 },
}

local function nextId(kind)
    state.sequence[kind] = (state.sequence[kind] or 0) + 1
    local format = prefixes[kind]
    return format[1] .. string.format("%0" .. format[2] .. "d", state.sequence[kind])
end

local function accountByName(name)
    local id = state.account_names[util.normalName(name)]
    return id and state.accounts[id] or nil
end

local function publicAccount(account)
    return {
        account_id = account.account_id,
        name = account.name,
        gender = account.gender,
        balance = account.balance,
        personal_number = account.personal_number,
        card_id = account.card_id,
        frozen = account.frozen,
        smart_declaration_lifetime = account.smart_declaration_lifetime,
        daily_spent = account.daily_spent,
        daily_sent = account.daily_sent,
    }
end

local function resetDailySpend(account)
    local day = util.ingameDay()
    if account.last_spent_day ~= day then
        account.last_spent_day = day
        account.daily_spent = 0
        account.daily_sent = 0
    end
end

local function verifyAccount(account, pin)
    return account and account.pin_hash == util.hashPin(pin)
end

local function checkAccountActive(account)
    need(account, "ACCOUNT_NOT_FOUND", "Account not found")
    need(not account.banned, "ACCOUNT_BANNED", "This account is banned")
    need(account.approved ~= false, "ACCOUNT_PENDING",
        "This account is waiting for government approval")
    need(not account.frozen, "ACCOUNT_FROZEN", "This account is frozen")
end

local function createSession(account)
    local token = util.token("SESSION")
    sessions[token] = {
        account_id = account.account_id,
        expires_at = util.nowMs() + config.session_ttl_ms,
    }
    return token
end

local function requireSession(payload)
    local session = sessions[payload and payload.session_token]
    need(session and session.expires_at > util.nowMs(),
        "SESSION_EXPIRED", "Please sign in again")
    local account = state.accounts[session.account_id]
    checkAccountActive(account)
    resetDailySpend(account)
    return account
end

local function requireTerminal(payload)
    local terminal = state.terminals[payload and payload.terminal_id]
    need(terminal and terminal.auth_token == payload.terminal_token,
        "TERMINAL_AUTH", "Kiosk is not registered")
    need(terminal.status == "active", "TERMINAL_INACTIVE", "Kiosk is inactive")
    terminal.last_seen = util.nowMs()
    return terminal
end

local function requireBorderController(payload)
    local controller =
        state.border_controllers[payload and payload.controller_id]
    need(controller and controller.auth_token == payload.controller_token,
        "BORDER_AUTH", "Border Controller is not registered")
    need(controller.status == "active",
        "BORDER_INACTIVE", "Border Controller is inactive")
    controller.last_seen = util.nowMs()
    return controller
end

local function requireGovernment(payload)
    local session = governmentSessions[payload and payload.government_token]
    need(session and session.expires_at > util.nowMs(),
        "GOVERNMENT_AUTH", "Government session expired")
    session.expires_at = util.nowMs() + config.session_ttl_ms
    return session
end

local function createBetSession(account)
    local token = util.token("BET")
    betSessions[token] = {
        account_id = account.account_id,
        expires_at = util.nowMs()
            + (tonumber(config.bet_access_ttl_ms) or 15 * 60 * 1000),
    }
    return token
end

local function requireBetSession(payload)
    local token = payload and payload.bet_token
    local session = betSessions[token]
    need(session and session.expires_at > util.nowMs(),
        "BET_SESSION_EXPIRED", "Unlock the Bet app with your PIN again")
    local account = state.accounts[session.account_id]
    checkAccountActive(account)
    session.expires_at = util.nowMs()
        + (tonumber(config.bet_access_ttl_ms) or 15 * 60 * 1000)
    return account
end

local function requireCCGConsole(payload)
    local console = state.ccg_consoles[payload and payload.console_id]
    need(console and console.auth_token == payload.console_token,
        "CCG_AUTH", "CCG console is not registered")
    need(console.status == "active", "CCG_INACTIVE", "CCG console is inactive")
    console.last_seen = util.nowMs()
    return console
end

local function notification(account, title, body, kind)
    local item = {
        notification_id = nextId("notification"),
        title = util.safeText(title, 40),
        body = util.safeText(body, 120),
        kind = kind or "info",
        created_day = util.ingameDay(),
        created_time = util.formatClock(),
        read = false,
    }
    table.insert(account.notifications, 1, item)
    while #account.notifications > 50 do table.remove(account.notifications) end
    return item
end

local function mapCount(map)
    local count = 0
    for _ in pairs(map or {}) do count = count + 1 end
    return count
end

local function territoryOwner(account, territoryId)
    local territory = state.territories[territoryId]
    need(territory and territory.status == "active",
        "TERRITORY_NOT_FOUND", "Territory not found")
    need(territory.owner_account_id == account.account_id,
        "NOT_TERRITORY_OWNER", "You do not control that territory")
    return territory
end

local function newVisaCode()
    local code
    repeat
        code = util.randomString(8, "ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    until not state.visa_codes[code]
    return code
end

local function matchingDocument(accountId, territoryId, kind)
    for _, document in pairs(state.visas) do
        if document.account_id == accountId
            and document.territory_id == territoryId
            and (not kind or document.kind == kind)
            and document.status ~= "revoked"
            and document.status ~= "expired"
            and document.status ~= "used" then
            return document
        end
    end
    return nil
end

local function issueDocument(account, territory, kind, options)
    options = options or {}
    local existing = matchingDocument(
        account.account_id, territory.territory_id, kind)
    if existing then return nil, existing end
    local visaId = nextId("visa")
    local document = {
        visa_id = visaId,
        code = newVisaCode(),
        account_id = account.account_id,
        territory_id = territory.territory_id,
        kind = kind,
        duration_days = kind == "visa"
            and math.floor(tonumber(options.duration_days) or 1) or nil,
        status = kind == "citizenship" and "active" or "issued",
        issued_day = util.ingameDay(),
        issued_by_account_id = options.issued_by_account_id,
        application_id = options.application_id,
    }
    state.visas[visaId] = document
    state.visa_codes[document.code] = visaId
    if kind == "citizenship" then
        territory.citizen_account_ids[account.account_id] = true
    end
    return document
end

local function openVisit(accountId, territoryId, visaId)
    local newest
    for _, visit in pairs(state.visits) do
        if visit.account_id == accountId
            and visit.territory_id == territoryId
            and (not visaId or visit.visa_id == visaId)
            and (visit.status == "visiting" or visit.status == "overdue")
            and (not newest
                or (visit.entered_at or 0) > (newest.entered_at or 0)) then
            newest = visit
        end
    end
    return newest
end

local function publicVisit(visit)
    if not visit then return nil end
    local remaining
    if visit.due_day then
        remaining = math.max(0, visit.due_day - util.ingameDay() + 1)
    end
    return {
        visit_id = visit.visit_id,
        territory_id = visit.territory_id,
        territory_name = state.territories[visit.territory_id]
            and state.territories[visit.territory_id].name or "Unknown",
        authorization = visit.authorization,
        entered_day = visit.entered_day,
        due_day = visit.due_day,
        remaining_days = remaining,
        permanent = visit.due_day == nil,
        status = visit.status,
    }
end

local function publicDocument(document)
    local territory = state.territories[document.territory_id]
    local freeRoam = {}
    if document.kind == "citizenship" then
        for _, destination in pairs(state.territories) do
            if destination.status == "active"
                and destination.territory_id ~= document.territory_id
                and destination.free_roam_territory_ids[
                    document.territory_id] then
                freeRoam[#freeRoam + 1] = {
                    territory_id = destination.territory_id,
                    territory_name = destination.name,
                }
            end
        end
        table.sort(freeRoam, function(a, b)
            return a.territory_name < b.territory_name
        end)
    end
    local visits = {}
    for _, visit in pairs(state.visits) do
        if visit.account_id == document.account_id
            and visit.visa_id == document.visa_id
            and (visit.status == "visiting" or visit.status == "overdue") then
            visits[#visits + 1] = publicVisit(visit)
        end
    end
    table.sort(visits, function(a, b)
        return (a.entered_day or 0) > (b.entered_day or 0)
    end)
    return {
        visa_id = document.visa_id,
        code = document.code,
        kind = document.kind,
        territory_id = document.territory_id,
        territory_name = territory and territory.name or "Unknown",
        duration_days = document.duration_days,
        permanent = document.kind == "citizenship",
        status = document.status,
        issued_day = document.issued_day,
        free_roam = freeRoam,
        visits = visits,
    }
end

local function publicApplication(application)
    local territory = state.territories[application.territory_id]
    local applicant = state.accounts[application.account_id]
    return {
        application_id = application.application_id,
        territory_id = application.territory_id,
        territory_name = territory and territory.name or "Unknown",
        applicant_name = applicant and applicant.name or "Unknown",
        requested_days = application.requested_days,
        status = application.status,
        created_day = application.created_day,
        reviewed_day = application.reviewed_day,
        visa_id = application.visa_id,
    }
end

local function accessForAccount(accountId, destination)
    local temporary
    for _, document in pairs(state.visas) do
        if document.account_id == accountId
            and document.status ~= "revoked"
            and document.status ~= "expired"
            and document.status ~= "used" then
            if document.kind == "citizenship"
                and document.territory_id == destination.territory_id then
                return "citizenship", document
            elseif document.kind == "citizenship"
                and destination.free_roam_territory_ids[
                    document.territory_id] then
                return "free_roam", document
            elseif document.kind == "visa"
                and document.territory_id == destination.territory_id then
                temporary = document
            end
        end
    end
    if temporary then return "visa", temporary end
    return nil
end

local function pendingApplication(accountId, territoryId)
    for _, application in pairs(state.visa_applications) do
        if application.account_id == accountId
            and application.territory_id == territoryId
            and application.status == "pending" then
            return application
        end
    end
    return nil
end

local function transaction(account, kind, amount, counterparty, description, extra)
    local item = {
        tx_id = nextId("transaction"),
        account_id = account and account.account_id or nil,
        type = kind,
        amount = util.roundMoney(amount) or 0,
        counterparty = util.safeText(counterparty, 40),
        description = util.safeText(description, 100),
        company_id = extra and extra.company_id or nil,
        terminal_id = extra and extra.terminal_id or nil,
        tax_amount = extra and extra.tax_amount or 0,
        day = util.ingameDay(),
        time = util.formatClock(),
        timestamp = util.nowMs(),
    }
    table.insert(state.transactions, item)
    while #state.transactions > 3000 do table.remove(state.transactions, 1) end
    return item
end

local function companyOwner(terminal)
    local company = terminal.company_id and state.companies[terminal.company_id] or nil
    local owner = company and state.accounts[company.owner_account_id] or nil
    return company, owner
end

local function merchantBalance(terminal)
    local _, owner = companyOwner(terminal)
    return owner and owner.balance or terminal.balance
end

local function creditMerchant(terminal, amount, description, payer)
    local company, owner = companyOwner(terminal)
    if owner then
        owner.balance = util.roundMoney(owner.balance + amount)
        transaction(owner, "merchant_credit", amount,
            payer and payer.name or terminal.name, description, {
                company_id = company.company_id,
                terminal_id = terminal.terminal_id,
            })
        notification(owner, "Sale received", util.money(amount, config.currency)
            .. " via " .. terminal.name, "money")
    else
        terminal.balance = util.roundMoney(terminal.balance + amount)
    end
    terminal.sales_total = util.roundMoney((terminal.sales_total or 0) + amount)
end

local function debitMerchant(terminal, amount, description, recipient)
    local company, owner = companyOwner(terminal)
    if owner then
        need(owner.balance >= amount, "INSUFFICIENT_FUNDS",
            "Merchant balance is too low")
        owner.balance = util.roundMoney(owner.balance - amount)
        transaction(owner, "merchant_debit", -amount,
            recipient and recipient.name or terminal.name, description, {
                company_id = company.company_id,
                terminal_id = terminal.terminal_id,
            })
    else
        need(terminal.balance >= amount, "INSUFFICIENT_FUNDS",
            "Kiosk balance is too low")
        terminal.balance = util.roundMoney(terminal.balance - amount)
    end
end

local function quickItems(terminal)
    local company = terminal.company_id and state.companies[terminal.company_id]
    return company and company.quick_items or terminal.quick_items
end

local function cleanupEphemeral()
    local now = util.nowMs()
    local travelChanged = false
    for code, payment in pairs(state.active_pay_codes) do
        if payment.expires_at <= now and payment.status == "pending" then
            payment.status = "expired"
        elseif payment.expires_at + 10 * 60 * 1000 < now then
            state.active_pay_codes[code] = nil
        end
    end
    for token, session in pairs(sessions) do
        if session.expires_at <= now then sessions[token] = nil end
    end
    for token, session in pairs(governmentSessions) do
        if session.expires_at <= now then governmentSessions[token] = nil end
    end
    for token, session in pairs(betSessions) do
        if session.expires_at <= now then betSessions[token] = nil end
    end
    local today = util.ingameDay()
    for _, visit in pairs(state.visits) do
        if visit.status == "visiting" and visit.due_day
            and visit.due_day < today then
            visit.status = "overdue"
            local document = state.visas[visit.visa_id]
            if document and document.kind == "visa" then
                document.status = "overdue"
            end
            travelChanged = true
        end
    end
    if travelChanged then save() end
end

local function validateAmount(value, maximum)
    local amount = util.roundMoney(value)
    need(amount and amount > 0, "INVALID_AMOUNT", "Enter an amount above zero")
    need(not maximum or amount <= maximum, "INVALID_AMOUNT",
        "Amount is above the allowed maximum")
    return amount
end

local actions = {}

function actions.PING()
    return {
        version = config.version,
        day = util.ingameDay(),
        time = util.formatClock(),
    }
end

function actions.REGISTER(payload)
    local name = util.safeText(util.trim(payload.name), 20)
    need(name:match("^[%w_ %-]+$") and #name >= 2,
        "INVALID_NAME", "Use 2-20 letters, numbers, spaces, _ or -")
    need(not accountByName(name), "NAME_TAKEN", "That account name is taken")
    need(util.validPin(payload.pin), "INVALID_PIN", "PIN must be four digits")

    local accountId = nextId("account")
    local personalNumber
    repeat personalNumber = util.randomString(5, "0123456789")
        local duplicate = false
        for _, existing in pairs(state.accounts) do
            if existing.personal_number == personalNumber then duplicate = true break end
        end
    until not duplicate

    local account = {
        account_id = accountId,
        name = name,
        pin_hash = util.hashPin(payload.pin),
        gender = util.safeText(payload.gender or "Not set", 20),
        balance = config.starting_balance,
        personal_number = personalNumber,
        card_id = "PUMPE_" .. accountId,
        frozen = false,
        banned = false,
        smart_declaration_lifetime = false,
        subscriptions = {},
        notifications = {},
        bet_wallet = { balance = 0, holds = {}, activity = {} },
        daily_spent = 0,
        daily_sent = 0,
        last_spent_day = util.ingameDay(),
        created_day = util.ingameDay(),
    }
    if state.settings and state.settings.account_approval == true then
        account.approved = false
    end
    state.accounts[accountId] = account
    state.account_names[util.normalName(name)] = accountId
    notification(account, "Welcome to your Foxy Account",
        "Your PUMPE starts with " .. util.money(config.starting_balance, config.currency),
        "success")
    transaction(account, "opening_credit", config.starting_balance,
        "PUMPE Bank", "Starting balance")
    save()
    logActivity("New account: " .. name, colors.lime)
    return { account = publicAccount(account), session_token = createSession(account) }
end

function actions.LOGIN(payload)
    local account = accountByName(payload.name)
    need(verifyAccount(account, payload.pin), "BAD_LOGIN", "Name or PIN is incorrect")
    checkAccountActive(account)
    resetDailySpend(account)
    logActivity("Login: " .. account.name, colors.cyan)
    return { account = publicAccount(account), session_token = createSession(account) }
end

-- Assigned by the social section further down, which needs helpers defined
-- after this route. The home screen badges come from one summary call.
local socialBadges

function actions.ACCOUNT_SUMMARY(payload)
    local account = requireSession(payload)
    local unread = 0
    for _, item in ipairs(account.notifications) do
        if not item.read then unread = unread + 1 end
    end
    local badges = socialBadges and socialBadges(account) or {}
    return {
        account = publicAccount(account),
        unread_notifications = unread,
        unread_messages = badges.messages or 0,
        friend_requests = badges.friend_requests or 0,
        friend_count = badges.friends or 0,
        day = util.ingameDay(),
        time = util.formatClock(),
    }
end

local function buildSendMoneyQuote(sender, payload)
    local recipient = accountByName(payload.recipient)
    checkAccountActive(recipient)
    need(recipient.account_id ~= sender.account_id,
        "INVALID_RECIPIENT", "You cannot send money to yourself")
    local amount = validateAmount(payload.amount)
    local breakdown = util.transferBreakdown(amount, config.send_money_fee_rate)
    local dailyLimit = tonumber(config.send_money_daily_limit) or 2000
    local withinLimit, dailyRemaining = util.dailyLimitRemaining(
        sender.daily_sent, breakdown.amount, dailyLimit)
    need(withinLimit,
        "SEND_LIMIT_REACHED", "Your daily Send Money limit is "
            .. util.money(dailyLimit, config.currency))
    need(sender.balance >= breakdown.total,
        "INSUFFICIENT_FUNDS", "Not enough money including the processing fee")
    return {
        recipient_account = recipient,
        recipient = recipient.name,
        amount = breakdown.amount,
        fee = breakdown.fee,
        total = breakdown.total,
        daily_limit = dailyLimit,
        daily_remaining = dailyRemaining,
    }
end

function actions.SEND_MONEY_QUOTE(payload)
    local sender = requireSession(payload)
    local quote = buildSendMoneyQuote(sender, payload)
    quote.recipient_account = nil
    return quote
end

-- One transfer path for PUMPE Pay, Messages, and Urgent Contact, so the 10%
-- processing fee, the daily limit, and the transaction log can never differ
-- between them.
local function performTransfer(sender, recipientName, amount, description)
    local quote = buildSendMoneyQuote(sender, {
        recipient = recipientName,
        amount = amount,
    })
    local recipient = quote.recipient_account
    sender.balance = util.roundMoney(sender.balance - quote.total)
    recipient.balance = util.roundMoney(recipient.balance + quote.amount)
    sender.daily_spent = util.roundMoney(sender.daily_spent + quote.total)
    sender.daily_sent = util.roundMoney(sender.daily_sent + quote.amount)
    state.processing_fee_revenue = util.roundMoney(
        state.processing_fee_revenue + quote.fee)
    transaction(sender, "transfer_out", -quote.amount, recipient.name,
        description or "Money sent")
    if quote.fee > 0 then
        transaction(sender, "processing_fee", -quote.fee, "PUMPE",
            "Send Money processing fee")
    end
    transaction(recipient, "transfer_in", quote.amount, sender.name,
        description or "Money received")
    notification(recipient, "Money received",
        sender.name .. " sent you " .. util.money(quote.amount, config.currency), "money")
    save()
    logActivity("Transfer " .. util.money(quote.amount, config.currency)
        .. " " .. sender.name .. " > " .. recipient.name, colors.lime)
    quote.recipient_account = nil
    quote.balance = sender.balance
    return quote, recipient
end

function actions.SEND_MONEY(payload)
    local sender = requireSession(payload)
    need(verifyAccount(sender, payload.pin), "BAD_PIN", "Incorrect PIN")
    return (performTransfer(sender, payload.recipient, payload.amount,
        payload.description))
end

function actions.HISTORY(payload)
    local account = requireSession(payload)
    local output = {}
    for index = #state.transactions, 1, -1 do
        local item = state.transactions[index]
        if item.account_id == account.account_id then
            output[#output + 1] = util.copy(item)
            if #output >= 50 then break end
        end
    end
    return { transactions = output }
end

function actions.NOTIFICATIONS(payload)
    local account = requireSession(payload)
    return { notifications = util.copy(account.notifications) }
end

function actions.MARK_NOTIFICATIONS_READ(payload)
    local account = requireSession(payload)
    for _, item in ipairs(account.notifications) do item.read = true end
    save()
    return { ok = true }
end

function actions.LIST_SUBSCRIPTIONS(payload)
    local account = requireSession(payload)
    local output = util.sortedValues(account.subscriptions, nil, function(a, b)
        if a.active ~= b.active then return a.active end
        return a.next_charge_day < b.next_charge_day
    end)
    return { subscriptions = util.copy(output) }
end

function actions.CANCEL_SUBSCRIPTION(payload)
    local account = requireSession(payload)
    local subscription = account.subscriptions[payload.subscription_id]
    need(subscription and subscription.active, "NOT_FOUND", "Subscription not found")
    subscription.active = false
    subscription.cancelled_day = util.ingameDay()
    save()
    return { subscription = util.copy(subscription) }
end

-- ComputerCraftGaming / Bet Wallet routes ---------------------------------

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

local function walletFor(account)
    account.bet_wallet = account.bet_wallet or {
        balance = 0,
        holds = {},
        activity = {},
    }
    account.bet_wallet.balance = util.roundMoney(
        account.bet_wallet.balance or 0) or 0
    account.bet_wallet.holds = account.bet_wallet.holds or {}
    account.bet_wallet.activity = account.bet_wallet.activity or {}
    return account.bet_wallet
end

local function betActivity(account, kind, amount, description, extra)
    local wallet = walletFor(account)
    local item = {
        activity_id = nextId("bet_activity"),
        type = kind,
        amount = util.roundMoney(amount) or 0,
        description = util.safeText(description, 80),
        game = extra and extra.game or nil,
        lobby_code = extra and extra.lobby_code or nil,
        day = util.ingameDay(),
        time = util.formatClock(),
        timestamp = util.nowMs(),
    }
    table.insert(wallet.activity, 1, item)
    while #wallet.activity > 60 do table.remove(wallet.activity) end
    return item
end

local function releaseAccountBetHolds(account)
    local wallet = walletFor(account)
    local released = 0
    local nowMoment = util.ingameMoment()
    for _, hold in pairs(wallet.holds) do
        local releaseMoment = tonumber(hold.release_moment)
        if not releaseMoment and hold.release_day then
            releaseMoment = tonumber(hold.release_day) * 24
        end
        if hold.status == "holding" and releaseMoment
            and nowMoment >= releaseMoment then
            hold.status = "released"
            hold.released_day = util.ingameDay()
            hold.released_time = util.formatClock()
            wallet.balance = util.roundMoney(wallet.balance + hold.amount)
            released = released + hold.amount
            betActivity(account, "winnings_released", hold.amount,
                (hold.game_name or "CCG") .. " winnings released", {
                    game = hold.game,
                    lobby_code = hold.lobby_code,
                })
        end
    end
    if released > 0 then
        notification(account, "Bet Wallet funds released",
            util.money(released, config.currency)
                .. " is now available in your Bet Wallet", "gaming")
    end
    return util.roundMoney(released)
end

local function processBetHolds()
    local changed = false
    for _, account in pairs(state.accounts) do
        if releaseAccountBetHolds(account) > 0 then changed = true end
    end
    if changed then save() end
    return changed
end

local function betWalletSnapshot(account)
    local wallet = walletFor(account)
    local holds = util.sortedValues(wallet.holds, nil, function(a, b)
        return (a.created_at or 0) > (b.created_at or 0)
    end)
    local pending, pendingCount = 0, 0
    for _, hold in ipairs(holds) do
        if hold.status == "holding" then
            pending = util.roundMoney(pending + hold.amount)
            pendingCount = pendingCount + 1
        end
    end
    return {
        available = wallet.balance,
        held = pending,
        hold_count = pendingCount,
        holds = util.copy(holds),
        activity = util.copy(wallet.activity),
    }
end

local function addBetHold(account, lobby, amount)
    local wallet = walletFor(account)
    local releaseMoment = util.ingameMoment()
        + (tonumber(config.bet_hold_ingame_hours) or 24)
    local releaseDay, releaseTime = util.formatIngameMoment(releaseMoment)
    local holdId = nextId("bet_hold")
    local hold = {
        hold_id = holdId,
        amount = util.roundMoney(amount),
        status = "holding",
        game = lobby.game,
        game_name = CCG_GAMES[lobby.game].name,
        lobby_code = lobby.code,
        created_day = util.ingameDay(),
        created_time = util.formatClock(),
        created_at = util.nowMs(),
        release_moment = releaseMoment,
        release_day = releaseDay,
        release_time = releaseTime,
    }
    wallet.holds[holdId] = hold
    betActivity(account, "winnings_held", hold.amount,
        hold.game_name .. " winnings - holding", {
            game = lobby.game,
            lobby_code = lobby.code,
        })
    return hold
end

local function uniqueCCGCode()
    local code
    repeat code = util.randomString(6, "ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    until not state.ccg_codes[code]
    return code
end

local function lobbyByCode(code)
    code = string.upper(util.trim(code))
    local lobbyId = state.ccg_codes[code]
    return lobbyId and state.ccg_lobbies[lobbyId] or nil
end

local function publicCCGPlayer(player)
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

local function publicCCGLobby(lobby, revealOutcome)
    local players = {}
    for _, accountId in ipairs(lobby.player_order or {}) do
        local player = lobby.players[accountId]
        if player then players[#players + 1] = publicCCGPlayer(player) end
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

local function refundLobby(lobby, reason)
    if lobby.escrow_closed then return false end
    for accountId, player in pairs(lobby.players or {}) do
        if (player.wager or 0) > 0 and not player.settled then
            local account = state.accounts[accountId]
            if account then
                local wallet = walletFor(account)
                wallet.balance = util.roundMoney(wallet.balance + player.wager)
                betActivity(account, "wager_refund", player.wager,
                    CCG_GAMES[lobby.game].name .. " wager refunded", {
                        game = lobby.game,
                        lobby_code = lobby.code,
                    })
            end
            player.settled = true
            player.refunded = true
        end
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
    local totalStakes, totalPayouts = 0, 0
    for accountId, player in pairs(lobby.players) do
        local wager = util.roundMoney(player.wager or 0) or 0
        totalStakes = util.roundMoney(totalStakes + wager)
        local account = state.accounts[accountId]
        local won = winnerIds[accountId] == true
        local payout = won and util.roundMoney(
            wager * CCG_GAMES[lobby.game].multiplier) or 0
        player.won = won
        player.payout = payout
        player.settled = true
        if account then
            if payout > 0 then
                local hold = addBetHold(account, lobby, payout)
                player.hold_id = hold.hold_id
                notification(account, "CCG win - funds holding",
                    util.money(payout, config.currency) .. " from "
                        .. CCG_GAMES[lobby.game].name
                        .. " releases on day " .. hold.release_day
                        .. " at " .. hold.release_time, "gaming")
                totalPayouts = util.roundMoney(totalPayouts + payout)
            else
                betActivity(account, "bet_lost", -wager,
                    CCG_GAMES[lobby.game].name .. " result", {
                        game = lobby.game,
                        lobby_code = lobby.code,
                    })
                notification(account, "CCG result",
                    "Your " .. CCG_GAMES[lobby.game].name
                        .. " wager did not win", "gaming")
            end
        end
    end
    state.ccg_house_profit = util.roundMoney(
        (state.ccg_house_profit or 0) + totalStakes - totalPayouts)
    lobby.escrow_closed = true
    lobby.status = "finished"
    lobby.finished_at = util.nowMs()
    logActivity("CCG settled " .. lobby.code .. " / "
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

local function processCCGGames()
    local now, changed = util.nowMs(), false
    for lobbyId, lobby in pairs(state.ccg_lobbies) do
        if lobby.status == "lobby" and lobby.expires_at <= now then
            changed = refundLobby(lobby, "Lobby expired") or changed
        elseif lobby.status == "running" then
            if lobby.game == "survivor" then
                if lobby.bank_boot_id ~= BANK_BOOT_ID then
                    changed = refundLobby(lobby,
                        "Bank restarted during Survivor") or changed
                else
                    changed = advanceSurvivor(lobby, now) or changed
                end
            elseif lobby.reveal_at and now >= lobby.reveal_at then
                changed = settleChanceLobby(lobby) or changed
            end
        elseif (lobby.status == "finished" or lobby.status == "cancelled")
            and lobby.finished_at and lobby.finished_at + 30 * 60 * 1000 < now then
            if state.ccg_codes[lobby.code] == lobbyId then
                state.ccg_codes[lobby.code] = nil
            end
            state.ccg_lobbies[lobbyId] = nil
            changed = true
        end
    end
    if changed then save() end
    return changed
end

function actions.BET_UNLOCK(payload)
    local account = requireSession(payload)
    need(verifyAccount(account, payload.pin), "BAD_PIN", "Incorrect PIN")
    releaseAccountBetHolds(account)
    save()
    return {
        bet_token = createBetSession(account),
        wallet = betWalletSnapshot(account),
    }
end

function actions.BET_WALLET_SUMMARY(payload)
    local account = requireSession(payload)
    if releaseAccountBetHolds(account) > 0 then save() end
    return { wallet = betWalletSnapshot(account) }
end

function actions.BET_WALLET_DEPOSIT(payload)
    local account = requireSession(payload)
    need(verifyAccount(account, payload.pin), "BAD_PIN", "Incorrect PIN")
    local amount = validateAmount(payload.amount, account.balance)
    local wallet = walletFor(account)
    account.balance = util.roundMoney(account.balance - amount)
    wallet.balance = util.roundMoney(wallet.balance + amount)
    transaction(account, "bet_wallet_deposit", -amount,
        "CCG Bet Wallet", "Moved to Bet Wallet")
    betActivity(account, "wallet_deposit", amount,
        "Added from Foxy Account")
    save()
    return {
        account_balance = account.balance,
        wallet = betWalletSnapshot(account),
    }
end

function actions.BET_WALLET_WITHDRAW(payload)
    local account = requireSession(payload)
    need(verifyAccount(account, payload.pin), "BAD_PIN", "Incorrect PIN")
    releaseAccountBetHolds(account)
    local wallet = walletFor(account)
    local amount = validateAmount(payload.amount, wallet.balance)
    wallet.balance = util.roundMoney(wallet.balance - amount)
    account.balance = util.roundMoney(account.balance + amount)
    transaction(account, "bet_wallet_withdrawal", amount,
        "CCG Bet Wallet", "Moved from Bet Wallet")
    betActivity(account, "wallet_withdrawal", -amount,
        "Sent to Foxy Account")
    save()
    return {
        account_balance = account.balance,
        wallet = betWalletSnapshot(account),
    }
end

function actions.CCG_REGISTER(payload)
    if payload.console_id and payload.console_token then
        local existing = state.ccg_consoles[payload.console_id]
        if existing and existing.auth_token == payload.console_token then
            existing.last_seen = util.nowMs()
            return {
                console_id = existing.console_id,
                console_token = existing.auth_token,
                name = existing.name,
            }
        end
    end
    local consoleId = nextId("ccg_console")
    local console = {
        console_id = consoleId,
        auth_token = util.token("CCG_CONSOLE"),
        name = util.safeText(payload.name or ("CCG " .. consoleId), 24),
        status = "active",
        created_day = util.ingameDay(),
        last_seen = util.nowMs(),
    }
    state.ccg_consoles[consoleId] = console
    save()
    logActivity("Registered " .. console.name, colors.magenta)
    return {
        console_id = console.console_id,
        console_token = console.auth_token,
        name = console.name,
    }
end

function actions.CCG_CREATE_LOBBY(payload)
    local console = requireCCGConsole(payload)
    processCCGGames()
    local game = string.lower(util.trim(payload.game))
    need(CCG_GAMES[game], "INVALID_GAME", "Choose a supported CCG game")
    for _, lobby in pairs(state.ccg_lobbies) do
        need(lobby.console_id ~= console.console_id
            or (lobby.status ~= "lobby" and lobby.status ~= "running"),
            "LOBBY_ACTIVE", "Finish or cancel the current lobby first")
    end
    local lobbyId = nextId("ccg_lobby")
    local code = uniqueCCGCode()
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
    state.ccg_lobbies[lobbyId] = lobby
    state.ccg_codes[code] = lobbyId
    console.active_lobby_id = lobbyId
    save()
    return { lobby = publicCCGLobby(lobby, false) }
end

function actions.CCG_CONSOLE_STATUS(payload)
    local console = requireCCGConsole(payload)
    processCCGGames()
    local lobby = payload.code and lobbyByCode(payload.code)
        or (console.active_lobby_id
            and state.ccg_lobbies[console.active_lobby_id])
    need(lobby and lobby.console_id == console.console_id,
        "LOBBY_NOT_FOUND", "CCG lobby not found")
    return { lobby = publicCCGLobby(lobby, true) }
end

function actions.CCG_CANCEL_LOBBY(payload)
    local console = requireCCGConsole(payload)
    local lobby = lobbyByCode(payload.code)
    need(lobby and lobby.console_id == console.console_id,
        "LOBBY_NOT_FOUND", "CCG lobby not found")
    need(lobby.status == "lobby", "GAME_STARTED",
        "A running game cannot be cancelled")
    refundLobby(lobby, "Cancelled by console")
    save()
    return { lobby = publicCCGLobby(lobby, false) }
end

function actions.BET_JOIN(payload)
    local account = requireBetSession(payload)
    processCCGGames()
    local lobby = lobbyByCode(payload.code)
    need(lobby and lobby.status == "lobby"
        and lobby.expires_at > util.nowMs(),
        "LOBBY_NOT_FOUND", "Lobby code is invalid or closed")
    local displayName = util.safeText(util.trim(payload.display_name), 14)
    need(#displayName >= 2 and displayName:match("^[%w_ %-]+$"),
        "INVALID_NAME", "Use 2-14 letters, numbers, spaces, _ or -")
    for otherId, other in pairs(lobby.players) do
        need(otherId == account.account_id
            or util.normalName(other.display_name) ~= util.normalName(displayName),
            "NAME_TAKEN", "That player name is already in this lobby")
    end
    local player = lobby.players[account.account_id]
    if not player then
        need(#lobby.player_order < CCG_GAMES[lobby.game].maximum_players,
            "LOBBY_FULL", "This lobby is full")
        player = {
            account_id = account.account_id,
            seat = #lobby.player_order + 1,
            display_name = displayName,
            wager = 0,
            joined_at = util.nowMs(),
        }
        lobby.players[account.account_id] = player
        lobby.player_order[#lobby.player_order + 1] = account.account_id
    elseif (player.wager or 0) == 0 then
        player.display_name = displayName
    end
    save()
    return {
        lobby = publicCCGLobby(lobby, false),
        player = publicCCGPlayer(player),
    }
end

local function validRaceSelection(selection)
    for _, value in ipairs(RACE_COLORS) do
        if selection == value then return true end
    end
    return false
end

function actions.BET_PLACE_WAGER(payload)
    local account = requireBetSession(payload)
    local lobby = lobbyByCode(payload.code)
    need(lobby and lobby.status == "lobby",
        "LOBBY_CLOSED", "Betting is closed for this lobby")
    local player = lobby.players[account.account_id]
    need(player, "NOT_JOINED", "Join the lobby before placing a wager")
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
    local amount = validateAmount(payload.amount,
        tonumber(config.bet_maximum) or 10000)
    need(amount >= (tonumber(config.bet_minimum) or 1),
        "INVALID_AMOUNT", "Wager is below the minimum")
    local wallet = walletFor(account)
    local previous = util.roundMoney(player.wager or 0) or 0
    need(wallet.balance + previous >= amount,
        "INSUFFICIENT_BET_FUNDS", "Not enough available in your Bet Wallet")
    if previous > 0 then
        wallet.balance = util.roundMoney(wallet.balance + previous)
        betActivity(account, "wager_changed", previous,
            "Previous wager returned", {
                game = lobby.game,
                lobby_code = lobby.code,
            })
    end
    wallet.balance = util.roundMoney(wallet.balance - amount)
    player.wager = amount
    player.selection = selection
    player.ready_at = util.nowMs()
    betActivity(account, "wager_reserved", -amount,
        CCG_GAMES[lobby.game].name .. " wager reserved", {
            game = lobby.game,
            lobby_code = lobby.code,
        })
    save()
    return {
        lobby = publicCCGLobby(lobby, false),
        player = publicCCGPlayer(player),
        wallet = betWalletSnapshot(account),
    }
end

function actions.BET_LEAVE(payload)
    local account = requireBetSession(payload)
    local lobby = lobbyByCode(payload.code)
    need(lobby and lobby.status == "lobby",
        "GAME_STARTED", "You cannot leave after the game starts")
    local player = lobby.players[account.account_id]
    need(player, "NOT_JOINED", "You are not in this lobby")
    if (player.wager or 0) > 0 then
        local wallet = walletFor(account)
        wallet.balance = util.roundMoney(wallet.balance + player.wager)
        betActivity(account, "wager_refund", player.wager,
            CCG_GAMES[lobby.game].name .. " lobby left", {
                game = lobby.game,
                lobby_code = lobby.code,
            })
    end
    lobby.players[account.account_id] = nil
    for index, accountId in ipairs(lobby.player_order) do
        if accountId == account.account_id then
            table.remove(lobby.player_order, index)
            break
        end
    end
    for index, accountId in ipairs(lobby.player_order) do
        lobby.players[accountId].seat = index
    end
    save()
    return { wallet = betWalletSnapshot(account), left = true }
end

function actions.BET_LOBBY_STATUS(payload)
    local account = requireBetSession(payload)
    processCCGGames()
    local lobby = lobbyByCode(payload.code)
    need(lobby, "LOBBY_NOT_FOUND", "CCG lobby not found")
    local player = lobby.players[account.account_id]
    need(player, "NOT_JOINED", "You are not in this lobby")
    return {
        lobby = publicCCGLobby(lobby, false),
        player = publicCCGPlayer(player),
        wallet = betWalletSnapshot(account),
    }
end

function actions.BET_CONTROL(payload)
    local account = requireBetSession(payload)
    local lobby = lobbyByCode(payload.code)
    need(lobby and lobby.status == "running" and lobby.game == "survivor",
        "NOT_INTERACTIVE", "Survivor is not running")
    local player = lobby.players[account.account_id]
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
    local console = requireCCGConsole(payload)
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
    -- Seed the server RNG even when this is a restored console and no new
    -- account/token has been created since the Bank Server restarted.
    util.randomString(1)
    lobby.status = "running"
    lobby.started_at = util.nowMs()
    lobby.bank_boot_id = BANK_BOOT_ID
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
    logActivity("CCG started " .. lobby.code .. " / "
        .. CCG_GAMES[lobby.game].name, colors.cyan)
    return { lobby = publicCCGLobby(lobby, true) }
end

function actions.CCG_TICK(payload)
    local console = requireCCGConsole(payload)
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
    return { lobby = publicCCGLobby(lobby, true) }
end

-- Friends, Messages, and Urgent Contact ------------------------------------
-- Conversations are persistent; urgent calls are deliberately not. A Bank
-- restart drops a live call the way a dropped connection would, and only a
-- transcript both people agreed to save reaches the database.

local SOCIAL = { max_group = 8, max_message = 160 }
-- Conversations are the first PUMPE feature that grows the database on its
-- own. At 160 characters plus metadata a message costs roughly 260 bytes, so
-- this cap keeps even a busy account well inside a ComputerCraft computer.
SOCIAL.max_conversation = 60
SOCIAL.ring_ms = 30 * 1000
SOCIAL.idle_ms = 10 * 60 * 1000
local urgentCalls = {}

local function socialAccount(account)
    account.friends = account.friends or {}
    account.friend_requests_in = account.friend_requests_in or {}
    account.friend_requests_out = account.friend_requests_out or {}
    account.conversation_ids = account.conversation_ids or {}
    return account
end

local function areFriends(account, other)
    return socialAccount(account).friends[other.account_id] == true
end

local function requireFriend(account, accountId)
    local other = state.accounts[accountId]
    checkAccountActive(other)
    need(areFriends(account, other), "NOT_FRIENDS",
        "You can only do that with a friend")
    return socialAccount(other)
end

local function linkFriends(first, second)
    socialAccount(first).friends[second.account_id] = true
    socialAccount(second).friends[first.account_id] = true
    first.friend_requests_in[second.account_id] = nil
    first.friend_requests_out[second.account_id] = nil
    second.friend_requests_in[first.account_id] = nil
    second.friend_requests_out[first.account_id] = nil
end

local function friendCard(accountId)
    local other = state.accounts[accountId]
    if not other then return nil end
    return { account_id = other.account_id, name = other.name }
end

function actions.FRIEND_OVERVIEW(payload)
    local account = socialAccount(requireSession(payload))
    local friends, incoming, outgoing = {}, {}, {}
    for friendId in pairs(account.friends) do
        friends[#friends + 1] = friendCard(friendId)
    end
    for requesterId in pairs(account.friend_requests_in) do
        incoming[#incoming + 1] = friendCard(requesterId)
    end
    for targetId in pairs(account.friend_requests_out) do
        outgoing[#outgoing + 1] = friendCard(targetId)
    end
    local byName = function(a, b) return a.name < b.name end
    table.sort(friends, byName)
    table.sort(incoming, byName)
    table.sort(outgoing, byName)
    return { friends = friends, incoming = incoming, outgoing = outgoing }
end

function actions.FRIEND_SEARCH(payload)
    local account = socialAccount(requireSession(payload))
    local query = util.normalName(util.trim(payload.query or ""))
    need(#query >= 2, "QUERY_TOO_SHORT", "Type at least two characters")
    local results = {}
    for normal, accountId in pairs(state.account_names) do
        local other = state.accounts[accountId]
        if accountId ~= account.account_id and other and not other.banned
            and normal:find(query, 1, true) then
            results[#results + 1] = {
                account_id = accountId,
                name = other.name,
                friend = account.friends[accountId] == true,
                requested = account.friend_requests_out[accountId] == true,
                incoming = account.friend_requests_in[accountId] ~= nil,
            }
        end
    end
    table.sort(results, function(a, b) return a.name < b.name end)
    while #results > 12 do table.remove(results) end
    return { results = results }
end

function actions.FRIEND_REQUEST(payload)
    local account = socialAccount(requireSession(payload))
    local other = payload.account_id and state.accounts[payload.account_id]
        or accountByName(payload.name or "")
    checkAccountActive(other)
    need(other.account_id ~= account.account_id,
        "INVALID_FRIEND", "That is your own account")
    socialAccount(other)
    need(not account.friends[other.account_id], "ALREADY_FRIENDS",
        other.name .. " is already a friend")
    if account.friend_requests_in[other.account_id] then
        linkFriends(account, other)
        notification(other, "Friend added",
            account.name .. " accepted your friend request", "social")
        save()
        return { status = "friends", name = other.name }
    end
    if not account.friend_requests_out[other.account_id] then
        account.friend_requests_out[other.account_id] = true
        other.friend_requests_in[account.account_id] = {
            created_day = util.ingameDay(),
            created_time = util.formatClock(),
        }
        notification(other, "Friend request",
            account.name .. " wants to be your friend", "social")
        save()
    end
    return { status = "requested", name = other.name }
end

function actions.FRIEND_RESPOND(payload)
    local account = socialAccount(requireSession(payload))
    local other = state.accounts[payload.account_id]
    need(other and account.friend_requests_in[other.account_id],
        "NOT_FOUND", "That friend request is no longer waiting")
    socialAccount(other)
    if payload.accept == true then
        linkFriends(account, other)
        notification(other, "Friend added",
            account.name .. " accepted your friend request", "social")
        save()
        return { status = "friends", name = other.name }
    end
    account.friend_requests_in[other.account_id] = nil
    other.friend_requests_out[account.account_id] = nil
    save()
    return { status = "declined", name = other.name }
end

function actions.FRIEND_REMOVE(payload)
    local account = socialAccount(requireSession(payload))
    local other = state.accounts[payload.account_id]
    need(other, "NOT_FOUND", "Account not found")
    socialAccount(other)
    account.friends[other.account_id] = nil
    other.friends[account.account_id] = nil
    save()
    return { status = "removed", name = other.name }
end

-- Conversations -------------------------------------------------------------

local function directKey(firstId, secondId)
    if firstId < secondId then return firstId .. "|" .. secondId end
    return secondId .. "|" .. firstId
end

local function unreadFor(conversation, accountId)
    local member = conversation.members[accountId]
    if not member then return 0 end
    local unread = 0
    for _, item in ipairs(conversation.messages) do
        if item.seq > (member.last_read_seq or 0)
            and item.sender_id ~= accountId then
            unread = unread + 1
        end
    end
    return unread
end

local function conversationTitle(conversation, accountId)
    if conversation.kind == "group" then return conversation.title end
    for _, memberId in ipairs(conversation.member_ids) do
        if memberId ~= accountId then
            local other = state.accounts[memberId]
            return other and other.name or "Unknown"
        end
    end
    return "Empty chat"
end

local function conversationSummary(conversation, account)
    local last = conversation.messages[#conversation.messages]
    local names = {}
    for _, memberId in ipairs(conversation.member_ids) do
        local member = state.accounts[memberId]
        if member then names[#names + 1] = member.name end
    end
    return {
        conversation_id = conversation.conversation_id,
        kind = conversation.kind,
        title = conversationTitle(conversation, account.account_id),
        member_names = names,
        member_count = #conversation.member_ids,
        unread = unreadFor(conversation, account.account_id),
        last_at = conversation.last_at,
        last_preview = last and (last.kind == "text" and last.body
            or last.kind == "money_request"
                and ("asked for " .. util.money(last.amount, config.currency))
            or last.kind == "money_sent"
                and ("sent " .. util.money(last.amount, config.currency))
            or last.body) or "No messages yet",
        last_sender = last and last.sender_name or nil,
    }
end

local function appendMessage(conversation, senderId, kind, body, extra)
    local sender = senderId and state.accounts[senderId]
    local item = {
        seq = conversation.next_seq,
        sender_id = senderId,
        sender_name = sender and sender.name or "PUMPE",
        kind = kind,
        body = util.safeText(body, SOCIAL.max_message),
        day = util.ingameDay(),
        time = util.formatClock(),
        at = util.nowMs(),
    }
    for key, value in pairs(extra or {}) do item[key] = value end
    conversation.next_seq = conversation.next_seq + 1
    conversation.messages[#conversation.messages + 1] = item
    while #conversation.messages > SOCIAL.max_conversation do
        table.remove(conversation.messages, 1)
    end
    conversation.last_at = item.at
    if senderId and conversation.members[senderId] then
        conversation.members[senderId].last_read_seq = item.seq
    end
    return item
end

-- Only the first unread message in a conversation raises an alert, so a busy
-- group chat cannot flood the 50-entry Alerts list.
local function notifyNewMessage(conversation, senderId, preview)
    for _, memberId in ipairs(conversation.member_ids) do
        if memberId ~= senderId then
            local member = state.accounts[memberId]
            if member and unreadFor(conversation, memberId) <= 1 then
                notification(member, "Message from "
                    .. conversationTitle(conversation, memberId),
                    preview, "message")
            end
        end
    end
end

local function newConversation(kind, memberIds, title, ownerId)
    local conversationId = nextId("conversation")
    local conversation = {
        conversation_id = conversationId,
        kind = kind,
        title = title,
        owner_id = ownerId,
        member_ids = memberIds,
        members = {},
        messages = {},
        next_seq = 1,
        created_at = util.nowMs(),
        last_at = util.nowMs(),
    }
    for _, memberId in ipairs(memberIds) do
        conversation.members[memberId] = { last_read_seq = 0 }
        local member = state.accounts[memberId]
        if member then socialAccount(member).conversation_ids[conversationId] = true end
    end
    state.conversations[conversationId] = conversation
    if kind == "direct" then
        state.direct_conversations[directKey(memberIds[1], memberIds[2])] =
            conversationId
    end
    return conversation
end

local function directConversation(first, second)
    local existing = state.direct_conversations[
        directKey(first.account_id, second.account_id)]
    local conversation = existing and state.conversations[existing]
    if conversation then return conversation end
    return newConversation("direct",
        { first.account_id, second.account_id }, nil, first.account_id)
end

local function requireConversation(account, conversationId)
    local conversation = state.conversations[conversationId]
    need(conversation and conversation.members[account.account_id],
        "NOT_FOUND", "That chat is not available")
    return conversation
end

function actions.CHAT_LIST(payload)
    local account = socialAccount(requireSession(payload))
    local list = {}
    for conversationId in pairs(account.conversation_ids) do
        local conversation = state.conversations[conversationId]
        if conversation then
            list[#list + 1] = conversationSummary(conversation, account)
        else
            account.conversation_ids[conversationId] = nil
        end
    end
    table.sort(list, function(a, b)
        return (a.last_at or 0) > (b.last_at or 0)
    end)
    return { conversations = list }
end

function actions.CHAT_START(payload)
    local account = socialAccount(requireSession(payload))
    local requested = type(payload.account_ids) == "table"
        and payload.account_ids or {}
    need(#requested >= 1, "NO_MEMBERS", "Choose at least one friend")
    need(#requested + 1 <= SOCIAL.max_group, "TOO_MANY_MEMBERS",
        "A group holds at most " .. SOCIAL.max_group .. " people")
    local memberIds, seen = { account.account_id }, {
        [account.account_id] = true,
    }
    for _, accountId in ipairs(requested) do
        if not seen[accountId] then
            requireFriend(account, accountId)
            seen[accountId] = true
            memberIds[#memberIds + 1] = accountId
        end
    end
    if #memberIds == 2 then
        local conversation = directConversation(account,
            state.accounts[memberIds[2]])
        save()
        return { conversation = conversationSummary(conversation, account) }
    end
    local title = util.safeText(util.trim(payload.title or ""), 24)
    if title == "" then title = account.name .. "'s group" end
    local conversation = newConversation("group", memberIds, title,
        account.account_id)
    appendMessage(conversation, nil, "system",
        account.name .. " created " .. title)
    for _, memberId in ipairs(memberIds) do
        if memberId ~= account.account_id then
            notification(state.accounts[memberId], "Added to a group",
                account.name .. " added you to " .. title, "message")
        end
    end
    save()
    return { conversation = conversationSummary(conversation, account) }
end

function actions.CHAT_OPEN(payload)
    local account = socialAccount(requireSession(payload))
    local conversation = requireConversation(account, payload.conversation_id)
    local afterSeq = math.max(0, math.floor(tonumber(payload.after_seq) or 0))
    local messages = {}
    for _, item in ipairs(conversation.messages) do
        if item.seq > afterSeq then messages[#messages + 1] = util.copy(item) end
    end
    -- An open chat polls this every second. Only write the database when the
    -- read marker actually moved.
    local member = conversation.members[account.account_id]
    if payload.mark_read ~= false
        and member.last_read_seq ~= conversation.next_seq - 1 then
        member.last_read_seq = conversation.next_seq - 1
        save()
    end
    return {
        conversation = conversationSummary(conversation, account),
        messages = messages,
        next_seq = conversation.next_seq,
    }
end

function actions.CHAT_SEND(payload)
    local account = socialAccount(requireSession(payload))
    local conversation = requireConversation(account, payload.conversation_id)
    local body = util.safeText(util.trim(payload.body or ""), SOCIAL.max_message)
    need(#body > 0, "EMPTY_MESSAGE", "Type a message first")
    local item = appendMessage(conversation, account.account_id, "text", body)
    notifyNewMessage(conversation, account.account_id, body)
    save()
    return { message = util.copy(item) }
end

function actions.CHAT_REQUEST_MONEY(payload)
    local account = socialAccount(requireSession(payload))
    local conversation = requireConversation(account, payload.conversation_id)
    local amount = validateAmount(payload.amount)
    local item = appendMessage(conversation, account.account_id,
        "money_request", util.safeText(payload.note or "", 60), {
            amount = amount,
            status = "pending",
        })
    notifyNewMessage(conversation, account.account_id,
        account.name .. " asked for " .. util.money(amount, config.currency))
    save()
    return { message = util.copy(item) }
end

local function conversationCounterpart(conversation, account, accountId)
    if accountId then
        need(conversation.members[accountId], "NOT_FOUND",
            "That person is not in this chat")
        return state.accounts[accountId]
    end
    need(conversation.kind == "direct", "CHOOSE_MEMBER",
        "Choose who to pay in a group chat")
    for _, memberId in ipairs(conversation.member_ids) do
        if memberId ~= account.account_id then return state.accounts[memberId] end
    end
end

function actions.CHAT_SEND_MONEY(payload)
    local account = socialAccount(requireSession(payload))
    local conversation = requireConversation(account, payload.conversation_id)
    need(verifyAccount(account, payload.pin), "BAD_PIN", "Incorrect PIN")
    local recipient = conversationCounterpart(conversation, account,
        payload.to_account_id)
    checkAccountActive(recipient)
    local quote = performTransfer(account, recipient.name, payload.amount,
        "Sent in Messages")
    appendMessage(conversation, account.account_id, "money_sent",
        "sent " .. util.money(quote.amount, config.currency)
            .. " to " .. recipient.name,
        { amount = quote.amount, to_account_id = recipient.account_id })
    save()
    return { quote = quote }
end

function actions.CHAT_PAY_REQUEST(payload)
    local account = socialAccount(requireSession(payload))
    local conversation = requireConversation(account, payload.conversation_id)
    need(verifyAccount(account, payload.pin), "BAD_PIN", "Incorrect PIN")
    local requestSeq = math.floor(tonumber(payload.seq) or 0)
    local target
    for _, item in ipairs(conversation.messages) do
        if item.seq == requestSeq and item.kind == "money_request" then
            target = item
        end
    end
    need(target, "NOT_FOUND", "That money request is no longer here")
    need(target.status == "pending", "ALREADY_HANDLED",
        "That request was already handled")
    need(target.sender_id ~= account.account_id, "OWN_REQUEST",
        "That is your own request")
    local recipient = state.accounts[target.sender_id]
    checkAccountActive(recipient)
    local quote = performTransfer(account, recipient.name, target.amount,
        "Money request in Messages")
    target.status = "paid"
    target.paid_by = account.account_id
    appendMessage(conversation, account.account_id, "money_sent",
        "paid " .. util.money(quote.amount, config.currency)
            .. " to " .. recipient.name,
        { amount = quote.amount, to_account_id = recipient.account_id })
    save()
    return { quote = quote }
end

function actions.CHAT_DECLINE_REQUEST(payload)
    local account = socialAccount(requireSession(payload))
    local conversation = requireConversation(account, payload.conversation_id)
    local requestSeq = math.floor(tonumber(payload.seq) or 0)
    for _, item in ipairs(conversation.messages) do
        if item.seq == requestSeq and item.kind == "money_request"
            and item.status == "pending"
            and item.sender_id ~= account.account_id then
            item.status = "declined"
            appendMessage(conversation, account.account_id, "system",
                account.name .. " declined the request")
            save()
            return { status = "declined" }
        end
    end
    need(false, "NOT_FOUND", "That money request is no longer here")
end

socialBadges = function(account)
    socialAccount(account)
    local messages, requests, friends = 0, 0, 0
    for conversationId in pairs(account.conversation_ids) do
        local conversation = state.conversations[conversationId]
        if conversation then
            messages = messages + unreadFor(conversation, account.account_id)
        end
    end
    for _ in pairs(account.friend_requests_in) do requests = requests + 1 end
    for _ in pairs(account.friends) do friends = friends + 1 end
    return { messages = messages, friend_requests = requests, friends = friends }
end

-- Urgent Contact ------------------------------------------------------------

local function endCall(call, reason, endedById)
    if call.status == "ended" then return call end
    call.status = "ended"
    call.ended_at = util.nowMs()
    call.ended_reason = reason
    call.ended_by = endedById
    if call.save_votes[call.from_id] and call.save_votes[call.to_id] then
        local from = state.accounts[call.from_id]
        local to = state.accounts[call.to_id]
        if from and to then
            local conversation = directConversation(from, to)
            appendMessage(conversation, nil, "system",
                "Urgent Contact transcript saved")
            for _, item in ipairs(call.messages) do
                if item.kind ~= "system" then
                    appendMessage(conversation, item.sender_id, item.kind,
                        item.body, { amount = item.amount })
                end
            end
            call.saved = true
            save()
        end
    end
    return call
end

local function cleanupUrgentCalls()
    local now = util.nowMs()
    for callId, call in pairs(urgentCalls) do
        if call.status == "ringing" and now - call.created_at > SOCIAL.ring_ms then
            call.status = "missed"
            call.ended_at = now
            local to = state.accounts[call.to_id]
            local from = state.accounts[call.from_id]
            if to then
                notification(to, "Missed Urgent Contact",
                    call.from_name .. " tried to reach you", "warning")
            end
            if from then
                notification(from, "No answer",
                    call.to_name .. " did not answer", "warning")
            end
            save()
        elseif call.status == "active" and now - (call.last_at or now) > SOCIAL.idle_ms then
            endCall(call, "Timed out")
        elseif call.status ~= "ringing" and call.status ~= "active"
            and (call.ended_at or now) + 120 * 1000 < now then
            urgentCalls[callId] = nil
        end
    end
end

local function busyCall(accountId)
    for _, call in pairs(urgentCalls) do
        if (call.status == "ringing" or call.status == "active")
            and (call.from_id == accountId or call.to_id == accountId) then
            return call
        end
    end
    return nil
end

local function requireCall(account, callId)
    local call = urgentCalls[callId]
    need(call and (call.from_id == account.account_id
        or call.to_id == account.account_id),
        "NOT_FOUND", "That Urgent Contact has ended")
    return call
end

local function publicCall(call, accountId)
    local mine = call.from_id == accountId
    return {
        call_id = call.call_id,
        status = call.status,
        other_name = mine and call.to_name or call.from_name,
        other_id = mine and call.to_id or call.from_id,
        outgoing = mine,
        saved = call.saved == true,
        save_votes = (call.save_votes[call.from_id] and 1 or 0)
            + (call.save_votes[call.to_id] and 1 or 0),
        i_saved = call.save_votes[accountId] == true,
        ended_reason = call.ended_reason,
        next_seq = call.next_seq,
    }
end

function actions.URGENT_RING(payload)
    local account = requireSession(payload)
    cleanupUrgentCalls()
    for _, call in pairs(urgentCalls) do
        if call.to_id == account.account_id and call.status == "ringing" then
            return { call = publicCall(call, account.account_id) }
        end
    end
    return {}
end

function actions.URGENT_CALL(payload)
    local account = socialAccount(requireSession(payload))
    cleanupUrgentCalls()
    local other = requireFriend(account, payload.account_id)
    need(not busyCall(account.account_id), "CALL_BUSY",
        "You already have an Urgent Contact open")
    need(not busyCall(other.account_id), "CALL_BUSY",
        other.name .. " is already on an Urgent Contact")
    local call = {
        call_id = util.token("CALL"),
        from_id = account.account_id,
        from_name = account.name,
        to_id = other.account_id,
        to_name = other.name,
        status = "ringing",
        created_at = util.nowMs(),
        last_at = util.nowMs(),
        messages = {},
        next_seq = 1,
        save_votes = {},
    }
    urgentCalls[call.call_id] = call
    notification(other, "Urgent Contact",
        account.name .. " is reaching you right now", "urgent")
    logActivity("Urgent Contact " .. account.name .. " > " .. other.name,
        colors.orange)
    return { call = publicCall(call, account.account_id) }
end

function actions.URGENT_ANSWER(payload)
    local account = requireSession(payload)
    local call = requireCall(account, payload.call_id)
    need(call.to_id == account.account_id, "NOT_CALLEE",
        "Only the person being reached can answer")
    need(call.status == "ringing", "CALL_CLOSED", "That Urgent Contact ended")
    if payload.accept == true then
        call.status = "active"
        call.answered_at = util.nowMs()
        call.last_at = call.answered_at
        return { call = publicCall(call, account.account_id) }
    end
    call.status = "declined"
    call.ended_at = util.nowMs()
    local from = state.accounts[call.from_id]
    if from then
        notification(from, "Urgent Contact declined",
            call.to_name .. " could not talk", "warning")
        save()
    end
    return { call = publicCall(call, account.account_id) }
end

local function appendCallMessage(call, senderId, kind, body, extra)
    local sender = senderId and state.accounts[senderId]
    local item = {
        seq = call.next_seq,
        sender_id = senderId,
        sender_name = sender and sender.name or "PUMPE",
        kind = kind,
        body = util.safeText(body, SOCIAL.max_message),
        time = util.formatClock(),
        at = util.nowMs(),
    }
    for key, value in pairs(extra or {}) do item[key] = value end
    call.next_seq = call.next_seq + 1
    call.messages[#call.messages + 1] = item
    while #call.messages > SOCIAL.max_conversation do
        table.remove(call.messages, 1)
    end
    call.last_at = item.at
    return item
end

function actions.URGENT_STATE(payload)
    local account = requireSession(payload)
    cleanupUrgentCalls()
    local call = requireCall(account, payload.call_id)
    local afterSeq = math.max(0, math.floor(tonumber(payload.after_seq) or 0))
    local messages = {}
    for _, item in ipairs(call.messages) do
        if item.seq > afterSeq then messages[#messages + 1] = util.copy(item) end
    end
    return { call = publicCall(call, account.account_id), messages = messages }
end

function actions.URGENT_SEND(payload)
    local account = requireSession(payload)
    local call = requireCall(account, payload.call_id)
    need(call.status == "active", "CALL_CLOSED", "That Urgent Contact ended")
    local body = util.safeText(util.trim(payload.body or ""), SOCIAL.max_message)
    need(#body > 0, "EMPTY_MESSAGE", "Type something first")
    local item = appendCallMessage(call, account.account_id, "text", body)
    return { message = util.copy(item) }
end

function actions.URGENT_SAVE(payload)
    local account = requireSession(payload)
    local call = requireCall(account, payload.call_id)
    need(call.status == "active", "CALL_CLOSED", "That Urgent Contact ended")
    if call.save_votes[account.account_id] then
        call.save_votes[account.account_id] = nil
        appendCallMessage(call, nil, "system",
            account.name .. " no longer wants to save this")
    else
        call.save_votes[account.account_id] = true
        appendCallMessage(call, nil, "system",
            account.name .. " wants to save this conversation")
    end
    return { call = publicCall(call, account.account_id) }
end

function actions.URGENT_REQUEST_MONEY(payload)
    local account = requireSession(payload)
    local call = requireCall(account, payload.call_id)
    need(call.status == "active", "CALL_CLOSED", "That Urgent Contact ended")
    local amount = validateAmount(payload.amount)
    local item = appendCallMessage(call, account.account_id, "money_request",
        "asked for " .. util.money(amount, config.currency),
        { amount = amount, status = "pending" })
    return { message = util.copy(item) }
end

function actions.URGENT_SEND_MONEY(payload)
    local account = requireSession(payload)
    local call = requireCall(account, payload.call_id)
    need(call.status == "active", "CALL_CLOSED", "That Urgent Contact ended")
    need(verifyAccount(account, payload.pin), "BAD_PIN", "Incorrect PIN")
    local otherId = call.from_id == account.account_id
        and call.to_id or call.from_id
    local recipient = state.accounts[otherId]
    checkAccountActive(recipient)
    local quote = performTransfer(account, recipient.name, payload.amount,
        "Sent in Urgent Contact")
    appendCallMessage(call, account.account_id, "money_sent",
        "sent " .. util.money(quote.amount, config.currency),
        { amount = quote.amount })
    return { quote = quote }
end

function actions.URGENT_PAY_REQUEST(payload)
    local account = requireSession(payload)
    local call = requireCall(account, payload.call_id)
    need(call.status == "active", "CALL_CLOSED", "That Urgent Contact ended")
    need(verifyAccount(account, payload.pin), "BAD_PIN", "Incorrect PIN")
    local requestSeq = math.floor(tonumber(payload.seq) or 0)
    local target
    for _, item in ipairs(call.messages) do
        if item.seq == requestSeq and item.kind == "money_request" then
            target = item
        end
    end
    need(target and target.status == "pending", "NOT_FOUND",
        "That money request is no longer waiting")
    need(target.sender_id ~= account.account_id, "OWN_REQUEST",
        "That is your own request")
    local recipient = state.accounts[target.sender_id]
    checkAccountActive(recipient)
    local quote = performTransfer(account, recipient.name, target.amount,
        "Urgent Contact request")
    target.status = "paid"
    appendCallMessage(call, account.account_id, "money_sent",
        "paid " .. util.money(quote.amount, config.currency),
        { amount = quote.amount })
    return { quote = quote }
end

-- Proximity Pay ------------------------------------------------------------
-- Devices report where they are and the Bank keeps the map. A kiosk offers
-- its bill to the nearest PUMPE with a recent fix; declining passes it to the
-- next one rather than cancelling the sale.

local function recordPosition(holder, position)
    if type(holder) ~= "table" or type(position) ~= "table" then return end
    local x, y, z = tonumber(position.x), tonumber(position.y), tonumber(position.z)
    if not x or not y or not z then return end
    holder.position = { x = x, y = y, z = z, at = util.nowMs() }
end

local function freshPosition(holder)
    local position = holder and holder.position
    if not position then return nil end
    local maxAge = tonumber(config.position_max_age_ms) or 90000
    if util.nowMs() - (position.at or 0) > maxAge then return nil end
    return position
end

local function distanceBetween(first, second)
    local dx, dy, dz = first.x - second.x, first.y - second.y, first.z - second.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function nearestAccount(origin, excluded)
    local best, bestDistance
    local radius = tonumber(config.proximity_pay_radius) or 16
    for accountId, account in pairs(state.accounts) do
        local position = not excluded[accountId] and not account.banned
            and not account.frozen and freshPosition(account)
        if position then
            local distance = distanceBetween(origin, position)
            if distance <= radius and (not bestDistance or distance < bestDistance) then
                best, bestDistance = account, distance
            end
        end
    end
    return best, bestDistance
end

local function offerExpired(offer)
    return offer.status ~= "offered"
        or offer.expires_at <= util.nowMs()
end

-- Hands the bill to the next nearest PUMPE, or gives up when nobody is left.
local function retargetOffer(offer)
    local terminal = state.terminals[offer.terminal_id]
    local origin = terminal and freshPosition(terminal)
    if not origin then
        offer.status = "no_position"
        return offer
    end
    local account, distance = nearestAccount(origin, offer.declined)
    if not account then
        offer.status = "nobody_nearby"
        offer.target_account_id = nil
        return offer
    end
    offer.target_account_id = account.account_id
    offer.target_name = account.name
    offer.distance = math.floor(distance * 10) / 10
    offer.status = "offered"
    offer.expires_at = util.nowMs()
        + (tonumber(config.proximity_offer_ttl_ms) or 60000)
    notification(account, "Payment nearby",
        util.money(offer.amount, config.currency) .. " from " .. offer.merchant,
        "money")
    return offer
end

local function publicOffer(offer)
    local payment = state.active_pay_codes[offer.code]
    return {
        offer_id = offer.offer_id,
        code = offer.code,
        amount = offer.amount,
        merchant = offer.merchant,
        description = offer.description,
        status = payment and payment.status == "paid" and "paid" or offer.status,
        target_name = offer.target_name,
        distance = offer.distance,
    }
end

function actions.REPORT_POSITION(payload)
    local account = requireSession(payload)
    recordPosition(account, payload.position)
    return { ok = account.position ~= nil }
end

function actions.PROXIMITY_OFFER(payload)
    local terminal = requireTerminal(payload)
    cleanupEphemeral()
    recordPosition(terminal, payload.position)
    need(freshPosition(terminal), "NO_POSITION",
        "This kiosk has no GPS fix. Add GPS anchors nearby.")
    local created = actions.CREATE_PAY_CODE(payload)
    local offer = {
        offer_id = nextId("proximity"),
        code = created.code,
        terminal_id = terminal.terminal_id,
        merchant = util.safeText(terminal.name or "Kiosk", 20),
        description = util.safeText(payload.description or "Purchase", 60),
        amount = created.amount,
        declined = {},
        status = "offered",
        created_at = util.nowMs(),
        expires_at = util.nowMs()
            + (tonumber(config.proximity_offer_ttl_ms) or 60000),
    }
    state.proximity_offers[offer.offer_id] = offer
    retargetOffer(offer)
    save()
    return { offer = publicOffer(offer) }
end

function actions.PROXIMITY_STATUS(payload)
    local terminal = requireTerminal(payload)
    local offer = state.proximity_offers[payload.offer_id]
    need(offer and offer.terminal_id == terminal.terminal_id,
        "NOT_FOUND", "That offer has ended")
    local payment = state.active_pay_codes[offer.code]
    if payment and payment.status == "paid" then
        offer.status = "paid"
    elseif offer.status == "offered" and offer.expires_at <= util.nowMs() then
        offer.declined[offer.target_account_id or ""] = true
        retargetOffer(offer)
    end
    return { offer = publicOffer(offer) }
end

function actions.PROXIMITY_CANCEL(payload)
    local terminal = requireTerminal(payload)
    local offer = state.proximity_offers[payload.offer_id]
    need(offer and offer.terminal_id == terminal.terminal_id,
        "NOT_FOUND", "That offer has ended")
    offer.status = "cancelled"
    local payment = state.active_pay_codes[offer.code]
    if payment and payment.status == "pending" then
        state.active_pay_codes[offer.code] = nil
    end
    save()
    return { offer = publicOffer(offer) }
end

function actions.PROXIMITY_DECLINE(payload)
    local account = requireSession(payload)
    local offer = state.proximity_offers[payload.offer_id]
    need(offer, "NOT_FOUND", "That offer has ended")
    need(offer.target_account_id == account.account_id, "NOT_YOURS",
        "That offer is not yours")
    offer.declined[account.account_id] = true
    retargetOffer(offer)
    save()
    return { offer = publicOffer(offer) }
end

-- The offer waiting for this account, used by the OS poll.
local function offerFor(accountId)
    for _, offer in pairs(state.proximity_offers) do
        if offer.target_account_id == accountId and not offerExpired(offer) then
            local payment = state.active_pay_codes[offer.code]
            if payment and payment.status == "pending" then
                return publicOffer(offer)
            end
        end
    end
    return nil
end

-- Bank Admin Terminal routes -------------------------------------------------
-- Everything the government can do lives behind one session. The key itself
-- lives in the database rather than config.lua, so it can be changed from the
-- terminal without editing a file on the Bank.

-- Releases before 7.1 shipped a placeholder here. A Bank that self-updated
-- kept it, because an update preserves local settings, so the terminal kept
-- rejecting the documented key. A retired placeholder now means "unset".
local function governmentKey()
    local key = state.government_key
    if type(key) == "string" and key ~= "" then return key end
    key = config.government_key
    if type(key) ~= "string" or key == ""
        or key == "CHANGE-ME-GOVERNMENT-KEY" then
        return "Government1234"
    end
    return key
end

local function adminSettings()
    state.settings = state.settings or {}
    if state.settings.account_approval == nil then
        state.settings.account_approval = false
    end
    return state.settings
end

local function requireAccountId(payload)
    local account = state.accounts[payload and payload.account_id]
        or accountByName(payload and payload.name or "")
    need(account, "ACCOUNT_NOT_FOUND", "Account not found")
    return account
end

local function adminCard(account)
    return {
        account_id = account.account_id,
        name = account.name,
        balance = account.balance,
        banned = account.banned == true,
        frozen = account.frozen == true,
        approved = account.approved ~= false,
        tax_demand = account.tax_demand and util.copy(account.tax_demand) or nil,
    }
end

function actions.ADMIN_SET_KEY(payload)
    requireGovernment(payload)
    local key = util.trim(tostring(payload.new_key or ""))
    need(#key >= 6, "KEY_TOO_SHORT", "Use at least six characters")
    need(#key <= 40, "KEY_TOO_LONG", "Use at most forty characters")
    state.government_key = key
    save()
    logActivity("Government key changed", colors.orange)
    return { ok = true }
end

function actions.ADMIN_SETTINGS(payload)
    requireGovernment(payload)
    local settings = adminSettings()
    local pending = 0
    for _, account in pairs(state.accounts) do
        if account.approved == false then pending = pending + 1 end
    end
    return {
        account_approval = settings.account_approval == true,
        pending_approvals = pending,
        announcements = #(state.announcements or {}),
    }
end

function actions.ADMIN_SET_APPROVAL(payload)
    requireGovernment(payload)
    local settings = adminSettings()
    settings.account_approval = payload.enabled == true
    save()
    logActivity("Account approval "
        .. (settings.account_approval and "enabled" or "disabled"),
        colors.orange)
    return { account_approval = settings.account_approval }
end

function actions.ADMIN_ACCOUNTS(payload)
    requireGovernment(payload)
    local query = util.normalName(util.trim(payload.query or ""))
    local pendingOnly = payload.pending_only == true
    local results = {}
    for _, account in pairs(state.accounts) do
        local matches = query == ""
            or util.normalName(account.name):find(query, 1, true)
        if matches and (not pendingOnly or account.approved == false) then
            results[#results + 1] = adminCard(account)
        end
    end
    table.sort(results, function(a, b) return a.name < b.name end)
    while #results > 40 do table.remove(results) end
    return { accounts = results }
end

function actions.ADMIN_APPROVE_ACCOUNT(payload)
    requireGovernment(payload)
    local account = requireAccountId(payload)
    if payload.approve == false then
        account.approved = false
        notification(account, "Account not approved",
            "The government has not approved this account yet", "warning")
    else
        account.approved = true
        notification(account, "Account approved",
            "Your Foxy Account is ready to use", "success")
    end
    save()
    logActivity("Account " .. (account.approved and "approved" or "held")
        .. ": " .. account.name, colors.orange)
    return { account = adminCard(account) }
end

function actions.ADMIN_CREDIT(payload)
    requireGovernment(payload)
    local account = requireAccountId(payload)
    local amount = validateAmount(payload.amount, 1000000)
    local reason = util.safeText(payload.reason or "Government credit", 60)
    account.balance = util.roundMoney(account.balance + amount)
    transaction(account, "government_credit", amount, "Government", reason)
    notification(account, "Money added",
        util.money(amount, config.currency) .. " - " .. reason, "money")
    save()
    logActivity("Credited " .. util.money(amount, config.currency)
        .. " to " .. account.name, colors.lime)
    return { account = adminCard(account) }
end

function actions.ADMIN_DEBIT(payload)
    requireGovernment(payload)
    local account = requireAccountId(payload)
    local amount = validateAmount(payload.amount, 1000000)
    need(account.balance >= amount, "INSUFFICIENT_FUNDS",
        account.name .. " only holds "
            .. util.money(account.balance, config.currency))
    local reason = util.safeText(payload.reason or "Government debit", 60)
    account.balance = util.roundMoney(account.balance - amount)
    state.tax_revenue = util.roundMoney((state.tax_revenue or 0) + amount)
    transaction(account, "government_debit", -amount, "Government", reason)
    notification(account, "Money removed",
        util.money(amount, config.currency) .. " - " .. reason, "warning")
    save()
    logActivity("Debited " .. util.money(amount, config.currency)
        .. " from " .. account.name, colors.orange)
    return { account = adminCard(account) }
end

function actions.ADMIN_BAN(payload)
    requireGovernment(payload)
    local account = requireAccountId(payload)
    account.banned = payload.banned ~= false
    if account.banned then
        for token, session in pairs(sessions) do
            if session.account_id == account.account_id then
                sessions[token] = nil
            end
        end
        notification(account, "Account banned",
            util.safeText(payload.reason or "Contact the government", 60),
            "warning")
    else
        notification(account, "Ban lifted", "Your account works again",
            "success")
    end
    save()
    logActivity((account.banned and "Banned " or "Unbanned ") .. account.name,
        colors.red)
    return { account = adminCard(account) }
end

-- A demand the account has to settle from its own PUMPE. Nothing is taken
-- without the holder paying it, so the money always moves with their PIN.
function actions.ADMIN_TAX_DEMAND(payload)
    requireGovernment(payload)
    local account = requireAccountId(payload)
    local amount = validateAmount(payload.amount, 1000000)
    account.tax_demand = {
        amount = amount,
        reason = util.safeText(payload.reason or "Government tax demand", 60),
        created_day = util.ingameDay(),
        created_at = util.nowMs(),
    }
    notification(account, "Tax demand",
        util.money(amount, config.currency) .. " - " .. account.tax_demand.reason,
        "warning")
    save()
    logActivity("Tax demand " .. util.money(amount, config.currency)
        .. " to " .. account.name, colors.orange)
    return { account = adminCard(account) }
end

function actions.TAX_DEMAND_STATUS(payload)
    local account = requireSession(payload)
    return { demand = account.tax_demand and util.copy(account.tax_demand) or nil }
end

function actions.PAY_TAX_DEMAND(payload)
    local account = requireSession(payload)
    need(account.tax_demand, "NOT_FOUND", "You have no tax demand")
    need(verifyAccount(account, payload.pin), "BAD_PIN", "Incorrect PIN")
    local amount = account.tax_demand.amount
    need(account.balance >= amount, "INSUFFICIENT_FUNDS",
        "Not enough money to settle the demand")
    account.balance = util.roundMoney(account.balance - amount)
    state.tax_revenue = util.roundMoney((state.tax_revenue or 0) + amount)
    transaction(account, "tax_demand", -amount, "Government",
        account.tax_demand.reason)
    account.tax_demand = nil
    save()
    logActivity("Tax demand settled by " .. account.name, colors.lime)
    return { balance = account.balance }
end

-- Announcements --------------------------------------------------------------

function actions.ADMIN_ANNOUNCE(payload)
    requireGovernment(payload)
    local title = util.safeText(util.trim(payload.title or ""), 40)
    local body = util.safeText(util.trim(payload.body or ""), 160)
    need(#title > 0, "EMPTY_TITLE", "Give the announcement a title")
    local mode = payload.mode == "modal" and "modal" or "banner"
    state.announcements = state.announcements or {}
    local item = {
        announcement_id = nextId("announcement"),
        title = title,
        body = body,
        mode = mode,
        created_day = util.ingameDay(),
        created_time = util.formatClock(),
        created_at = util.nowMs(),
        acknowledged = {},
    }
    table.insert(state.announcements, 1, item)
    while #state.announcements > 20 do table.remove(state.announcements) end
    -- Every announcement is also an ordinary alert, so it survives being
    -- dismissed and can be read again later.
    for _, account in pairs(state.accounts) do
        notification(account, title, body, mode == "modal" and "urgent" or "info")
    end
    save()
    logActivity("Announcement: " .. title, colors.magenta)
    return { announcement = util.copy(item) }
end

local function announcementFor(accountId)
    for _, item in ipairs(state.announcements or {}) do
        if not item.acknowledged[accountId] then
            return {
                announcement_id = item.announcement_id,
                title = item.title,
                body = item.body,
                mode = item.mode,
            }
        end
    end
    return nil
end

function actions.ANNOUNCEMENT_ACK(payload)
    local account = requireSession(payload)
    for _, item in ipairs(state.announcements or {}) do
        if item.announcement_id == payload.announcement_id then
            item.acknowledged[account.account_id] = true
            save()
            return { ok = true }
        end
    end
    return { ok = false }
end

-- One poll for the whole PUMPE OS: an incoming Urgent Contact, the newest
-- unread alert for the banner, and every home screen badge. The phone checks
-- this a few times a second, so it must stay a single cheap request.
function actions.PUMPE_POLL(payload)
    local account = requireSession(payload)
    recordPosition(account, payload.position)
    cleanupUrgentCalls()
    local ring
    for _, call in pairs(urgentCalls) do
        if call.to_id == account.account_id and call.status == "ringing" then
            ring = publicCall(call, account.account_id)
        end
    end
    local unread, latest = 0, nil
    for _, item in ipairs(account.notifications) do
        if not item.read then
            unread = unread + 1
            if not latest then latest = item end
        end
    end
    local badges = socialBadges(account)
    return {
        call = ring,
        balance = account.balance,
        unread_notifications = unread,
        unread_messages = badges.messages,
        friend_requests = badges.friend_requests,
        offer = offerFor(account.account_id),
        announcement = announcementFor(account.account_id),
        latest = latest and {
            notification_id = latest.notification_id,
            title = latest.title,
            body = latest.body,
            kind = latest.kind,
        } or nil,
    }
end

function actions.URGENT_END(payload)
    local account = requireSession(payload)
    local call = requireCall(account, payload.call_id)
    endCall(call, "Hung up", account.account_id)
    return { call = publicCall(call, account.account_id) }
end

-- Customs, citizenship, and visa routes -------------------------------------

function actions.CUSTOMS_OVERVIEW(payload)
    local account = requireSession(payload)
    cleanupEphemeral()
    local territories = util.sortedValues(state.territories, function(territory)
        return territory.owner_account_id == account.account_id
            and territory.status == "active"
    end, function(a, b) return a.name < b.name end)
    local output = {}
    for _, territory in ipairs(territories) do
        local pending = 0
        for _, application in pairs(state.visa_applications) do
            if application.territory_id == territory.territory_id
                and application.status == "pending" then
                pending = pending + 1
            end
        end
        output[#output + 1] = {
            territory_id = territory.territory_id,
            name = territory.name,
            citizen_count = mapCount(territory.citizen_account_ids),
            free_roam_count = mapCount(territory.free_roam_territory_ids),
            pending_count = pending,
            created_day = territory.created_day,
        }
    end
    return {
        territories = output,
        maximum_territories =
            math.max(1, math.floor(tonumber(config.max_territories_per_account)
                or 3)),
    }
end

function actions.CUSTOMS_DETAIL(payload)
    local account = requireSession(payload)
    local territory = territoryOwner(account, payload.territory_id)
    cleanupEphemeral()
    local citizens = {}
    for accountId in pairs(territory.citizen_account_ids) do
        local citizen = state.accounts[accountId]
        local document = matchingDocument(
            accountId, territory.territory_id, "citizenship")
        if citizen and document then
            citizens[#citizens + 1] = {
                account_id = accountId,
                name = citizen.name,
                code = document.code,
                issued_day = document.issued_day,
            }
        end
    end
    table.sort(citizens, function(a, b) return a.name < b.name end)

    local applications = {}
    for _, application in pairs(state.visa_applications) do
        if application.territory_id == territory.territory_id then
            applications[#applications + 1] =
                publicApplication(application)
        end
    end
    table.sort(applications, function(a, b)
        if a.status ~= b.status then return a.status == "pending" end
        return (a.created_day or 0) > (b.created_day or 0)
    end)

    local otherTerritories = {}
    for _, other in pairs(state.territories) do
        if other.status == "active"
            and other.territory_id ~= territory.territory_id then
            otherTerritories[#otherTerritories + 1] = {
                territory_id = other.territory_id,
                name = other.name,
                free_roam =
                    territory.free_roam_territory_ids[other.territory_id]
                        == true,
            }
        end
    end
    table.sort(otherTerritories, function(a, b) return a.name < b.name end)
    return {
        territory = {
            territory_id = territory.territory_id,
            name = territory.name,
            citizen_count = #citizens,
            free_roam_count = mapCount(territory.free_roam_territory_ids),
        },
        citizens = citizens,
        applications = applications,
        other_territories = otherTerritories,
    }
end

function actions.CUSTOMS_CREATE_TERRITORY(payload)
    local account = requireSession(payload)
    need(verifyAccount(account, payload.pin), "BAD_PIN", "Incorrect PIN")
    local name = util.safeText(util.trim(payload.name), 24)
    need(#name >= 3 and name:match("^[%w _%-]+$"),
        "INVALID_TERRITORY",
        "Use 3-24 letters, numbers, spaces, _ or -")
    need(not state.territory_names[util.normalName(name)],
        "TERRITORY_TAKEN", "That territory name is already registered")
    local owned = 0
    for _, territory in pairs(state.territories) do
        if territory.owner_account_id == account.account_id
            and territory.status == "active" then
            owned = owned + 1
        end
    end
    local maximum = math.max(1,
        math.floor(tonumber(config.max_territories_per_account) or 3))
    need(owned < maximum, "TERRITORY_LIMIT",
        "A Foxy Account can control up to " .. maximum .. " territories")

    local territoryId = nextId("territory")
    local territory = {
        territory_id = territoryId,
        name = name,
        owner_account_id = account.account_id,
        citizen_account_ids = {},
        free_roam_territory_ids = {},
        status = "active",
        created_day = util.ingameDay(),
    }
    state.territories[territoryId] = territory
    state.territory_names[util.normalName(name)] = territoryId
    local citizenship = assert(issueDocument(
        account, territory, "citizenship", {
            issued_by_account_id = account.account_id,
        }))
    notification(account, "Territory created",
        name .. " citizenship code: " .. citizenship.code, "travel")
    save()
    logActivity("Territory created: " .. name, colors.lightBlue)
    return {
        territory = {
            territory_id = territoryId,
            name = name,
        },
        citizenship = publicDocument(citizenship),
    }
end

function actions.CUSTOMS_ISSUE_CITIZENSHIP(payload)
    local owner = requireSession(payload)
    local territory = territoryOwner(owner, payload.territory_id)
    need(verifyAccount(owner, payload.pin), "BAD_PIN", "Incorrect PIN")
    local citizen = accountByName(payload.username)
    checkAccountActive(citizen)
    local document, existing = issueDocument(
        citizen, territory, "citizenship", {
            issued_by_account_id = owner.account_id,
        })
    need(document, "ALREADY_CITIZEN",
        existing and "That Foxy Account is already a citizen"
            or "Citizenship could not be created")
    notification(citizen, "Citizenship granted",
        territory.name .. " permanent code: " .. document.code, "travel")
    save()
    logActivity("Citizenship: " .. citizen.name .. " / " .. territory.name,
        colors.cyan)
    return {
        citizen_name = citizen.name,
        document = publicDocument(document),
    }
end

function actions.CUSTOMS_SET_FREE_ROAM(payload)
    local owner = requireSession(payload)
    local territory = territoryOwner(owner, payload.territory_id)
    need(verifyAccount(owner, payload.pin), "BAD_PIN", "Incorrect PIN")
    local source = state.territories[payload.source_territory_id]
    need(source and source.status == "active",
        "TERRITORY_NOT_FOUND", "Partner territory not found")
    need(source.territory_id ~= territory.territory_id,
        "INVALID_TERRITORY", "A territory already accepts its own citizens")
    local enabled = payload.enabled == true
    territory.free_roam_territory_ids[source.territory_id] =
        enabled and true or nil
    save()
    logActivity((enabled and "Free Roam enabled: " or "Free Roam ended: ")
        .. source.name .. " > " .. territory.name,
        enabled and colors.lime or colors.orange)
    return {
        territory_id = territory.territory_id,
        source_territory_id = source.territory_id,
        enabled = enabled,
    }
end

function actions.CUSTOMS_REVIEW_APPLICATION(payload)
    local owner = requireSession(payload)
    local application = state.visa_applications[payload.application_id]
    need(application and application.status == "pending",
        "APPLICATION_NOT_FOUND", "Pending visa application not found")
    local territory = territoryOwner(owner, application.territory_id)
    need(verifyAccount(owner, payload.pin), "BAD_PIN", "Incorrect PIN")
    local applicant = state.accounts[application.account_id]
    checkAccountActive(applicant)

    local document
    if payload.approved == true then
        local access = accessForAccount(applicant.account_id, territory)
        need(not access, "ACCESS_EXISTS",
            "This traveler already has entry rights")
        document = assert(issueDocument(
            applicant, territory, "visa", {
                duration_days = application.requested_days,
                issued_by_account_id = owner.account_id,
                application_id = application.application_id,
            }))
        application.status = "approved"
        application.visa_id = document.visa_id
        notification(applicant, "Visa approved",
            territory.name .. " for " .. application.requested_days
                .. " day(s). Code: " .. document.code, "travel")
    else
        application.status = "denied"
        notification(applicant, "Visa declined",
            territory.name .. " declined your application", "travel")
    end
    application.reviewed_day = util.ingameDay()
    application.reviewed_by_account_id = owner.account_id
    save()
    logActivity("Visa " .. application.status .. ": "
        .. applicant.name .. " / " .. territory.name,
        document and colors.lime or colors.orange)
    return {
        application = publicApplication(application),
        document = document and publicDocument(document) or nil,
    }
end

function actions.VISA_OVERVIEW(payload)
    local account = requireSession(payload)
    cleanupEphemeral()
    local documents = {}
    for _, document in pairs(state.visas) do
        if document.account_id == account.account_id then
            documents[#documents + 1] = publicDocument(document)
        end
    end
    table.sort(documents, function(a, b)
        if a.kind ~= b.kind then return a.kind == "citizenship" end
        return a.territory_name < b.territory_name
    end)

    local applications = {}
    for _, application in pairs(state.visa_applications) do
        if application.account_id == account.account_id then
            applications[#applications + 1] =
                publicApplication(application)
        end
    end
    table.sort(applications, function(a, b)
        return (a.created_day or 0) > (b.created_day or 0)
    end)

    local territories = {}
    for _, territory in pairs(state.territories) do
        if territory.status == "active" then
            local accessKind = accessForAccount(account.account_id, territory)
            local pending = pendingApplication(
                account.account_id, territory.territory_id) ~= nil
            territories[#territories + 1] = {
                territory_id = territory.territory_id,
                name = territory.name,
                access = accessKind,
                pending = pending,
                can_apply = not accessKind and not pending,
            }
        end
    end
    table.sort(territories, function(a, b) return a.name < b.name end)
    return {
        documents = documents,
        applications = applications,
        territories = territories,
        visa_min_days =
            math.max(1, math.floor(tonumber(config.visa_min_days) or 1)),
        visa_max_days =
            math.max(1, math.floor(tonumber(config.visa_max_days) or 30)),
    }
end

function actions.VISA_APPLY(payload)
    local account = requireSession(payload)
    local territory = state.territories[payload.territory_id]
    need(territory and territory.status == "active",
        "TERRITORY_NOT_FOUND", "Territory not found")
    local minimum =
        math.max(1, math.floor(tonumber(config.visa_min_days) or 1))
    local maximum =
        math.max(minimum, math.floor(tonumber(config.visa_max_days) or 30))
    local requestedDays = math.floor(tonumber(payload.requested_days) or 0)
    need(requestedDays >= minimum and requestedDays <= maximum,
        "INVALID_STAY", "Choose a stay from " .. minimum
            .. " to " .. maximum .. " days")
    local access = accessForAccount(account.account_id, territory)
    need(not access, "ACCESS_EXISTS",
        "You already have entry rights for this territory")
    need(not pendingApplication(account.account_id, territory.territory_id),
        "APPLICATION_PENDING", "You already have an application pending")

    local applicationId = nextId("visa_application")
    local application = {
        application_id = applicationId,
        account_id = account.account_id,
        territory_id = territory.territory_id,
        requested_days = requestedDays,
        status = "pending",
        created_day = util.ingameDay(),
    }
    state.visa_applications[applicationId] = application
    local owner = state.accounts[territory.owner_account_id]
    if owner then
        notification(owner, "New visa request",
            account.name .. " requests " .. requestedDays
                .. " day(s) in " .. territory.name, "travel")
    end
    save()
    logActivity("Visa applied: " .. account.name .. " / " .. territory.name,
        colors.lightBlue)
    return { application = publicApplication(application) }
end

-- Border Controller routes --------------------------------------------------

function actions.BORDER_REGISTER(payload)
    local owner = requireSession(payload)
    local territory = territoryOwner(owner, payload.territory_id)
    local controllerId = nextId("border")
    local controller = {
        controller_id = controllerId,
        auth_token = util.token("BORDER"),
        territory_id = territory.territory_id,
        owner_account_id = owner.account_id,
        label = util.safeText(
            util.trim(payload.label or ("Border " .. controllerId)), 24),
        status = "active",
        created_day = util.ingameDay(),
        last_seen = util.nowMs(),
    }
    state.border_controllers[controllerId] = controller
    save()
    logActivity("Border online: " .. territory.name, colors.purple)
    return {
        controller_id = controller.controller_id,
        controller_token = controller.auth_token,
        territory_id = territory.territory_id,
        territory_name = territory.name,
        label = controller.label,
    }
end

function actions.BORDER_STATUS(payload)
    local controller = requireBorderController(payload)
    local territory = state.territories[controller.territory_id]
    need(territory and territory.status == "active",
        "TERRITORY_NOT_FOUND", "Configured territory is unavailable")
    return {
        controller_id = controller.controller_id,
        territory_id = territory.territory_id,
        territory_name = territory.name,
        label = controller.label,
        day = util.ingameDay(),
        time = util.formatClock(),
    }
end

function actions.BORDER_OWNER_PIN(payload)
    local controller = requireBorderController(payload)
    local owner = state.accounts[controller.owner_account_id]
    need(owner and verifyAccount(owner, payload.pin),
        "BAD_PIN", "Owner PIN is incorrect")
    return { authorized = true }
end

function actions.BORDER_CHECK(payload)
    local controller = requireBorderController(payload)
    cleanupEphemeral()
    local territory = state.territories[controller.territory_id]
    need(territory and territory.status == "active",
        "TERRITORY_NOT_FOUND", "Configured territory is unavailable")
    local code = string.upper(util.trim(payload.code))
    local direction = string.lower(util.trim(payload.direction))
    need(direction == "enter" or direction == "exit",
        "BORDER_DIRECTION", "Choose Enter Territory or Exit Territory")
    need(code:match("^[A-Z2-9]+$") and #code == 8,
        "VISA_CODE_INVALID", "Enter the eight-character travel code")
    local documentId = state.visa_codes[code]
    local document = documentId and state.visas[documentId]
    need(document and document.status ~= "revoked",
        "VISA_NOT_FOUND", "Travel code was not found")
    need(document.status ~= "expired",
        "VISA_EXPIRED", "This visa has expired")
    local traveler = state.accounts[document.account_id]
    checkAccountActive(traveler)

    local authorization
    if document.kind == "citizenship"
        and document.territory_id == territory.territory_id then
        authorization = "citizenship"
    elseif document.kind == "citizenship"
        and territory.free_roam_territory_ids[document.territory_id] then
        authorization = "free_roam"
    elseif document.kind == "visa"
        and document.territory_id == territory.territory_id then
        authorization = "visa"
    end
    need(authorization, "VISA_WRONG_TERRITORY",
        "This document does not allow entry here")

    local visit = openVisit(
        traveler.account_id, territory.territory_id, document.visa_id)
    local now = util.nowMs()
    local today = util.ingameDay()
    local permanent = authorization ~= "visa"
    local actionLabel

    if direction == "enter" then
        need(not visit, "ALREADY_VISITING",
            "This traveler is already inside; choose Exit Territory")
        if not permanent then
            need(document.status == "issued",
                "VISA_ALREADY_USED", "This temporary visa has already been used")
        else
            local nextEntry = tonumber(document.next_border_entry_at) or 0
            local remaining = math.ceil(math.max(0, nextEntry - now) / 1000)
            need(remaining <= 0, "VISA_COOLDOWN",
                "This permanent travel code is cooling down for "
                    .. remaining .. " second(s)")
        end
        local visitId = nextId("visit")
        local dueDay
        if authorization == "visa" then
            dueDay = today
                + math.max(1, document.duration_days or 1) - 1
            document.status = "visiting"
            document.entered_day = today
            document.due_day = dueDay
        else
            local cooldown = math.max(1,
                math.floor(tonumber(config.permanent_visa_cooldown_seconds)
                    or 30))
            document.next_border_entry_at = now + cooldown * 1000
        end
        visit = {
            visit_id = visitId,
            account_id = traveler.account_id,
            territory_id = territory.territory_id,
            visa_id = document.visa_id,
            authorization = authorization,
            entered_day = today,
            entered_at = now,
            due_day = dueDay,
            status = "visiting",
            controller_id = controller.controller_id,
        }
        state.visits[visitId] = visit
        notification(traveler, "Border entry recorded",
            territory.name .. (dueDay and
                (" - leave by day " .. dueDay) or " - permanent stay"),
            "travel")
        logActivity("Border entry: " .. traveler.name .. " > "
            .. territory.name, colors.lime)
        actionLabel = "entered"
    else
        need(visit, "NOT_VISITING",
            "No active visit was found for this travel code")
        visit.status = "exited"
        visit.exited_day = today
        visit.exited_at = now
        visit.exit_controller_id = controller.controller_id
        if permanent then
            local cooldown = math.max(1,
                math.floor(tonumber(config.permanent_visa_cooldown_seconds)
                    or 30))
            document.next_border_entry_at = now + cooldown * 1000
            document.last_exit_day = today
        else
            document.status = "used"
            document.exited_day = today
        end
        notification(traveler, "Border exit recorded",
            "You left " .. territory.name
                .. (permanent and "" or "; temporary visa locked"), "travel")
        logActivity("Border exit: " .. traveler.name .. " < "
            .. territory.name, colors.orange)
        actionLabel = "exited"
    end
    save()
    local remaining = visit.due_day
        and math.max(0, visit.due_day - today + 1) or nil
    return {
        approved = true,
        direction = direction,
        action = actionLabel,
        traveler_name = traveler.name,
        territory_name = territory.name,
        authorization = authorization,
        permanent = permanent,
        stay_days = remaining,
        due_day = visit.due_day,
        entered_day = visit.entered_day,
        exited_day = visit.exited_day,
        visiting = direction == "enter",
    }
end

function actions.PAY_CODE_PREVIEW(payload)
    local account = requireSession(payload)
    cleanupEphemeral()
    local code = string.upper(util.trim(payload.code))
    local payment = state.active_pay_codes[code]
    need(payment and payment.status == "pending"
        and payment.expires_at > util.nowMs(),
        "BAD_CODE", "Code is invalid or expired")
    local terminal = state.terminals[payment.terminal_id]
    need(terminal, "TERMINAL_NOT_FOUND", "Kiosk no longer exists")
    resetDailySpend(account)
    local pinRequired = payment.kind == "subscription"
        or (payment.kind ~= "withdrawal"
        and (payment.amount > config.pin_free_limit
            or account.daily_spent + payment.amount > config.daily_spend_limit)
        )
    return {
        code = code,
        kind = payment.kind,
        amount = payment.amount,
        merchant = terminal.name,
        items = util.copy(payment.items or {}),
        description = payment.description,
        pin_required = pinRequired,
        expires_in_ms = payment.expires_at - util.nowMs(),
    }
end

local function settleCode(account, payment, pin)
    local terminal = state.terminals[payment.terminal_id]
    need(terminal, "TERMINAL_NOT_FOUND", "Kiosk no longer exists")
    resetDailySpend(account)
    local subscriptionId
    if payment.kind == "withdrawal" then
        debitMerchant(terminal, payment.amount,
            "Withdrawal code " .. payment.code, account)
        account.balance = util.roundMoney(account.balance + payment.amount)
        transaction(account, "kiosk_withdrawal", payment.amount,
            terminal.name, payment.description or "Kiosk withdrawal", {
                company_id = terminal.company_id,
                terminal_id = terminal.terminal_id,
            })
        notification(account, "Withdrawal received",
            util.money(payment.amount, config.currency) .. " from " .. terminal.name,
            "money")
    elseif payment.kind == "subscription" then
        need(verifyAccount(account, pin), "BAD_PIN", "Incorrect PIN")
        need(account.balance >= payment.amount,
            "INSUFFICIENT_FUNDS", "Not enough money for the first charge")
        account.balance = util.roundMoney(account.balance - payment.amount)
        account.daily_spent = util.roundMoney(
            account.daily_spent + payment.amount)
        creditMerchant(terminal, payment.amount,
            payment.description or "Subscription", account)
        transaction(account, "subscription_start", -payment.amount,
            terminal.name, payment.description or "Subscription", {
                company_id = terminal.company_id,
                terminal_id = terminal.terminal_id,
            })
        subscriptionId = nextId("subscription")
        account.subscriptions[subscriptionId] = {
            subscription_id = subscriptionId,
            amount = payment.amount,
            description = util.safeText(
                payment.description or "Kiosk subscription", 60),
            kiosk_id = terminal.terminal_id,
            company_id = terminal.company_id,
            next_charge_day = util.ingameDay() + 1,
            active = true,
            created_day = util.ingameDay(),
            source_code = payment.code,
        }
        notification(account, "Subscription started",
            util.safeText(payment.description or terminal.name, 40)
                .. " - " .. util.money(payment.amount, config.currency)
                .. "/day", "subscription")
    else
        local pinRequired = payment.amount > config.pin_free_limit
            or account.daily_spent + payment.amount > config.daily_spend_limit
        if pinRequired then
            need(verifyAccount(account, pin), "BAD_PIN", "Incorrect PIN")
        end
        need(account.balance >= payment.amount, "INSUFFICIENT_FUNDS", "Not enough money")
        account.balance = util.roundMoney(account.balance - payment.amount)
        account.daily_spent = util.roundMoney(account.daily_spent + payment.amount)
        creditMerchant(terminal, payment.amount,
            payment.description or "Kiosk payment", account)
        transaction(account, "purchase", -payment.amount, terminal.name,
            payment.description or "Kiosk payment", {
                company_id = terminal.company_id,
                terminal_id = terminal.terminal_id,
            })
        notification(account, "Payment accepted",
            util.money(payment.amount, config.currency) .. " at " .. terminal.name,
            "success")
    end
    payment.status = "paid"
    payment.paid_by = account.account_id
    payment.paid_at = util.nowMs()
    save()
    logActivity("Code " .. payment.code .. " paid "
        .. util.money(payment.amount, config.currency), colors.lime)
    return {
        amount = payment.amount,
        kind = payment.kind,
        merchant = terminal.name,
        balance = account.balance,
        subscription_id = subscriptionId,
    }
end

function actions.PAY_CODE_CONFIRM(payload)
    local account = requireSession(payload)
    cleanupEphemeral()
    local code = string.upper(util.trim(payload.code))
    local payment = state.active_pay_codes[code]
    need(payment and payment.status == "pending"
        and payment.expires_at > util.nowMs(),
        "BAD_CODE", "Code is invalid or expired")
    return settleCode(account, payment, payload.pin)
end

function actions.LIST_EVENTS(payload)
    requireSession(payload)
    local today = util.ingameDay()
    local events = util.sortedValues(state.events, function(event)
        return event.status == "active" and tonumber(event.event_day) >= today
    end, function(a, b)
        if a.event_day ~= b.event_day then return a.event_day < b.event_day end
        return (util.parseEventTime(a.event_time) or 0)
            < (util.parseEventTime(b.event_time) or 0)
    end)
    local output = {}
    for _, event in ipairs(events) do
        local sold, total, minimum = 0, 0, nil
        for _, typeId in ipairs(event.ticket_type_ids or {}) do
            local ticketType = state.ticket_types[typeId]
            if ticketType then
                sold = sold + ticketType.sold_quantity
                total = total + ticketType.total_quantity
                minimum = not minimum and ticketType.price or math.min(minimum, ticketType.price)
            end
        end
        output[#output + 1] = {
            event_id = event.event_id,
            title = event.title,
            description = event.description,
            location = event.location,
            event_day = event.event_day,
            event_time = event.event_time,
            sold = sold,
            total = total,
            from_price = minimum,
        }
    end
    return { events = output }
end

function actions.EVENT_DETAILS(payload)
    requireSession(payload)
    local event = state.events[payload.event_id]
    need(event and event.status == "active", "NOT_FOUND", "Event not found")
    local types = {}
    for _, id in ipairs(event.ticket_type_ids or {}) do
        local ticketType = state.ticket_types[id]
        if ticketType then
            local item = util.copy(ticketType)
            item.available_quantity = ticketType.total_quantity - ticketType.sold_quantity
            types[#types + 1] = item
        end
    end
    return { event = util.copy(event), ticket_types = types }
end

function actions.BUY_TICKETS(payload)
    local account = requireSession(payload)
    local event = state.events[payload.event_id]
    local ticketType = state.ticket_types[payload.ticket_type_id]
    need(event and event.status == "active" and ticketType
        and ticketType.event_id == event.event_id,
        "NOT_FOUND", "Ticket type not found")
    local quantity = math.floor(tonumber(payload.quantity) or 0)
    need(quantity >= 1 and quantity <= config.max_ticket_quantity,
        "BAD_QUANTITY", "Choose 1-" .. config.max_ticket_quantity .. " tickets")
    need(ticketType.sold_quantity + quantity <= ticketType.total_quantity,
        "SOLD_OUT", "Not enough tickets are left")
    need(verifyAccount(account, payload.pin), "BAD_PIN", "Incorrect PIN")
    local total = util.roundMoney(ticketType.price * quantity)
    need(account.balance >= total, "INSUFFICIENT_FUNDS", "Not enough money")

    local organizer = state.accounts[event.organizer_account_id]
    checkAccountActive(organizer)
    account.balance = util.roundMoney(account.balance - total)
    organizer.balance = util.roundMoney(organizer.balance + total)
    account.daily_spent = util.roundMoney(account.daily_spent + total)
    ticketType.sold_quantity = ticketType.sold_quantity + quantity
    if ticketType.sold_quantity >= ticketType.total_quantity then
        ticketType.status = "sold_out"
    end

    local tickets = {}
    for _ = 1, quantity do
        local ticket = {
            ticket_id = nextId("ticket"),
            event_id = event.event_id,
            ticket_type_id = ticketType.ticket_type_id,
            account_id = account.account_id,
            qr_code = util.randomString(8),
            used = false,
            status = "valid",
            purchased_day = util.ingameDay(),
        }
        state.tickets[ticket.ticket_id] = ticket
        tickets[#tickets + 1] = util.copy(ticket)
    end
    transaction(account, "ticket_purchase", -total, event.title,
        quantity .. "x " .. ticketType.name)
    transaction(organizer, "ticket_revenue", total, account.name,
        event.title .. " - " .. ticketType.name)
    notification(account, "Tickets purchased",
        quantity .. "x " .. ticketType.name .. " for " .. event.title, "event")
    notification(organizer, "Ticket sale",
        account.name .. " bought " .. quantity .. "x " .. ticketType.name, "money")
    save()
    logActivity("Tickets sold: " .. event.title .. " x" .. quantity, colors.magenta)
    return {
        tickets = tickets,
        total = total,
        balance = account.balance,
        event = util.copy(event),
        ticket_type = util.copy(ticketType),
    }
end

function actions.MY_TICKETS(payload)
    local account = requireSession(payload)
    local output = {}
    for _, ticket in pairs(state.tickets) do
        if ticket.account_id == account.account_id then
            local event = state.events[ticket.event_id]
            local ticketType = state.ticket_types[ticket.ticket_type_id]
            if event and ticketType then
                local item = util.copy(ticket)
                item.event_title = event.title
                item.location = event.location
                item.event_day = event.event_day
                item.event_time = event.event_time
                item.ticket_type_name = ticketType.name
                output[#output + 1] = item
            end
        end
    end
    table.sort(output, function(a, b)
        if a.event_day ~= b.event_day then return a.event_day < b.event_day end
        return a.event_time < b.event_time
    end)
    return { tickets = output }
end

function actions.DECLARATION_STATUS(payload)
    local account = requireSession(payload)
    local openPeriod
    for _, period in pairs(state.declaration_periods) do
        if period.status == "open" then openPeriod = period break end
    end
    if not openPeriod then return { period = nil } end
    local declaration = state.declarations[openPeriod.period_id]
        and state.declarations[openPeriod.period_id][account.account_id] or nil
    return {
        period = util.copy(openPeriod),
        declaration = util.copy(declaration),
        smart_lifetime = account.smart_declaration_lifetime,
    }
end

local function calculatePersonalDue(account, period)
    local income = 0
    for _, tx in ipairs(state.transactions) do
        if tx.account_id == account.account_id
            and tx.day >= period.start_day and tx.day <= period.end_day
            and tx.amount > 0
            and (tx.type == "transfer_in" or tx.type == "merchant_credit"
                or tx.type == "ticket_revenue") then
            income = income + tx.amount
        end
    end
    return util.roundMoney(income * period.personal_rate / 100), income
end

local function submitDeclaration(account, period, amount, smart)
    local declarations = state.declarations[period.period_id]
    declarations[account.account_id] = declarations[account.account_id] or {
        account_id = account.account_id,
        status = "requested",
    }
    local record = declarations[account.account_id]
    local due, income = calculatePersonalDue(account, period)
    local payment = amount
    local fee = 0
    if smart then
        payment = due
        if not account.smart_declaration_lifetime then
            fee = config.smart_declare_fee
        end
    end
    need(account.balance >= payment + fee, "INSUFFICIENT_FUNDS",
        "Not enough money for declaration and fee")
    account.balance = util.roundMoney(account.balance - payment - fee)
    state.tax_revenue = util.roundMoney(state.tax_revenue + payment + fee)
    record.status = "submitted"
    record.declared_amount = payment
    record.calculated_due = due
    record.taxable_income = income
    record.smart = smart == true
    record.fee = fee
    record.submitted_day = util.ingameDay()
    record.difference = util.roundMoney(due - payment)
    transaction(account, "tax_payment", -(payment + fee), "Government",
        smart and "Smart declaration" or "Tax declaration", { tax_amount = payment })
    if record.difference > 0 then
        notification(account, "Tax difference due",
            "Please pay " .. util.money(record.difference, config.currency)
                .. " more for period " .. period.period_id, "warning")
    elseif record.difference < 0 then
        local refund = math.abs(record.difference)
        account.balance = util.roundMoney(account.balance + refund)
        state.tax_revenue = util.roundMoney(state.tax_revenue - refund)
        transaction(account, "tax_refund", refund, "Government",
            "Tax overpayment refund", { tax_amount = -refund })
        record.refund = refund
    end
    save()
    return {
        declaration = util.copy(record),
        balance = account.balance,
    }
end

function actions.FILE_DECLARATION(payload)
    local account = requireSession(payload)
    local period = state.declaration_periods[payload.period_id]
    need(period and period.status == "open", "NO_PERIOD", "Tax period is closed")
    need(verifyAccount(account, payload.pin), "BAD_PIN", "Incorrect PIN")
    return submitDeclaration(account, period, validateAmount(payload.amount), false)
end

function actions.SMART_DECLARE(payload)
    local account = requireSession(payload)
    local period = state.declaration_periods[payload.period_id]
    need(period and period.status == "open", "NO_PERIOD", "Tax period is closed")
    need(verifyAccount(account, payload.pin), "BAD_PIN", "Incorrect PIN")
    if payload.buy_lifetime and not account.smart_declaration_lifetime then
        need(account.balance >= config.lifetime_smart_declare_fee,
            "INSUFFICIENT_FUNDS", "Not enough money for lifetime Smart Declare")
        account.balance = util.roundMoney(account.balance
            - config.lifetime_smart_declare_fee)
        state.tax_revenue = util.roundMoney(state.tax_revenue
            + config.lifetime_smart_declare_fee)
        account.smart_declaration_lifetime = true
        transaction(account, "service_fee", -config.lifetime_smart_declare_fee,
            "Government", "Lifetime Smart Declare")
    end
    return submitDeclaration(account, period, 0, true)
end

function actions.PAY_TAX_DIFFERENCE(payload)
    local account = requireSession(payload)
    local period = state.declaration_periods[payload.period_id]
    need(period, "NO_PERIOD", "Tax period not found")
    local record = state.declarations[period.period_id]
        and state.declarations[period.period_id][account.account_id]
    need(record and record.status == "submitted" and (record.difference or 0) > 0,
        "NOTHING_DUE", "No tax difference is due")
    need(verifyAccount(account, payload.pin), "BAD_PIN", "Incorrect PIN")
    local amount = util.roundMoney(record.difference)
    need(account.balance >= amount, "INSUFFICIENT_FUNDS",
        "Not enough money for the tax difference")
    account.balance = util.roundMoney(account.balance - amount)
    state.tax_revenue = util.roundMoney(state.tax_revenue + amount)
    record.supplemental_payment = util.roundMoney(
        (record.supplemental_payment or 0) + amount)
    record.declared_amount = util.roundMoney((record.declared_amount or 0) + amount)
    record.difference = 0
    record.settled_day = util.ingameDay()
    transaction(account, "tax_payment", -amount, "Government",
        "Tax difference for " .. period.period_id, { tax_amount = amount })
    notification(account, "Tax settled",
        period.period_id .. " is now fully paid", "success")
    save()
    return {
        declaration = util.copy(record),
        paid = amount,
        balance = account.balance,
    }
end

-- Service kiosk routes -------------------------------------------------------

function actions.KIOSK_REGISTER(payload)
    if payload.terminal_id and payload.terminal_token then
        local existing = state.terminals[payload.terminal_id]
        if existing and existing.auth_token == payload.terminal_token then
            existing.last_seen = util.nowMs()
            return {
                terminal_id = existing.terminal_id,
                terminal_token = existing.auth_token,
                name = existing.name,
                linked = existing.company_id ~= nil,
            }
        end
    end
    local terminalId = nextId("terminal")
    local terminal = {
        terminal_id = terminalId,
        auth_token = util.token("TERMINAL"),
        name = util.safeText(payload.name or ("Kiosk " .. terminalId), 24),
        company_id = nil,
        quick_items = {},
        balance = 0,
        sales_total = 0,
        status = "active",
        created_day = util.ingameDay(),
        last_seen = util.nowMs(),
    }
    state.terminals[terminalId] = terminal
    save()
    logActivity("Registered " .. terminal.name, colors.orange)
    return {
        terminal_id = terminalId,
        terminal_token = terminal.auth_token,
        name = terminal.name,
        linked = false,
    }
end

function actions.KIOSK_OWNER_LOGIN(payload)
    requireTerminal(payload)
    local account = accountByName(payload.name)
    need(verifyAccount(account, payload.pin), "BAD_LOGIN", "Owner name or PIN is wrong")
    checkAccountActive(account)
    return {
        owner_session = createSession(account),
        owner = publicAccount(account),
    }
end

function actions.OWNER_COMPANIES(payload)
    local owner = requireSession({ session_token = payload.owner_session })
    local output = util.sortedValues(state.companies, function(company)
        return company.owner_account_id == owner.account_id
            and company.status == "active"
    end, function(a, b) return a.name < b.name end)
    return { companies = util.copy(output) }
end

function actions.CREATE_COMPANY(payload)
    local owner = requireSession({ session_token = payload.owner_session })
    local name = util.safeText(util.trim(payload.company_name), 28)
    need(#name >= 2, "INVALID_NAME", "Company name is too short")
    for _, company in pairs(state.companies) do
        need(util.normalName(company.name) ~= util.normalName(name),
            "NAME_TAKEN", "Company name is taken")
    end
    local companyId = nextId("company")
    local company = {
        company_id = companyId,
        name = name,
        tax_id = "TX-" .. util.randomString(6),
        owner_account_id = owner.account_id,
        linked_terminal_ids = {},
        quick_items = {},
        status = "active",
        created_day = util.ingameDay(),
    }
    state.companies[companyId] = company
    save()
    return { company = util.copy(company) }
end

function actions.LINK_TERMINAL(payload)
    local terminal = requireTerminal(payload)
    local owner = requireSession({ session_token = payload.owner_session })
    local company = state.companies[payload.company_id]
    need(company and company.owner_account_id == owner.account_id,
        "NOT_OWNER", "You do not own that company")
    if terminal.company_id and terminal.company_id ~= company.company_id then
        local previous = state.companies[terminal.company_id]
        if previous then
            for index = #previous.linked_terminal_ids, 1, -1 do
                if previous.linked_terminal_ids[index] == terminal.terminal_id then
                    table.remove(previous.linked_terminal_ids, index)
                end
            end
        end
    end
    terminal.company_id = company.company_id
    local found = false
    for _, id in ipairs(company.linked_terminal_ids) do
        if id == terminal.terminal_id then found = true break end
    end
    if not found then company.linked_terminal_ids[#company.linked_terminal_ids + 1]
        = terminal.terminal_id end
    save()
    logActivity(terminal.name .. " linked to " .. company.name, colors.cyan)
    return { company = util.copy(company), terminal = util.copy(terminal) }
end

function actions.KIOSK_STATE(payload)
    local terminal = requireTerminal(payload)
    cleanupEphemeral()
    local company, owner = companyOwner(terminal)
    return {
        terminal = {
            terminal_id = terminal.terminal_id,
            name = terminal.name,
            company_id = terminal.company_id,
            balance = merchantBalance(terminal),
            sales_total = terminal.sales_total,
        },
        company = company and {
            company_id = company.company_id,
            name = company.name,
            tax_id = company.tax_id,
            owner_name = owner and owner.name,
        } or nil,
        products = util.copy(quickItems(terminal)),
        -- Kept for one release so an older kiosk can update cleanly.
        quick_items = util.copy(quickItems(terminal)),
    }
end

function actions.ADD_PRODUCT(payload)
    local terminal = requireTerminal(payload)
    local items = quickItems(terminal)
    need(#items < 80, "ITEM_LIMIT", "Maximum 80 products")
    local name = util.safeText(util.trim(payload.name), 20)
    need(#name >= 1, "INVALID_NAME", "Product needs a name")
    local price = validateAmount(payload.price, 1000000)
    local kind = string.lower(util.trim(payload.kind))
    need(kind == "one_time" or kind == "subscription",
        "INVALID_PRODUCT_KIND", "Choose One Time or Subscription")
    local item = {
        item_id = util.token("ITEM"):sub(1, 13),
        name = name,
        price = price,
        kind = kind,
        favorite = payload.favorite == true,
    }
    items[#items + 1] = item
    save()
    return { item = util.copy(item), products = util.copy(items) }
end

function actions.SET_PRODUCT_FAVORITE(payload)
    local terminal = requireTerminal(payload)
    local items = quickItems(terminal)
    for _, item in ipairs(items) do
        if item.item_id == payload.item_id then
            item.favorite = payload.favorite == true
            save()
            return { item = util.copy(item), products = util.copy(items) }
        end
    end
    reject("NOT_FOUND", "Product not found")
end

function actions.REMOVE_PRODUCT(payload)
    local terminal = requireTerminal(payload)
    local items = quickItems(terminal)
    for index, item in ipairs(items) do
        if item.item_id == payload.item_id then
            table.remove(items, index)
            save()
            return { products = util.copy(items) }
        end
    end
    reject("NOT_FOUND", "Item not found")
end

-- Compatibility aliases for kiosks updating from v5.3.
function actions.ADD_QUICK_ITEM(payload)
    payload.kind = payload.kind or "one_time"
    local result = actions.ADD_PRODUCT(payload)
    result.quick_items = result.products
    return result
end

function actions.REMOVE_QUICK_ITEM(payload)
    local result = actions.REMOVE_PRODUCT(payload)
    result.quick_items = result.products
    return result
end

local function uniqueCode(length)
    local code
    repeat code = util.randomString(length) until not state.active_pay_codes[code]
    return code
end

function actions.CREATE_PAY_CODE(payload)
    local terminal = requireTerminal(payload)
    local amount = validateAmount(payload.amount, 1000000)
    local purchaseType = string.lower(util.trim(
        payload.purchase_type or "one_time"))
    need(purchaseType == "one_time" or purchaseType == "subscription",
        "INVALID_PURCHASE_TYPE", "Choose One Time or Subscription")
    local code = uniqueCode(6)
    local items = {}
    for index, item in ipairs(payload.items or {}) do
        if index > 30 then break end
        items[#items + 1] = {
            name = util.safeText(item.name, 20),
            price = validateAmount(item.price, 1000000),
            quantity = math.max(1, math.floor(tonumber(item.quantity) or 1)),
        }
    end
    state.active_pay_codes[code] = {
        code = code,
        kind = purchaseType == "subscription" and "subscription" or "sale",
        amount = amount,
        items = items,
        description = util.safeText(payload.description or "Purchase", 80),
        terminal_id = terminal.terminal_id,
        company_id = terminal.company_id,
        status = "pending",
        created_at = util.nowMs(),
        expires_at = util.nowMs() + config.payment_code_ttl_ms,
    }
    save()
    return {
        code = code,
        amount = amount,
        kind = state.active_pay_codes[code].kind,
        expires_at = state.active_pay_codes[code].expires_at,
    }
end

function actions.CREATE_WITHDRAWAL_CODE(payload)
    local terminal = requireTerminal(payload)
    local amount = validateAmount(payload.amount, merchantBalance(terminal))
    local code = uniqueCode(6)
    state.active_pay_codes[code] = {
        code = code,
        kind = "withdrawal",
        amount = amount,
        description = util.safeText(payload.description or "Kiosk withdrawal", 80),
        terminal_id = terminal.terminal_id,
        company_id = terminal.company_id,
        status = "pending",
        created_at = util.nowMs(),
        expires_at = util.nowMs() + config.payment_code_ttl_ms,
    }
    save()
    return {
        code = code,
        amount = amount,
        expires_at = state.active_pay_codes[code].expires_at,
    }
end

function actions.CODE_STATUS(payload)
    local terminal = requireTerminal(payload)
    cleanupEphemeral()
    local payment = state.active_pay_codes[string.upper(payload.code or "")]
    need(payment and payment.terminal_id == terminal.terminal_id,
        "NOT_FOUND", "Code not found")
    local payer = payment.paid_by and state.accounts[payment.paid_by]
    return {
        status = payment.status,
        amount = payment.amount,
        kind = payment.kind,
        payer = payer and payer.name,
        expires_in_ms = math.max(0, payment.expires_at - util.nowMs()),
    }
end

function actions.CANCEL_CODE(payload)
    local terminal = requireTerminal(payload)
    local code = string.upper(util.trim(payload.code))
    local payment = state.active_pay_codes[code]
    need(payment and payment.terminal_id == terminal.terminal_id,
        "NOT_FOUND", "Code not found")
    need(payment.status == "pending", "ALREADY_COMPLETE",
        "Code has already been completed")
    payment.status = "cancelled"
    payment.cancelled_at = util.nowMs()
    save()
    return { status = "cancelled" }
end

-- Event organizer routes ----------------------------------------------------

function actions.EVENT_DASHBOARD(payload)
    local owner = requireSession(payload)
    local active, sold, revenue = 0, 0, 0
    for _, event in pairs(state.events) do
        if event.organizer_account_id == owner.account_id then
            if event.status == "active" then active = active + 1 end
            for _, typeId in ipairs(event.ticket_type_ids or {}) do
                local ticketType = state.ticket_types[typeId]
                if ticketType then
                    sold = sold + ticketType.sold_quantity
                    revenue = revenue + ticketType.sold_quantity * ticketType.price
                end
            end
        end
    end
    return {
        account = publicAccount(owner),
        active_events = active,
        tickets_sold = sold,
        revenue = util.roundMoney(revenue),
    }
end

function actions.CREATE_EVENT(payload)
    local owner = requireSession(payload)
    local title = util.safeText(util.trim(payload.title), 40)
    need(#title >= 2, "INVALID_TITLE", "Event title is too short")
    local day = math.floor(tonumber(payload.event_day) or -1)
    need(day >= util.ingameDay(), "INVALID_DAY", "Event day is in the past")
    need(util.parseEventTime(payload.event_time), "INVALID_TIME", "Use time HH:MM")
    local id = nextId("event")
    local event = {
        event_id = id,
        title = title,
        description = util.safeText(payload.description, 120),
        location = util.safeText(payload.location, 60),
        event_day = day,
        event_time = payload.event_time,
        organizer_account_id = owner.account_id,
        ticket_type_ids = {},
        status = "active",
        created_day = util.ingameDay(),
    }
    state.events[id] = event
    save()
    logActivity("Event created: " .. title, colors.magenta)
    return { event = util.copy(event) }
end

function actions.MY_EVENTS(payload)
    local owner = requireSession(payload)
    local output = util.sortedValues(state.events, function(event)
        return event.organizer_account_id == owner.account_id
    end, function(a, b) return a.event_day < b.event_day end)
    for _, event in ipairs(output) do
        event.ticket_types = {}
        for _, id in ipairs(event.ticket_type_ids or {}) do
            event.ticket_types[#event.ticket_types + 1] = util.copy(state.ticket_types[id])
        end
    end
    return { events = util.copy(output) }
end

local function ownedEvent(payload)
    local owner = requireSession(payload)
    local event = state.events[payload.event_id]
    need(event and event.organizer_account_id == owner.account_id,
        "NOT_OWNER", "Event not found or not yours")
    return owner, event
end

function actions.ADD_TICKET_TYPE(payload)
    local _, event = ownedEvent(payload)
    local name = util.safeText(util.trim(payload.name), 28)
    need(#name >= 1, "INVALID_NAME", "Ticket type needs a name")
    local price = validateAmount(payload.price, 1000000)
    local quantity = math.floor(tonumber(payload.quantity) or 0)
    need(quantity >= 1 and quantity <= 100000,
        "INVALID_QUANTITY", "Quantity must be 1-100000")
    local id = nextId("ticket_type")
    local ticketType = {
        ticket_type_id = id,
        event_id = event.event_id,
        name = name,
        description = util.safeText(payload.description, 80),
        price = price,
        total_quantity = quantity,
        sold_quantity = 0,
        perks = payload.perks or {},
        status = "available",
    }
    state.ticket_types[id] = ticketType
    event.ticket_type_ids[#event.ticket_type_ids + 1] = id
    save()
    return { ticket_type = util.copy(ticketType) }
end

function actions.VERIFY_TICKET(payload)
    local owner = requireSession(payload)
    local code = string.upper(util.trim(payload.code))
    local found
    for _, ticket in pairs(state.tickets) do
        if ticket.qr_code == code then found = ticket break end
    end
    need(found, "NOT_FOUND", "Ticket code not found")
    local event = state.events[found.event_id]
    need(event and event.organizer_account_id == owner.account_id,
        "NOT_OWNER", "Ticket is for another organizer")
    local ticketType = state.ticket_types[found.ticket_type_id]
    local holder = state.accounts[found.account_id]
    return {
        ticket = util.copy(found),
        event = util.copy(event),
        ticket_type = util.copy(ticketType),
        holder = holder and holder.name or "Unknown",
        valid = found.status == "valid" and not found.used
            and event.status == "active",
    }
end

function actions.MARK_TICKET_USED(payload)
    local owner = requireSession(payload)
    local ticket = state.tickets[payload.ticket_id]
    need(ticket, "NOT_FOUND", "Ticket not found")
    local event = state.events[ticket.event_id]
    need(event and event.organizer_account_id == owner.account_id,
        "NOT_OWNER", "Ticket is for another organizer")
    need(ticket.status == "valid" and not ticket.used,
        "ALREADY_USED", "Ticket has already been used")
    ticket.used = true
    ticket.status = "used"
    ticket.used_day = util.ingameDay()
    ticket.used_time = util.formatClock()
    save()
    logActivity("Ticket admitted: " .. ticket.qr_code, colors.lime)
    return { ticket = util.copy(ticket) }
end

-- Government routes --------------------------------------------------------

function actions.GOVERNMENT_LOGIN(payload)
    need(payload.key == governmentKey(),
        "BAD_KEY", "Government key is incorrect")
    local token = util.token("GOV")
    governmentSessions[token] = {
        expires_at = util.nowMs() + config.session_ttl_ms,
    }
    logActivity("Government controller login", colors.orange)
    return { government_token = token }
end

function actions.GOVERNMENT_STATS(payload)
    requireGovernment(payload)
    local companies, declarations = 0, 0
    for _ in pairs(state.companies) do companies = companies + 1 end
    for _, period in pairs(state.declarations) do
        for _ in pairs(period) do declarations = declarations + 1 end
    end
    local accounts = 0
    for _ in pairs(state.accounts) do accounts = accounts + 1 end
    return {
        accounts = accounts,
        companies = companies,
        transactions = #state.transactions,
        declarations = declarations,
        tax_revenue = state.tax_revenue,
        version = config.version,
        uptime = math.floor(os.clock()),
        day = util.ingameDay(),
    }
end

function actions.TAX_OVERVIEW(payload)
    requireGovernment(payload)
    local periods = util.sortedValues(state.declaration_periods, nil, function(a, b)
        return a.start_day > b.start_day
    end)
    local output = {}
    for _, period in ipairs(periods) do
        local requested, submitted, collected = 0, 0, 0
        for _, declaration in pairs(state.declarations[period.period_id] or {}) do
            requested = requested + 1
            if declaration.status == "submitted" then
                submitted = submitted + 1
                collected = collected + (declaration.declared_amount or 0)
                    + (declaration.fee or 0)
            end
        end
        local item = util.copy(period)
        item.requested = requested
        item.submitted = submitted
        item.collected = util.roundMoney(collected)
        output[#output + 1] = item
    end
    return {
        periods = output,
        total_revenue = state.tax_revenue,
    }
end

function actions.OPEN_TAX_PERIOD(payload)
    requireGovernment(payload)
    for _, existing in pairs(state.declaration_periods) do
        need(existing.status ~= "open", "PERIOD_OPEN", "A period is already open")
    end
    local endDay = math.floor(tonumber(payload.end_day) or 0)
    need(endDay >= util.ingameDay(), "INVALID_DAY", "End day cannot be in the past")
    local personalRate = tonumber(payload.personal_rate)
    local commercialRate = tonumber(payload.commercial_rate)
    local threshold = tonumber(payload.threshold)
    need(personalRate and personalRate >= 0 and personalRate <= 100,
        "INVALID_RATE", "Personal rate must be 0-100")
    need(commercialRate and commercialRate >= 0 and commercialRate <= 100,
        "INVALID_RATE", "Commercial rate must be 0-100")
    need(threshold and threshold >= 0, "INVALID_THRESHOLD", "Threshold is invalid")
    local id = nextId("period")
    local period = {
        period_id = id,
        start_day = util.ingameDay(),
        end_day = endDay,
        personal_rate = personalRate,
        commercial_rate = commercialRate,
        threshold = threshold,
        status = "open",
    }
    state.declaration_periods[id] = period
    state.declarations[id] = {}
    for accountId, account in pairs(state.accounts) do
        local _, income = calculatePersonalDue(account, period)
        if income >= threshold then
            state.declarations[id][accountId] = {
                account_id = accountId,
                status = "requested",
            }
            notification(account, "Tax declaration open",
                "File by in-game day " .. endDay, "tax")
        end
    end
    save()
    logActivity("Tax period opened: " .. id, colors.orange)
    return { period = util.copy(period) }
end

function actions.SET_TAX_RATES(payload)
    requireGovernment(payload)
    local period
    for _, candidate in pairs(state.declaration_periods) do
        if candidate.status == "open" then period = candidate break end
    end
    need(period, "NO_PERIOD", "No tax period is open")
    local personalRate = tonumber(payload.personal_rate)
    local commercialRate = tonumber(payload.commercial_rate)
    need(personalRate and personalRate >= 0 and personalRate <= 100,
        "INVALID_RATE", "Personal rate must be 0-100")
    need(commercialRate and commercialRate >= 0 and commercialRate <= 100,
        "INVALID_RATE", "Commercial rate must be 0-100")
    period.personal_rate = personalRate
    period.commercial_rate = commercialRate
    save()
    return { period = util.copy(period) }
end

function actions.CLOSE_TAX_PERIOD(payload)
    requireGovernment(payload)
    local period = state.declaration_periods[payload.period_id]
    need(period and period.status == "open", "NO_PERIOD", "Period is not open")
    period.status = "closed"
    period.closed_day = util.ingameDay()
    save()
    logActivity("Tax period closed: " .. period.period_id, colors.red)
    return { period = util.copy(period) }
end

function actions.STATE_DEPOSIT(payload)
    requireGovernment(payload)
    local account = accountByName(payload.recipient)
    checkAccountActive(account)
    local amount = validateAmount(payload.amount, 1000000000)
    account.balance = util.roundMoney(account.balance + amount)
    transaction(account, "state_deposit", amount, "Government",
        payload.reason or "State deposit")
    notification(account, "State deposit",
        util.money(amount, config.currency) .. " - "
            .. util.safeText(payload.reason or "Government payment", 60), "money")
    save()
    logActivity("State deposit to " .. account.name, colors.lime)
    return { account = publicAccount(account), amount = amount }
end

function actions.AUDIT_COMPANY(payload)
    requireGovernment(payload)
    local query = util.normalName(payload.query)
    local found
    for _, company in pairs(state.companies) do
        if util.normalName(company.name) == query
            or util.normalName(company.tax_id) == query then
            found = company break
        end
    end
    need(found, "NOT_FOUND", "Company not found")
    local owner = state.accounts[found.owner_account_id]
    return {
        company = util.copy(found),
        owner_name = owner and owner.name,
    }
end

local function processSubscriptions()
    local today = util.ingameDay()
    if state.last_subscription_day == today then return end
    state.last_subscription_day = today
    local changed = false
    for _, account in pairs(state.accounts) do
        for _, subscription in pairs(account.subscriptions or {}) do
            if subscription.active and subscription.next_charge_day <= today then
                local terminal = state.terminals[subscription.kiosk_id]
                if terminal and account.balance >= subscription.amount
                    and not account.frozen and not account.banned then
                    account.balance = util.roundMoney(account.balance - subscription.amount)
                    creditMerchant(terminal, subscription.amount,
                        subscription.description, account)
                    transaction(account, "subscription", -subscription.amount,
                        terminal.name, subscription.description, {
                            company_id = subscription.company_id,
                            terminal_id = terminal.terminal_id,
                        })
                    notification(account, "Subscription charged",
                        subscription.description .. " -"
                            .. util.money(subscription.amount, config.currency),
                        "subscription")
                else
                    notification(account, "Subscription failed",
                        subscription.description .. " - insufficient funds",
                        "warning")
                end
                subscription.next_charge_day = today + 1
                changed = true
            end
        end
    end
    if changed then
        save()
        logActivity("Daily subscriptions processed", colors.cyan)
    end
end

local function deploymentReply(recipient, requestId, ok, data, err, code)
    rednet.send(recipient, {
        version = 1,
        kind = "deploy_response",
        request_id = requestId,
        ok = ok == true,
        data = data,
        error = err,
        code = code,
    }, DEPLOY.protocol)
end

local function deploymentError(recipient, requestId, code, message)
    deploymentReply(recipient, requestId, false, nil, message, code)
end

local function authorizedDeploymentRole(role, code)
    if not RELEASE.programs[role] then
        return false, "INVALID_ROLE", "Unknown PUMPE role"
    end
    if protectedDeployRole(role) and tostring(code or "") ~= DEPLOY.code then
        return false, "PROTECTED_ROLE", "Download code is incorrect"
    end
    return true
end

local function deploymentSourceFor(role, requestedPath)
    for _, file in ipairs(deploymentFilesForRole(role) or {}) do
        if file.path == requestedPath then return file.source end
    end
    return nil
end

-- Role programs are fetched from the public manifest the first time a client
-- actually asks to install one, then cached in /updates. A Bank that nobody
-- installs from never holds a second copy of the release at all.
local function fetchDepotFile(path)
    local manifestUrl = tostring(config.update_manifest_url or "")
    if manifestUrl == "" or config.auto_update == false then return nil end
    local manifest = onlineUpdate.fetchManifest(manifestUrl,
        RELEASE.published, config.update_channel or "stable",
        RELEASE.optional)
    if not manifest or manifest.version ~= config.version then return nil end
    for _, file in ipairs(manifest.files) do
        if file.path == path then
            local body = onlineUpdate.fetchFile(manifestUrl, file,
                manifest.version)
            if body then
                pcall(util.writeFile, fs.combine(UPDATES_DIR, path), body)
                logActivity("Fetched " .. path .. " for deployment", colors.cyan)
            end
            return body
        end
    end
    return nil
end

local function deploymentBody(source)
    if source == "public/config.lua" then
        return util.readFile(fs.combine(UPDATES_DIR, source))
    end
    local body = localUpdateBody(source)
    if body then return body end
    if RELEASE.depot_set[source] then return fetchDepotFile(source) end
    return nil
end

local function deploymentManifest(role)
    local files = deploymentFilesForRole(role)
    if not files then return nil, "Unknown PUMPE role" end
    local manifest = {}
    for _, file in ipairs(files) do
        local body = deploymentBody(file.source)
        if not body then return nil, "Could not read " .. file.source end
        manifest[#manifest + 1] = {
            path = file.path,
            size = #body,
            checksum = util.checksum(body),
        }
    end
    return manifest
end

local function deploymentRoute(sender, message)
    if type(message) ~= "table" or message.kind ~= "deploy_request"
        or type(message.request_id) ~= "string" then return end
    local payload = type(message.payload) == "table" and message.payload or {}
    local role = string.lower(tostring(payload.role or ""))
    local authorized, authCode, authMessage =
        authorizedDeploymentRole(role, payload.code)
    if not authorized then
        deploymentError(sender, message.request_id, authCode, authMessage)
        return
    end

    if message.action == "MANIFEST" then
        local manifest, err = deploymentManifest(role)
        if not manifest then
            deploymentError(sender, message.request_id, "DEPOT_INCOMPLETE", err)
            return
        end
        deploymentReply(sender, message.request_id, true, {
            role = role,
            version = config.version,
            install_root = "/pumpe",
            chunk_size = DEPLOY.chunk,
            files = manifest,
        })
    elseif message.action == "FILE_CHUNK" then
        local requestedPath = tostring(payload.path or "")
        local source = deploymentSourceFor(role, requestedPath)
        if not source then
            deploymentError(sender, message.request_id, "FILE_DENIED",
                "File is not part of this role")
            return
        end
        local body = deploymentBody(source)
        if not body then
            deploymentError(sender, message.request_id, "FILE_MISSING",
                "Update file is unavailable")
            return
        end
        local offset = math.floor(tonumber(payload.offset) or -1)
        local limit = math.floor(tonumber(payload.limit) or DEPLOY.chunk)
        if offset < 0 or offset > #body then
            deploymentError(sender, message.request_id, "BAD_OFFSET",
                "Invalid file offset")
            return
        end
        limit = math.max(1, math.min(DEPLOY.chunk, limit))
        local chunk = body:sub(offset + 1, offset + limit)
        local nextOffset = offset + #chunk
        deploymentReply(sender, message.request_id, true, {
            path = requestedPath,
            offset = offset,
            data = chunk,
            next_offset = nextOffset,
            done = nextOffset >= #body,
            total_size = #body,
        })
    else
        deploymentError(sender, message.request_id, "UNKNOWN_ACTION",
            "Unknown deployment action")
    end
end

local function route(sender, message)
    if type(message) ~= "table" or message.kind ~= "request"
        or type(message.action) ~= "string" then return end
    local handler = actions[message.action]
    if not handler then
        net.reply(sender, config.protocol, message.request_id, false, nil,
            "Unknown bank action", "UNKNOWN_ACTION")
        return
    end
    local ok, result = pcall(handler, message.payload or {}, sender)
    if ok then
        net.reply(sender, config.protocol, message.request_id, true, result)
    elseif type(result) == "table" and result.pumpe then
        net.reply(sender, config.protocol, message.request_id, false, nil,
            result.message, result.code)
    else
        logActivity("Server error: " .. tostring(result), colors.red)
        net.reply(sender, config.protocol, message.request_id, false, nil,
            "Internal bank error", "SERVER_ERROR")
    end
end

-- What the dashboard shows, kept in one table rather than six top-level
-- locals. The file's top level is a single Lua function with a 200 local
-- ceiling, and it was two over.
local dash = {
    stage = fs.combine(ROOT, ".online_update_stage"),
    update_status = "URL NOT CONFIGURED",
    update_color = colors.lightGray,
    last_error = nil,
    deploy_status = "STARTING",
    deploy_color = colors.orange,
}
if tostring(config.update_manifest_url or "") ~= "" then
    dash.update_status, dash.update_color = "CHECKING", colors.orange
end

local function loadConfigTable(path)
    local loader, loadError = loadfile(path)
    if not loader then return nil, loadError end
    local ok, value = pcall(loader)
    if not ok or type(value) ~= "table" then
        return nil, ok and "Config did not return a table" or tostring(value)
    end
    return value
end

local function preserveLocalConfig(manifest)
    local stagedPath = fs.combine(dash.stage, "config.lua")
    local defaults, err = loadConfigTable(stagedPath)
    if not defaults then return nil, "Downloaded config is invalid: " .. tostring(err) end
    if tostring(defaults.version or "") ~= manifest.version then
        return nil, "Downloaded config version does not match the manifest"
    end

    local merged = util.copy(defaults)
    for key, value in pairs(config) do
        if key ~= "version" then merged[key] = util.copy(value) end
    end
    merged.version = manifest.version
    util.writeFile(stagedPath,
        "-- PUMPE configuration. Local settings are preserved during updates.\n"
        .. "return " .. textutils.serialize(merged, { compact = false }) .. "\n")
    return true
end

-- The Bank updates itself through the same shared engine every other role
-- uses, so it downloads only the files it runs rather than the whole release.
local function checkForOnlineUpdate()
    if config.auto_update == false then
        dash.update_status, dash.update_color = "DISABLED", colors.lightGray
        return false
    end
    if tostring(config.update_manifest_url or "") == "" then
        dash.update_status, dash.update_color = "URL NOT CONFIGURED",
            colors.lightGray
        return false
    end

    dash.update_status, dash.update_color = "CHECKING INTERNET", colors.orange
    local updated, detail = onlineUpdate.selfUpdate({
        config = config,
        role = "bank",
        root = ROOT,
        requiredPaths = RELEASE.published,
        optionalPaths = RELEASE.optional,
        onProgress = function(_, index, total)
            dash.update_status = "DOWNLOADING " .. index .. "/" .. total
            dash.update_color = colors.cyan
        end,
        -- Cached role programs are re-fetchable on demand, so they are always
        -- the first thing to give up when a release needs the room.
        onSpaceNeeded = function()
            local freed = 0
            for _, path in ipairs(RELEASE.depot_files) do
                local cached = fs.combine(UPDATES_DIR, path)
                if fs.exists(cached) and not fs.isDir(cached) then
                    local ok, size = pcall(fs.getSize, cached)
                    if ok and type(size) == "number" then freed = freed + size end
                    pcall(fs.delete, cached)
                end
            end
            if freed > 0 then
                logActivity("Dropped " .. math.floor(freed / 1024)
                    .. " KiB of cached role programs", colors.orange)
            end
        end,
    })

    if updated then
        ensureBankStartup()
        util.writeFile(DEPLOY.restart_marker, tostring(detail))
        pcall(save)
        dash.update_status, dash.update_color = "RESTARTING v" .. tostring(detail),
            colors.lime
        logActivity("Online update installed; restarting", colors.lime)
        sleep(0.1)
        os.reboot()
        return true
    end

    if detail == "current" then
        dash.update_status = "CURRENT v" .. config.version
        dash.update_color = colors.lime
        dash.last_error = nil
        return false
    end
    if detail == "disabled" or detail == "no manifest url" then
        dash.update_status, dash.update_color = "DISABLED", colors.lightGray
        return false
    end

    dash.update_status, dash.update_color = "CHECK FAILED", colors.red
    if detail ~= dash.last_error then
        logActivity("Online update: " .. tostring(detail), colors.red)
        dash.last_error = detail
    end
    return false
end

local function serverLoop()
    while running do
        local sender, message = rednet.receive(config.protocol, 1)
        if sender then route(sender, message) end
    end
end

local function deploymentLoop()
    while running do
        local sender, message = rednet.receive(DEPLOY.protocol, 1)
        if sender then
            local ok, err = pcall(deploymentRoute, sender, message)
            if not ok then
                logActivity("Deployment error: " .. tostring(err), colors.red)
                if type(message) == "table" and message.request_id then
                    deploymentError(sender, message.request_id, "DEPLOY_ERROR",
                        "Bank deployment service failed")
                end
            end
        end
    end
end

local function schedulerLoop()
    while running do
        cleanupEphemeral()
        processSubscriptions()
        processBetHolds()
        sleep(10)
    end
end

local function ccgGameLoop()
    while running do
        processCCGGames()
        sleep(0.15)
    end
end

local function onlineUpdateLoop()
    while running do
        checkForOnlineUpdate()
        local interval = math.max(5,
            math.floor(tonumber(config.update_check_seconds) or 10))
        sleep(interval)
    end
end

local function count(map)
    local value = 0
    for _ in pairs(map) do value = value + 1 end
    return value
end

local function dashboardLoop()
    local target = term.current()
    local blink = true
    while running do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "PUMPE BANK SERVER", "v" .. config.version,
            util.formatClock(blink))
        local cardWidth = math.floor((width - 4) / 3)
        local cards = {
            { "ACCOUNTS", count(state.accounts), colors.cyan },
            { "PAYMENTS", #state.transactions, colors.magenta },
            { "CCG GAMES", count(state.ccg_lobbies), colors.lime },
        }
        for index, card in ipairs(cards) do
            local x = 2 + (index - 1) * (cardWidth + 1)
            local panelWidth = index == #cards and width - 1 - x or cardWidth
            ui.card(target, x, 5, panelWidth, 4, card[3])
            ui.text(target, x + 2, 6, card[1], colors.lightGray, colors.gray)
            ui.text(target, x + 2, 7, tostring(card[2]), colors.white,
                colors.gray, panelWidth - 3)
        end
        ui.text(target, 2, 10,
            ui.truncate("INTERNET  " .. dash.update_status, width - 2),
            dash.update_color)
        ui.text(target, 2, 11,
            ui.truncate("DEPLOYMENT  " .. dash.deploy_status, width - 2), dash.deploy_color)

        local scene = ui.scene(target)
        local feedY = 13
        ui.text(target, 2, feedY, "ACTIVITY", colors.lightGray)
        local maxFeed = math.max(1, height - feedY - 2)
        for index = 1, math.min(#activity, maxFeed) do
            local item = activity[index]
            ui.text(target, 2, feedY + index,
                item.time .. "  " .. ui.truncate(item.text, width - 10),
                item.color)
        end
        scene:button("save", width - 18, height, 8, 1, "SAVE",
            { background = colors.blue })
        scene:button("stop", width - 9, height, 8, 1, "STOP",
            { background = colors.red })
        local action = scene:wait({ tickRate = 0.5, flash = false })
        blink = not blink
        if action == "save" then
            save()
            logActivity("Manual save complete", colors.lime)
        elseif action == "stop" then
            if ui.confirm(target, "STOP SERVER", "Save and shut down?",
                "STOP", "BACK") then
                running = false
                save()
                return
            end
        elseif action == "__terminate" then
            running = false
            save()
            return
        end
    end
end

if TEST_MODE then
    return {
        actions = actions,
        state = state,
        cleanup = cleanupEphemeral,
        process_bet_holds = processBetHolds,
        process_ccg_games = processCCGGames,
        advance_survivor = advanceSurvivor,
        deployment_files = deploymentFilesForRole,
        deployment_body = deploymentBody,
        ensure_bank_startup = ensureBankStartup,
        local_update_body = localUpdateBody,
        compact_bank_storage = compactBankStorage,
        deployment_fetch = fetchDepotFile,
        drop_stale_cache = dropStaleDepotCache,
        urgent_calls = urgentCalls,
    }
end

ui.boot(term.current(), "PUMPE BANK", "SECURE ECONOMY CORE")
net.host(config.protocol, config.hostname)
rednet.host(DEPLOY.protocol, DEPLOY.hostname)
logActivity("Server online on computer #" .. os.getComputerID(), colors.lime)
local depotMissing = updateDepotMissingFiles()
if #depotMissing == 0 then
    dash.deploy_status, dash.deploy_color = "READY", colors.lime
    logActivity("Easy Deployment online", colors.lime)
else
    dash.deploy_status = "REPAIRING " .. #depotMissing .. " FILE(S)"
    dash.deploy_color = colors.orange
    logActivity("Deployment missing " .. #depotMissing .. " files", colors.orange)
end
save()

parallel.waitForAny(serverLoop, deploymentLoop, schedulerLoop,
    ccgGameLoop, onlineUpdateLoop, dashboardLoop)
pcall(rednet.unhost, config.protocol)
pcall(rednet.unhost, DEPLOY.protocol)
ui.clear(term.current())
print("PUMPE Bank Server stopped safely.")
