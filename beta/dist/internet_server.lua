local ROOT = fs.getDir(shell.getRunningProgram())
if ROOT == "" then ROOT = "." end
package.path = package.path .. ";" .. fs.combine(ROOT, "?.lua")
    .. ";" .. fs.combine(ROOT, "?/init.lua")

-- PUMPE INTERNET SERVER AND TERMINAL
--
-- The web, new in 10.0. This machine holds the pages; it does not hold the
-- names. Who owns a domain, and when that domain starts answering, lives in
-- the Bank Vault -- so a name means the same thing to everybody on the
-- network and survives this computer being broken, rebuilt or replaced.
--
-- That split is also what keeps this machine from having to be trusted. It
-- never sees an account and never checks a PIN. A PUMPE that wants to
-- publish fetches a one-shot ticket from the Bank for a domain it owns and
-- hands it over; this server takes the ticket back to the Bank and is told
-- whose site it is. Anyone can lie to an Internet Server about who they are;
-- nobody can produce a ticket for a domain they do not own.

-- Stamped by tools/build_release_manifest.js. A program running beside a
-- config.lua from a different release means a partial install.
local PROGRAM_VERSION = "15.5.1"
local config = require("config")
local util = require("lib.util")
local net = require("lib.net")
local ui = require("lib.ui")

local PROTOCOL = config.web_protocol or "PUMPE_WEB_V1"
local HOSTNAME = config.web_hostname or "INTERNET_SERVER"
local MAX_BYTES = tonumber(config.max_web_bytes) or 8 * 1024
local MAX_SITES = tonumber(config.max_web_sites) or 200

local target = term.current()
local bank = net.client(config)
local running = true
local dataFile = fs.combine(ROOT, "internet_server_v1.dat")
local activity = {}

local function logActivity(text, color)
    table.insert(activity, 1, {
        text = util.safeText(text, 42),
        color = color or colors.lightGray,
        time = util.formatClock(),
    })
    while #activity > 16 do table.remove(activity) end
end

local state = util.loadTable(dataFile, { sites = {}, order = {}, visits = 0 })
state.sites = state.sites or {}
state.order = state.order or {}
state.visits = state.visits or 0

local function save() pcall(util.saveTable, dataFile, state) end

local function reject(code, message)
    error({ pumpe = true, code = code, message = message }, 0)
end

local function need(condition, code, message)
    if not condition then reject(code, message) end
end

local function domainKey(value)
    return string.lower(util.trim(tostring(value or "")))
end

-- The same shape the Vault accepts. Checked here too, because a server that
-- only validates what it is told by the thing it is validating is not
-- validating anything.
local function validDomain(value)
    local key = domainKey(value)
    if #key < 3 or #key > 20 then return nil end
    if not key:match("^[%a%d%-]+$") then return nil end
    if key:sub(1, 1) == "-" or key:sub(-1) == "-" then return nil end
    return key
end

-- Asking the Bank. Everything this server is not allowed to decide for
-- itself is decided here instead.
local function askBank(action, payload)
    local result, err, code = bank:request(action, payload or {}, 6)
    if result then return result end
    return nil, err or "The Bank did not answer", code
end

