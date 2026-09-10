local ROOT = fs.getDir(shell.getRunningProgram())
if ROOT == "" then ROOT = "." end
package.path = package.path .. ";" .. fs.combine(ROOT, "?.lua")
    .. ";" .. fs.combine(ROOT, "?/init.lua")

-- Stamped by tools/build_release_manifest.js. A program running beside a
-- config.lua from a different release means a partial install.
local PROGRAM_VERSION = "9.1.0"
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

-- Banking between banks -----------------------------------------------------
-- Every bank on the network shares one thing: the Account ID. Sixteen
-- digits, the first four naming the bank that holds it and the last twelve
-- unique inside it, so an ID is enough on its own to find where the money
-- lives. Foxy is bank 0001; a third-party bank picks its own four when its
-- server is set up. Declared here rather than beside its own section because
-- registration mints one, and that runs a thousand lines above.
-- The Account ID and the apply-once rule are shared with every third-party
-- bank, so they live in util. What is not shared is debiting and crediting:
-- an account here has tax demands, pots and a bet wallet, and an account at
-- a third-party bank has a balance and nothing else.
local ledger = setmetatable({}, { __index = util.ledger })

-- Pair Mode. A second Bank Server takes the update depot and the app record
-- store off the Core, so banking never queues behind a file transfer. Both
-- halves run this same program and agree which is which when they pair.
local pair = {
    role = "solo",              -- "solo", "core" or "vault"
    code = nil,                 -- the six digits this server is showing
    partner = nil,              -- the other server's computer id
    partner_code = nil,
    since = nil,
    file = fs.combine(ROOT, "bank_pair_v1.dat"),
}
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
    "app_server.lua",
    "foxy.lua",
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
    "bank_app_server.lua",
    "ccg_server.lua",
    "service_kiosk.lua",
    "event_kiosk.lua",
    "tax_controller.lua",
    "admin_terminal.lua",
    "border_controller.lua",
    "ccg.lua",
    "gps_anchor.lua",
    "app_server.lua",
    "foxy.lua",
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
    "app_server.lua",
    "foxy.lua",
    "bank_app_server.lua",
    "buckapp.lua",
    "ccg_server.lua",
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
    apps = "app_server.lua",
    tpbank = "bank_app_server.lua",
    ccgserver = "ccg_server.lua",
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
    -- The App Server ships with Foxy so a fresh world has something to
    -- download the moment the store is up.
    if role == "apps" then
        files[#files + 1] = { path = "foxy.lua", source = "foxy.lua" }
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
        -- Account ID -> account_id. The index behind the one address every
        -- bank on the network shares.
        bank_account_ids = {},
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
        -- Lobbies and consoles moved to ccg_server.lua in 9.1. What the
        -- Bank holds is the money in play.
        ccg_escrow = {},
        ccg_servers = {},
        ccg_house_profit = 0,
        conversations = {},
        direct_conversations = {},
        proximity_offers = {},
        developers = {},
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
    state.ccg_escrow = state.ccg_escrow or {}
    state.ccg_servers = state.ccg_servers or {}
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
    scan = { "SCAN", 8 },
    pot = { "POT", 8 },
    developer = { "DEV", 6 },
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

-- The Account ID -------------------------------------------------------------
-- Sixteen digits: four naming the bank, twelve naming the account inside it.
-- It is the one thing every bank on the network agrees on, so it is what a
-- transfer is addressed to and what an account is known by anywhere else.

function ledger.bankCode()
    local code = tostring(state.bank_code or config.foxy_bank_code or "0001")
    return code:match("^%d%d%d%d$") and code or "0001"
end

function ledger.mint()
    state.bank_account_ids = state.bank_account_ids or {}
    return ledger.newId(ledger.bankCode(), state.bank_account_ids)
end

-- Every account has one, including every account made before 9.0. Minting
-- them lazily rather than in a migration keeps a Bank with a large ledger
-- from doing all the work at once on the first boot after the update.
function ledger.idFor(account)
    if account.bank_account_id then return account.bank_account_id end
    account.bank_account_id = ledger.mint()
    state.bank_account_ids = state.bank_account_ids or {}
    state.bank_account_ids[account.bank_account_id] = account.account_id
    return account.bank_account_id
end

function ledger.byBankId(bankAccountId)
    bankAccountId = ledger.clean(bankAccountId)
    state.bank_account_ids = state.bank_account_ids or {}
    local accountId = state.bank_account_ids[bankAccountId]
    return accountId and state.accounts[accountId] or nil
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
        -- The one address every bank on the network understands, and
        -- whether the money is still here to be addressed.
        bank_account_id = ledger.idFor(account),
        bank_name = config.bank_name or "Foxy",
        bank_closed = account.bank_closed == true,
        moved_to = account.moved_to,
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

-- `receiving` is passed at the one place money is credited to somebody else,
-- so a send to an account that has moved its money away is refused rather
-- than left sitting somewhere it cannot be spent.
local function checkAccountActive(account, receiving)
    need(account, "ACCOUNT_NOT_FOUND", "Account not found")
    if receiving then
        need(not (account and account.bank_closed), "RECIPIENT_CLOSED",
            (account and account.name or "That account")
                .. " has moved to another bank")
    end
    need(not account.banned, "ACCOUNT_BANNED", "This account is banned")
    need(account.approved ~= false, "ACCOUNT_PENDING",
        "This account is waiting for government approval")
    need(not account.frozen, "ACCOUNT_FROZEN", "This account is frozen")
end

-- Payment features are switched off while a tax demand is outstanding, so a
-- demand handed out as a fine cannot be dodged by spending the balance first.
-- Receiving money, and paying the demand itself, are deliberately still open.
local function checkNoTaxDemand(account)
    need(not account.tax_demand, "TAX_DEMAND_DUE",
        "Settle your tax demand before paying for anything else")
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

-- An account whose money has moved to another bank keeps its Foxy identity,
-- its friends and its apps -- but the money is not here any more, so nothing
-- that spends it can work until it is transferred back.
local function checkBankOpen(account)
    need(not account.bank_closed, "BANK_CLOSED",
        "Your money is at " .. tostring(account.moved_to_name or "another bank")
            .. ". Transfer it back to use it here.")
end

-- Every route that moves money out of an account. requireSession alone is not
-- enough: a new spending action must be added here on purpose.
local function requireSpender(payload)
    local account = requireSession(payload)
    checkBankOpen(account)
    checkNoTaxDemand(account)
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

local function notification(account, title, body, kind, extra)
    local item = {
        notification_id = nextId("notification"),
        title = util.safeText(title, 40),
        body = util.safeText(body, 120),
        kind = kind or "info",
        created_day = util.ingameDay(),
        created_time = util.formatClock(),
        read = false,
    }
    -- An app notification carries the app that sent it and how loudly it may
    -- arrive. Everything the PUMPE itself raises leaves both unset.
    for key, value in pairs(extra or {}) do
        if item[key] == nil then item[key] = value end
    end
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

-- Settling between banks -----------------------------------------------------
-- A transfer crosses two servers, and a lost reply must never mean money
-- created or destroyed. So it is done in three steps, each one safe to
-- repeat: the money is taken out of the balance and parked in a pending
-- record, the far bank is asked to credit it under a transfer id it will
-- only honour once, and only an acknowledged credit clears the record. A
-- transfer that never gets its answer stays parked, and is retried or given
-- back -- it is never simply gone.

function ledger.reach(bankCode)
    return net.client({
        protocol = config.ledger_protocol or "PUMPE_LEDGER_V1",
        hostname = ledger.hostFor(bankCode),
    })
end

function ledger.ask(bankCode, action, payload, timeout)
    if bankCode == ledger.bankCode() then
        -- Both accounts are here. No radio involved.
        local handler = ledger.actions[action]
        if not handler then return nil, "Unknown ledger action" end
        local ok, result = pcall(handler, payload or {})
        if ok then return result end
        if type(result) == "table" and result.pumpe then
            return nil, result.message, result.code
        end
        return nil, "Ledger error"
    end
    return ledger.reach(bankCode):request(action, payload, timeout or 6)
end

function ledger.pending(account)
    account.pending_transfers = account.pending_transfers or {}
    return account.pending_transfers
end

-- Everything a bank will say about one of its accounts to another bank:
-- enough to show who the money is going to, and nothing else.
ledger.actions = {}

function ledger.actions.LEDGER_LOOKUP(payload)
    local account = ledger.byBankId(payload.bank_account_id)
    need(account, "NO_SUCH_ACCOUNT", "No account has that Account ID")
    need(not account.banned, "ACCOUNT_BANNED", "That account is banned")
    return {
        bank_account_id = ledger.idFor(account),
        name = account.name,
        bank_name = config.bank_name or "Foxy",
        bank_code = ledger.bankCode(),
        -- A closed account still takes money: arriving money is exactly
        -- what reopens it, and is how somebody moves back here. Only an
        -- account nobody may pay at all is not accepting.
        accepting = not account.banned,
        closed = account.bank_closed == true,
    }
end

-- Applied at most once, however many times it arrives.
function ledger.actions.LEDGER_STATUS(payload)
    state.applied_transfers = state.applied_transfers or {}
    local applied = ledger.applied(state.applied_transfers,
        util.safeText(tostring(payload.transfer_id or ""), 32))
    return { applied = applied ~= nil, amount = applied and applied.amount }
end

function ledger.actions.LEDGER_CREDIT(payload)
    local account = ledger.byBankId(payload.bank_account_id)
    need(account, "NO_SUCH_ACCOUNT", "No account has that Account ID")
    need(not account.banned, "ACCOUNT_BANNED", "That account is banned")
    local amount = math.floor(tonumber(payload.amount) or 0)
    need(amount > 0, "BAD_AMOUNT", "A transfer has to be worth something")
    local transferId = util.safeText(tostring(payload.transfer_id or ""), 32)
    need(#transferId >= 8, "BAD_TRANSFER", "That transfer has no id")

    state.applied_transfers = state.applied_transfers or {}
    local credited, repeated = ledger.applyOnce(state.applied_transfers,
        transferId, amount, function()
            account.balance = account.balance + amount
            -- Money arriving is how an account comes home. A player who
            -- moved to a third-party bank transfers back to this Account ID,
            -- and the bank account it closed opens again with the money in
            -- it.
            if account.bank_closed then
                account.bank_closed = nil
                account.moved_to = nil
                account.moved_to_name = nil
                notification(account, "Your bank account reopened",
                    "Your money is back at "
                        .. tostring(config.bank_name or "Foxy"), "success")
            end
        end)
    if repeated then
        -- The credit landed; only the answer was lost. Say yes again.
        return { credited = credited, balance = account.balance,
                 repeated = true }
    end
    ledger.forget(state.applied_transfers)
    transaction(account, "bank_transfer_in", amount,
        util.safeText(tostring(payload.from_bank_name or "Another bank"), 20),
        "Transferred in from " .. tostring(payload.from_name or "another bank"))
    notification(account, "Money arrived",
        util.money(amount, config.currency) .. " transferred in from "
            .. tostring(payload.from_bank_name or "another bank"), "money")
    save()
    return { credited = amount, balance = account.balance }
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

-- Sending money out, with the one distinction that matters --------------------
-- A transfer that comes back with a code was refused by the far bank, and
-- nothing was applied: the money can safely go back. A transfer that just
-- never answers might have been applied or might not, and refunding it on a
-- guess is how money gets created. So that case is parked and reconciled
-- later by asking the far bank whether it ever saw the id.
--
-- Returns "sent", "refused" or "unknown".
function ledger.settle(account, targetId, amount, transferId, extra)
    local bankCode = ledger.bankOf(targetId)
    account.balance = util.roundMoney((account.balance or 0) - amount)
    ledger.pending(account)[transferId] = {
        transfer_id = transferId, amount = amount,
        to = targetId, to_bank = bankCode, at = util.nowMs(),
    }
    save()

    local payload = {
        bank_account_id = targetId,
        amount = amount,
        transfer_id = transferId,
        from_name = account.name,
        from_bank_name = config.bank_name or "Foxy",
        from_bank_account_id = ledger.idFor(account),
    }
    for key, value in pairs(extra or {}) do payload[key] = value end
    local outcome, err, code = ledger.outcome(ledger.ask(bankCode,
        "LEDGER_CREDIT", payload, 8))
    if outcome == "sent" then
        ledger.pending(account)[transferId] = nil
        save()
        return "sent"
    end
    if outcome == "refused" then
        -- The far bank answered and said no, so nothing was applied there.
        account.balance = util.roundMoney((account.balance or 0) + amount)
        ledger.pending(account)[transferId] = nil
        save()
        return "refused", err, code
    end
    -- Nobody answered. The money stays parked until ledger.reconcile can
    -- find out which way it went.
    return "unknown", err
end

-- Parked transfers, resolved by asking rather than assuming.
function ledger.reconcile()
    for _, account in pairs(state.accounts) do
        for transferId, parked in pairs(ledger.pending(account)) do
            local answer = ledger.ask(ledger.bankOf(parked.to),
                "LEDGER_STATUS", { transfer_id = transferId }, 6)
            if answer then
                if answer.applied then
                    -- It did land. The debit stands.
                    ledger.pending(account)[transferId] = nil
                    transaction(account, "bank_transfer_out", parked.amount,
                        account.moved_to_name or "Another bank",
                        "Transfer confirmed")
                else
                    -- It never landed, and now we know it.
                    account.balance = util.roundMoney(
                        (account.balance or 0) + parked.amount)
                    ledger.pending(account)[transferId] = nil
                    notification(account, "Transfer came back",
                        util.money(parked.amount, config.currency)
                            .. " could not be delivered", "warning")
                end
                save()
            end
        end
    end
end

-- Money that lands in a closed account follows it -------------------------------
-- There are about twenty places in this file that credit an account, and
-- sealing every one of them against a closed account is the kind of change
-- that misses one. So instead of trying to keep money out, anything that
-- does arrive is forwarded to the bank the account moved to. Nothing is
-- stranded even if a door was left open.
function ledger.sweep()
    for _, account in pairs(state.accounts) do
        if account.bank_closed and account.moved_to
            and (account.balance or 0) > 0 then
            local amount = math.floor(account.balance)
            if ledger.settle(account, account.moved_to, amount,
                util.token("SWEEP")) == "sent" then
                transaction(account, "bank_transfer_out", amount,
                    account.moved_to_name or "Another bank",
                    "Followed your money to " .. tostring(
                        account.moved_to_name or "your new bank"))
                save()
            end
        end
    end
end

-- Bank Transfer --------------------------------------------------------------
-- Moving your money to another bank, and the account here closing behind it.
-- Everything the player sees of this is two questions: where to, and are you
-- sure.

function actions.BANK_TRANSFER_QUOTE(payload)
    local account = requireSession(payload)
    checkBankOpen(account)
    checkNoTaxDemand(account)
    local wanted = ledger.clean(payload.bank_account_id)
    need(#wanted == 16, "BAD_ACCOUNT_ID", "An Account ID is sixteen digits")
    need(wanted ~= ledger.idFor(account), "SAME_ACCOUNT",
        "That is this account")
    local bankCode = ledger.bankOf(wanted)
    local found, err, code = ledger.ask(bankCode, "LEDGER_LOOKUP",
        { bank_account_id = wanted })
    if not found then
        need(false, code or "BANK_UNREACHABLE",
            err or ("Bank " .. tostring(bankCode) .. " did not answer"))
    end
    need(found.accepting, "BANK_CLOSED",
        "That account has moved its own money elsewhere")
    return {
        bank_account_id = wanted,
        formatted = ledger.format(wanted),
        name = found.name,
        bank_name = found.bank_name,
        amount = account.balance,
    }
end

function actions.BANK_TRANSFER_CONFIRM(payload)
    local account = requireSession(payload)
    checkBankOpen(account)
    checkNoTaxDemand(account)
    need(verifyAccount(account, payload.pin), "BAD_PIN", "Incorrect PIN")
    local wanted = ledger.clean(payload.bank_account_id)
    need(#wanted == 16, "BAD_ACCOUNT_ID", "An Account ID is sixteen digits")
    need(wanted ~= ledger.idFor(account), "SAME_ACCOUNT", "That is this account")
    local amount = math.floor(account.balance or 0)
    need(amount > 0, "NOTHING_TO_MOVE", "There is nothing here to transfer")

    local bankCode = ledger.bankOf(wanted)
    local found, lookupErr, lookupCode = ledger.ask(bankCode, "LEDGER_LOOKUP",
        { bank_account_id = wanted })
    if not found then
        need(false, lookupCode or "BANK_UNREACHABLE",
            lookupErr or "That bank did not answer")
    end

    local outcome, err, code = ledger.settle(account, wanted, amount,
        util.token("XFER"))
    if outcome == "refused" then
        need(false, code or "TRANSFER_FAILED",
            err or "That bank would not take the transfer")
    elseif outcome == "unknown" then
        -- The money is parked, not lost. Calling this a failure would be a
        -- lie, and giving it back on a guess is how money gets created.
        need(false, "TRANSFER_PENDING",
            "That bank did not answer. Your money is held and will finish"
                .. " moving, or come back, on its own.")
    end

    account.bank_closed = true
    account.moved_to = wanted
    account.moved_to_name = found.bank_name
    transaction(account, "bank_transfer_out", amount, found.bank_name,
        "Transferred to " .. found.bank_name .. " " .. ledger.format(wanted))
    notification(account, "Your money moved",
        util.money(amount, config.currency) .. " went to " .. found.bank_name
            .. ". Your Foxy bank account is closed.", "warning")
    logActivity("Bank transfer " .. account.name .. " > " .. found.bank_name,
        colors.orange)
    save()
    return {
        moved = amount,
        bank_name = found.bank_name,
        bank_account_id = wanted,
    }
end

-- Your own Account ID, and what to do if the money is elsewhere. The one
-- screen that still works when the bank account is closed.
function actions.BANK_IDENTITY(payload)
    local account = requireSession(payload)
    local id = ledger.idFor(account)
    return {
        bank_account_id = id,
        formatted = ledger.format(id),
        bank_name = config.bank_name or "Foxy",
        bank_closed = account.bank_closed == true,
        moved_to = account.moved_to,
        moved_to_name = account.moved_to_name,
        balance = account.balance,
    }
end

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
        bank_account_id = ledger.mint(),
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
    state.bank_account_ids = state.bank_account_ids or {}
    state.bank_account_ids[account.bank_account_id] = accountId
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
    checkAccountActive(recipient, true)
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
    local sender = requireSpender(payload)
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
    local sender = requireSpender(payload)
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

-- Bet Wallet and CCG escrow ---------------------------------------------------
-- The games themselves moved to their own computer in 9.1 (ccg_server.lua).
-- What stays here is the money, because that is what a bank is for: the Bet
-- Wallet, and an escrow the CCG Server can put wagers into but cannot take
-- anything out of.
--
-- The split is drawn so that the worst a rogue or broken CCG Server can do
-- is freeze wagers and choose winners. It never names an amount: the Bank
-- multiplies the stake it is holding by its own copy of the game's
-- multiplier. And escrow nobody settles is refunded here rather than left
-- sitting.

local CCG_GAMES = {
    heads_tails = { name = "Heads or Tails", multiplier = 2 },
    race = { name = "Race", multiplier = 3 },
    survivor = { name = "Survivor", multiplier = 3 },
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

-- Updating out of a world mid-game ---------------------------------------------
-- Before 9.1 a wager lived on the lobby record here, and lobbies are gone.
-- Anybody who was sat in one when the Bank updated would have had their
-- stake vanish with it, so it is given back once, on the first load that
-- finds the old tables.
local function drainPreNineOneLobbies()
    if type(state.ccg_lobbies) ~= "table" then return end
    local refunded, players = 0, 0
    for _, lobby in pairs(state.ccg_lobbies) do
        if not lobby.escrow_closed then
            for accountId, player in pairs(lobby.players or {}) do
                local amount = util.roundMoney(player.wager or 0) or 0
                local account = state.accounts[accountId]
                if account and amount > 0 and not player.settled then
                    local wallet = walletFor(account)
                    wallet.balance = util.roundMoney(wallet.balance + amount)
                    betActivity(account, "wager_refund", amount,
                        "Lobby closed by the 9.1 update",
                        { game = lobby.game, lobby_code = lobby.code })
                    refunded = util.roundMoney(refunded + amount)
                    players = players + 1
                end
            end
        end
    end
    state.ccg_lobbies = nil
    state.ccg_codes = nil
    state.ccg_consoles = nil
    if refunded > 0 then
        logActivity("Refunded " .. players .. " CCG wager(s) closed by 9.1",
            colors.orange)
    end
    save()
end

drainPreNineOneLobbies()

-- A hold is created from a lobby that lives on another computer now, so it
-- is told the game and the code rather than handed a lobby.
local function addBetHold(account, game, lobbyCode, amount)
    local wallet = walletFor(account)
    local releaseMoment = util.ingameMoment()
        + (tonumber(config.bet_hold_ingame_hours) or 24)
    local releaseDay, releaseTime = util.formatIngameMoment(releaseMoment)
    local holdId = nextId("bet_hold")
    local hold = {
        hold_id = holdId,
        amount = util.roundMoney(amount),
        status = "holding",
        game = game,
        game_name = (CCG_GAMES[game] or {}).name or "CCG",
        lobby_code = lobbyCode,
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
            game = game, lobby_code = lobbyCode,
        })
    return hold
end

function actions.BET_UNLOCK(payload)
    local account = requireSpender(payload)
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
    local account = requireSpender(payload)
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

-- The escrow ------------------------------------------------------------------

local function ccgEscrow()
    state.ccg_escrow = state.ccg_escrow or {}
    return state.ccg_escrow
end

-- A CCG Server proves itself once with the operator code, the same code that
-- installs a Bank. It is operator infrastructure, trusted the way a Bank
-- Server is -- but only ever to say who won, never how much.
local function requireCCGServer(payload)
    local token = payload and payload.server_token
    need(type(token) == "string" and state.ccg_servers
        and state.ccg_servers[token], "CCG_AUTH",
        "This CCG Server is not registered with the Bank")
    state.ccg_servers[token].last_seen = util.nowMs()
    return state.ccg_servers[token]
end

local function escrowFor(lobbyCode, game)
    local code = string.upper(util.safeText(
        util.trim(tostring(lobbyCode or "")), 12))
    need(code:match("^[%w]+$"), "BAD_LOBBY", "That lobby has no code")
    local all = ccgEscrow()
    all[code] = all[code] or {
        code = code, game = game, stakes = {},
        opened_at = util.nowMs(),
    }
    if game then all[code].game = game end
    return all[code]
end

-- Anything a CCG Server takes and never settles comes back on its own. This
-- is what makes it safe to hand wagers to a computer that might be switched
-- off mid-game.
local function sweepAbandonedEscrow()
    local limit = (tonumber(config.ccg_escrow_hours) or 2) * 60 * 60 * 1000
    local now = util.nowMs()
    for code, escrow in pairs(ccgEscrow()) do
        if now - (escrow.opened_at or 0) > limit then
            for accountId, amount in pairs(escrow.stakes) do
                local account = state.accounts[accountId]
                if account and amount > 0 then
                    local wallet = walletFor(account)
                    wallet.balance = util.roundMoney(wallet.balance + amount)
                    betActivity(account, "wager_refund", amount,
                        "Abandoned lobby refunded",
                        { game = escrow.game, lobby_code = code })
                end
            end
            ccgEscrow()[code] = nil
            logActivity("Refunded abandoned CCG lobby " .. code, colors.orange)
            save()
        end
    end
end

function actions.CCG_SERVER_REGISTER(payload)
    need(tostring(payload.code or "") == DEPLOY.code, "BAD_CODE",
        "That is not the operator code")
    state.ccg_servers = state.ccg_servers or {}
    local token = util.token("CCG_SERVER")
    state.ccg_servers[token] = {
        token = token,
        name = util.safeText(util.trim(payload.name or "CCG Server"), 24),
        registered_day = util.ingameDay(),
        last_seen = util.nowMs(),
    }
    save()
    logActivity("CCG Server registered", colors.magenta)
    return { server_token = token, games = CCG_GAMES }
end

-- Who a player is. A CCG Server has no accounts of its own, so it asks --
-- and only ever with the player's own PIN-unlocked bet session, so it
-- cannot look anybody up who has not sat down at a game.
function actions.CCG_WHO(payload)
    requireCCGServer(payload)
    local account = requireBetSession(payload)
    return {
        account_id = account.account_id,
        name = account.name,
        wallet = betWalletSnapshot(account),
    }
end

-- Setting a player's stake. The player's own PIN-unlocked bet session is
-- what authorises the money leaving their wallet, exactly as it did when
-- this ran on the Bank.
function actions.CCG_ESCROW_SET(payload)
    requireCCGServer(payload)
    local account = requireBetSession(payload)
    local escrow = escrowFor(payload.lobby_code, payload.game)
    need(CCG_GAMES[escrow.game], "BAD_GAME", "That is not a CCG game")
    local amount = validateAmount(payload.amount,
        tonumber(config.bet_maximum) or 10000)
    need(amount >= (tonumber(config.bet_minimum) or 1),
        "INVALID_AMOUNT", "Wager is below the minimum")
    local wallet = walletFor(account)
    local previous = util.roundMoney(escrow.stakes[account.account_id] or 0)
    need(wallet.balance + previous >= amount,
        "INSUFFICIENT_BET_FUNDS", "Not enough available in your Bet Wallet")
    if previous > 0 then
        wallet.balance = util.roundMoney(wallet.balance + previous)
        betActivity(account, "wager_changed", previous,
            "Previous wager returned",
            { game = escrow.game, lobby_code = escrow.code })
    end
    wallet.balance = util.roundMoney(wallet.balance - amount)
    escrow.stakes[account.account_id] = amount
    betActivity(account, "wager_reserved", -amount,
        CCG_GAMES[escrow.game].name .. " wager reserved",
        { game = escrow.game, lobby_code = escrow.code })
    save()
    return {
        account_id = account.account_id,
        staked = amount,
        wallet = betWalletSnapshot(account),
    }
end

function actions.CCG_ESCROW_RELEASE(payload)
    requireCCGServer(payload)
    local escrow = escrowFor(payload.lobby_code)
    local accountId = tostring(payload.account_id or "")
    local amount = util.roundMoney(escrow.stakes[accountId] or 0)
    escrow.stakes[accountId] = nil
    local account = state.accounts[accountId]
    if account and amount > 0 then
        local wallet = walletFor(account)
        wallet.balance = util.roundMoney(wallet.balance + amount)
        betActivity(account, "wager_refund", amount, "Wager returned",
            { game = escrow.game, lobby_code = escrow.code })
        save()
        return { released = amount, wallet = betWalletSnapshot(account) }
    end
    save()
    return { released = 0 }
end

function actions.CCG_ESCROW_REFUND(payload)
    requireCCGServer(payload)
    local escrow = escrowFor(payload.lobby_code)
    local refunded = 0
    for accountId, amount in pairs(escrow.stakes) do
        local account = state.accounts[accountId]
        if account and amount > 0 then
            local wallet = walletFor(account)
            wallet.balance = util.roundMoney(wallet.balance + amount)
            betActivity(account, "wager_refund", amount,
                util.safeText(payload.reason or "Lobby cancelled", 60),
                { game = escrow.game, lobby_code = escrow.code })
            refunded = util.roundMoney(refunded + amount)
        end
    end
    ccgEscrow()[escrow.code] = nil
    save()
    return { refunded = refunded }
end

-- Settling. The server says who won and nothing else; the payout is this
-- Bank multiplying the stake it is already holding, so a server that lies
-- can pick the wrong winner but cannot invent money.
function actions.CCG_ESCROW_SETTLE(payload)
    requireCCGServer(payload)
    local escrow = escrowFor(payload.lobby_code)
    local game = CCG_GAMES[escrow.game]
    need(game, "BAD_GAME", "That lobby has no game")
    local winners = {}
    for _, accountId in ipairs(type(payload.winners) == "table"
        and payload.winners or {}) do
        winners[tostring(accountId)] = true
    end
    local stakes, payouts = 0, 0
    local settled = {}
    for accountId, amount in pairs(escrow.stakes) do
        amount = util.roundMoney(amount) or 0
        stakes = util.roundMoney(stakes + amount)
        local account = state.accounts[accountId]
        if account and amount > 0 then
            if winners[accountId] then
                local payout = util.roundMoney(amount * game.multiplier)
                local hold = addBetHold(account, escrow.game, escrow.code,
                    payout)
                notification(account, "CCG win - funds holding",
                    util.money(payout, config.currency) .. " from "
                        .. game.name .. " releases on day " .. hold.release_day
                        .. " at " .. hold.release_time, "gaming")
                payouts = util.roundMoney(payouts + payout)
                settled[#settled + 1] = { account_id = accountId,
                    won = true, payout = payout }
            else
                betActivity(account, "bet_lost", -amount,
                    game.name .. " result",
                    { game = escrow.game, lobby_code = escrow.code })
                notification(account, "CCG result",
                    "Your " .. game.name .. " wager did not win", "gaming")
                settled[#settled + 1] = { account_id = accountId,
                    won = false, payout = 0 }
            end
        end
    end
    state.ccg_house_profit = util.roundMoney(
        (state.ccg_house_profit or 0) + stakes - payouts)
    ccgEscrow()[escrow.code] = nil
    save()
    logActivity("CCG settled " .. escrow.code .. " / " .. game.name,
        colors.magenta)
    return { settled = settled, stakes = stakes, payouts = payouts }
end

-- What the Bank is holding for a lobby, so a CCG Server that restarts can
-- pick up where it left off rather than stranding the money.
function actions.CCG_ESCROW_STATUS(payload)
    requireCCGServer(payload)
    local open = {}
    for code, escrow in pairs(ccgEscrow()) do
        local stakes, count = 0, 0
        for _, amount in pairs(escrow.stakes) do
            stakes = util.roundMoney(stakes + amount)
            count = count + 1
        end
        open[#open + 1] = { lobby_code = code, game = escrow.game,
            players = count, stakes = stakes,
            opened_at = escrow.opened_at }
    end
    return { lobbies = open }
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

-- The proximity scan engine, gathered under one name. Open scans are
-- deliberately not persisted: a Bank restart drops a half-finished door check
-- the way a dropped connection would.
local scans = { requests = {}, kinds = { ticket = true, visa = true } }
-- Declared here rather than beside its own section below: Urgent
-- Contact reaches into it, and a local declared further down the file
-- is a nil global at any use site above it.
local appstore = {}

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
    if conversation.kind == "government" then return "Government" end
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
        sender_name = sender and sender.name
            or (senderId == "GOVERNMENT" and "Government") or "PUMPE",
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
    need(conversation.kind ~= "government", "GOVERNMENT_THREAD",
        "Only the government can move money in this chat")
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
    local account = socialAccount(requireSpender(payload))
    local conversation = requireConversation(account, payload.conversation_id)
    need(conversation.kind ~= "government", "GOVERNMENT_THREAD",
        "Only the government can move money in this chat")
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
    -- Paying the government is never blocked by owing the government.
    if conversation.kind ~= "government" then checkNoTaxDemand(account) end
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
    -- A government demand is paid to the state. There is no counterpart
    -- account to credit, so it settles like a fine rather than a transfer.
    if conversation.kind == "government" then
        local amount = validateAmount(target.amount)
        need(account.balance >= amount, "INSUFFICIENT_FUNDS",
            "Not enough money to pay this")
        account.balance = util.roundMoney(account.balance - amount)
        state.tax_revenue = util.roundMoney((state.tax_revenue or 0) + amount)
        transaction(account, "government", -amount, "Government",
            util.safeText(target.body or "Government demand", 60))
        target.status = "paid"
        target.paid_by = account.account_id
        appendMessage(conversation, account.account_id, "money_sent",
            "paid " .. util.money(amount, config.currency) .. " to Government",
            { amount = amount })
        logActivity(account.name .. " paid a government demand", colors.lime)
        save()
        return { quote = { amount = amount, total = amount, fee = 0,
            recipient = "Government" } }
    end
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
        app_name = call.app_name,
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
    local session = requireSession(payload)
    local account = socialAccount(session)
    cleanupUrgentCalls()
    local other = requireFriend(account, payload.account_id)
    -- The Urgent Contact API. A messaging app can raise the same alert the
    -- PUMPE raises, but it has to be signed in, and the name on the alert
    -- comes from the grant rather than from the app asking.
    local appName
    if payload.app_id then
        appName = appstore.requireGrant(session,
            appstore.appId(payload)).app_name
    end
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
        app_name = appName,
    }
    urgentCalls[call.call_id] = call
    notification(other, appName and (appName .. " call") or "Urgent Contact",
        account.name .. " is reaching you right now"
            .. (appName and (" on " .. appName) or ""), "urgent")
    logActivity("Urgent Contact " .. account.name .. " > " .. other.name
        .. (appName and (" via " .. appName) or ""), colors.orange)
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
    local account = requireSpender(payload)
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
    local account = requireSpender(payload)
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

-- A scanner sends its own coordinates rather than borrowing an account's, so
-- an organiser standing at their own door is not mistaken for the terminal.
function scans.position(payload)
    local position = type(payload) == "table" and payload.position or nil
    local x = position and tonumber(position.x)
    local y = position and tonumber(position.y)
    local z = position and tonumber(position.z)
    need(x and y and z, "NO_POSITION",
        "This computer has no GPS fix. Add GPS anchors nearby.")
    return { x = x, y = y, z = z }
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
    -- Portable Mode picks the customer first and the basket second. Once
    -- somebody has said yes, the bill is theirs and is never passed along.
    if offer.claimed_by then return offer end
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
    local payment = offer.code and state.active_pay_codes[offer.code]
    return {
        offer_id = offer.offer_id,
        code = offer.code,
        amount = offer.amount,
        items = offer.items and util.copy(offer.items) or nil,
        merchant = offer.merchant,
        description = offer.description,
        portable = offer.portable == true,
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

-- Portable Mode. A kiosk with no customer-facing screen asks who is paying
-- before anything is rung up, then sends the finished basket to that same
-- PUMPE. The customer confirms twice: once to take the sale, once to pay it.
function actions.PROXIMITY_CLAIM(payload)
    local terminal = requireTerminal(payload)
    cleanupEphemeral()
    recordPosition(terminal, payload.position)
    need(freshPosition(terminal), "NO_POSITION",
        "This kiosk has no GPS fix. Add GPS anchors nearby.")
    local offer = {
        offer_id = nextId("proximity"),
        terminal_id = terminal.terminal_id,
        merchant = util.safeText(terminal.name or "Kiosk", 20),
        description = util.safeText(payload.description or "Portable sale", 60),
        portable = true,
        declined = {},
        status = "claiming",
        created_at = util.nowMs(),
        expires_at = util.nowMs()
            + (tonumber(config.proximity_offer_ttl_ms) or 60000),
    }
    state.proximity_offers[offer.offer_id] = offer
    retargetOffer(offer)
    if offer.status == "offered" then offer.status = "claiming" end
    save()
    return { offer = publicOffer(offer) }
end

function actions.PROXIMITY_ACCEPT(payload)
    local account = requireSpender(payload)
    local offer = state.proximity_offers[payload.offer_id]
    need(offer and offer.status == "claiming", "NOT_FOUND",
        "That kiosk is no longer waiting")
    need(offer.target_account_id == account.account_id, "NOT_YOURS",
        "That offer is not yours")
    checkAccountActive(account)
    offer.claimed_by = account.account_id
    offer.status = "claimed"
    offer.expires_at = util.nowMs()
        + (tonumber(config.proximity_offer_ttl_ms) or 60000) * 5
    save()
    return { offer = publicOffer(offer) }
end

-- The basket, once the operator has rung it up.
function actions.PROXIMITY_BILL(payload)
    local terminal = requireTerminal(payload)
    local offer = state.proximity_offers[payload.offer_id]
    need(offer and offer.terminal_id == terminal.terminal_id,
        "NOT_FOUND", "That sale has ended")
    need(offer.claimed_by, "NO_CUSTOMER", "Nobody has taken this sale yet")
    need(not offer.code, "ALREADY_BILLED", "That sale was already sent")
    local created = actions.CREATE_PAY_CODE(payload)
    local payment = state.active_pay_codes[created.code]
    offer.code = created.code
    offer.amount = created.amount
    offer.items = payment and util.copy(payment.items) or nil
    offer.description = util.safeText(payload.description or offer.description, 60)
    offer.status = "offered"
    offer.expires_at = util.nowMs() + config.payment_code_ttl_ms
    local account = state.accounts[offer.claimed_by]
    if account then
        notification(account, "Your basket is ready",
            util.money(offer.amount, config.currency) .. " at " .. offer.merchant,
            "money")
    end
    save()
    return { offer = publicOffer(offer) }
end

function actions.PROXIMITY_STATUS(payload)
    local terminal = requireTerminal(payload)
    local offer = state.proximity_offers[payload.offer_id]
    need(offer and offer.terminal_id == terminal.terminal_id,
        "NOT_FOUND", "That offer has ended")
    local payment = offer.code and state.active_pay_codes[offer.code]
    if payment and payment.status == "paid" then
        offer.status = "paid"
    elseif offer.expires_at <= util.nowMs()
        and (offer.status == "offered" or offer.status == "claiming") then
        if offer.claimed_by then
            offer.status = "expired"
        else
            offer.declined[offer.target_account_id or ""] = true
            retargetOffer(offer)
            if offer.portable and offer.status == "offered" then
                offer.status = "claiming"
            end
        end
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
    if offer.claimed_by == account.account_id and offer.code then
        -- They took the sale and the operator rang the basket up for them.
        -- Handing that basket on would bill a stranger for someone else's
        -- shopping, so a declined Portable sale ends instead.
        offer.claimed_by = nil
        offer.status = "declined"
        local payment = state.active_pay_codes[offer.code]
        if payment and payment.status == "pending" then
            state.active_pay_codes[offer.code] = nil
        end
    else
        offer.claimed_by = nil
        retargetOffer(offer)
        if offer.portable and offer.status == "offered" then
            offer.status = "claiming"
        end
    end
    save()
    return { offer = publicOffer(offer) }
end

-- Foxy ------------------------------------------------------------------------
-- The account you already have, split into pots you name yourself. The main
-- balance is still the one every other part of the system spends from; a pot
-- is money set aside, and moving between them never leaves the account.

local foxy = {}

function foxy.account(account)
    account.pots = account.pots or {}
    account.pot_order = account.pot_order or {}
    return account
end

function foxy.potList(account)
    foxy.account(account)
    local list = {}
    for _, potId in ipairs(account.pot_order) do
        local pot = account.pots[potId]
        if pot then
            list[#list + 1] = {
                pot_id = potId, name = pot.name, balance = pot.balance,
            }
        end
    end
    return list
end

function foxy.saved(account)
    local total = 0
    for _, pot in pairs(foxy.account(account).pots) do
        total = total + (pot.balance or 0)
    end
    return util.roundMoney(total)
end

-- "main" is the ordinary balance; anything else is a pot the holder made.
function foxy.balanceOf(account, potId)
    if potId == nil or potId == "main" then return account.balance end
    local pot = foxy.account(account).pots[potId]
    need(pot, "POT_NOT_FOUND", "That account is not there any more")
    return pot.balance
end

function foxy.adjust(account, potId, delta)
    if potId == nil or potId == "main" then
        account.balance = util.roundMoney(account.balance + delta)
        return
    end
    local pot = foxy.account(account).pots[potId]
    need(pot, "POT_NOT_FOUND", "That account is not there any more")
    pot.balance = util.roundMoney(pot.balance + delta)
end

function actions.FOXY_OVERVIEW(payload)
    local account = requireSession(payload)
    return {
        name = account.name,
        card_id = account.card_id,
        personal_number = account.personal_number,
        balance = account.balance,
        saved = foxy.saved(account),
        pots = foxy.potList(account),
        max_pots = tonumber(config.max_pots_per_account) or 8,
        fee_rate = tonumber(config.foxy_cash_fee_rate) or 0.02,
        tax_demand = account.tax_demand
            and util.copy(account.tax_demand) or nil,
    }
end

function actions.FOXY_POT_CREATE(payload)
    local account = foxy.account(requireSession(payload))
    local name = util.safeText(util.trim(payload.name or ""), 18)
    need(#name >= 2, "INVALID_NAME", "Give the account a name")
    need(#account.pot_order < (tonumber(config.max_pots_per_account) or 8),
        "TOO_MANY_POTS", "You already have as many accounts as you can hold")
    local potId = nextId("pot")
    account.pots[potId] = { pot_id = potId, name = name, balance = 0,
        created_day = util.ingameDay() }
    account.pot_order[#account.pot_order + 1] = potId
    save()
    return { pots = foxy.potList(account), balance = account.balance }
end

function actions.FOXY_POT_MOVE(payload)
    local account = foxy.account(requireSession(payload))
    local from = payload.from_pot or "main"
    local to = payload.to_pot or "main"
    need(from ~= to, "SAME_ACCOUNT", "Pick two different accounts")
    local amount = validateAmount(payload.amount)
    -- Moving out of the main balance is spending as far as a tax demand is
    -- concerned; a fine cannot be dodged by tucking the money into savings.
    if from == "main" then checkNoTaxDemand(account) end
    need(foxy.balanceOf(account, from) >= amount, "INSUFFICIENT_FUNDS",
        "Not enough money in that account")
    foxy.adjust(account, from, -amount)
    foxy.adjust(account, to, amount)
    save()
    return {
        pots = foxy.potList(account),
        balance = account.balance,
        saved = foxy.saved(account),
    }
end

function actions.FOXY_POT_CLOSE(payload)
    local account = foxy.account(requireSession(payload))
    local pot = account.pots[payload.pot_id]
    need(pot, "POT_NOT_FOUND", "That account is not there any more")
    account.balance = util.roundMoney(account.balance + (pot.balance or 0))
    account.pots[payload.pot_id] = nil
    for index = #account.pot_order, 1, -1 do
        if account.pot_order[index] == payload.pot_id then
            table.remove(account.pot_order, index)
        end
    end
    save()
    return { pots = foxy.potList(account), balance = account.balance }
end

-- Foxy Cash. Instant, friends only, a flat fee and no daily ceiling. The
-- ceiling is what the friendship replaces: you cannot reach a stranger.
function actions.FOXY_CASH_QUOTE(payload)
    local account = requireSpender(payload)
    local friend = requireFriend(socialAccount(account), payload.account_id)
    local amount = validateAmount(payload.amount)
    local rate = tonumber(config.foxy_cash_fee_rate) or 0.02
    local fee = util.roundMoney(amount * rate)
    return {
        recipient = friend.name,
        amount = amount,
        fee = fee,
        total = util.roundMoney(amount + fee),
        fee_rate = rate,
        balance = account.balance,
    }
end

function actions.FOXY_CASH_SEND(payload)
    local account = requireSpender(payload)
    local friend = requireFriend(socialAccount(account), payload.account_id)
    need(verifyAccount(account, payload.pin), "BAD_PIN", "Incorrect PIN")
    local amount = validateAmount(payload.amount)
    local rate = tonumber(config.foxy_cash_fee_rate) or 0.02
    local fee = util.roundMoney(amount * rate)
    local total = util.roundMoney(amount + fee)
    need(account.balance >= total, "INSUFFICIENT_FUNDS",
        "Not enough money including the Foxy Cash fee")
    account.balance = util.roundMoney(account.balance - total)
    friend.balance = util.roundMoney(friend.balance + amount)
    state.processing_fee_revenue = util.roundMoney(
        (state.processing_fee_revenue or 0) + fee)
    transaction(account, "foxy_cash_out", -amount, friend.name,
        "Foxy Cash to " .. friend.name)
    if fee > 0 then
        transaction(account, "processing_fee", -fee, "Foxy",
            "Foxy Cash fee")
    end
    transaction(friend, "foxy_cash_in", amount, account.name,
        "Foxy Cash from " .. account.name)
    notification(friend, "Foxy Cash received",
        account.name .. " sent you " .. util.money(amount, config.currency),
        "money")
    save()
    logActivity("Foxy Cash " .. util.money(amount, config.currency) .. " "
        .. account.name .. " > " .. friend.name, colors.lime)
    return { amount = amount, fee = fee, total = total,
        recipient = friend.name, balance = account.balance }
end

function actions.FOXY_SET_ACCOUNT(payload)
    local account = requireSession(payload)
    need(verifyAccount(account, payload.pin), "BAD_PIN", "Incorrect PIN")
    if payload.name and util.trim(payload.name) ~= "" then
        local name = util.safeText(util.trim(payload.name), 20)
        need(name:match("^[%w_ %-]+$") and #name >= 2,
            "INVALID_NAME", "Use 2-20 letters, numbers, spaces, _ or -")
        local taken = accountByName(name)
        need(not taken or taken.account_id == account.account_id,
            "NAME_TAKEN", "That account name is taken")
        state.account_names[util.normalName(account.name)] = nil
        account.name = name
        state.account_names[util.normalName(name)] = account.account_id
    end
    if payload.new_pin and payload.new_pin ~= "" then
        need(util.validPin(payload.new_pin), "INVALID_PIN",
            "PIN must be four digits")
        account.pin_hash = util.hashPin(payload.new_pin)
    end
    if payload.gender then
        account.gender = util.safeText(payload.gender, 20)
    end
    save()
    return { account = publicAccount(account) }
end

-- FoxyLogin and app storage ----------------------------------------------------
-- An installed app never sees the session token, so it cannot act as you by
-- accident. FoxyLogin is how it asks: it says what it wants to see, you
-- approve once, and it gets a profile with exactly that and nothing else.
-- The same grant is what lets it keep records here.

appstore.SCOPES = {
    name = "Your account name",
    number = "Your personal number",
    friends = "Who your friends are",
    balance = "Your balance",
}

function appstore.grants(account)
    account.app_grants = account.app_grants or {}
    return account.app_grants
end

function appstore.cleanScopes(requested)
    local scopes, seen = {}, { name = true }
    scopes[1] = "name"
    for _, scope in ipairs(type(requested) == "table" and requested or {}) do
        if appstore.SCOPES[scope] and not seen[scope] then
            seen[scope] = true
            scopes[#scopes + 1] = scope
        end
    end
    return scopes
end

function appstore.appId(payload)
    local appId = util.safeText(util.trim(tostring(payload.app_id or "")), 24)
    need(appId:match("^[%w_%-]+$"), "APP_REQUIRED", "That app has no id")
    return appId
end

function appstore.profile(account, scopes)
    local allowed = {}
    for _, scope in ipairs(scopes) do allowed[scope] = true end
    local profile = {
        account_id = account.account_id,
        name = account.name,
        scopes = scopes,
    }
    if allowed.number then profile.personal_number = account.personal_number end
    if allowed.balance then profile.balance = account.balance end
    if allowed.friends then
        local friends = {}
        for friendId in pairs(socialAccount(account).friends) do
            local friend = state.accounts[friendId]
            if friend then
                friends[#friends + 1] = { account_id = friendId,
                    name = friend.name }
            end
        end
        table.sort(friends, function(a, b) return a.name < b.name end)
        profile.friends = friends
    end
    return profile
end

function actions.FOXY_LOGIN_STATUS(payload)
    local account = requireSession(payload)
    local grant = appstore.grants(account)[appstore.appId(payload)]
    if not grant then return { approved = false } end
    return {
        approved = true,
        app_name = grant.app_name,
        scopes = grant.scopes,
        profile = appstore.profile(account, grant.scopes),
    }
end

function actions.FOXY_LOGIN_APPROVE(payload)
    local account = requireSession(payload)
    local appId = appstore.appId(payload)
    local scopes = appstore.cleanScopes(payload.scopes)
    appstore.grants(account)[appId] = {
        app_id = appId,
        app_name = util.safeText(util.trim(payload.app_name or appId), 18),
        scopes = scopes,
        approved_day = util.ingameDay(),
    }
    save()
    return { approved = true, profile = appstore.profile(account, scopes) }
end

function actions.FOXY_LOGIN_REVOKE(payload)
    local account = requireSession(payload)
    appstore.grants(account)[appstore.appId(payload)] = nil
    save()
    return { approved = false }
end

function actions.FOXY_LOGIN_LIST(payload)
    local account = requireSession(payload)
    local list = {}
    for _, grant in pairs(appstore.grants(account)) do
        list[#list + 1] = {
            app_id = grant.app_id, app_name = grant.app_name,
            scopes = grant.scopes, approved_day = grant.approved_day,
        }
    end
    table.sort(list, function(a, b) return a.app_name < b.app_name end)
    return { apps = list }
end

-- App records. A small shared store so an app can keep posts, comments or
-- anything else without the Bank knowing what any of it means. Records are
-- owned by whoever wrote them; reactions are the one thing anybody can add.

function appstore.collection(appId, name)
    state.app_data = state.app_data or {}
    state.app_data[appId] = state.app_data[appId] or {}
    local key = util.safeText(util.trim(tostring(name or "")), 20)
    need(key:match("^[%w_%-]+$"), "BAD_COLLECTION", "That collection has no name")
    local existing = state.app_data[appId][key]
    if existing then return existing end

    -- Opening a new collection is the only thing that is capped. An app that
    -- keeps one per conversation would otherwise be able to fill the Bank's
    -- disk a conversation at a time, and the disk is the scarce thing here.
    -- Emptied collections are swept first, so a chat whose messages have all
    -- expired gives its slot back rather than holding it forever.
    local limit = tonumber(config.max_app_collections) or 40
    local count = 0
    for _ in pairs(state.app_data[appId]) do count = count + 1 end
    if count >= limit then
        for otherKey, collection in pairs(state.app_data[appId]) do
            if #collection.items == 0 then
                state.app_data[appId][otherKey] = nil
                count = count - 1
            end
        end
        need(count < limit, "TOO_MANY",
            "That app is holding as much as it is allowed to")
    end
    state.app_data[appId][key] = { items = {}, sequence = 0 }
    return state.app_data[appId][key]
end

-- Measured rather than serialised: it bounds depth as well as length, so a
-- deeply nested record cannot slip past on size alone.
function appstore.dataSize(value, depth)
    depth = (depth or 0) + 1
    if depth > 4 then return math.huge end
    local kind = type(value)
    if kind == "string" then return #value + 2 end
    if kind ~= "table" then return 8 end
    local total = 2
    for key, item in pairs(value) do
        total = total + appstore.dataSize(key, depth)
            + appstore.dataSize(item, depth)
    end
    return total
end

-- The Pin API. An app can ask the owner to prove it is really them before it
-- opens something sensitive, without ever seeing the PIN: the PUMPE collects
-- it and only the answer comes back. A wrong-guess counter is here because
-- the app is the thing being defended against -- it stops a hostile app
-- grinding the PIN through the API it was handed.
function actions.PIN_CHECK(payload)
    local account = requireSession(payload)
    local appId = appstore.appId(payload)
    appstore.requireGrant(account, appId)
    account.pin_check_fails = account.pin_check_fails or 0
    if account.pin_check_fails >= 5 then
        local since = util.nowMs() - (account.pin_check_at or 0)
        local cool = (tonumber(config.pin_check_lockout_seconds) or 120) * 1000
        if since < cool then
            need(false, "TOO_MANY",
                "Too many wrong PINs. Try again in "
                    .. math.ceil((cool - since) / 1000) .. "s")
        end
        account.pin_check_fails = 0
    end
    if not verifyAccount(account, payload.pin) then
        account.pin_check_fails = account.pin_check_fails + 1
        account.pin_check_at = util.nowMs()
        save()
        need(false, "BAD_PIN", "Incorrect PIN")
    end
    account.pin_check_fails = 0
    save()
    return { ok = true }
end

-- Permissions. Signing in is one decision; letting an app interrupt you is
-- another, so it is asked for separately and kept where the owner can revisit
-- it. An app that has ever asked is listed, whatever the answer was.

function appstore.permissions(account)
    account.app_permissions = account.app_permissions or {}
    return account.app_permissions
end

function appstore.permission(account, appId, appName)
    local all = appstore.permissions(account)
    all[appId] = all[appId] or {
        app_id = appId,
        app_name = util.safeText(util.trim(tostring(appName or appId)), 18),
        notifications = "unset",
        fullscreen = false,
        asked_day = util.ingameDay(),
    }
    if appName then
        all[appId].app_name =
            util.safeText(util.trim(tostring(appName)), 18)
    end
    return all[appId]
end

function appstore.publicPermission(entry)
    return {
        app_id = entry.app_id,
        app_name = entry.app_name,
        notifications = entry.notifications,
        fullscreen = entry.fullscreen == true,
        asked_day = entry.asked_day,
    }
end

-- The app asks; the answer comes from the PUMPE, which is what actually put
-- the question to the owner. Asking again after a "no" only re-reads it: an
-- app cannot nag its way to a yes it was already refused.
function actions.APP_PERMISSION_ASK(payload)
    local account = requireSession(payload)
    local appId = appstore.appId(payload)
    -- Deliberately no grant check. An app should be able to ask this before
    -- it asks for your account, and recording the answer exposes nothing.
    -- APP_NOTIFY is where the grant is required, so a "yes" here is worth
    -- nothing on its own.
    local entry = appstore.permission(account, appId, payload.app_name)
    if entry.notifications == "unset" and payload.allow ~= nil then
        entry.notifications = payload.allow == true and "granted" or "denied"
        entry.asked_day = util.ingameDay()
        save()
    end
    return { permission = appstore.publicPermission(entry) }
end

function actions.APP_PERMISSION_LIST(payload)
    local account = requireSession(payload)
    local list = {}
    for _, entry in pairs(appstore.permissions(account)) do
        list[#list + 1] = appstore.publicPermission(entry)
    end
    table.sort(list, function(a, b) return a.app_name < b.app_name end)
    return { apps = list }
end

-- App Settings on the PUMPE. Fullscreen is only ever turned on from here,
-- never by the app, and it cannot outlive the notifications permission.
function actions.APP_PERMISSION_SET(payload)
    local account = requireSession(payload)
    local appId = appstore.appId(payload)
    local entry = appstore.permissions(account)[appId]
    need(entry, "NOT_FOUND", "That app has not asked for anything")
    if payload.notifications ~= nil then
        entry.notifications = payload.notifications == true
            and "granted" or "denied"
    end
    if payload.fullscreen ~= nil then
        entry.fullscreen = payload.fullscreen == true
    end
    if entry.notifications ~= "granted" then entry.fullscreen = false end
    save()
    return { permission = appstore.publicPermission(entry) }
end

function actions.APP_PERMISSION_FORGET(payload)
    local account = requireSession(payload)
    appstore.permissions(account)[appstore.appId(payload)] = nil
    save()
    return { ok = true }
end

-- An app notification. The recipient's own permission decides whether it
-- arrives at all and how loudly, so a sender cannot make its own alert
-- louder than the person allowed.
function actions.APP_NOTIFY(payload)
    local account = requireSession(payload)
    local appId = appstore.appId(payload)
    local grant = appstore.requireGrant(account, appId)
    -- "target" means a screen everywhere else in this file; this one is a
    -- person.
    local recipient = account
    local wantedId = payload.account_id
        and util.trim(tostring(payload.account_id))
    if wantedId and wantedId ~= "" and wantedId ~= account.account_id then
        recipient = state.accounts[wantedId]
        need(recipient, "ACCOUNT_NOT_FOUND", "Nobody has that account")
        -- An app can only reach across accounts between friends. Without
        -- this, one grant would be a licence to alert the whole server.
        need(socialAccount(account).friends[wantedId], "NOT_FRIENDS",
            "You can only reach a friend that way")
    end
    local entry = appstore.permissions(recipient)[appId]
    need(entry and entry.notifications == "granted", "NO_PERMISSION",
        recipient == account and "Allow notifications for that app first"
            or (recipient.name .. " has not allowed that app to notify them"))
    -- Fullscreen is the owner's setting, not the sender's request.
    local style = payload.style == "fullscreen" and entry.fullscreen == true
        and "fullscreen" or "banner"
    appstore.rateLimit(account, appId)
    local item = notification(recipient,
        util.safeText(util.trim(tostring(payload.title or grant.app_name)), 40),
        util.safeText(util.trim(tostring(payload.body or "")), 120),
        "app", { app_name = entry.app_name, style = style })
    save()
    return { sent = true, style = style, notification_id = item.notification_id }
end

-- A sender gets a small budget of alerts per in-game day, per app. It is
-- generous for a chat app and useless for a spammer.
function appstore.rateLimit(account, appId)
    account.app_notify_count = account.app_notify_count or {}
    local today = util.ingameDay()
    local bucket = account.app_notify_count[appId]
    if not bucket or bucket.day ~= today then
        bucket = { day = today, count = 0 }
        account.app_notify_count[appId] = bucket
    end
    need(bucket.count < (tonumber(config.max_app_notifications_per_day) or 60),
        "TOO_MANY", "That app has sent all the alerts it can today")
    bucket.count = bucket.count + 1
end

function appstore.requireGrant(account, appId)
    local grant = appstore.grants(account)[appId]
    need(grant, "NOT_SIGNED_IN", "Sign in to that app first")
    return grant
end

-- A record with an audience is private to the author and the people named
-- in it. One without is public to everybody using the app, which is what a
-- feed wants. The Bank still has no idea what any of it means.
function appstore.audience(payload)
    local raw = payload.audience
    if type(raw) ~= "table" or #raw == 0 then return nil end
    local out, seen = {}, {}
    for _, id in ipairs(raw) do
        id = util.safeText(util.trim(tostring(id or "")), 24)
        if id ~= "" and not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
        if #out >= 8 then break end
    end
    if #out == 0 then return nil end
    return out
end

function appstore.visible(record, accountId)
    if not record.audience then return true end
    if record.author_id == accountId then return true end
    for _, id in ipairs(record.audience) do
        if id == accountId then return true end
    end
    return false
end

-- Records can be told to go away. The clock only starts once the record has
-- been read, so a message nobody opened is still there tomorrow.
function appstore.prune(collection)
    local today, removed = util.ingameDay(), 0
    for index = #collection.items, 1, -1 do
        local record = collection.items[index]
        if record.expires_day and today >= record.expires_day then
            table.remove(collection.items, index)
            removed = removed + 1
        end
    end
    return removed
end

function appstore.publicRecord(record, accountId)
    local reactions, mine = 0, false
    for reactorId in pairs(record.reactions or {}) do
        reactions = reactions + 1
        if reactorId == accountId then mine = true end
    end
    return {
        id = record.id,
        parent = record.parent,
        data = util.copy(record.data),
        author_id = record.author_id,
        author_name = record.author_name,
        created_day = record.created_day,
        created_time = record.created_time,
        created_at = record.created_at,
        reactions = reactions,
        reacted = mine,
        mine = record.author_id == accountId,
        private = record.audience ~= nil,
        read = record.read_by ~= nil and record.read_by[accountId] == true,
        seen = record.read_by ~= nil and next(record.read_by) ~= nil,
        expires_day = record.expires_day,
    }
end

-- Where the records actually live ---------------------------------------------
-- The Core decides who you are and what you are allowed to touch; the store
-- itself is just data, and in Pair Mode it lives on the Vault. Splitting the
-- handlers here rather than duplicating them means there is exactly one
-- implementation of what an app record means, wherever it is kept.
appstore.ops = {}

function appstore.dispatch(op, account, appId, payload)
    if not pair.isCore() or not pair.paired() then
        return appstore.ops[op](account, appId, payload)
    end
    local result, err, code = pair.ask("VAULT_APP_DATA", {
        op = op, app_id = appId, payload = payload,
        -- The Core has already established this. The Vault holds no
        -- accounts and takes the Core's word for who is asking.
        caller = { account_id = account.account_id, name = account.name },
    })
    if not result then
        need(false, code or "VAULT_OFFLINE",
            err or "The Vault is not answering")
    end
    return result
end

function actions.APP_DATA_PUT(payload)
    local account = requireSession(payload)
    local appId = appstore.appId(payload)
    appstore.requireGrant(account, appId)
    return appstore.dispatch("put", account, appId, payload)
end

function appstore.ops.put(account, appId, payload)
    local collection = appstore.collection(appId, payload.collection)
    appstore.prune(collection)
    need(appstore.dataSize(payload.data or {})
        <= (tonumber(config.max_app_record_bytes) or 400),
        "RECORD_TOO_BIG", "That is more than an app record can hold")
    local record
    if payload.id then
        for _, item in ipairs(collection.items) do
            if item.id == payload.id
                and appstore.visible(item, account.account_id) then
                record = item
            end
        end
        need(record, "NOT_FOUND", "That record is gone")
        need(record.author_id == account.account_id, "NOT_YOURS",
            "That record belongs to somebody else")
        record.data = util.copy(payload.data or {})
    else
        collection.sequence = collection.sequence + 1
        record = {
            id = string.format("%s%06d", appId:sub(1, 3):upper(),
                collection.sequence),
            parent = payload.parent and util.safeText(payload.parent, 24) or nil,
            data = util.copy(payload.data or {}),
            author_id = account.account_id,
            author_name = account.name,
            created_day = util.ingameDay(),
            created_time = util.formatClock(),
            created_at = util.nowMs(),
            reactions = {},
            audience = appstore.audience(payload),
            expire_after_days = payload.expire_after_days
                and math.max(1, math.min(30,
                    math.floor(tonumber(payload.expire_after_days) or 1)))
                or nil,
        }
        table.insert(collection.items, 1, record)
        local limit = tonumber(config.max_app_records) or 200
        while #collection.items > limit do table.remove(collection.items) end
    end
    save()
    return { record = appstore.publicRecord(record, account.account_id) }
end

function actions.APP_DATA_LIST(payload)
    local account = requireSession(payload)
    local appId = appstore.appId(payload)
    appstore.requireGrant(account, appId)
    return appstore.dispatch("list", account, appId, payload)
end

function appstore.ops.list(account, appId, payload)
    local collection = appstore.collection(appId, payload.collection)
    if appstore.prune(collection) > 0 then save() end
    local parent = payload.parent
    local limit = math.max(1, math.min(60,
        math.floor(tonumber(payload.limit) or 40)))
    local out, visible = {}, 0
    for _, record in ipairs(collection.items) do
        if appstore.visible(record, account.account_id) then
            visible = visible + 1
            if (not parent or record.parent == parent) and #out < limit then
                out[#out + 1] = appstore.publicRecord(record,
                    account.account_id)
            end
        end
    end
    return { records = out, total = visible }
end

function actions.APP_DATA_DELETE(payload)
    local account = requireSession(payload)
    local appId = appstore.appId(payload)
    appstore.requireGrant(account, appId)
    return appstore.dispatch("delete", account, appId, payload)
end

function appstore.ops.delete(account, appId, payload)
    local collection = appstore.collection(appId, payload.collection)
    for index = #collection.items, 1, -1 do
        local record = collection.items[index]
        if record.id == payload.id
            and appstore.visible(record, account.account_id) then
            need(record.author_id == account.account_id, "NOT_YOURS",
                "That record belongs to somebody else")
            table.remove(collection.items, index)
            save()
            return { removed = payload.id }
        end
    end
    need(false, "NOT_FOUND", "That record is gone")
end

-- Reading a record is what starts its clock. An app that asked for an
-- expiry gets disappearing records for free, and one that did not is
-- simply told who has seen what.
function actions.APP_DATA_READ(payload)
    local account = requireSession(payload)
    local appId = appstore.appId(payload)
    appstore.requireGrant(account, appId)
    return appstore.dispatch("read", account, appId, payload)
end

function appstore.ops.read(account, appId, payload)
    local collection = appstore.collection(appId, payload.collection)
    appstore.prune(collection)
    local marked = {}
    local wanted = {}
    if type(payload.ids) == "table" then
        for _, id in ipairs(payload.ids) do wanted[tostring(id)] = true end
    end
    if payload.id then wanted[tostring(payload.id)] = true end
    for _, record in ipairs(collection.items) do
        if wanted[record.id]
            and appstore.visible(record, account.account_id)
            -- The author reading their own record back is not a read
            -- receipt, or every message would expire the moment it was sent.
            and record.author_id ~= account.account_id then
            record.read_by = record.read_by or {}
            if not record.read_by[account.account_id] then
                record.read_by[account.account_id] = true
                if record.expire_after_days and not record.expires_day then
                    record.expires_day = util.ingameDay()
                        + record.expire_after_days
                end
            end
            marked[#marked + 1] = record.id
        end
    end
    save()
    return { read = marked }
end

-- The one thing anybody can add to somebody else's record.
function actions.APP_DATA_REACT(payload)
    local account = requireSession(payload)
    local appId = appstore.appId(payload)
    appstore.requireGrant(account, appId)
    return appstore.dispatch("react", account, appId, payload)
end

function appstore.ops.react(account, appId, payload)
    local collection = appstore.collection(appId, payload.collection)
    for _, record in ipairs(collection.items) do
        if record.id == payload.id
            and appstore.visible(record, account.account_id) then
            record.reactions = record.reactions or {}
            if payload.on == false then
                record.reactions[account.account_id] = nil
            else
                local count = 0
                for _ in pairs(record.reactions) do count = count + 1 end
                need(count < (tonumber(config.max_app_reactions) or 60)
                    or record.reactions[account.account_id],
                    "TOO_MANY", "That record cannot hold more reactions")
                record.reactions[account.account_id] = true
            end
            save()
            return { record = appstore.publicRecord(record,
                account.account_id) }
        end
    end
    need(false, "NOT_FOUND", "That record is gone")
end

-- Developer accounts ----------------------------------------------------------
-- A Service Kiosk owner can become a developer and publish apps. The App
-- Server checks the token here once, when something is published; every
-- download after that never touches the Bank at all.

function actions.DEV_REGISTER(payload)
    local terminal = requireTerminal(payload)
    local _, owner = companyOwner(terminal)
    need(owner, "NO_COMPANY", "Link this kiosk to a company first")
    need(verifyAccount(owner, payload.pin), "BAD_PIN", "Incorrect owner PIN")
    state.developers = state.developers or {}
    local existing = state.developers[owner.account_id]
    if existing then
        return { developer_id = existing.developer_id,
            developer_token = existing.developer_token,
            name = owner.name, existing = true }
    end
    local developer = {
        developer_id = nextId("developer"),
        developer_token = util.token("DEV"),
        account_id = owner.account_id,
        name = owner.name,
        created_day = util.ingameDay(),
    }
    state.developers[owner.account_id] = developer
    save()
    logActivity("Developer account: " .. owner.name, colors.purple)
    return { developer_id = developer.developer_id,
        developer_token = developer.developer_token,
        name = owner.name, existing = false }
end

-- A signed-in PUMPE asking whether it is a developer, so the App Browser can
-- offer to delete the apps this account published and nobody else's.
function actions.DEV_MINE(payload)
    local account = requireSession(payload)
    local developer = (state.developers or {})[account.account_id]
    if not developer then return { developer_id = nil } end
    return {
        developer_id = developer.developer_id,
        developer_token = developer.developer_token,
        name = developer.name,
    }
end

-- Asked by the App Server, never by a PUMPE.
function actions.DEV_VERIFY(payload)
    for _, developer in pairs(state.developers or {}) do
        if developer.developer_id == payload.developer_id
            and developer.developer_token == payload.developer_token then
            local account = state.accounts[developer.account_id]
            need(account and not account.banned, "DEV_BANNED",
                "That developer account is not active")
            return { name = developer.name,
                account_id = developer.account_id }
        end
    end
    need(false, "DEV_UNKNOWN", "That developer is not registered")
end

-- Proximity scanning ---------------------------------------------------------
-- A PUMPE showing a ticket or a travel document tells the Bank what it is
-- holding up. A door or a border then asks who is nearest with the right
-- thing on screen, rather than anybody typing an eight character code.

function scans.presenting(account, kind)
    local held = account.presenting
    if type(held) ~= "table" or held.kind ~= kind then return nil end
    local maxAge = tonumber(config.present_max_age_ms) or 20000
    if util.nowMs() - (held.at or 0) > maxAge then return nil end
    return held
end

-- The nearest account holding up something this scanner accepts. `matches`
-- decides whether the held reference is valid here, so the ticket door and
-- the border gate share everything except that one rule.
function scans.nearest(origin, kind, matches, excluded)
    local best, bestDistance, bestHeld
    local radius = tonumber(config.proximity_pay_radius) or 16
    for accountId, account in pairs(state.accounts) do
        local held = not excluded[accountId] and not account.banned
            and not account.frozen and scans.presenting(account, kind)
        local position = held and freshPosition(account)
        if position and matches(account, held) then
            local distance = distanceBetween(origin, position)
            if distance <= radius
                and (not bestDistance or distance < bestDistance) then
                best, bestDistance, bestHeld = account, distance, held
            end
        end
    end
    return best, bestDistance, bestHeld
end

function scans.public(request)
    return {
        request_id = request.request_id,
        kind = request.kind,
        status = request.status,
        title = request.title,
        detail = request.detail,
        target_name = request.target_name,
        distance = request.distance,
        reference = request.reference,
        result = request.result,
    }
end

function scans.expired(request)
    return request.status ~= "offered" or request.expires_at <= util.nowMs()
end

-- Hands the ask to the next nearest holder, or reports that nobody is there.
function scans.retarget(request)
    local origin = request.origin
    local account, distance, held = scans.nearest(origin, request.kind,
        request.matches, request.declined)
    if not account then
        request.status = "nobody_nearby"
        request.target_account_id, request.target_name = nil, nil
        return request
    end
    request.target_account_id = account.account_id
    request.target_name = account.name
    request.reference = held.ref
    request.distance = math.floor(distance * 10) / 10
    request.status = "offered"
    request.expires_at = util.nowMs()
        + (tonumber(config.proximity_offer_ttl_ms) or 60000)
    notification(account, request.title, request.detail, "info")
    return request
end

-- Scans are in-memory, so they need their own sweep. A settled one is kept
-- briefly so the scanner's next poll still sees the result.
function scans.cleanup()
    local now = util.nowMs()
    for requestId, request in pairs(scans.requests) do
        local settled = request.settled_at or request.created_at
        if (request.status ~= "offered" and now - settled > 60 * 1000)
            or request.expires_at + 5 * 60 * 1000 < now then
            scans.requests[requestId] = nil
        end
    end
end

function scans.new(kind, origin, title, detail, matches, extra)
    cleanupEphemeral()
    scans.cleanup()
    local request = {
        request_id = nextId("scan"),
        kind = kind,
        origin = origin,
        title = util.safeText(title, 40),
        detail = util.safeText(detail, 90),
        matches = matches,
        declined = {},
        status = "offered",
        created_at = util.nowMs(),
        expires_at = util.nowMs()
            + (tonumber(config.proximity_offer_ttl_ms) or 60000),
    }
    for key, value in pairs(extra or {}) do request[key] = value end
    scans.requests[request.request_id] = request
    scans.retarget(request)
    return request
end

function scans.poll(request)
    scans.cleanup()
    if request.status == "offered" and request.expires_at <= util.nowMs() then
        request.declined[request.target_account_id or ""] = true
        scans.retarget(request)
    end
    return request
end

-- The scan waiting on this account, used by the OS poll.
function scans.forAccount(accountId)
    for _, request in pairs(scans.requests) do
        if request.target_account_id == accountId and not scans.expired(request) then
            return scans.public(request)
        end
    end
    return nil
end

-- The scanner's own view of a request it started.
function scans.requireOwn(ownerId, requestId, field)
    local request = scans.requests[requestId]
    need(request and request[field] == ownerId, "NOT_FOUND",
        "That check has ended")
    return request
end

function scans.require(account, requestId)
    local request = scans.requests[requestId]
    need(request and not scans.expired(request), "NOT_FOUND",
        "That request has ended")
    need(request.target_account_id == account.account_id, "NOT_YOURS",
        "That request is not yours")
    return request
end

function actions.PRESENT(payload)
    local account = requireSession(payload)
    recordPosition(account, payload.position)
    local kind = payload.kind
    if not scans.kinds[kind] or type(payload.ref) ~= "string" then
        account.presenting = nil
        return { presenting = false }
    end
    account.presenting = { kind = kind, ref = payload.ref, at = util.nowMs() }
    return { presenting = true }
end

-- Accepting runs the scan's own settle step: admitting a ticket, or putting a
-- traveller through the border. A refusal there ends this person's turn and
-- tells the scanner why, rather than silently passing to the next one.
function actions.SCAN_ACCEPT(payload)
    local account = requireSession(payload)
    local request = scans.require(account, payload.request_id)
    local ok, result = pcall(request.settle, request, account)
    if not ok then
        request.declined[account.account_id] = true
        request.status = "rejected"
        request.settled_at = util.nowMs()
        request.result = type(result) == "table" and result.message
            or "Could not be accepted"
        save()
        error(result, 0)
    end
    request.status = "accepted"
    request.settled_at = util.nowMs()
    request.settled_account_id = account.account_id
    request.result = result
    save()
    return { scan = scans.public(request) }
end

function actions.SCAN_DECLINE(payload)
    local account = requireSession(payload)
    local request = scans.require(account, payload.request_id)
    request.declined[account.account_id] = true
    scans.retarget(request)
    save()
    return { scan = scans.public(request) }
end

-- The offer waiting for this account, used by the OS poll.
local function offerFor(accountId)
    for _, offer in pairs(state.proximity_offers) do
        if offer.target_account_id == accountId then
            -- A Portable Mode offer waits for the customer before it has a
            -- basket, so there is no pay code to check yet.
            if offer.status == "claiming" and offer.expires_at > util.nowMs() then
                return publicOffer(offer)
            end
            local payment = offer.code and state.active_pay_codes[offer.code]
            if not offerExpired(offer) and payment
                and payment.status == "pending" then
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
    -- An announcement can be aimed at one account instead of the whole
    -- network. Everything else about it is identical.
    local target = payload.account_id and requireAccountId(payload) or nil
    state.announcements = state.announcements or {}
    local item = {
        announcement_id = nextId("announcement"),
        title = title,
        body = body,
        mode = mode,
        account_id = target and target.account_id or nil,
        target_name = target and target.name or nil,
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
        if not target or account.account_id == target.account_id then
            notification(account, title, body,
                mode == "modal" and "urgent" or "info")
        end
    end
    save()
    logActivity("Announcement: " .. title
        .. (target and (" -> " .. target.name) or ""), colors.magenta)
    return { announcement = util.copy(item) }
end

-- Government messages. A thread between the state and one account, used for
-- anything that needs a reply: a speeding ticket, a query, a warning. Only
-- the government can move money in it; the holder can answer and can settle
-- what is asked of them.
local function governmentThread(account)
    local threadId = account.government_conversation_id
    local existing = threadId and state.conversations[threadId]
    if existing then return existing end
    local conversation = newConversation("government",
        { account.account_id }, "Government", nil)
    account.government_conversation_id = conversation.conversation_id
    return conversation
end

local function governmentSay(conversation, account, kind, body, extra)
    local item = appendMessage(conversation, "GOVERNMENT", kind, body, extra)
    notification(account, "Government message",
        util.safeText(body, 90), "warning")
    return item
end

function actions.ADMIN_MESSAGE(payload)
    requireGovernment(payload)
    local account = requireAccountId(payload)
    local body = util.safeText(util.trim(payload.body or ""), SOCIAL.max_message)
    need(#body > 0, "EMPTY_MESSAGE", "Write something to send")
    local conversation = governmentThread(account)
    local item = governmentSay(conversation, account, "text", body)
    save()
    logActivity("Government message to " .. account.name, colors.magenta)
    return { conversation_id = conversation.conversation_id,
        message = util.copy(item) }
end

function actions.ADMIN_MESSAGE_DEMAND(payload)
    requireGovernment(payload)
    local account = requireAccountId(payload)
    local amount = validateAmount(payload.amount)
    local note = util.safeText(util.trim(payload.note or "Government demand"), 60)
    local conversation = governmentThread(account)
    local item = governmentSay(conversation, account, "money_request", note, {
        amount = amount,
        status = "pending",
    })
    save()
    logActivity("Government asked " .. account.name .. " for "
        .. util.money(amount, config.currency), colors.orange)
    return { conversation_id = conversation.conversation_id,
        message = util.copy(item) }
end

function actions.ADMIN_MESSAGE_PAY(payload)
    requireGovernment(payload)
    local account = requireAccountId(payload)
    local amount = validateAmount(payload.amount)
    local note = util.safeText(util.trim(payload.note or "Government payment"), 60)
    local conversation = governmentThread(account)
    account.balance = util.roundMoney(account.balance + amount)
    state.tax_revenue = util.roundMoney((state.tax_revenue or 0) - amount)
    transaction(account, "government", amount, "Government", note)
    governmentSay(conversation, account, "money_sent",
        "sent " .. util.money(amount, config.currency), { amount = amount })
    save()
    logActivity("Government paid " .. account.name .. " "
        .. util.money(amount, config.currency), colors.lime)
    return { conversation_id = conversation.conversation_id,
        balance = account.balance }
end

function actions.ADMIN_MESSAGE_HISTORY(payload)
    requireGovernment(payload)
    local account = requireAccountId(payload)
    local conversation = account.government_conversation_id
        and state.conversations[account.government_conversation_id]
    if not conversation then
        return { messages = {}, name = account.name }
    end
    local afterSeq = math.max(0, math.floor(tonumber(payload.after_seq) or 0))
    local messages = {}
    for _, item in ipairs(conversation.messages) do
        if item.seq > afterSeq then messages[#messages + 1] = util.copy(item) end
    end
    return {
        conversation_id = conversation.conversation_id,
        name = account.name,
        messages = messages,
        next_seq = conversation.next_seq,
    }
end

-- Every thread the government is holding, newest first, so the terminal can
-- see who has replied.
function actions.ADMIN_MESSAGE_THREADS(payload)
    requireGovernment(payload)
    local threads = {}
    for _, account in pairs(state.accounts) do
        local conversation = account.government_conversation_id
            and state.conversations[account.government_conversation_id]
        if conversation then
            local last = conversation.messages[#conversation.messages]
            threads[#threads + 1] = {
                account_id = account.account_id,
                name = account.name,
                last_at = conversation.last_at,
                last_body = last and util.safeText(last.body or "", 40) or "",
                waiting = last ~= nil and last.sender_id ~= "GOVERNMENT",
            }
        end
    end
    table.sort(threads, function(a, b)
        return (a.last_at or 0) > (b.last_at or 0)
    end)
    return { threads = threads }
end

local function announcementFor(accountId)
    for _, item in ipairs(state.announcements or {}) do
        -- An announcement aimed at one account is invisible to everyone else.
        if not item.acknowledged[accountId]
            and (not item.account_id or item.account_id == accountId) then
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
        scan = scans.forAccount(account.account_id),
        announcement = announcementFor(account.account_id),
        latest = latest and {
            notification_id = latest.notification_id,
            title = latest.title,
            body = latest.body,
            kind = latest.kind,
            app_name = latest.app_name,
            style = latest.style,
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
    local account = requireSpender(payload)
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

-- Proximity Visa. The controller leaves this on and the Bank keeps asking
-- whoever is nearest with a travel document on screen. Accepting runs the
-- ordinary border check, so entry rules, cooldowns and visits are identical
-- to typing the code in by hand.

function actions.VISA_SCAN(payload)
    local controller = requireBorderController(payload)
    local territory = state.territories[controller.territory_id]
    need(territory and territory.status == "active",
        "TERRITORY_NOT_FOUND", "Configured territory is unavailable")
    local origin = scans.position(payload)
    local request = scans.new("visa", origin, "Border check",
        "Stand at the " .. territory.name .. " border to cross",
        function(account, held)
            local document = state.visas[held.ref]
            return document ~= nil
                and document.account_id == account.account_id
                and document.status ~= "revoked"
                and document.status ~= "expired"
        end,
        {
            controller_id = controller.controller_id,
            controller_token = controller.auth_token,
            territory_id = territory.territory_id,
            settle = function(request, account)
                local document = state.visas[request.reference]
                need(document and document.account_id == account.account_id,
                    "NOT_YOURS", "That travel document is not yours")
                -- Leaving if they are already inside, entering otherwise. A
                -- gate has no Enter/Exit buttons to press.
                local inside = openVisit(account.account_id,
                    request.territory_id, document.visa_id)
                local outcome = actions.BORDER_CHECK({
                    controller_id = request.controller_id,
                    controller_token = request.controller_token,
                    code = document.code,
                    direction = inside and "exit" or "enter",
                })
                account.presenting = nil
                request.direction = outcome.direction
                return account.name .. "  -  " .. outcome.action
            end,
        })
    save()
    return { scan = scans.public(request) }
end

function actions.VISA_SCAN_STATUS(payload)
    local controller = requireBorderController(payload)
    local request = scans.requireOwn(controller.controller_id,
        payload.request_id, "controller_id")
    scans.poll(request)
    return { scan = scans.public(request) }
end

function actions.VISA_SCAN_CANCEL(payload)
    local controller = requireBorderController(payload)
    local request = scans.requireOwn(controller.controller_id,
        payload.request_id, "controller_id")
    request.status = "cancelled"
    request.settled_at = util.nowMs()
    return { scan = scans.public(request) }
end

function actions.PAY_CODE_PREVIEW(payload)
    local account = requireSpender(payload)
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
    local account = requireSpender(payload)
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
    local account = requireSpender(payload)
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
    local account = requireSpender(payload)
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

-- Proximity ticket scanning. The organiser turns it on at the door and the
-- Bank asks whoever is nearest with a ticket for this event on screen.

local function requireOrganizerEvent(owner, eventId)
    local event = state.events[eventId]
    need(event and event.organizer_account_id == owner.account_id,
        "NOT_OWNER", "That event is not yours")
    need(event.status == "active", "EVENT_CLOSED", "That event is closed")
    return event
end

function actions.TICKET_SCAN(payload)
    local owner = requireSession(payload)
    local event = requireOrganizerEvent(owner, payload.event_id)
    local origin = scans.position(payload)
    local request = scans.new("ticket", origin, "Ticket check",
        "Scan your ticket for " .. event.title,
        function(_, held)
            local ticket = state.tickets[held.ref]
            return ticket ~= nil and ticket.event_id == event.event_id
                and ticket.status == "valid" and not ticket.used
        end,
        {
            event_id = event.event_id,
            organizer_id = owner.account_id,
            settle = function(request, account)
                local ticket = state.tickets[request.reference]
                need(ticket and ticket.account_id == account.account_id,
                    "NOT_YOURS", "That ticket is not yours")
                need(ticket.event_id == request.event_id, "WRONG_EVENT",
                    "That ticket is for another event")
                need(ticket.status == "valid" and not ticket.used,
                    "ALREADY_USED", "That ticket has already been used")
                ticket.used = true
                ticket.status = "used"
                ticket.used_day = util.ingameDay()
                ticket.used_time = util.formatClock()
                account.presenting = nil
                local ticketType = state.ticket_types[ticket.ticket_type_id]
                logActivity("Ticket admitted: " .. ticket.qr_code, colors.lime)
                return account.name .. "  -  "
                    .. (ticketType and ticketType.name or "Ticket")
            end,
        })
    save()
    return { scan = scans.public(request) }
end

function actions.TICKET_SCAN_STATUS(payload)
    local owner = requireSession(payload)
    local request = scans.requireOwn(owner.account_id, payload.request_id,
        "organizer_id")
    scans.poll(request)
    return { scan = scans.public(request) }
end

function actions.TICKET_SCAN_CANCEL(payload)
    local owner = requireSession(payload)
    local request = scans.requireOwn(owner.account_id, payload.request_id,
        "organizer_id")
    request.status = "cancelled"
    request.settled_at = util.nowMs()
    return { scan = scans.public(request) }
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

local function ledgerLoop()
    local protocol = config.ledger_protocol or "PUMPE_LEDGER_V1"
    while running do
        local sender, message = rednet.receive(protocol, 1)
        if sender and type(message) == "table" and message.kind == "request"
            and type(message.action) == "string" then
            local handler = ledger.actions[message.action]
            if not handler then
                net.reply(sender, protocol, message.request_id, false, nil,
                    "Unknown ledger action", "UNKNOWN_ACTION")
            else
                local ok, result = pcall(handler, message.payload or {})
                if ok then
                    net.reply(sender, protocol, message.request_id, true,
                        result)
                elseif type(result) == "table" and result.pumpe then
                    net.reply(sender, protocol, message.request_id, false,
                        nil, result.message, result.code)
                else
                    logActivity("Ledger error: " .. tostring(result),
                        colors.red)
                    net.reply(sender, protocol, message.request_id, false,
                        nil, "Ledger failed", "LEDGER_ERROR")
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
        pcall(ledger.reconcile)
        pcall(ledger.sweep)
        sleep(10)
    end
end

local function ccgEscrowLoop()
    while running do
        pcall(sweepAbandonedEscrow)
        sleep(30)
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
            { "CCG ESCROW", count(state.ccg_escrow), colors.lime },
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

-- Pair Mode -------------------------------------------------------------------
-- Two Bank Servers, one bank. The split is deliberately not down the middle:
-- everyday banking is a hot path where a second radio hop would be felt on
-- every balance check, so the Core keeps all of it. What moves to the Vault
-- is the heavy, cold work -- serving update downloads, and holding the app
-- record store -- which is what was actually crowding the Core's disk and
-- making banking queue behind file transfers.
--
-- Clients never learn any of this. The depot simply answers from a different
-- computer, which rednet already resolves by name, and app records reach the
-- Vault through the Core.

function pair.load()
    local saved = util.loadTable(pair.file, {})
    if saved.role == "core" or saved.role == "vault" then
        pair.role = saved.role
        pair.partner = saved.partner
        pair.partner_code = saved.partner_code
        pair.since = saved.since
    end
end

function pair.store()
    pcall(util.saveTable, pair.file, {
        role = pair.role, partner = pair.partner,
        partner_code = pair.partner_code, since = pair.since,
    })
end

function pair.newCode()
    pair.code = util.randomString(6, "0123456789")
    return pair.code
end

function pair.isVault() return pair.role == "vault" end
function pair.isCore() return pair.role == "core" end
function pair.paired() return pair.partner ~= nil end

-- What a Vault answers. Everything the Core hands over lives behind this one
-- protocol, so nothing else on the network can reach it.
pair.actions = {}

function pair.actions.PAIR_HELLO(payload, sender)
    return {
        computer = os.getComputerID(),
        code = pair.code,
        accounts = mapCount(state.accounts),
        version = config.version,
    }
end

-- Claiming is what pairs them. The server whose code was entered decides
-- which half is which, and it protects data: whichever side already has
-- accounts stays the Core, so pairing can never strand a live ledger behind
-- a Vault that does no banking.
function pair.actions.PAIR_CLAIM(payload, sender)
    need(pair.role ~= "vault", "ALREADY_VAULT", "This server is already a Vault")
    need(not pair.paired(), "ALREADY_PAIRED", "This server is already paired")
    need(tostring(payload.code or "") == tostring(pair.code or ""),
        "BAD_CODE", "That is not this server's code")
    local mine = mapCount(state.accounts)
    local theirs = math.floor(tonumber(payload.accounts) or 0)
    -- A tie goes to the server that was already here: the one being claimed.
    local iAmCore = mine >= theirs
    pair.role = iAmCore and "core" or "vault"
    pair.partner = sender
    pair.partner_code = payload.code_of_theirs
    pair.since = util.nowMs()
    pair.store()
    logActivity("Paired with computer #" .. tostring(sender) .. " as "
        .. string.upper(pair.role), colors.lime)
    return {
        paired = true,
        their_role = iAmCore and "vault" or "core",
        computer = os.getComputerID(),
        accounts = mine,
    }
end

-- The app record store, once it lives on the Vault. The Core forwards the
-- whole action rather than reaching into the data, so there is exactly one
-- implementation of what an app record means.
function pair.actions.VAULT_APP_DATA(payload, sender)
    -- Only the Core this Vault is paired to. Rednet ids are as strong as
    -- anything else on this network, and without the check any computer
    -- could read every app's records by asking nicely.
    need(sender == pair.partner, "NOT_MY_CORE",
        "This Vault is paired to another server")
    local handler = appstore.ops[tostring(payload.op or "")]
    need(handler, "NOT_VAULT_WORK", "The Vault does not do that")
    local caller = type(payload.caller) == "table" and payload.caller or {}
    need(type(caller.account_id) == "string", "NO_CALLER",
        "The Core did not say who is asking")
    return handler(caller, payload.app_id, payload.payload or {})
end

function pair.reach()
    if not pair.partner then return nil end
    local client = net.client({
        protocol = config.pair_protocol or "PUMPE_PAIR_V1",
        hostname = config.pair_hostname or "BANK_VAULT",
    })
    client.serverId = pair.partner
    return client
end

function pair.ask(action, payload, timeout)
    local client = pair.reach()
    if not client then return nil, "No Vault is paired" end
    return client:request(action, payload, timeout or 6)
end

function pair.loop()
    local protocol = config.pair_protocol or "PUMPE_PAIR_V1"
    while running do
        local sender, message = rednet.receive(protocol, 1)
        if sender and type(message) == "table" and message.kind == "request"
            and type(message.action) == "string" then
            local handler = pair.actions[message.action]
            if not handler then
                net.reply(sender, protocol, message.request_id, false, nil,
                    "Unknown pair action", "UNKNOWN_ACTION")
            else
                local ok, result = pcall(handler, message.payload or {},
                    sender)
                if ok then
                    net.reply(sender, protocol, message.request_id, true,
                        result)
                elseif type(result) == "table" and result.pumpe then
                    net.reply(sender, protocol, message.request_id, false,
                        nil, result.message, result.code)
                else
                    logActivity("Pair error: " .. tostring(result), colors.red)
                    net.reply(sender, protocol, message.request_id, false,
                        nil, "Pair request failed", "PAIR_ERROR")
                end
            end
        end
    end
end

-- Entering the other server's code. A code is a rednet hostname while it is
-- being shown, so finding the other half is the same lookup everything else
-- on this network uses rather than a broadcast nobody can debug.
function pair.claim(code)
    code = tostring(code or ""):gsub("%D", "")
    if #code ~= 6 then return nil, "A pairing code is six digits" end
    if code == pair.code then return nil, "That is this server's own code" end
    local protocol = config.pair_protocol or "PUMPE_PAIR_V1"
    local other = rednet.lookup(protocol, "PAIRING_" .. code)
    if not other then return nil, "No server is showing that code" end
    local client = net.client({ protocol = protocol,
        hostname = "PAIRING_" .. code })
    client.serverId = other
    local claimed, err = client:request("PAIR_CLAIM", {
        code = code,
        code_of_theirs = pair.code,
        accounts = mapCount(state.accounts),
    }, 8)
    if not claimed then return nil, err or "That server did not answer" end
    pair.role = claimed.their_role
    pair.partner = other
    pair.partner_code = code
    pair.since = util.nowMs()
    pair.store()
    logActivity("Paired with computer #" .. tostring(other) .. " as "
        .. string.upper(pair.role), colors.lime)
    return true
end


if TEST_MODE then
    return {
        actions = actions,
        state = state,
        cleanup = cleanupEphemeral,
        process_bet_holds = processBetHolds,
        sweep_ccg_escrow = sweepAbandonedEscrow,
        deployment_files = deploymentFilesForRole,
        deployment_body = deploymentBody,
        ensure_bank_startup = ensureBankStartup,
        local_update_body = localUpdateBody,
        compact_bank_storage = compactBankStorage,
        deployment_fetch = fetchDepotFile,
        drop_stale_cache = dropStaleDepotCache,
        urgent_calls = urgentCalls,
        ledger = ledger,
        pair = pair,
    }
end

-- The launch question, asked once. A Bank that has already been paired or
-- has already been told to stay solo never asks again.
function pair.chooseMode(target)
    while true do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "PUMPE BANK SERVER", "v" .. config.version,
            util.formatClock())
        ui.center(target, 5, "HOW SHOULD THIS BANK RUN?", colors.white)
        local half = math.floor((width - 3) / 2)
        ui.card(target, 2, 7, half, 6, colors.cyan)
        ui.text(target, 4, 8, "SOLO", colors.white, colors.gray)
        ui.wrappedText(target, 4, 9, "One computer does everything. This is"
            .. " how every Bank before 9.0 ran.", half - 3, 4,
            colors.lightGray, colors.gray)
        ui.card(target, 3 + half, 7, width - 3 - half, 6, colors.lime)
        ui.text(target, 5 + half, 8, "PAIR", colors.white, colors.gray)
        ui.wrappedText(target, 5 + half, 9, "Two computers share the work."
            .. " Downloads and app data move off the banking computer.",
            width - 6 - half, 4, colors.lightGray, colors.gray)
        local scene = ui.scene(target)
        scene:button("solo", 2, 14, half, 3, "SOLO MODE",
            { background = colors.cyan, foreground = colors.black })
        scene:button("pair", 3 + half, 14, width - 3 - half, 3, "PAIR MODE",
            { background = colors.lime, foreground = colors.black })
        local action = scene:wait({ tickRate = 5, flash = false })
        if action == "solo" then return "solo" end
        if action == "pair" then return "pair" end
        if action == "__terminate" then return "solo" end
    end
end

-- Showing a code and being able to type the other one. Both servers show
-- both, which is what makes it not matter which computer you walk to first.
function pair.pairingScreen(target)
    local protocol = config.pair_protocol or "PUMPE_PAIR_V1"
    pair.newCode()
    net.openModems()
    pcall(rednet.unhost, protocol)
    rednet.host(protocol, "PAIRING_" .. pair.code)
    local message, messageColor = nil, colors.lightGray

    -- Answering PAIR_CLAIM while the code is on screen is what lets the
    -- other server pair with this one without anybody touching this
    -- keyboard.
    local function listen()
        while not pair.paired() do
            local sender, packet = rednet.receive(protocol, 0.4)
            if sender and type(packet) == "table"
                and packet.kind == "request" then
                local handler = pair.actions[packet.action]
                if handler then
                    local ok, result = pcall(handler, packet.payload or {},
                        sender)
                    if ok then
                        net.reply(sender, protocol, packet.request_id, true,
                            result)
                    else
                        net.reply(sender, protocol, packet.request_id, false,
                            nil, type(result) == "table" and result.message
                                or "Pairing failed",
                            type(result) == "table" and result.code or nil)
                    end
                end
            end
        end
    end

    local function draw()
        while not pair.paired() do
            local width, height = target.getSize()
            ui.clear(target)
            ui.header(target, "PAIR MODE", "Waiting for the other server",
                util.formatClock())
            ui.card(target, 2, 5, width - 2, 5, colors.lime)
            ui.text(target, 4, 6, "THIS SERVER'S CODE", colors.lightGray,
                colors.gray)
            ui.center(target, 8, pair.code, colors.white, colors.gray)
            ui.wrappedText(target, 2, 11, "Open a second Bank Server, choose"
                .. " PAIR MODE, and type this code into it -- or type its"
                .. " code in here. Either way round works.",
                width - 2, 4, colors.lightGray)
            if message then
                ui.text(target, 2, height - 4,
                    ui.truncate(message, width - 2), messageColor)
            end
            local scene = ui.scene(target)
            scene:button("enter", 2, height - 2, 22, 2, "ENTER THEIR CODE",
                { background = colors.blue })
            scene:button("solo", width - 11, height - 2, 10, 2, "GO SOLO",
                { background = colors.gray })
            local action = scene:wait({ tickRate = 0.4, flash = false })
            if action == "solo" or action == "__terminate" then
                pair.role = "solo"
                return
            elseif action == "enter" then
                local typed = ui.input(target, "THEIR CODE", {
                    hint = "Six digits from the other server",
                    mode = "number", maxLength = 6,
                })
                if typed then
                    local ok, err = pair.claim(typed)
                    if not ok then
                        message, messageColor = err, colors.orange
                    end
                end
            end
        end
    end

    parallel.waitForAny(listen, draw)
    pcall(rednet.unhost, protocol)
    return pair.role
end

ui.boot(term.current(), "PUMPE BANK", "SECURE ECONOMY CORE")

-- Solo or Pair, asked once. A Bank that was already answered -- paired, or
-- told to stay solo -- comes straight up the way it was left.
pair.load()
if pair.role == "solo" or not pair.role then
    if not fs.exists(pair.file) then
        if pair.chooseMode(term.current()) == "pair" then
            pair.pairingScreen(term.current())
        else
            pair.role = "solo"
        end
        pair.store()
    else
        pair.role = "solo"
    end
end

net.openModems()
if pair.isVault() then
    -- The Vault does no banking. It serves downloads and holds the app
    -- record store, and it is the only half that hosts the depot, so a
    -- client looking for updates simply resolves a different computer.
    rednet.host(config.pair_protocol or "PUMPE_PAIR_V1",
        config.pair_hostname or "BANK_VAULT")
    rednet.host(DEPLOY.protocol, DEPLOY.hostname)
    logActivity("Vault online for computer #" .. tostring(pair.partner),
        colors.lime)
else
    net.host(config.protocol, config.hostname)
    if pair.isCore() then
        -- The depot belongs to the Vault now. Not hosting it here is what
        -- takes file transfers off the banking computer.
        logActivity("Core online, Vault is computer #"
            .. tostring(pair.partner), colors.lime)
    else
        rednet.host(DEPLOY.protocol, DEPLOY.hostname)
    end
    -- Every bank answers to LEDGER_<its four digits>. Claimed only by the
    -- half that runs ledgerLoop: both halves of a pair share one bank code,
    -- so a Vault claiming it took the name its own Core needed and killed
    -- whichever started second with "Hostname in use".
    state.bank_code = state.bank_code or config.foxy_bank_code or "0001"
    rednet.host(config.ledger_protocol or "PUMPE_LEDGER_V1",
        "LEDGER_" .. ledger.bankCode())
end
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

if pair.isVault() then
    -- Everything the Vault is for, and nothing else.
    parallel.waitForAny(deploymentLoop, pair.loop, dashboardLoop)
else
    parallel.waitForAny(serverLoop, deploymentLoop, ledgerLoop, pair.loop,
        schedulerLoop, ccgEscrowLoop, onlineUpdateLoop, dashboardLoop)
end
pcall(rednet.unhost, config.protocol)
pcall(rednet.unhost, DEPLOY.protocol)
pcall(rednet.unhost, config.ledger_protocol or "PUMPE_LEDGER_V1")
pcall(rednet.unhost, config.pair_protocol or "PUMPE_PAIR_V1")
ui.clear(term.current())
print("PUMPE Bank Server stopped safely.")
