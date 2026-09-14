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
local PROGRAM_VERSION = "10.0.0"
local config = require("config")
local util = require("lib.util")
local net = require("lib.net")
local ui = require("lib.ui")

local PROTOCOL = config.web_protocol or "PUMPE_WEB_V1"
local HOSTNAME = config.web_hostname or "INTERNET_SERVER"
local MAX_PAGES = tonumber(config.max_web_pages) or 3
local MAX_BLOCKS = tonumber(config.max_web_blocks) or 14
local MAX_TEXT = tonumber(config.max_web_text) or 240
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
    while #activity > 8 do table.remove(activity) end
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

-- Reading a page a PUMPE sent. Anything that is not a title or a line of
-- text is dropped rather than stored: this is a website, not a filesystem.
local function readPage(raw, index)
    need(type(raw) == "table", "BAD_PAGE", "Page " .. index .. " is not a page")
    local title = util.safeText(util.trim(tostring(raw.title or "")), 40)
    need(#title > 0, "BAD_PAGE", "Page " .. index .. " has no title")
    local blocks = {}
    for _, block in ipairs(type(raw.blocks) == "table" and raw.blocks or {}) do
        if #blocks >= MAX_BLOCKS then break end
        if type(block) == "table" then
            local kind = block.kind == "title" and "title" or "text"
            local text = util.safeText(util.trim(tostring(block.text or "")),
                kind == "title" and 40 or MAX_TEXT)
            if #text > 0 then
                blocks[#blocks + 1] = { kind = kind, text = text }
            end
        end
    end
    return { title = title, blocks = blocks }
end

local actions = {}

function actions.WEB_INFO()
    return {
        version = config.version,
        computer_id = os.getComputerID(),
        sites = #state.order,
        visits = state.visits,
        max_pages = MAX_PAGES,
        max_blocks = MAX_BLOCKS,
        max_text = MAX_TEXT,
    }
end

-- Publishing. The ticket is what proves this is the owner's site; the Bank
-- burns it on the way past, so a ticket somebody copied is worth one publish
-- and only until the owner's next one.
function actions.WEB_PUBLISH(payload)
    local key = validDomain(payload.domain)
    need(key, "BAD_DOMAIN", "A domain is 3-20 letters, numbers or dashes")
    local pages = type(payload.pages) == "table" and payload.pages or {}
    need(#pages >= 1, "NO_PAGES", "A website needs at least a main page")
    need(#pages <= MAX_PAGES, "TOO_MANY_PAGES",
        "A website is a main page and up to " .. (MAX_PAGES - 1) .. " more")

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
    local stored = {}
    for index, raw in ipairs(pages) do stored[index] = readPage(raw, index) end
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
        pages = stored,
        updated_day = util.ingameDay(),
        revision = (existing and existing.revision or 0) + 1,
    }
    save()
    logActivity(key .. " published by " .. tostring(claim.owner_name),
        colors.lime)
    return { domain = key, pages = #stored,
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
    state.visits = state.visits + 1
    local wanted = math.max(1, math.min(tonumber(payload.page) or 1,
        #site.pages))
    local names = {}
    for index, page in ipairs(site.pages) do names[index] = page.title end
    return {
        domain = key,
        owner_name = site.owner_name,
        page = wanted,
        pages = names,
        title = site.pages[wanted].title,
        blocks = site.pages[wanted].blocks,
        updated_day = site.updated_day,
        revision = site.revision,
    }
end

-- Everything this server is holding, so the Internet app has somewhere to
-- start rather than an empty box and a blinking cursor.
function actions.WEB_DIRECTORY(payload)
    local listed, skip = {}, math.max(0, tonumber(payload.offset) or 0)
    for index = skip + 1, math.min(#state.order, skip + 12) do
        local site = state.sites[state.order[index]]
        -- The domain here is the last one this site was read or published
        -- under. A rename nobody has visited yet still lists the old name;
        -- opening it corrects both.
        if site then
            listed[#listed + 1] = {
                domain = site.domain,
                owner_name = site.owner_name,
                title = site.pages[1] and site.pages[1].title or site.domain,
                updated_day = site.updated_day,
            }
        end
    end
    return { sites = listed, total = #state.order,
        next_offset = skip + #listed }
end

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
local function dashboardLoop()
    local blink = true
    while running do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "PUMPE INTERNET", "#" .. os.getComputerID()
            .. "  v" .. config.version, util.formatClock(blink))
        local cardWidth = math.floor((width - 3) / 2)
        ui.card(target, 2, 5, cardWidth, 4, ui.theme.accent)
        ui.text(target, 4, 6, "SITES", ui.theme.muted, ui.theme.panel)
        ui.text(target, 4, 7, tostring(#state.order), ui.theme.ink,
            ui.theme.panel, cardWidth - 3)
        ui.card(target, 3 + cardWidth, 5, width - cardWidth - 3, 4,
            ui.theme.success)
        ui.text(target, 5 + cardWidth, 6, "PAGES READ", ui.theme.muted,
            ui.theme.panel)
        ui.text(target, 5 + cardWidth, 7, tostring(state.visits),
            ui.theme.ink, ui.theme.panel, width - cardWidth - 6)

        ui.text(target, 2, 10, "HOSTED", ui.theme.muted)
        local row = 11
        for _, key in ipairs(state.order) do
            local site = state.sites[key]
            if site and row <= height - 6 then
                ui.text(target, 2, row,
                    ui.truncate(site.domain .. "  by "
                        .. tostring(site.owner_name), width - 3), ui.theme.ink)
                row = row + 1
            end
        end
        if #state.order == 0 then
            ui.text(target, 2, 11, "Nothing published yet", ui.theme.muted)
            ui.wrappedText(target, 2, 13, "Websites are written in Website"
                .. " Crafter on a PUMPE and published here.", width - 3, 3,
                ui.theme.muted)
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
            if ui.confirm(target, "STOP INTERNET SERVER",
                "Every website on this machine goes off the web.",
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

ui.boot(target, "PUMPE INTERNET", "INTERNET SERVER v" .. config.version)
net.autoUpdate(config, "internet", ROOT, nil,
    { force = true, programVersion = PROGRAM_VERSION })
net.host(PROTOCOL, HOSTNAME)
bank:discover()
logActivity("Internet Server online on #" .. os.getComputerID(), colors.lime)
save()

parallel.waitForAny(serverLoop, updateLoop, dashboardLoop)
pcall(rednet.unhost, PROTOCOL)
ui.clear(target)
print("PUMPE Internet Server stopped.")
