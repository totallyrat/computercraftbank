local ROOT = fs.getDir(shell.getRunningProgram())
if ROOT == "" then ROOT = "." end
package.path = package.path .. ";" .. fs.combine(ROOT, "?.lua")
    .. ";" .. fs.combine(ROOT, "?/init.lua")

-- Stamped by tools/build_release_manifest.js. A program running beside a
-- config.lua from a different release means a partial install.
local PROGRAM_VERSION = "9.4.0"
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

-- Pair Mode. A Bank is two computers joined by a cable: this one, the Core,
-- holds the money and decides who is asking, and the Vault runs
-- bank_vault.lua and holds everything that is about an account without being
-- its balance -- conversations, visas, tickets, app records. A Core with no
-- Vault still banks; it just cannot answer for what the Vault owns.
local pair = {
    role = "solo",              -- "solo" (no Vault yet), "core" or "vault"
    partner = nil,              -- the other half's computer id
    since = nil,
    wired = nil,                -- proved to be on a cable when they paired
    pairing = false,            -- true only while the pairing screen is up
    online = nil,               -- did the Vault answer the last time we asked
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
    "revolution.lua",
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
    "revolution.lua",
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
    -- The other half of this Bank. Easy Deployment has to know this role
    -- like any other: 9.3.0 added it to the installer's list but not to
    -- this one, so a computer that had just been made a Vault rebooted,
    -- asked its Core for the program, was told there is no such role, and
    -- stopped with "Run Easy Deployment again".
    vault = "bank_vault.lua",
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

local function ensureBankStartup(installerBody, roleId)
    roleId = roleId or "bank"
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
        .. ", \"--boot\", " .. string.format("%q", roleId) .. ")\n"
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
            account = 0, company = 0, terminal = 0, transaction = 0,
            period = 0, notification = 0, subscription = 0,
            bet_hold = 0, bet_activity = 0,
            ccg_console = 0, ccg_lobby = 0,
            proximity = 0, announcement = 0,
        },
        accounts = {},
        account_names = {},
        -- Account ID -> account_id. The index behind the one address every
        -- bank on the network shares.
        bank_account_ids = {},
        companies = {},
        terminals = {},
        transactions = {},
        declaration_periods = {},
        declarations = {},
        active_pay_codes = {},
        -- Lobbies and consoles moved to ccg_server.lua in 9.1. What the
        -- Bank holds is the money in play.
        ccg_escrow = {},
        ccg_servers = {},
        ccg_house_profit = 0,
        -- Conversations, calls, territories, visas, border registers, events,
        -- tickets and app records moved to bank_vault.lua in 9.3. A Bank
        -- upgrading from 9.2 still has them in its saved state; pair.migrate
        -- hands each one over and clears it, so they are deliberately absent
        -- from a fresh Bank rather than kept empty here.
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
    -- Everything that used to be repaired here -- territory names, visa
    -- codes, visit statuses, event ticket lists -- is repaired on the Vault
    -- now, because that is where those records live. A Bank arriving from
    -- 9.2 still has its copies; pair.migrate hands them over untouched and
    -- the Vault indexes them on the way in.
    state.schema = 9
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

-- What the Vault is told about who is asking. Never a session token: the
-- Core has already decided this, and a Vault that has not been given the
-- means to check cannot be talked into acting as somebody else.
local function vaultCaller(account, extra)
    local caller = {
        account_id = account.account_id,
        name = account.name,
        position = account.position,
    }
    for key, value in pairs(extra or {}) do caller[key] = value end
    return caller
end

-- Friendship is a Vault record, and a handful of money routes here turn on
-- it. Worth the hop: sending cash to a friend is rare next to a balance
-- check, and getting it wrong would mean paying a stranger.
local function requireVaultFriend(account, accountId)
    pair.forward("VAULT_FRIEND", { account_id = accountId },
        vaultCaller(account))
    -- The Vault answers whether they are friends. Who they are, and what
    -- their money is, is still this half's to look up.
    local friend = state.accounts[accountId]
    need(friend, "NOT_FOUND", "Account not found")
    checkAccountActive(friend, true)
    return friend
end

local function requireTerminal(payload)
    local terminal = state.terminals[payload and payload.terminal_id]
    need(terminal and terminal.auth_token == payload.terminal_token,
        "TERMINAL_AUTH", "Kiosk is not registered")
    need(terminal.status == "active", "TERMINAL_INACTIVE", "Kiosk is inactive")
    terminal.last_seen = util.nowMs()
    return terminal
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
end

local function validateAmount(value, maximum)
    local amount = util.roundMoney(value)
    need(amount and amount > 0, "INVALID_AMOUNT", "Enter an amount above zero")
    need(not maximum or amount <= maximum, "INVALID_AMOUNT",
        "Amount is above the allowed maximum")
    return amount
end

-- Paying a Foxy kiosk from another bank ------------------------------------------
-- A kiosk belongs to this bank, and since 9.4 its code is the only way an
-- account somewhere else can pay one. The paying bank quotes the code, takes
-- the money from its own holder, and then tells this bank to credit the
-- merchant under a transfer id -- the same three steps, safe to repeat, that
-- a Bank Transfer uses. This bank never touches the payer's balance and the
-- paying bank never touches the merchant's.
function ledger.actions.LEDGER_CODE_QUOTE(payload)
    cleanupEphemeral()
    local code = string.upper(util.trim(tostring(payload.code or "")))
    local payment = state.active_pay_codes[code]
    need(payment and payment.status == "pending"
        and payment.expires_at > util.nowMs(),
        "BAD_CODE", "Code is invalid or expired")
    -- A withdrawal hands out this bank's money and a subscription is a
    -- standing charge against an account here. Neither is a thing another
    -- bank can settle on somebody's behalf.
    need(payment.kind ~= "withdrawal", "NOT_PAYABLE",
        "A withdrawal code can only be used by the account it pays into")
    need(payment.kind ~= "subscription", "NOT_PAYABLE",
        "A subscription has to be started from an account at this bank")
    local terminal = state.terminals[payment.terminal_id]
    need(terminal, "TERMINAL_NOT_FOUND", "Kiosk no longer exists")
    return {
        code = code,
        kind = payment.kind,
        amount = payment.amount,
        merchant = terminal.name,
        description = payment.description,
        items = util.copy(payment.items or {}),
        expires_in_ms = payment.expires_at - util.nowMs(),
    }
end