-- Checking a website before it goes on the web. Compiling it here is the
-- one place that can: a PUMPE app has no `load` of its own, and a page that
-- does not parse would otherwise fail on every reader's phone instead of on
-- its author's.
local function compile(source)
    need(type(source) == "string", "NO_SOURCE", "A website is a program now")
    need(#source > 0, "NO_SOURCE", "There is nothing to publish")
    need(#source <= MAX_BYTES, "TOO_BIG",
        "A website is at most " .. math.floor(MAX_BYTES / 1024) .. " KB")
    local built, err = load(source, "website", "t", {})
    need(built, "BAD_SOURCE", tostring(err or "That does not parse"))
    return source
end

local actions = {}

function actions.WEB_INFO()
    return {
        version = config.version,
        computer_id = os.getComputerID(),
        sites = #state.order,
        visits = state.visits,
        max_bytes = MAX_BYTES,
    }
end

-- Offered so Website Crafter can say what is wrong with a website before
-- anybody publishes it, rather than after.
function actions.WEB_CHECK(payload)
    local ok, err = pcall(compile, payload.source)
    if ok then return { ok = true, bytes = #tostring(payload.source) } end
    if type(err) == "table" and err.pumpe then
        return { ok = false, error = err.message, code = err.code }
    end
    return { ok = false, error = tostring(err) }
end

-- Publishing. The ticket is what proves this is the owner's site; the Bank
-- burns it on the way past, so a ticket somebody copied is worth one publish
-- and only until the owner's next one.
function actions.WEB_PUBLISH(payload)
    local key = validDomain(payload.domain)
    need(key, "BAD_DOMAIN", "A domain is 3-20 letters, numbers or dashes")
    local source = compile(payload.source)

    local claim, err, code = askBank("WEB_CLAIM",
        { domain = key, token = tostring(payload.token or "") })
    if not claim then
        need(false, code or "BANK_UNREACHABLE", err)
    end
    -- Filed under the site the Bank minted, not under the name it currently
    -- answers to. Renaming a domain then moves the site instead of orphaning
    -- its pages under the old name -- where, once somebody else reserved
    -- that name, this server would have served them one owner's pages under
    -- another owner's domain.
    local siteId = tostring(claim.site_id or key)
    local existing = state.sites[siteId]
    if not existing then
        need(#state.order < MAX_SITES, "SERVER_FULL",
            "This Internet Server is full")
        state.order[#state.order + 1] = siteId
    end
    state.sites[siteId] = {
        site_id = siteId,
        domain = key,
        owner_name = claim.owner_name,
        source = source,
        bytes = #source,
        updated_day = util.ingameDay(),
        revision = (existing and existing.revision or 0) + 1,
    }
    save()
    logActivity(key .. " published by " .. tostring(claim.owner_name),
        colors.lime)
    return { domain = key, bytes = #source,
        revision = state.sites[siteId].revision }
end

-- Taking a site down. The same ticket, because taking somebody's website off
-- the web is at least as serious as putting one on it.
function actions.WEB_UNPUBLISH(payload)
    local key = validDomain(payload.domain)
    need(key, "BAD_DOMAIN", "A domain is 3-20 letters, numbers or dashes")
    local claim, err, code = askBank("WEB_CLAIM",
        { domain = key, token = tostring(payload.token or "") })
    if not claim then need(false, code or "BANK_UNREACHABLE", err) end
    local siteId = tostring(claim.site_id or key)
    state.sites[siteId] = nil
    for index = #state.order, 1, -1 do
        if state.order[index] == siteId then
            table.remove(state.order, index)
        end
    end
    save()
    logActivity(key .. " taken down", colors.orange)
    return { domain = key, removed = true }
end

-- Reading a site. The Bank decides whether it is live; this server only
-- decides what is on it. A domain that is reserved but has not come up yet
-- says so, because "not found" would read as a mistake by the visitor.
function actions.WEB_SITE(payload)
    local key = validDomain(payload.domain)
    need(key, "BAD_DOMAIN", "A domain is 3-20 letters, numbers or dashes")
    local found, err, code = askBank("WEB_LOOKUP", { domain = key })
    if not found then
        need(false, code or "BANK_UNREACHABLE", err)
    end
    local site = found.site_id and state.sites[tostring(found.site_id)] or nil
    if not found.live or not site then
        return {
            domain = key,
            owner_name = found.owner_name,
            preparing = true,
            hours_left = found.hours_left,
        }
    end
    -- The name may have changed since it was published. The pages did not.
    if site.domain ~= key then
        site.domain = key
        save()
    end
    -- Published before 10.1, when a website was a page of text rather than
    -- a program. Say so: the owner has to publish it again, and a reader
    -- being told that is better than a reader being shown nothing.
    if type(site.source) ~= "string" then
        return { domain = key, owner_name = site.owner_name,
            needs_update = true }
    end
    state.visits = state.visits + 1
    return {
        domain = key,
        owner_name = site.owner_name,
        source = site.source,
        bytes = site.bytes or #site.source,
        updated_day = site.updated_day,
        revision = site.revision,
    }
end

-- There is no directory. Up to 10.1 the Internet app opened on a list of
-- every site on the server, which is a phone book nobody asked for and a
-- front page belonging to whoever published first. You type a domain, the
-- way you would say one out loud.

local function route(sender, message)
    if type(message) ~= "table" or message.kind ~= "request"
        or type(message.action) ~= "string" then return end
    local handler = actions[message.action]
    if not handler then
        net.reply(sender, PROTOCOL, message.request_id, false, nil,
            "Unknown web action", "UNKNOWN_ACTION")
        return
    end
    local ok, result = pcall(handler, message.payload or {})
    if ok then
        net.reply(sender, PROTOCOL, message.request_id, true, result)
    elseif type(result) == "table" and result.pumpe then
        net.reply(sender, PROTOCOL, message.request_id, false, nil,
            result.message, result.code)
    else
        logActivity("Server error: " .. tostring(result), colors.red)
        net.reply(sender, PROTOCOL, message.request_id, false, nil,
            "Internal web error", "SERVER_ERROR")
    end
end

local function serverLoop()
    while running do
        local sender, message = rednet.receive(PROTOCOL, 2)
        if sender then route(sender, message) end
    end
end

local function updateLoop()
    while running do
        net.autoUpdate(config, "internet", ROOT, nil,
            { programVersion = PROGRAM_VERSION })
        sleep(10)
    end
end

-- The Terminal. What this machine is holding, and who has been reading it.
-- 12.0: Status, Activity and Server tabs, as on every server.
local function dashboardLoop()
    ui.serverTabs({
        version = config.version,
        target = target, title = "INTERNET SERVER",
        subtitle = "#" .. os.getComputerID() .. "  v" .. config.version,
        cards = function()
            return { { "SITES", #state.order, ui.theme.accent },
                { "PAGES READ", state.visits, ui.theme.success } }
        end,
        lines = function()
            local lines = { { "HOSTED", ui.theme.muted } }
            for _, key in ipairs(state.order) do
                local site = state.sites[key]
                if site then
                    lines[#lines + 1] = { site.domain .. "  by " .. tostring(site.owner_name) }
                end
            end
            if #state.order == 0 then
                lines[#lines + 1] = { "Nothing published yet. Websites are written in",
                    ui.theme.muted }
                lines[#lines + 1] = { "Website Crafter on a Pocket.", ui.theme.muted }
            end
            return lines
        end,
        activity = activity, root = ROOT, colorTitle = "Server colour",
        actions = { { id = "stop", label = "STOP", hint = "Every site here goes off the web",
            color = ui.theme.danger, run = function()
                if ui.confirm(target, "STOP INTERNET SERVER",
                    "Every website on this machine goes off the web.", "STOP", "BACK") then
                    running = false
                    save()
                    return true
                end
            end } },
        running = function() return running end,
    })
end

if rawget(_G, "PUMPE_TEST_MODE") == true then
    return { actions = actions, state = state }
end

-- 12.0: this server's main colour, orange unless its owner chose one.
if type(ui.useMainColor) == "function" then ui.useMainColor(ROOT) end
ui.boot(target, "INTERNET SERVER", (ui.osLabel and ui.osLabel(config) or "FoxyOS"))
net.autoUpdate(config, "internet", ROOT, nil,
    { force = true, programVersion = PROGRAM_VERSION })
net.host(PROTOCOL, HOSTNAME)
bank:discover()
logActivity("Internet Server online on #" .. os.getComputerID(), colors.lime)
save()

parallel.waitForAny(serverLoop, updateLoop, dashboardLoop)
pcall(rednet.unhost, PROTOCOL)
ui.clear(target)
print("Internet Server stopped.")