function ledger.actions.LEDGER_CODE_SETTLE(payload)
    local code = string.upper(util.trim(tostring(payload.code or "")))
    local transferId = util.safeText(tostring(payload.transfer_id or ""), 32)
    need(#transferId >= 8, "BAD_TRANSFER", "That payment has no id")
    state.applied_transfers = state.applied_transfers or {}

    local payment = state.active_pay_codes[code]
    local settled, repeated = ledger.applyOnce(state.applied_transfers,
        transferId, 1, function()
            need(payment and payment.status == "pending"
                and payment.expires_at > util.nowMs(),
                "BAD_CODE", "Code is invalid or expired")
            need(payment.kind ~= "withdrawal" and payment.kind ~= "subscription",
                "NOT_PAYABLE", "That code cannot be paid from another bank")
            local amount = math.floor(tonumber(payload.amount) or 0)
            need(amount == payment.amount, "AMOUNT_MISMATCH",
                "That is not what this code is worth")
            local terminal = state.terminals[payment.terminal_id]
            need(terminal, "TERMINAL_NOT_FOUND", "Kiosk no longer exists")
            local payerName = util.safeText(
                tostring(payload.from_name or "Another bank"), 24)
            creditMerchant(terminal, amount,
                (payment.description or "Kiosk sale") .. " - " .. payerName
                    .. " (" .. tostring(payload.from_bank_name or "another bank")
                    .. ")", nil)
            payment.status = "paid"
            payment.paid_at = util.nowMs()
            payment.paid_by_bank = payload.from_bank_code
            payment.paid_by_name = payerName
        end)
    if repeated then
        -- The kiosk was already paid; only the answer was lost. Say yes
        -- again rather than charging somebody twice for one basket.
        return { settled = true, repeated = true, code = code }
    end
    ledger.forget(state.applied_transfers)
    save()
    logActivity("Kiosk code " .. code .. " paid from "
        .. tostring(payload.from_bank_name or "another bank"), colors.lime)
    return { settled = settled ~= nil, code = code }
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

function actions.ACCOUNT_SUMMARY(payload)
    local account = requireSession(payload)
    local unread = 0
    for _, item in ipairs(account.notifications) do
        if not item.read then unread = unread + 1 end
    end
    -- Unread counts belong to the Vault, but this is the most called action
    -- on the network and a cable hop inside it would be felt everywhere. The
    -- Vault pushes the counts up whenever they move; this reads them from
    -- memory, and a Vault that is offline simply leaves them where they were.
    local badges = account.badges or {}
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

-- The proximity scan engine, gathered under one name. Open scans are
-- deliberately not persisted: a Bank restart drops a half-finished door check
-- the way a dropped connection would.
local scans = { kinds = { ticket = true, visa = true } }
-- Declared here rather than beside its own section below: Urgent
-- Contact reaches into it, and a local declared further down the file
-- is a nil global at any use site above it.
local appstore = {}











-- Conversations -------------------------------------------------------------




















-- Urgent Contact ------------------------------------------------------------
















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
    local friend = requireVaultFriend(account, payload.account_id)
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
    local friend = requireVaultFriend(account, payload.account_id)
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
        local listed = pair.forward("VAULT_FRIEND_LIST", {},
            vaultCaller(account))
        profile.friends = listed.friends or {}
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
        requireVaultFriend(account, wantedId)
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

-- In-app purchases --------------------------------------------------------------
-- An app can sell things. The money goes to the account that published it --
-- the company owner who made the developer account -- less the government's
-- share, and the Bank records what was bought so the app cannot decide for
-- itself that somebody has paid.
--
-- The app never handles money, names a recipient, or is asked whether a
-- purchase went through. It asks the Bank what this player owns.

function appstore.owners()
    state.app_owners = state.app_owners or {}
    return state.app_owners
end

-- Recorded by the App Server when an app is published, which is the only
-- moment anybody knows both the app id and the developer behind it.
function actions.APP_OWNER_SET(payload)
    local appId = appstore.appId(payload)
    for _, developer in pairs(state.developers or {}) do
        if developer.developer_id == payload.developer_id
            and developer.developer_token == payload.developer_token then
            appstore.owners()[appId] = {
                account_id = developer.account_id,
                name = developer.name,
                app_name = util.safeText(util.trim(payload.app_name or appId), 18),
            }
            save()
            return { ok = true }
        end
    end
    need(false, "DEV_UNKNOWN", "That developer is not registered")
end

function appstore.purchases(account, appId)
    account.app_purchases = account.app_purchases or {}
    account.app_purchases[appId] = account.app_purchases[appId] or {}
    return account.app_purchases[appId]
end

function appstore.publicEntitlement(entry)
    return {
        product_id = entry.product_id,
        name = entry.name,
        amount = entry.amount,
        bought_day = entry.bought_day,
        subscription = entry.period ~= nil,
        period = entry.period,
        active = entry.active ~= false,
        next_charge_day = entry.next_charge_day,
        -- A one-off boost that only covers one thing carries what it was
        -- bought for, so the app can tell them apart.
        target = entry.target,
    }
end

-- The split. Thirty per cent of everything an app sells is tax, taken here
-- rather than trusted to the app or the seller.
function appstore.splitPurchase(amount)
    local rate = tonumber(config.app_purchase_tax_rate) or 0.30
    local tax = util.roundMoney(amount * rate)
    return util.roundMoney(amount - tax), tax
end

function appstore.priceOf(payload)
    local amount = validateAmount(payload.amount,
        tonumber(config.max_app_purchase) or 5000)
    need(amount >= 1, "INVALID_AMOUNT", "A purchase has to cost something")
    return amount
end

function actions.APP_PURCHASE_QUOTE(payload)
    local account = requireSession(payload)
    local appId = appstore.appId(payload)
    appstore.requireGrant(account, appId)
    local amount = appstore.priceOf(payload)
    local toSeller, tax = appstore.splitPurchase(amount)
    local owner = appstore.owners()[appId]
    return {
        product_id = util.safeText(util.trim(payload.product_id or ""), 24),
        name = util.safeText(util.trim(payload.name or ""), 24),
        amount = amount,
        tax = tax,
        to_seller = toSeller,
        seller = owner and owner.name or "the developer",
        period = payload.period == "day" and "day" or nil,
        balance = account.balance,
    }
end

function actions.APP_PURCHASE(payload)
    -- A purchase is spending, so it is refused for the same reasons every
    -- other payment is: a tax demand outstanding, or the money moved to
    -- another bank.
    local account = requireSpender(payload)
    local appId = appstore.appId(payload)
    appstore.requireGrant(account, appId)
    need(verifyAccount(account, payload.pin), "BAD_PIN", "Incorrect PIN")
    local productId = util.safeText(util.trim(payload.product_id or ""), 24)
    need(#productId >= 1, "NO_PRODUCT", "That purchase has no id")
    local amount = appstore.priceOf(payload)
    need(account.balance >= amount, "INSUFFICIENT_FUNDS",
        "Not enough money for that")
    local period = payload.period == "day" and "day" or nil
    local owned = appstore.purchases(account, appId)
    if period then
        local existing = owned[productId]
        need(not (existing and existing.period and existing.active ~= false),
            "ALREADY_SUBSCRIBED", "That subscription is already running")
    end

    local toSeller, tax = appstore.splitPurchase(amount)
    account.balance = util.roundMoney(account.balance - amount)
    state.tax_revenue = util.roundMoney((state.tax_revenue or 0) + tax)
    local owner = appstore.owners()[appId]
    local seller = owner and state.accounts[owner.account_id]
    local sellerName = owner and owner.name or "App developer"
    if seller then
        seller.balance = util.roundMoney(seller.balance + toSeller)
        transaction(seller, "app_sale", toSeller, account.name,
            (owner.app_name or appId) .. " sale")
        notification(seller, "App sale",
            util.money(toSeller, config.currency) .. " from "
                .. (owner.app_name or appId), "money")
    else
        -- Nobody to pay: the developer's account is gone. The government
        -- still takes its share and the rest is not conjured anywhere.
        state.tax_revenue = util.roundMoney(state.tax_revenue + toSeller)
    end
    transaction(account, "app_purchase", -amount, sellerName,
        util.safeText(util.trim(payload.name or productId), 40))

    owned[productId] = {
        product_id = productId,
        name = util.safeText(util.trim(payload.name or productId), 24),
        amount = amount,
        period = period,
        active = true,
        bought_day = util.ingameDay(),
        next_charge_day = period and (util.ingameDay() + 1) or nil,
        target = payload.target
            and util.safeText(util.trim(tostring(payload.target)), 24) or nil,
    }
    save()
    logActivity(account.name .. " bought " .. owned[productId].name,
        colors.purple)
    return {
        bought = appstore.publicEntitlement(owned[productId]),
        paid = amount, tax = tax, balance = account.balance,
    }
end

function actions.APP_ENTITLEMENTS(payload)
    local account = requireSession(payload)
    local appId = appstore.appId(payload)
    appstore.requireGrant(account, appId)
    local list = {}
    for _, entry in pairs(appstore.purchases(account, appId)) do
        list[#list + 1] = appstore.publicEntitlement(entry)
    end
    table.sort(list, function(a, b)
        return (a.product_id or "") < (b.product_id or "")
    end)
    return { entitlements = list }
end

function actions.APP_SUBSCRIPTION_CANCEL(payload)
    local account = requireSession(payload)
    local appId = appstore.appId(payload)
    appstore.requireGrant(account, appId)
    local entry = appstore.purchases(account, appId)[
        util.safeText(util.trim(payload.product_id or ""), 24)]
    need(entry and entry.period, "NOT_SUBSCRIBED",
        "That is not a subscription")
    entry.active = false
    entry.next_charge_day = nil
    save()
    return { cancelled = true }
end

-- Charged with the rest of the day's subscriptions. A day nobody could pay
-- for ends the subscription rather than running up a debt.
function appstore.chargeSubscriptions(today)
    for _, account in pairs(state.accounts) do
        for appId, owned in pairs(account.app_purchases or {}) do
            for _, entry in pairs(owned) do
                if entry.period and entry.active ~= false
                    and (entry.next_charge_day or today) <= today then
                    local owner = appstore.owners()[appId]
                    local seller = owner and state.accounts[owner.account_id]
                    if account.balance >= entry.amount
                        and not account.frozen and not account.banned
                        and not account.bank_closed then
                        local toSeller, tax = appstore.splitPurchase(
                            entry.amount)
                        account.balance = util.roundMoney(
                            account.balance - entry.amount)
                        state.tax_revenue = util.roundMoney(
                            (state.tax_revenue or 0) + tax)
                        if seller then
                            seller.balance = util.roundMoney(
                                seller.balance + toSeller)
                            transaction(seller, "app_sale", toSeller,
                                account.name, entry.name .. " subscription")
                        else
                            state.tax_revenue = util.roundMoney(
                                state.tax_revenue + toSeller)
                        end
                        transaction(account, "app_subscription",
                            -entry.amount, owner and owner.name or "App",
                            entry.name)
                        entry.next_charge_day = today + 1
                    else
                        entry.active = false
                        entry.next_charge_day = nil
                        notification(account, "Subscription stopped",
                            entry.name .. " could not be charged",
                            "subscription")
                    end
                end
            end
        end
    end
end

function appstore.requireGrant(account, appId)
    local grant = appstore.grants(account)[appId]
    need(grant, "NOT_SIGNED_IN", "Sign in to that app first")
    return grant
end





-- Where the records actually live ---------------------------------------------
-- The Core decides who you are and what you are allowed to touch; the store
-- itself is just data, and in Pair Mode it lives on the Vault. Splitting the
-- handlers here rather than duplicating them means there is exactly one
-- implementation of what an app record means, wherever it is kept.












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
-- The thread itself is a conversation, and conversations are the Vault's.
-- The money and the demand behind a government message are still settled
-- here; only the line of text crosses the cable.
local function governmentSay(account, kind, body, extra)
    local said = pair.forward("VAULT_GOV_SAY", {
        account_id = account.account_id,
        name = account.name,
        kind = kind, body = body, extra = extra,
    }, { kind = "government" })
    notification(account, "Government message",
        util.safeText(body, 90), "warning")
    return said
end

function actions.ADMIN_MESSAGE(payload)
    requireGovernment(payload)
    local account = requireAccountId(payload)
    local body = util.safeText(util.trim(payload.body or ""), SOCIAL.max_message)
    need(#body > 0, "EMPTY_MESSAGE", "Write something to send")
    local said = governmentSay(account, "text", body)
    save()
    logActivity("Government message to " .. account.name, colors.magenta)
    return { conversation_id = said.conversation_id, message = said.message }
end

function actions.ADMIN_MESSAGE_DEMAND(payload)
    requireGovernment(payload)
    local account = requireAccountId(payload)
    local amount = validateAmount(payload.amount)
    local note = util.safeText(util.trim(payload.note or "Government demand"), 60)
    local said = governmentSay(account, "money_request", note, {
        amount = amount,
        status = "pending",
    })
    save()
    logActivity("Government asked " .. account.name .. " for "
        .. util.money(amount, config.currency), colors.orange)
    return { conversation_id = said.conversation_id, message = said.message }
end

function actions.ADMIN_MESSAGE_PAY(payload)
    requireGovernment(payload)
    local account = requireAccountId(payload)
    local amount = validateAmount(payload.amount)
    local note = util.safeText(util.trim(payload.note or "Government payment"), 60)
    account.balance = util.roundMoney(account.balance + amount)
    state.tax_revenue = util.roundMoney((state.tax_revenue or 0) - amount)
    transaction(account, "government", amount, "Government", note)
    local said = governmentSay(account, "money_sent",
        "sent " .. util.money(amount, config.currency), { amount = amount })
    save()
    logActivity("Government paid " .. account.name .. " "
        .. util.money(amount, config.currency), colors.lime)
    return { conversation_id = said.conversation_id,
        balance = account.balance }
end

function actions.ADMIN_MESSAGE_HISTORY(payload)
    requireGovernment(payload)
    local account = requireAccountId(payload)
    local history = pair.forward("VAULT_GOV_HISTORY", {
        account_id = account.account_id,
        after_seq = payload.after_seq,
    }, { kind = "government" })
    history.name = account.name
    return history
end

-- Every thread the government is holding, newest first, so the terminal can
-- see who has replied.
function actions.ADMIN_MESSAGE_THREADS(payload)
    requireGovernment(payload)
    return pair.forward("VAULT_GOV_THREADS", {}, { kind = "government" })
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
-- A ringing call and an open scan both belong to the Vault, and both have to
-- reach a phone that is polling this. Rather than put the cable on the poll
-- path -- every phone, several times a second -- the Vault pushes the short
-- list of people something is actually waiting on, and this reads it out of
-- memory. Expiry is checked here so a pushed entry cannot outlive its ring.
local function waitingFor(account)
    local held = account.waiting
    if not held then return nil, nil end
    local now, call, scan = util.nowMs(), held.call, held.scan
    if call and (held.call_expires_at or 0) <= now then call = nil end
    if scan and (held.scan_expires_at or 0) <= now then scan = nil end
    return call, scan
end

function actions.PUMPE_POLL(payload)
    local account = requireSession(payload)
    recordPosition(account, payload.position)
    local unread, latest = 0, nil
    for _, item in ipairs(account.notifications) do
        if not item.read then
            unread = unread + 1
            if not latest then latest = item end
        end
    end
    local badges = account.badges or {}
    local ring, scan = waitingFor(account)
    return {
        call = ring,
        balance = account.balance,
        unread_notifications = unread,
        unread_messages = badges.messages or 0,
        friend_requests = badges.friend_requests or 0,
        offer = offerFor(account.account_id),
        scan = scan,
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


-- Customs, citizenship, and visa routes -------------------------------------









-- Border Controller routes --------------------------------------------------





-- Proximity Visa. The controller leaves this on and the Bank keeps asking
-- whoever is nearest with a travel document on screen. Accepting runs the
-- ordinary border check, so entry rules, cooldowns and visits are identical
-- to typing the code in by hand.




-- Kiosk codes and a Foxy account ------------------------------------------------
-- Since 9.4 a Foxy account pays in person with Foxy Pay, not by typing a
-- code. A code can still put money into a Foxy account -- a withdrawal is a
-- kiosk handing you cash, which is the opposite of paying -- but it can no
-- longer take money out of one. Paying a kiosk by code is what an account at
-- Revolution or another third-party bank does, and that arrives over the
-- ledger rather than through here.
--
-- Enforced on the Bank rather than in the phone: the screen is gone from the
-- PUMPE either way, and a rule that only exists in the client is a rule that
-- holds until somebody edits the client.
local function checkCodePayable(payment)
    -- A withdrawal is a kiosk handing you money, and a subscription is a
    -- standing arrangement you can see and cancel in Subs. Neither is the
    -- thing Foxy Pay replaced, and neither has a proximity equivalent: a
    -- kiosk offers a basket in person, never a daily billing agreement. So
    -- what is refused here is exactly the one-off purchase.
    need(payment.kind == "withdrawal" or payment.kind == "subscription",
        "FOXY_PAY_ONLY",
        "Foxy accounts pay in person with Foxy Pay. Use a bank app like"
            .. " Revolution to pay a kiosk with its code.")
end

local function paymentPreview(account, code, payment)
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

function actions.PAY_CODE_PREVIEW(payload)
    local account = requireSpender(payload)
    cleanupEphemeral()
    local code = string.upper(util.trim(payload.code))
    local payment = state.active_pay_codes[code]
    need(payment and payment.status == "pending"
        and payment.expires_at > util.nowMs(),
        "BAD_CODE", "Code is invalid or expired")
    checkCodePayable(payment)
    return paymentPreview(account, code, payment)
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
    checkCodePayable(payment)
    return settleCode(account, payment, payload.pin)
end

-- Foxy Pay ------------------------------------------------------------------
-- The same settlement as a typed code, reached a different way: the kiosk
-- picked this account by standing next to it, rather than this account
-- naming a code. That difference is the whole permission -- an offer is
-- addressed, so paying one is not something a client can talk its way into
-- the way it could by typing a code it overheard. Which is why this is a
-- route of its own rather than a flag on the code route: a flag would be
-- the client's word for how it got here.
local function foxyPayable(account, offerId)
    local offer = state.proximity_offers[tostring(offerId or "")]
    need(offer, "NOT_FOUND", "That payment is no longer waiting")
    need(offer.target_account_id == account.account_id
        or offer.claimed_by == account.account_id,
        "NOT_YOURS", "That payment is for somebody else")
    local payment = offer.code and state.active_pay_codes[offer.code]
    need(payment and payment.status == "pending"
        and payment.expires_at > util.nowMs(),
        "BAD_CODE", "That payment has expired")
    return offer, payment
end

function actions.FOXY_PAY_PREVIEW(payload)
    local account = requireSpender(payload)
    cleanupEphemeral()
    local offer, payment = foxyPayable(account, payload.offer_id)
    return paymentPreview(account, offer.code, payment)
end

function actions.FOXY_PAY_CONFIRM(payload)
    local account = requireSpender(payload)
    cleanupEphemeral()
    local offer, payment = foxyPayable(account, payload.offer_id)
    return settleCode(account, payment, payload.pin)
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








-- Proximity ticket scanning. The organiser turns it on at the door and the
-- Bank asks whoever is nearest with a ticket for this event on screen.





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
    -- App subscriptions are charged on the same daily pass as kiosk ones.
    pcall(appstore.chargeSubscriptions, today)
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

-- What the Vault owns ---------------------------------------------------------
-- Listing them here rather than letting anything unknown fall through is
-- deliberate: a typo in a client must still be an unknown action, not a
-- question quietly posted down a cable. Each entry is the rule the Core
-- applies before forwarding -- who is asking, whether they may spend, and
-- whether they had to prove it with a PIN -- so authentication stays on the
-- half that holds the accounts.
--
--   session  someone signed in            pin    also prove it with a PIN
--   spender  ... whose money can move     app    ... signed in to that app
--   device   a Border Controller          account  fold the balance into the
--                                                  reply, which is the Core's
pair.routes = {
    FRIEND_OVERVIEW = { auth = "session" },
    FRIEND_SEARCH = { auth = "session" },
    FRIEND_REQUEST = { auth = "session" },
    FRIEND_RESPOND = { auth = "session" },
    FRIEND_REMOVE = { auth = "session" },
    CHAT_LIST = { auth = "session" },
    CHAT_START = { auth = "session" },
    CHAT_OPEN = { auth = "session" },
    CHAT_SEND = { auth = "session" },
    CHAT_REQUEST_MONEY = { auth = "session" },
    CHAT_SEND_MONEY = { auth = "spender", pin = true },
    -- Session rather than spender: paying the government is never blocked by
    -- owing the government, and the transfer route applies the rest.
    CHAT_PAY_REQUEST = { auth = "session", pin = true },
    CHAT_DECLINE_REQUEST = { auth = "session" },
    URGENT_RING = { auth = "session" },
    URGENT_CALL = { auth = "session", app = "optional" },
    URGENT_ANSWER = { auth = "session" },
    URGENT_STATE = { auth = "session" },
    URGENT_SEND = { auth = "session" },
    URGENT_SAVE = { auth = "session" },
    URGENT_REQUEST_MONEY = { auth = "session" },
    URGENT_SEND_MONEY = { auth = "spender", pin = true },
    URGENT_PAY_REQUEST = { auth = "spender", pin = true },
    URGENT_END = { auth = "session" },
    APP_DATA_PUT = { auth = "session", app = "required" },
    APP_DATA_LIST = { auth = "session", app = "required" },
    APP_DATA_DELETE = { auth = "session", app = "required" },
    APP_DATA_READ = { auth = "session", app = "required" },
    APP_DATA_REACT = { auth = "session", app = "required" },
    SCAN_ACCEPT = { auth = "session" },
    SCAN_DECLINE = { auth = "session" },
    CUSTOMS_OVERVIEW = { auth = "session" },
    CUSTOMS_DETAIL = { auth = "session" },
    CUSTOMS_CREATE_TERRITORY = { auth = "session", pin = true },
    CUSTOMS_ISSUE_CITIZENSHIP = { auth = "session", pin = true },
    CUSTOMS_SET_FREE_ROAM = { auth = "session", pin = true },
    CUSTOMS_REVIEW_APPLICATION = { auth = "session", pin = true },
    VISA_OVERVIEW = { auth = "session" },
    VISA_APPLY = { auth = "spender" },
    BORDER_REGISTER = { auth = "session" },
    BORDER_STATUS = { auth = "device" },
    BORDER_OWNER_PIN = { auth = "device" },
    BORDER_CHECK = { auth = "device" },
    VISA_SCAN = { auth = "device" },
    VISA_SCAN_STATUS = { auth = "device" },
    VISA_SCAN_CANCEL = { auth = "device" },
    LIST_EVENTS = { auth = "session" },
    EVENT_DETAILS = { auth = "session" },
    BUY_TICKETS = { auth = "spender", pin = true },
    MY_TICKETS = { auth = "session" },
    EVENT_DASHBOARD = { auth = "session", account = true },
    CREATE_EVENT = { auth = "session" },
    MY_EVENTS = { auth = "session" },
    ADD_TICKET_TYPE = { auth = "session" },
    VERIFY_TICKET = { auth = "session" },
    MARK_TICKET_USED = { auth = "session" },
    TICKET_SCAN = { auth = "session" },
    TICKET_SCAN_STATUS = { auth = "session" },
    TICKET_SCAN_CANCEL = { auth = "session" },
}

-- Everything the Core checks before a question goes down the cable.
local function routeToVault(action, spec, payload)
    if spec.auth == "device" then
        -- A Border Controller proves itself against the Vault's own register
        -- of them. Nothing here can help: the Core does not hold that list.
        return pair.forward(action, payload, { kind = "device" })
    end
    local account = spec.auth == "spender" and requireSpender(payload)
        or requireSession(payload)
    if spec.pin then
        need(verifyAccount(account, payload.pin), "BAD_PIN", "Incorrect PIN")
    end
    local extra = {}
    if spec.app == "required" then
        local appId = appstore.appId(payload)
        appstore.requireGrant(account, appId)
        extra.app_id = appId
    elseif spec.app == "optional" and payload.app_id then
        local appId = appstore.appId(payload)
        extra.app_id = appId
        extra.app_name = appstore.requireGrant(account, appId).app_name
    end
    -- The PIN stops here. Nothing downstream has any use for it, and a
    -- secret that does not travel cannot be logged on the far side.
    local forwarded = {}
    for key, value in pairs(payload) do
        if key ~= "pin" and key ~= "session_token" then
            forwarded[key] = value
        end
    end
    local result = pair.forward(action, forwarded,
        vaultCaller(account, extra))
    if spec.account and type(result) == "table" then
        result.account = publicAccount(account)
    end
    return result
end

local function route(sender, message)
    if type(message) ~= "table" or message.kind ~= "request"
        or type(message.action) ~= "string" then return end
    local handler = actions[message.action]
    local spec = not handler and pair.routes[message.action] or nil
    if not handler and not spec then
        net.reply(sender, config.protocol, message.request_id, false, nil,
            "Unknown bank action", "UNKNOWN_ACTION")
        return
    end
    local ok, result
    if spec then
        ok, result = pcall(routeToVault, message.action, spec,
            message.payload or {})
    else
        ok, result = pcall(handler, message.payload or {}, sender)
    end
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
        ui.text(target, 2, 12, ui.truncate("VAULT  " .. pair.status(),
            width - 12), pair.statusColor())

        local scene = ui.scene(target)
        local feedY = 14
        ui.text(target, 2, feedY, "ACTIVITY", colors.lightGray)
        local maxFeed = math.max(1, height - feedY - 2)
        for index = 1, math.min(#activity, maxFeed) do
            local item = activity[index]
            ui.text(target, 2, feedY + index,
                item.time .. "  " .. ui.truncate(item.text, width - 10),
                item.color)
        end
        -- A Vault that has been destroyed, or a cable that has been cut,
        -- must not leave the Bank with no way back: the same button that
        -- pairs the first one pairs a replacement.
        scene:button("vault", 2, height, 9, 1,
            pair.paired() and "RE-PAIR" or "PAIR", { background = colors.lime })
        scene:button("save", width - 18, height, 8, 1, "SAVE",
            { background = colors.blue })
        scene:button("stop", width - 9, height, 8, 1, "STOP",
            { background = colors.red })
        local action = scene:wait({ tickRate = 0.5, flash = false })
        blink = not blink
        if action == "vault" then
            pair.repairScreen(target)
        elseif action == "save" then
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
-- Two Bank Servers, one bank. The split is not down the middle and is not
-- about load: it is about what a thing IS. The Core holds anything where
-- being wrong means money is wrong -- balances, sessions, the ledger, tax,
-- escrow. The Vault holds everything that is merely ABOUT an account:
-- conversations, visas and border records, tickets, app records, who is
-- standing near whom. Those are the parts that grew without limit, and
-- moving them is what took this program from 287 KB back under 200 KB, which
-- is the difference between a Bank that can be updated and one that cannot.
--
-- The Vault runs a different program, bank_vault.lua. That is the whole point:
-- before 9.3 both halves ran this file, so the Vault carried 287 KB to use
-- 25 KB of it and the Core saved nothing at all by having a partner.
--
-- Clients never learn any of this. They ask the Core, as they always have,
-- and the Core answers or passes the question down the cable.

function pair.load()
    local saved = util.loadTable(pair.file, {})
    if saved.role == "core" or saved.role == "vault" then
        pair.role = saved.role
        pair.partner = saved.partner
        pair.since = saved.since
        pair.wired = saved.wired
    end
end

function pair.store()
    pcall(util.saveTable, pair.file, {
        role = pair.role, partner = pair.partner, since = pair.since,
        wired = pair.wired,
    })
end

function pair.isVault() return pair.role == "vault" end
function pair.isCore() return pair.role == "core" end
function pair.paired() return pair.partner ~= nil end

-- Wired only, on purpose ------------------------------------------------------
-- Since 9.3 a Vault is not a spare computer holding cold files: it answers
-- part of every session, so the link between the halves is on the path of a
-- player's request rather than beside it. A wireless modem shares the air
-- with every pocket computer on the server and stops existing when the chunk
-- unloads; a cable does neither. So the handshake runs with the wireless
-- modems shut. Whatever answers is on the other end of a physical cable, and
-- that is the whole of the authorisation -- there is no code to type because
-- a code proves nothing the cable has not already proved.

function pair.modemSides()
    local wired, wireless = {}, {}
    local sides = peripheral and peripheral.getNames and peripheral.getNames()
    for _, side in ipairs(sides or {}) do
        if peripheral.getType(side) == "modem" then
            local ok, isWireless = pcall(peripheral.call, side, "isWireless")
            if ok and isWireless then
                wireless[#wireless + 1] = side
            else
                wired[#wired + 1] = side
            end
        end
    end
    return wired, wireless
end

function pair.wireAttached()
    local wired = pair.modemSides()
    return #wired > 0
end

-- Shutting the wireless modems for the length of the handshake, so that
-- being heard at all is proof of a cable.
function pair.wiredOnly()
    local wired, wireless = pair.modemSides()
    if #wired == 0 then return nil end
    for _, side in ipairs(wireless) do
        if rednet.isOpen(side) then rednet.close(side) end
    end
    for _, side in ipairs(wired) do
        if not rednet.isOpen(side) then rednet.open(side) end
    end
    return wired
end

-- Every Bank Server looking for a partner hosts its own computer id, so one
-- lookup returns the whole cable rather than a code someone has to carry
-- between two keyboards.
function pair.beacon()
    local protocol = config.pair_protocol or "PUMPE_PAIR_V1"
    pcall(rednet.unhost, protocol)
    rednet.host(protocol, "BANKPAIR_" .. os.getComputerID())
end

function pair.discover()
    local protocol = config.pair_protocol or "PUMPE_PAIR_V1"
    local mine, peers, seen = os.getComputerID(), {}, {}
    for _, id in ipairs({ rednet.lookup(protocol) }) do
        if type(id) == "number" and id ~= mine and not seen[id] then
            seen[id] = true
            peers[#peers + 1] = id
        end
    end
    table.sort(peers)
    return peers
end

-- What a half answers to its other half. Everything here is reachable only
-- over the pair protocol, and the money actions below are the only way the
-- Vault can ever touch a balance: it asks, the Core decides.
pair.actions = {}

function pair.actions.PAIR_HELLO(payload, sender)
    return {
        computer = os.getComputerID(),
        accounts = mapCount(state.accounts),
        version = config.version,
        pairing = pair.pairing == true,
        role = pair.role,
    }
end

-- Claiming is what pairs them. Whichever side already has accounts stays the
-- Core, so pairing can never strand a live ledger behind a half that does no
-- banking. A tie goes to the server being claimed: it was here first.
function pair.actions.PAIR_CLAIM(payload, sender)
    need(pair.pairing == true, "NOT_PAIRING",
        "That server is not looking for a partner")
    need(pair.role ~= "vault", "ALREADY_VAULT", "That server is already a Vault")
    need(not pair.paired(), "ALREADY_PAIRED", "That server is already paired")
    local mine = mapCount(state.accounts)
    local theirs = math.floor(tonumber(payload.accounts) or 0)
    local iAmCore = mine >= theirs
    pair.role = iAmCore and "core" or "vault"
    pair.partner = sender
    pair.since = util.nowMs()
    pair.wired = true
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

-- Handing the Vault its own program over the cable. The Core already holds
-- every published file for Easy Deployment, so the half that has just been
-- told it is a Vault does not need the internet to become one.
function pair.actions.PAIR_FETCH(payload, sender)
    local path = tostring(payload.path or "")
    need(path == "bank_vault.lua" or path == "config.lua"
        or path:match("^lib/[%w_]+%.lua$") ~= nil,
        "NOT_PAIR_FILE", "That file is not handed out over the pair link")
    -- Role programs are not kept on the Bank's own disk; they are fetched
    -- when somebody installs one. So look locally first and fall back to the
    -- depot's own fetch, which is what makes handing a Vault its program
    -- work on a Bank that has never deployed one before.
    local body = localUpdateBody(path)
    if not body then body = fetchDepotFile(path) end
    need(body, "NO_FILE", "This Bank does not have " .. path)
    return { path = path, body = body, checksum = util.checksum(body) }
end

-- What the Core does on the Vault's behalf ------------------------------------
-- The Vault owns records, never money. When something it owns has to move
-- money -- a ticket bought, a note paid inside a conversation -- it asks
-- here, and the Core does both halves of the move in one step so there is
-- never a moment where the money is in neither account. The move id is what
-- makes a lost reply harmless: asking again with the same id returns the
-- first answer instead of moving the money a second time.
function pair.actions.CORE_MOVE(payload, sender)
    need(sender == pair.partner, "NOT_MY_PARTNER", "Not this Bank's Vault")
    local moveId = tostring(payload.move_id or "")
    need(#moveId > 0, "NO_MOVE_ID", "A move needs an id")
    state.vault_moves = state.vault_moves or {}
    local already = state.vault_moves[moveId]
    if already then return already.result end
    local from = state.accounts[tostring(payload.from or "")]
    local to = state.accounts[tostring(payload.to or "")]
    need(from, "NO_PAYER", "That account is not at this bank")
    need(to, "NO_PAYEE", "That account is not at this bank")
    need(from ~= to, "SELF_MOVE", "That is the same account")
    local amount = validateAmount(payload.amount, config.max_transfer)
    checkAccountActive(from)
    checkBankOpen(from)
    checkNoTaxDemand(from)
    checkAccountActive(to, true)
    if not payload.priced then
        need((from.balance or 0) >= amount, "INSUFFICIENT_FUNDS",
            "There is not enough money in that account")
    end
    local kind = util.safeText(payload.kind or "transfer", 24)
    local description = util.safeText(payload.description or "", 100)
    local result
    if payload.priced then
        -- Money sent between two people, wherever it was typed. It is the
        -- same move as Send Money and has to cost the same: the processing
        -- fee, the daily ceilings and the recipient's alert all live in
        -- performTransfer, and a second implementation of them here is how a
        -- fee quietly stops being charged.
        local quote = performTransfer(from, to.name, amount, description)
        result = {
            from_balance = from.balance, to_balance = to.balance,
            from_name = from.name, to_name = to.name,
            amount = quote.amount, fee = quote.fee, total = quote.total,
        }
    else
        from.balance = util.roundMoney(from.balance - amount)
        to.balance = util.roundMoney((to.balance or 0) + amount)
        transaction(from, kind .. "_out", -amount, to.name, description)
        transaction(to, kind .. "_in", amount, from.name, description)
        result = {
            from_balance = from.balance, to_balance = to.balance,
            from_name = from.name, to_name = to.name,
            amount = amount, fee = 0, total = amount,
        }
    end
    state.vault_moves[moveId] = { result = result, at = util.nowMs() }
    -- The record only has to outlive a retry, not the day.
    for id, entry in pairs(state.vault_moves) do
        if util.nowMs() - (entry.at or 0) > 600000 then
            state.vault_moves[id] = nil
        end
    end
    save()
    return result
end

function pair.actions.CORE_NOTIFY(payload, sender)
    need(sender == pair.partner, "NOT_MY_PARTNER", "Not this Bank's Vault")
    local account = state.accounts[tostring(payload.account_id or "")]
    need(account, "NO_ACCOUNT", "No such account")
    local item = notification(account, payload.title, payload.body,
        payload.kind, type(payload.extra) == "table" and payload.extra or nil)
    save()
    return { notification_id = item.notification_id }
end

-- Unread counts, pushed rather than asked for. ACCOUNT_SUMMARY is the most
-- called action on the network -- every PUMPE polls it -- and it would be a
-- poor trade to put a cable round trip inside it just to colour a badge. So
-- the Vault tells the Core when a count changes and the Core answers
-- summaries out of its own memory.
function pair.actions.CORE_BADGES(payload, sender)
    need(sender == pair.partner, "NOT_MY_PARTNER", "Not this Bank's Vault")
    local account = state.accounts[tostring(payload.account_id or "")]
    need(account, "NO_ACCOUNT", "No such account")
    account.badges = {
        messages = math.max(0, math.floor(tonumber(payload.messages) or 0)),
        friend_requests =
            math.max(0, math.floor(tonumber(payload.friend_requests) or 0)),
        friends = math.max(0, math.floor(tonumber(payload.friends) or 0)),
    }
    return { ok = true }
end

function pair.actions.CORE_ACCOUNT(payload, sender)
    need(sender == pair.partner, "NOT_MY_PARTNER", "Not this Bank's Vault")
    local account
    if payload.account_id ~= nil then
        account = state.accounts[tostring(payload.account_id)]
    elseif payload.name ~= nil then
        account = accountByName(payload.name)
    end
    if not account then return { found = false } end
    return {
        found = true,
        account_id = account.account_id,
        name = account.name,
        gender = account.gender,
        personal_number = account.personal_number,
        balance = account.balance,
        frozen = account.frozen == true,
        banned = account.banned == true,
        approved = account.approved,
        bank_closed = account.bank_closed == true,
    }
end

-- Searching by name stays here because the name index is part of who holds
-- an account, not part of what the Vault records about them.
function pair.actions.CORE_SEARCH(payload, sender)
    need(sender == pair.partner, "NOT_MY_PARTNER", "Not this Bank's Vault")
    local query = util.normalName(util.trim(payload.query or ""))
    need(#query >= 2, "QUERY_TOO_SHORT", "Type at least two characters")
    local exclude = tostring(payload.exclude or "")
    local results = {}
    for normal, accountId in pairs(state.account_names) do
        local other = state.accounts[accountId]
        if accountId ~= exclude and other and not other.banned
            and normal:find(query, 1, true) then
            results[#results + 1] =
                { account_id = accountId, name = other.name }
        end
    end
    table.sort(results, function(a, b) return a.name < b.name end)
    while #results > 12 do table.remove(results) end
    return { results = results }
end

-- Who is standing nearby holding up the right kind of thing. Positions and
-- what a phone is presenting both stay here, because the OS poll already
-- carries them and moving them would put a cable hop inside it. Whether a
-- candidate's ticket or visa is actually valid needs the records, so the
-- Vault decides that from this list.
function pair.actions.CORE_NEAREST(payload, sender)
    need(sender == pair.partner, "NOT_MY_PARTNER", "Not this Bank's Vault")
    local origin = type(payload.origin) == "table" and payload.origin or {}
    local kind = tostring(payload.kind or "")
    local excluded = type(payload.exclude) == "table" and payload.exclude or {}
    local radius = tonumber(config.proximity_pay_radius) or 16
    local found = {}
    for accountId, account in pairs(state.accounts) do
        local held = not excluded[accountId] and not account.banned
            and not account.frozen and scans.presenting(account, kind)
        local position = held and freshPosition(account)
        if position then
            local distance = distanceBetween(origin, position)
            if distance <= radius then
                found[#found + 1] = {
                    account_id = accountId,
                    name = account.name,
                    ref = held.ref,
                    distance = distance,
                }
            end
        end
    end
    table.sort(found, function(a, b) return a.distance < b.distance end)
    return { candidates = found }
end

function pair.actions.CORE_CLEAR_PRESENTING(payload, sender)
    need(sender == pair.partner, "NOT_MY_PARTNER", "Not this Bank's Vault")
    local account = state.accounts[tostring(payload.account_id or "")]
    if account then account.presenting = nil end
    return { ok = true }
end

-- A PIN is never held anywhere but here, so a Vault route that turns on one
-- -- a Border Controller asking its owner to unlock it -- asks this.
function pair.actions.CORE_VERIFY_PIN(payload, sender)
    need(sender == pair.partner, "NOT_MY_PARTNER", "Not this Bank's Vault")
    local account = state.accounts[tostring(payload.account_id or "")]
    return { ok = account ~= nil and verifyAccount(account, payload.pin) }
end

-- Paying a government demand. There is no counterpart account to credit, so
-- it settles like a fine rather than a transfer.
function pair.actions.CORE_GOV_PAY(payload, sender)
    need(sender == pair.partner, "NOT_MY_PARTNER", "Not this Bank's Vault")
    local moveId = tostring(payload.move_id or "")
    need(#moveId > 0, "NO_MOVE_ID", "A payment needs an id")
    state.vault_moves = state.vault_moves or {}
    local already = state.vault_moves[moveId]
    if already then return already.result end
    local account = state.accounts[tostring(payload.account_id or "")]
    need(account, "NO_ACCOUNT", "No such account")
    local amount = validateAmount(payload.amount, config.max_transfer)
    checkAccountActive(account)
    checkBankOpen(account)
    need((account.balance or 0) >= amount, "INSUFFICIENT_FUNDS",
        "Not enough money to pay this")
    account.balance = util.roundMoney(account.balance - amount)
    state.tax_revenue = util.roundMoney((state.tax_revenue or 0) + amount)
    transaction(account, "government", -amount, "Government",
        util.safeText(payload.description or "Government demand", 60))
    local result = { balance = account.balance, amount = amount }
    state.vault_moves[moveId] = { result = result, at = util.nowMs() }
    save()
    return result
end

-- What is waiting on somebody, pushed up rather than polled for. Kept on the
-- account so a restart does not drop a ringing call, and stamped with an
-- expiry so a push that stops arriving cannot leave a phone ringing forever.
function pair.actions.CORE_WAITING(payload, sender)
    need(sender == pair.partner, "NOT_MY_PARTNER", "Not this Bank's Vault")
    local entries = type(payload.entries) == "table" and payload.entries or {}
    for _, account in pairs(state.accounts) do
        if account.waiting then account.waiting = nil end
    end
    local held = 0
    for accountId, entry in pairs(entries) do
        local account = state.accounts[accountId]
        if account and type(entry) == "table" then
            account.waiting = entry
            held = held + 1
        end
    end
    return { held = held }
end

-- Handing over what the Core used to keep ---------------------------------------
-- A Bank upgrading from 9.2 still has every conversation, visa, territory,
-- event and app record in its own state file, because until 9.3 that is
-- where they lived. They are sent one table at a time and each one is
-- acknowledged before the Core lets go of its copy, so an interrupted move
-- leaves the data on the Core rather than nowhere. Running it twice is
-- harmless: what has already gone is no longer here to send.
pair.moving = {
    "territories", "territory_names", "visas", "visa_codes",
    "visa_applications", "visits", "border_controllers",
    "conversations", "direct_conversations",
    "events", "ticket_types", "tickets", "app_data",
}

function pair.migrate()
    if not pair.isCore() or not pair.paired() then return false, "No Vault" end
    local moved, failed = 0, nil
    for _, name in ipairs(pair.moving) do
        local rows = state[name]
        if type(rows) == "table" and next(rows) ~= nil then
            local ok, err = pair.ask("VAULT_MIGRATE",
                { table = name, rows = rows }, 20)
            if ok then
                state[name] = nil
                moved = moved + 1
                logActivity("Handed " .. name .. " to the Vault", colors.lime)
            else
                failed = failed or err
            end
        else
            state[name] = nil
        end
    end

    -- The counters have to go too, or the Vault starts numbering at one and
    -- writes a second CHAT00000001 over somebody's conversation.
    local counters = {}
    for _, key in ipairs({ "territory", "visa", "visa_application", "visit",
        "border", "conversation", "scan", "event", "ticket_type",
        "ticket" }) do
        if state.sequence[key] then
            counters[key] = state.sequence[key]
        end
    end
    if next(counters) ~= nil then
        if pair.ask("VAULT_MIGRATE", { table = "sequence", rows = counters },
            10) then
            for key in pairs(counters) do state.sequence[key] = nil end
            moved = moved + 1
        end
    end

    -- And the parts of an account that were never about money.
    local holders = {}
    for accountId, account in pairs(state.accounts) do
        local fields = {}
        local any = false
        for _, key in ipairs({ "friends", "friend_requests_in",
            "friend_requests_out", "conversation_ids",
            "government_conversation_id" }) do
            if account[key] ~= nil then
                fields[key] = account[key]
                any = true
            end
        end
        if any then
            fields.name = account.name
            holders[accountId] = fields
        end
    end
    if next(holders) ~= nil then
        if pair.ask("VAULT_MIGRATE", { table = "holders", rows = holders },
            20) then
            for accountId in pairs(holders) do
                local account = state.accounts[accountId]
                account.friends = nil
                account.friend_requests_in = nil
                account.friend_requests_out = nil
                account.conversation_ids = nil
                account.government_conversation_id = nil
            end
            moved = moved + 1
        end
    end

    if moved > 0 then
        save()
        logActivity("Handed " .. moved .. " record sets to the Vault",
            colors.lime)
    end
    return failed == nil, failed
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
    if not client then return nil, "No Vault is paired", "NO_VAULT" end
    local data, err, code = client:request(action, payload, timeout or 6)
    pair.online = data ~= nil
    pair.last_error = data and nil or err
    return data, err, code
end

-- Handing a client's request to the half that owns it. The Core has already
-- decided who is asking by the time this runs: the Vault is told an identity,
-- never a session token, so a Vault that is lied to cannot be talked into
-- acting as somebody else.
function pair.forward(action, payload, caller)
    need(pair.paired(), "NO_VAULT",
        "This Bank has no Vault yet. Pair a second Bank Server to use this.")
    local data, err, code = pair.ask("VAULT_CALL", {
        action = action, payload = payload, caller = caller,
    }, 6)
    if data then return data end
    if code then reject(code, err or "The Vault refused that") end
    reject("VAULT_OFFLINE", err or "The Vault is not answering")
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

-- Pairing with the Bank Server at the other end of the cable.
function pair.claim(id)
    id = math.floor(tonumber(id) or 0)
    if id <= 0 then return nil, "That is not a computer id" end
    if id == os.getComputerID() then
        return nil, "That is this server's own id"
    end
    local protocol = config.pair_protocol or "PUMPE_PAIR_V1"
    local client = net.client({ protocol = protocol,
        hostname = "BANKPAIR_" .. id })
    client.serverId = id
    local hello, helloError = client:request("PAIR_HELLO", {}, 4)
    if not hello then
        return nil, helloError or "That computer did not answer"
    end
    if hello.version ~= config.version then
        return nil, "That server is on v" .. tostring(hello.version)
            .. ", this one is on v" .. tostring(config.version)
    end
    local claimed, failed = client:request("PAIR_CLAIM", {
        accounts = mapCount(state.accounts),
    }, 8)
    if not claimed then
        return nil, failed or "That server would not pair"
    end
    pair.role = claimed.their_role
    pair.partner = id
    pair.since = util.nowMs()
    pair.wired = true
    pair.store()
    logActivity("Paired with computer #" .. tostring(id) .. " as "
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
        ledger = ledger,
        pair = pair,
        appstore = appstore,
        -- The dispatcher itself, so a test can reach a Vault route exactly
        -- the way the server loop does rather than through a hand-written
        -- imitation of it. A stub that is more forgiving than the real thing
        -- is how a bug ships.
        routes = pair.routes,
        route_to_vault = routeToVault,
        vault_caller = vaultCaller,
    }
end

-- What the dashboard says about the other half.
function pair.status()
    if pair.isVault() then
        return "THIS IS THE VAULT FOR #" .. tostring(pair.partner)
    end
    if not pair.paired() then
        if pair.wireAttached() then
            return "NONE PAIRED - PRESS PAIR"
        end
        return "NONE PAIRED - NO WIRED MODEM"
    end
    if pair.online == false then
        return "#" .. tostring(pair.partner) .. " NOT ANSWERING"
    end
    if not pair.wireAttached() then
        return "#" .. tostring(pair.partner) .. " - WIRED MODEM GONE"
    end
    return "#" .. tostring(pair.partner) .. " LINKED OVER CABLE"
end

function pair.statusColor()
    if not pair.paired() then return colors.orange end
    if pair.online == false or not pair.wireAttached() then
        return colors.red
    end
    return colors.lime
end

-- Becoming the Vault. The half that loses the coin toss is not running the
-- right program yet, so it takes bank_vault.lua off the cable from the Core
-- -- which already holds every published file for Easy Deployment -- points
-- its startup at it and restarts into it.
function pair.becomeVault(target)
    ui.message(target, "info", "BECOMING THE VAULT",
        "Taking bank_vault.lua from computer #" .. tostring(pair.partner), 1.2)
    local client = net.client({
        protocol = config.pair_protocol or "PUMPE_PAIR_V1",
        hostname = "BANKPAIR_" .. tostring(pair.partner),
    })
    client.serverId = pair.partner
    local file, err = client:request("PAIR_FETCH",
        { path = "bank_vault.lua" }, 12)
    if not file or type(file.body) ~= "string" then
        -- Not fatal, and not worth stranding the computer over: the role is
        -- written anyway and the installer will fetch the program from the
        -- internet on the next boot the way every other role does.
        logActivity("Vault program not on the cable: " .. tostring(err),
            colors.orange)
    else
        util.writeFile(fs.combine(ROOT, "bank_vault.lua"), file.body)
    end
    local ok, startupError = ensureBankStartup(nil, "vault")
    if not ok then
        ui.message(target, "error", "COULD NOT SET STARTUP",
            tostring(startupError), 3)
        return false
    end
    ui.message(target, "success", "PAIRED AS THE VAULT",
        "Restarting into bank_vault.lua", 1.5)
    os.reboot()
    return true
end

-- Finding the other half ------------------------------------------------------
-- One screen, no codes. It shuts the wireless modems, lists the Bank Servers
-- that answer over the cable, and pairs with the one you press. It also
-- answers a claim from the other end, so whichever computer you happen to be
-- standing at is the one you can do this from.
-- Waiting for somebody to run a cable. Nothing can arrive over one that is
-- not there, so this stage listens for nothing and simply asks.
function pair.waitForWire(target, title)
    while true do
        local wired = pair.wiredOnly()
        if wired then return wired end
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, title, "A Bank needs a cable", util.formatClock())
        ui.card(target, 2, 5, width - 2, 7, colors.orange)
        ui.wrappedText(target, 4, 6, "Put a WIRED MODEM on this computer and"
            .. " on the second Bank Server, run networking cable between"
            .. " them, and right-click both modems so they light up.",
            width - 6, 6, colors.white, colors.gray)
        ui.wrappedText(target, 2, 13, "A wireless modem is not enough. The two"
            .. " halves answer parts of the same request, so the link between"
            .. " them has to be as fast and as reliable as the disk.",
            width - 2, 4, colors.lightGray)
        local scene = ui.scene(target)
        scene:button("rescan", 2, height - 2, 16, 2, "CHECK AGAIN",
            { background = colors.lime, foreground = colors.black })
        scene:button("skip", width - 17, height - 2, 16, 2, "BANK ONLY",
            { background = colors.gray })
        local action = scene:wait({ tickRate = 1, flash = false })
        if action == "skip" or action == "__terminate" then return nil end
    end
end

-- Finding the other half ------------------------------------------------------
-- One screen, no codes. The wireless modems are already shut, so everything
-- that answers is on the cable. It also answers a claim from the other end,
-- so whichever computer you happen to be standing at is the one you can do
-- this from.
function pair.findOnWire(target, title)
    local protocol = config.pair_protocol or "PUMPE_PAIR_V1"
    local message, messageColor = nil, colors.lightGray
    local peers = {}
    pair.pairing = true
    pair.beacon()

    local function listen()
        while pair.pairing and not pair.paired() do
            local sender, packet = rednet.receive(protocol, 0.4)
            if sender and type(packet) == "table"
                and packet.kind == "request" then
                local handler = pair.actions[packet.action]
                if handler then
                    local ok, result = pcall(handler, packet.payload or {},
                        sender)
                    net.reply(sender, protocol, packet.request_id, ok,
                        ok and result or nil,
                        (not ok) and (type(result) == "table"
                            and result.message or "Pairing failed") or nil,
                        (not ok) and type(result) == "table"
                            and result.code or nil)
                end
            end
        end
    end

    local function draw()
        local scanAt = 0
        while not pair.paired() do
            if util.nowMs() >= scanAt then
                peers = pair.discover()
                scanAt = util.nowMs() + 2000
            end
            local width, height = target.getSize()
            ui.clear(target)
            ui.header(target, title, "Looking along the cable",
                util.formatClock())
            ui.text(target, 2, 5, "THIS SERVER IS COMPUTER #"
                .. os.getComputerID(), colors.lightGray)
            local scene = ui.scene(target)
            if #peers == 0 then
                ui.card(target, 2, 7, width - 2, 5, colors.orange)
                ui.wrappedText(target, 4, 8, "No other Bank Server is"
                    .. " answering on this cable yet. Start the second one"
                    .. " and leave it on this screen.", width - 6, 3,
                    colors.white, colors.gray)
            else
                ui.text(target, 2, 7, "ON THIS CABLE", colors.lightGray)
                for index = 1, math.min(#peers, 4) do
                    scene:button("peer" .. index, 2, 8 + (index - 1) * 3,
                        width - 3, 2, "PAIR WITH COMPUTER #" .. peers[index],
                        { background = colors.lime,
                          foreground = colors.black })
                end
            end
            if message then
                ui.text(target, 2, height - 3,
                    ui.truncate(message, width - 2), messageColor)
            end
            scene:button("skip", width - 17, height - 1, 16, 2, "BANK ONLY",
                { background = colors.gray })
            local action = scene:wait({ tickRate = 0.5, flash = false })
            if action == "skip" or action == "__terminate" then return end
            local index = tostring(action or ""):match("^peer(%d+)$")
            if index and peers[tonumber(index)] then
                local ok, err = pair.claim(peers[tonumber(index)])
                if not ok then
                    message, messageColor = err, colors.orange
                    peers = pair.discover()
                end
            end
        end
    end

    parallel.waitForAny(listen, draw)
    pair.pairing = false
    pcall(rednet.unhost, protocol)
end

function pair.findScreen(target, title)
    if pair.waitForWire(target, title) then
        pair.findOnWire(target, title)
    end
    -- The wireless modems were shut for the handshake. Everything else on
    -- this network still needs them.
    net.openModems()
    return pair.role
end

-- Pairing a replacement Vault from the dashboard. Forgetting the old one
-- first is what makes this work at all: a Core that still believes it has a
-- partner refuses to be claimed.
function pair.repairScreen(target)
    if pair.isVault() then
        ui.message(target, "info", "THIS IS A VAULT",
            "Re-pair from the Core instead", 2)
        return
    end
    if pair.paired() then
        if not ui.confirm(target, "REPLACE THE VAULT",
            "Forget computer #" .. tostring(pair.partner)
                .. " and pair another? Records already on it stay there.",
            "REPLACE", "BACK") then
            return
        end
        pair.partner = nil
        pair.since = nil
        pair.role = "solo"
        pair.store()
        logActivity("Vault forgotten, looking for another", colors.orange)
    end
    pair.findScreen(target, "PAIR A VAULT")
    pair.store()
    if pair.isVault() then pair.becomeVault(target) end
end

ui.boot(term.current(), "PUMPE BANK", "SECURE ECONOMY CORE")

-- Looking for the other half, asked once. A Bank that has already answered --
-- paired, or told to bank on its own -- comes straight up the way it was
-- left, and the dashboard's PAIR button is how it is asked again.
pair.load()
if not pair.paired() and not fs.exists(pair.file) then
    pair.findScreen(term.current(), "SET UP THIS BANK")
    pair.store()
end

-- The half that was made the Vault is not running the right program yet.
if pair.isVault() then pair.becomeVault(term.current()) end

net.openModems()
if pair.isVault() then
    -- Reached only when becomeVault could not write a startup, so this
    -- computer is a Vault running the Core's program. It must not bank --
    -- two halves answering as the Bank is how a ledger gets two truths --
    -- so it serves downloads and says what is wrong until it is fixed.
    rednet.host(config.pair_protocol or "PUMPE_PAIR_V1",
        config.pair_hostname or "BANK_VAULT")
    logActivity("VAULT WITHOUT ITS PROGRAM - reinstall this computer",
        colors.red)
else
    net.host(config.protocol, config.hostname)
    -- Easy Deployment stays here, on the half that is always present.
    -- Through 9.2 the Vault held it, on the reasoning that a Vault was idle
    -- and the Core was not. Both halves of that reasoning died in 9.3: the
    -- Vault now answers player requests, so file transfers would land on a
    -- hot path rather than beside one, and -- worse -- a Vault that holds
    -- the installer is a Vault you cannot reinstall once it breaks. The
    -- Core serving a download between balance checks costs a few ticks;
    -- that deadlock costs the bank.
    rednet.host(DEPLOY.protocol, DEPLOY.hostname)
    if pair.isCore() then
        logActivity("Core online, Vault is computer #"
            .. tostring(pair.partner), colors.lime)
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
-- A Bank arriving from 9.2 is still holding the Vault's records. Cheap and
-- silent once there is nothing left to hand over, so it runs every boot
-- rather than behind a flag that could be wrong.
if pair.isCore() and pair.paired() then
    local handed, handError = pair.migrate()
    if not handed then
        logActivity("Vault handover incomplete: " .. tostring(handError),
            colors.orange)
    end
end
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
