-- PUMPE EASY DEPLOYMENT
-- This file is intentionally standalone. Everything it installs comes
-- straight from the published release on GitHub.
--
-- 12.0 rebuilt it as a downloader. The PUMPE has the first screen to itself;
-- the down arrow (or simply typing) opens a search of every program, and
-- each one downloads its own files over HTTPS, checked against the release
-- manifest. Nothing is fetched from a Bank Server any more. That is what
-- went wrong in 11.2: a Bank handed every device its copy of this file, and
-- a Bank whose own program sat in that copy's place turned every device it
-- set up into a Bank, whatever was picked.
--
-- A computer boots through its installed copy, which /startup.lua names:
--   installer.lua --boot <program>   update if the release is newer, then start
--   installer.lua --auto <program>   update if the release is newer (lib/net)

local INSTALLER_VERSION = "11.9.1"
local MANIFEST_URL =
    "https://raw.githubusercontent.com/totallyrat/computercraftbank/main/release_manifest.json"
local INSTALL_ROOT = "/pumpe"
local PROTECTED_CODE = "4040"
local HEADER = "-- PUMPE EASY DEPLOYMENT"
local ROLE_MARKER = "-- PUMPE ROLE STARTUP"
local arguments = { ... }
local mode = arguments[1]
local modeProgram = string.lower(tostring(arguments[2] or ""))

-- Where this copy lives. /startup.lua names it, so this is where a computer's
-- programs are: /pumpe on everything Easy Deployment set up, and wherever a
-- Bank built by hand keeps its files. Booting never assumes /pumpe, which is
-- what lets a hand-built Bank update itself and still start.
local function homeDir()
    if type(shell) ~= "table" or type(shell.getRunningProgram) ~= "function" then
        return INSTALL_ROOT
    end
    return fs.getDir(shell.getRunningProgram() or "")
end

-- A Delivery Terminal in Pickup mode faces the public and leaves this file
-- behind. Booting with it, Ctrl+T is ignored from the first moment, before
-- anything below waits on the network: a customer who reboots the counter
-- comes back to the counter, not to a shell beside every locker. Only a
-- Delivery Terminal: a lock another program finds is a leftover.
local function keyboardLocked()
    return mode == "--boot" and modeProgram == "delivery"
        and (fs.exists(fs.combine(homeDir(), "keyboard.lock"))
            or fs.exists(fs.combine(INSTALL_ROOT, "keyboard.lock")))
end
if keyboardLocked() then os.pullEvent = os.pullEventRaw end

-- Every program there is. `words` is what search also looks at, so a kiosk
-- turns up for "shop" and the CCG console for "casino". `code` asks for the
-- operator's code first. `extra` files come with the program.
local PROGRAMS = {
    { id = "pumpe", name = "Personal PUMPE", file = "pumpe.lua",
      detail = "The phone: money, friends, apps",
      about = "Money, friends, tickets and travel papers, all in one pocket computer.",
      words = "phone pocket foxy money wallet apps" },
    { id = "service", name = "Service Kiosk", file = "service_kiosk.lua",
      detail = "A shop's checkout",
      about = "A shop's till: sell, take Foxy Pay, run an online store.",
      words = "shop store till pos checkout sell pay" },
    { id = "delivery", name = "Delivery Terminal", file = "delivery_terminal.lua",
      detail = "Orders and pickup points",
      about = "Packs a shop's orders, or runs a pickup point with lockers.",
      words = "warehouse parcel locker pickup courier orders" },
    { id = "event", name = "Event Kiosk", file = "event_kiosk.lua",
      detail = "Tickets and the door",
      about = "Sells tickets and checks them at the door.",
      words = "tickets door concert show" },
    { id = "border", name = "Border Controller", file = "border_controller.lua",
      detail = "The visa gate",
      about = "Checks visas and opens the gate.",
      words = "visa passport gate travel territory" },
    { id = "bank", name = "Bank Server", file = "bank_server.lua", code = true,
      detail = "Foxy: the economy itself",
      about = "Foxy's Bank Core: every balance in the world. Needs the operator's code.",
      words = "foxy core server money economy" },
    -- Its Core updates it over the cable, to exactly the release the Core
    -- runs, so booting never updates it from the internet: a Vault ahead of
    -- its Core would be answering another release's questions.
    { id = "vault", name = "Bank Vault", file = "bank_vault.lua", byCore = true,
      detail = "The other half of a Bank",
      about = "Holds history, chats, shops and mail for a Bank. Cable it to the Bank.",
      words = "vault records server pair cable" },
    { id = "tpbank", name = "3rd Party Bank Server", file = "bank_app_server.lua",
      detail = "Hosts somebody's own bank",
      about = "Runs a bank of your own, with its own app on every PUMPE.",
      words = "third party bank app server" },
    { id = "admin", name = "Admin Terminal", file = "admin_terminal.lua", code = true,
      detail = "For the government",
      about = "Taxes, territories and the government's tools. Needs the operator's code.",
      words = "government tax admin" },
    { id = "ccg", name = "CCG Bet Console", file = "ccg.lua",
      detail = "ComputerCraftGaming",
      about = "Heads or tails and the rest, with a Bet Wallet.",
      words = "casino bet game gaming gamble" },
    { id = "ccgserver", name = "CCG Server", file = "ccg_server.lua",
      detail = "Runs the games",
      about = "The server the CCG consoles play against.",
      words = "casino bet game server" },
    { id = "anchor", name = "GPS Anchor", file = "gps_anchor.lua",
      detail = "A positioning beacon",
      about = "One of the four beacons that tell a PUMPE where it is.",
      words = "gps location position beacon" },
    { id = "apps", name = "App Server", file = "app_server.lua",
      detail = "Hosts the App Browser",
      about = "Serves the apps every PUMPE can download.",
      words = "apps store browser server",
      extra = { "foxy.lua", "buckapp.lua", "revolution.lua", "wc.lua",
          "internet.lua", "shop.lua", "foxmail.lua", "company.lua" } },
    { id = "internet", name = "Internet Server", file = "internet_server.lua",
      detail = "Hosts the web",
      about = "Serves the websites and domains of the web.",
      words = "web website internet domain server" },
    -- Retired in 7.1. Still bootable so an installed Tax Controller can say
    -- so instead of failing with an unknown program.
    { id = "tax", name = "Tax Controller", file = "tax_controller.lua",
      detail = "Retired", about = "Retired.", hidden = true },
}

-- What every program comes with. startup.lua is this file; it is installed
-- as installer.lua beside the program.
local COMMON_FILES = { "startup.lua", "config.lua", "lib/net.lua", "lib/ui.lua",
    "lib/update.lua", "lib/util.lua" }

local function programById(id)
    for _, program in ipairs(PROGRAMS) do
        if program.id == id then return program end
    end
    return nil
end

local function filesFor(program)
    local paths = { program.file }
    for _, path in ipairs(COMMON_FILES) do paths[#paths + 1] = path end
    for _, path in ipairs(program.extra or {}) do paths[#paths + 1] = path end
    return paths
end

local function installPath(path)
    return path == "startup.lua" and "installer.lua" or path
end

-- Drawing --------------------------------------------------------------------

local target = term.current()
-- 12.0: orange, like the fox and like every PUMPE device out of the box.
local theme = {
    background = colors.black, panel = colors.gray, panelAlt = colors.lightGray,
    ink = colors.white, muted = colors.lightGray, accent = colors.orange,
    accentDark = colors.brown, success = colors.lime, warning = colors.yellow,
    danger = colors.red,
}

local function clear()
    target.setBackgroundColor(theme.background)
    target.setTextColor(theme.ink)
    target.clear()
    target.setCursorPos(1, 1)
end

local function fill(x, y, width, height, background)
    local screenWidth, screenHeight = target.getSize()
    width = math.max(0, math.min(width, screenWidth - x + 1))
    height = math.max(0, math.min(height, screenHeight - y + 1))
    if width <= 0 or height <= 0 then return end
    target.setBackgroundColor(background)
    local line = string.rep(" ", width)
    for row = y, y + height - 1 do
        if row >= 1 then
            target.setCursorPos(x, row)
            target.write(line)
        end
    end
end

local function writeAt(x, y, value, foreground, background)
    local screenWidth, screenHeight = target.getSize()
    if x < 1 or x > screenWidth or y < 1 or y > screenHeight then return end
    value = tostring(value or ""):sub(1, screenWidth - x + 1)
    if background then target.setBackgroundColor(background) end
    target.setTextColor(foreground or theme.ink)
    target.setCursorPos(x, y)
    target.write(value)
end

local function truncate(value, width)
    value = tostring(value or "")
    if #value <= width then return value end
    if width <= 2 then return value:sub(1, math.max(0, width)) end
    return value:sub(1, width - 2) .. ".."
end

local function center(y, value, foreground, background)
    local width = target.getSize()
    value = truncate(value, width - 2)
    writeAt(math.floor((width - #value) / 2) + 1, y, value, foreground, background)
end

local function wrapText(value, width)
    local lines, line = {}, ""
    for word in tostring(value or ""):gmatch("%S+") do
        local candidate = line == "" and word or (line .. " " .. word)
        if #candidate <= width then
            line = candidate
        else
            if line ~= "" then lines[#lines + 1] = line end
            line = truncate(word, width)
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return lines
end

-- A 3x5 block face, so the PUMPE's screen has a title you can read across
-- the room. False when the screen cannot hold it.
local BIG_GLYPHS = {
    P = { "###", "# #", "###", "#  ", "#  " },
    U = { "# #", "# #", "# #", "# #", "###" },
    M = { "# #", "###", "###", "# #", "# #" },
    E = { "###", "#  ", "###", "#  ", "###" },
}

local function wordmark(y, word, color)
    local width, height = target.getSize()
    local span = #word * 4 - 1
    if span > width or y + 4 > height or height < 16 then return false end
    local left = math.floor((width - span) / 2) + 1
    for index = 1, #word do
        local glyph = BIG_GLYPHS[word:sub(index, index)]
        for row = 1, 5 do
            for column = 1, 3 do
                if glyph[row]:sub(column, column) == "#" then
                    fill(left + (index - 1) * 4 + column - 1, y + row - 1, 1, 1,
                        color)
                end
            end
        end
    end
    return true
end

local function header(title, subtitle)
    local width = target.getSize()
    fill(1, 1, width, 3, theme.panel)
    writeAt(2, 1, truncate(title, width - 3), theme.ink, theme.panel)
    writeAt(2, 2, truncate(subtitle or "", width - 3), theme.muted, theme.panel)
    fill(1, 3, width, 1, theme.accent)
end

local function button(buttons, id, x, y, width, height, label, background, foreground)
    fill(x, y, width, height, background or theme.panel)
    local lines = {}
    for line in tostring(label):gmatch("[^\n]+") do lines[#lines + 1] = line end
    local firstY = y + math.floor((height - #lines) / 2)
    for index, line in ipairs(lines) do
        line = truncate(line, width - 2)
        writeAt(x + math.max(0, math.floor((width - #line) / 2)), firstY + index - 1,
            line, foreground or theme.ink, background or theme.panel)
    end
    buttons[#buttons + 1] = { id = id, x1 = x, y1 = y,
        x2 = x + width - 1, y2 = y + height - 1 }
end

-- Waits for a tap on a button or a bound key. `typed`, when given, is what
-- any other printable character means; it comes back with the character.
local function waitForButton(buttons, bindings, typed)
    bindings = bindings or {}
    while true do
        local event = { os.pullEvent() }
        if event[1] == "mouse_click" or event[1] == "monitor_touch" then
            local x, y = event[3], event[4]
            for index = #buttons, 1, -1 do
                local item = buttons[index]
                if x >= item.x1 and x <= item.x2 and y >= item.y1 and y <= item.y2 then
                    return item.id
                end
            end
        elseif event[1] == "key" and bindings[event[2]] then
            return bindings[event[2]]
        elseif event[1] == "char" then
            if bindings[event[2]] then return bindings[event[2]] end
            if typed then return typed, event[2] end
        elseif event[1] == "terminate" then
            return "__terminate"
        end
    end
end

local function message(kind, title, body, duration)
    local width, height = target.getSize()
    local color = kind == "success" and theme.success
        or kind == "error" and theme.danger or theme.warning
    clear()
    local y = math.max(2, math.floor(height / 2) - 3)
    fill(math.floor(width / 2) - 2, y, 5, 3, color)
    center(y + 1, kind == "success" and "OK" or "!", colors.black, color)
    center(y + 4, title, color)
    local lines = wrapText(body or "", width - 4)
    for index = 1, math.min(#lines, 3) do center(y + 5 + index, lines[index], theme.muted) end
    sleep(duration or 1.4)
end

local function enterKey(key)
    return type(keys) == "table" and (key == keys.enter or key == keys.numPadEnter)
end

-- Files ------------------------------------------------------------------------

local function readFile(path)
    local handle = fs.open(path, "r")
    if not handle then return nil end
    local body = handle.readAll()
    handle.close()
    return body
end

-- True, or nil and why: a full disk throws from write or close, and that
-- is an answer here, not a crash.
local function writeFile(path, body)
    local ok, err = pcall(function()
        local directory = fs.getDir(path)
        if directory ~= "" and not fs.exists(directory) then fs.makeDir(directory) end
        local handle = fs.open(path, "w")
        if not handle then error("Could not write " .. path, 0) end
        handle.write(body)
        handle.close()
    end)
    if ok then return true end
    return nil, tostring(err)
end

local function loadTable(body, name)
    if type(body) ~= "string" then return nil end
    local chunk = load(body, "=" .. (name or "config"), "t", {})
    if not chunk then return nil end
    local ok, value = pcall(chunk)
    if ok and type(value) == "table" then return value end
    return nil
end

local function versionParts(value)
    local major, minor, patch = tostring(value or ""):match("^(%d+)%.(%d+)%.(%d+)")
    if not major then return nil end
    return tonumber(major), tonumber(minor), tonumber(patch)
end

local function newerVersion(candidate, current)
    local a, b, c = versionParts(candidate)
    local x, y, z = versionParts(current)
    if not a or not x then return false end
    if a ~= x then return a > x end
    if b ~= y then return b > y end
    return c > z
end

local function installedVersion(root)
    local installed = loadTable(readFile(fs.combine(root, "config.lua")))
    return installed and tostring(installed.version or "0.0.0") or "0.0.0"
end

-- The program /startup.lua boots into, if Easy Deployment wrote it.
local function installedProgram()
    local body = readFile("/startup.lua")
    local id = body and body:match('--boot",%s*"(%w+)"')
    return id and programById(id) and id or nil
end

-- Ours to replace: missing, this file, or a boot entry this file wrote. By
-- the first line -- a program can mention the markers without being either.
local function ownStartup(body)
    return not body or body:sub(1, #HEADER) == HEADER
        or body:sub(1, #ROLE_MARKER) == ROLE_MARKER
end

local function writeStartup(program)
    if not ownStartup(readFile("/startup.lua")) then
        return false, "Your own /startup.lua was kept"
    end
    local written = writeFile("/startup.lua", ROLE_MARKER .. "\nshell.run(\"/"
        .. fs.combine(INSTALL_ROOT, "installer.lua") .. "\", \"--boot\", \""
        .. program.id .. "\")\n")
    if not written then return false, "/startup.lua could not be written" end
    return true
end

-- The release -------------------------------------------------------------------

local function yieldNow()
    os.queueEvent("pumpe_installer_yield")
    os.pullEvent("pumpe_installer_yield")
end

local function checksum(body)
    local hash = 5381
    for index = 1, #body do
        hash = (hash * 33 + string.byte(body, index)) % 4294967296
        if index % 4096 == 0 then yieldNow() end
    end
    -- By hand, as lib/util does: the proven way on ComputerCraft's Lua.
    local digits = {}
    for index = 8, 1, -1 do
        local digit = hash % 16
        digits[index] = ("0123456789abcdef"):sub(digit + 1, digit + 1)
        hash = math.floor(hash / 16)
    end
    return table.concat(digits)
end

local function httpReady()
    return type(http) == "table" and type(http.get) == "function"
end

local function fetchHttps(url, maximumBytes)
    if not httpReady() then return nil, "HTTP is switched off on this server" end
    local separator = url:find("?", 1, true) and "&" or "?"
    local ok, response, err = pcall(http.get, {
        url = url .. separator .. "pumpe=" .. tostring(os.epoch and os.epoch("utc")
            or os.clock()),
        headers = { ["Cache-Control"] = "no-cache" },
        binary = false, redirect = false, timeout = 10,
    })
    if not ok then return nil, tostring(response) end
    if not response then return nil, tostring(err or "GitHub did not answer") end
    local chunks, length = {}, 0
    while true do
        local chunk = response.read(8192)
        if not chunk then break end
        length = length + #chunk
        if length > maximumBytes then
            response.close()
            return nil, "A download was larger than the release says"
        end
        chunks[#chunks + 1] = chunk
    end
    response.close()
    return table.concat(chunks)
end

local function safePath(path)
    return type(path) == "string" and path ~= "" and path:sub(1, 1) ~= "/"
        and not path:find("..", 1, true) and path:match("^[%w_%-/%.]+$") ~= nil
end

local release = {}

-- The published manifest, read once per run. Every file in it, required or
-- optional, by the path it installs under.
local function readManifest()
    if release.manifest then return release.manifest end
    local body, err = fetchHttps(MANIFEST_URL, 256 * 1024)
    if not body then return nil, err end
    local ok, raw = pcall(textutils.unserializeJSON, body)
    if not ok or type(raw) ~= "table" or raw.schema ~= 1 or raw.channel ~= "stable"
        or not versionParts(raw.version) or type(raw.files) ~= "table" then
        return nil, "The release manifest could not be read"
    end
    local byPath = {}
    for _, key in ipairs({ "files", "extra_files", "optional_files" }) do
        for _, entry in ipairs(type(raw[key]) == "table" and raw[key] or {}) do
            local source = type(entry) == "table" and (entry.source or entry.path)
            if source and safePath(entry.path) and safePath(source)
                and not byPath[entry.path]
                and type(entry.size) == "number" and entry.size >= 1
                and entry.size <= 1024 * 1024 and type(entry.checksum) == "string"
                and entry.checksum:match("^%x%x%x%x%x%x%x%x$") then
                byPath[entry.path] = { path = entry.path, source = source,
                    size = entry.size, checksum = string.lower(entry.checksum) }
            end
        end
    end
    release.manifest = { version = raw.version, label = raw.label, byPath = byPath }
    return release.manifest
end

local function download(entry, version)
    local base = MANIFEST_URL:match("^(https://.*/)[^/]+$")
    local body, err = fetchHttps(base .. entry.source .. "?v=" .. tostring(version),
        entry.size + 1)
    if not body then return nil, err end
    if #body ~= entry.size or checksum(body) ~= entry.checksum then
        return nil, entry.path .. " did not match the release"
    end
    return body
end

local function releaseBytes(program, manifest)
    local total = 0
    for _, path in ipairs(filesFor(program)) do
        local entry = manifest and manifest.byPath[path]
        if not entry then return nil end
        total = total + entry.size
    end
    return total
end

-- Local settings survive a reinstall: a phone keeps its settings, a Bank its
-- government key. Any program but the Bank gets no government key at all.
local function configFor(program, body, existingPath, version)
    local stripped = program.id == "bank" and body
        or (body:gsub('(government_key%s*=%s*)"[^"]*"',
            '%1"CLIENT-NO-GOVERNMENT-ACCESS"', 1))
    local existing = loadTable(readFile(existingPath))
    local defaults = existing and loadTable(body)
    if not defaults then return stripped end
    local resets = type(defaults.config_resets) == "table" and defaults.config_resets or {}
    for key, value in pairs(existing) do
        if key ~= "version" and key ~= "config_resets" and key ~= "release_name"
            and value ~= resets[key] then
            defaults[key] = value
        end
    end
    defaults.version = version
    if program.id ~= "bank" then defaults.government_key = "CLIENT-NO-GOVERNMENT-ACCESS" end
    return "-- PUMPE configuration. Local settings are kept when it is reinstalled.\n"
        .. "return " .. textutils.serialize(defaults) .. "\n"
end

local progressDrawn
local function progress(program, entry, done, total, index, count)
    local width, height = target.getSize()
    local barWidth = math.max(8, width - 6)
    local barY = math.max(9, math.min(height - 4, 11))
    if progressDrawn ~= program.id then
        progressDrawn = program.id
        clear()
        header("INSTALLING " .. string.upper(program.name), "From the published release")
        fill(4, barY, barWidth, 2, theme.panel)
    end
    fill(1, 6, width, 1, theme.background)
    center(6, entry and installPath(entry.path) or "", theme.ink)
    fill(1, 8, width, 1, theme.background)
    center(8, math.floor(done / 1024) .. " / " .. math.floor(total / 1024) .. " KiB",
        theme.muted)
    fill(4, barY, math.floor(barWidth * done / math.max(1, total)), 2, theme.accent)
    fill(1, barY + 3, width, 1, theme.background)
    center(barY + 3, "file " .. index .. " of " .. count, theme.accent)
end

-- Downloads a program's files into `root`, checks every one against the
-- release, then puts them all in place together or none at all.
local function install(program, root, manifest)
    local entries, total = {}, 0
    for _, path in ipairs(filesFor(program)) do
        local entry = manifest.byPath[path]
        if not entry then return nil, "The release has no " .. path end
        entries[#entries + 1] = entry
        total = total + entry.size
    end
    local free = fs.getFreeSpace(fs.exists(root) and root or "/")
    if type(free) == "number" and free < total + 8192 then
        return nil, "Needs " .. math.ceil((total + 8192 - free) / 1024)
            .. " KiB more free space"
    end
    local staging = fs.combine(root, ".deploy_tmp")
    local backup = fs.combine(root, ".deploy_backup")
    for _, stale in ipairs({ staging, backup }) do
        if fs.exists(stale) then fs.delete(stale) end
    end
    progressDrawn = nil
    local done = 0
    for index, entry in ipairs(entries) do
        progress(program, entry, done, total, index, #entries)
        local body, err = download(entry, manifest.version)
        if body and entry.path == "startup.lua" and body:sub(1, #HEADER) ~= HEADER then
            body, err = nil, "The release's installer is not Easy Deployment"
        end
        if body and entry.path == "config.lua" then
            body = configFor(program, body, fs.combine(root, "config.lua"),
                manifest.version)
        end
        local written, writeError = false, err
        if body then
            written, writeError = writeFile(fs.combine(staging, installPath(entry.path)),
                body)
        end
        if not written then
            if fs.exists(staging) then fs.delete(staging) end
            return nil, tostring(writeError or "Download failed")
        end
        done = done + entry.size
    end
    progress(program, nil, done, total, #entries, #entries)

    local moved = {}
    local ok, err = pcall(function()
        for _, entry in ipairs(entries) do
            local name = installPath(entry.path)
            local destination = fs.combine(root, name)
            if fs.exists(destination) then
                local saved = fs.combine(backup, name)
                if not fs.exists(fs.getDir(saved)) then fs.makeDir(fs.getDir(saved)) end
                fs.move(destination, saved)
            end
            if not fs.exists(fs.getDir(destination)) then
                fs.makeDir(fs.getDir(destination))
            end
            fs.move(fs.combine(staging, name), destination)
            moved[#moved + 1] = name
        end
    end)
    if not ok then
        for _, name in ipairs(moved) do
            local destination = fs.combine(root, name)
            if fs.exists(destination) then pcall(fs.delete, destination) end
        end
        for _, entry in ipairs(entries) do
            local name = installPath(entry.path)
            if fs.exists(fs.combine(backup, name)) then
                pcall(fs.move, fs.combine(backup, name), fs.combine(root, name))
            end
        end
    end
    for _, stale in ipairs({ staging, backup }) do
        if fs.exists(stale) then fs.delete(stale) end
    end
    if not ok then return nil, tostring(err) end
    return true
end

-- A newer Easy Deployment replaces this file and restarts, so the menu and
-- every boot run the newest one. Trusts the downloaded file's own version,
-- not the manifest's: a release published with a stale stamp would
-- otherwise install the same file and restart for ever.
local function updateSelf(manifest)
    local entry = manifest and manifest.byPath["startup.lua"]
    if not entry or not newerVersion(manifest.version, INSTALLER_VERSION) then
        return false
    end
    local body = download(entry, manifest.version)
    if not body or body:sub(1, #HEADER) ~= HEADER
        or not newerVersion(body:match('INSTALLER_VERSION = "([%d%.]+)"'),
            INSTALLER_VERSION) then
        return false
    end
    local path = shell.getRunningProgram()
    if not path or path == "" or path:sub(1, 4) == "rom/" then return false end
    local temporary, previous = path .. ".update", path .. ".previous"
    for _, stale in ipairs({ temporary, previous }) do
        if fs.exists(stale) then pcall(fs.delete, stale) end
    end
    local written = writeFile(temporary, body)
    local replaced = written and pcall(function()
        fs.move(path, previous)
        fs.move(temporary, path)
    end)
    if not replaced and fs.exists(previous) and not fs.exists(path) then
        pcall(fs.move, previous, path)
    end
    for _, stale in ipairs({ temporary, previous }) do
        if fs.exists(stale) then pcall(fs.delete, stale) end
    end
    if not replaced then return false end
    message("success", "EASY DEPLOYMENT UPDATED", "Now v"
        .. body:match('INSTALLER_VERSION = "([%d%.]+)"'), 0.6)
    os.reboot()
    return true
end

-- Asking -------------------------------------------------------------------------

local function operatorCode()
    local width, height = target.getSize()
    local value = ""
    local layout = { { "1", "2", "3" }, { "4", "5", "6" }, { "7", "8", "9" },
        { "C", "0", "<" } }
    while true do
        clear()
        header("OPERATOR CODE", "The four-digit code")
        center(5, string.rep("* ", #value) .. string.rep("- ", 4 - #value), theme.accent)
        local buttons = {}
        local keyWidth = math.max(5, math.min(10, math.floor((width - 6) / 3)))
        local left = math.floor((width - (keyWidth * 3 + 2)) / 2) + 1
        local top = math.max(7, math.floor((height - 8) / 2) + 5)
        for row = 1, 4 do
            for column = 1, 3 do
                local label = layout[row][column]
                button(buttons, "pin:" .. label, left + (column - 1) * (keyWidth + 1),
                    top + (row - 1) * 2, keyWidth, 1, label,
                    label == "C" and theme.danger or label == "<" and theme.panel
                        or theme.panelAlt,
                    label:match("%d") and colors.black or colors.white)
            end
        end
        button(buttons, "back", 1, height, 8, 1, "< BACK", theme.panel)
        local bindings = {}
        for digit = 0, 9 do bindings[tostring(digit)] = "pin:" .. digit end
        if type(keys) == "table" then bindings[keys.backspace] = "pin:<" end
        local action = waitForButton(buttons, bindings)
        if action == "back" or action == "__terminate" then return nil end
        local key = action and action:match("^pin:(.)$")
        if key == "C" then
            value = ""
        elseif key == "<" then
            value = value:sub(1, -2)
        elseif key then
            value = value .. key
            if #value == 4 then return value end
        end
    end
end

-- Screens --------------------------------------------------------------------------

-- A program's own full screen: the PUMPE's is the first thing anybody sees,
-- and every other program gets the same one from search. Returns "install",
-- "open", "search" (with what was typed), "back", "start" or "exit".
local function programScreen(program, installed, first)
    local width, height = target.getSize()
    clear()
    local titleY = 3
    if program.id == "pumpe" and wordmark(2, "PUMPE", theme.accent) then titleY = 8 end
    center(titleY, string.upper(program.name), program.id == "pumpe" and theme.ink
        or theme.accent)
    local buttonY = height - 5
    for index, line in ipairs(wrapText(program.about, width - 4)) do
        local y = titleY + 1 + index
        if y <= buttonY - 2 then center(y, line, theme.muted) end
    end
    local mine = installed == program.id
    local buttons = {}
    button(buttons, mine and "open" or "install", 2, buttonY, width - 2, 3,
        (mine and "OPEN" or "INSTALL") .. (program.id == "pumpe" and " PUMPE" or ""),
        theme.success, colors.black)

    local manifest = release.manifest
    local status
    if mine then
        status = "Installed - v" .. installedVersion(INSTALL_ROOT)
    elseif not httpReady() then
        status = "HTTP is off: nothing can download"
    elseif manifest then
        local bytes = releaseBytes(program, manifest)
        status = "v" .. manifest.version .. (bytes and ("  -  "
            .. math.ceil(bytes / 1024) .. " KiB") or "")
            .. (program.code and "  -  code" or "")
    else
        status = "GitHub cannot be reached right now"
    end
    if first and installed and not mine then
        status = "This computer: " .. string.upper(programById(installed).name)
    end
    center(height - 2, status, theme.muted)

    if first then
        button(buttons, "search", 1, height - 1, width, 1, "v  SEARCH ALL PROGRAMS",
            theme.accentDark)
        button(buttons, "exit", 2, height, 6, 1, "EXIT", theme.panel)
        if installed and not mine then
            button(buttons, "start", width - 7, height, 7, 1, "START",
                theme.success, colors.black)
        end
    else
        button(buttons, "back", 2, height, 8, 1, "< BACK", theme.panel)
    end
    if mine then
        button(buttons, "install", width - 12, height, 11, 1, "REINSTALL", theme.panel)
    end

    local bindings = {}
    if type(keys) == "table" then
        bindings[keys.enter] = mine and "open" or "install"
        if keys.numPadEnter then bindings[keys.numPadEnter] = bindings[keys.enter] end
        if first then
            bindings[keys.down] = "search"
        else
            bindings[keys.backspace] = "back"
            bindings[keys.up] = "back"
        end
    end
    local action, typed = waitForButton(buttons, bindings, first and "search" or nil)
    if action == "__terminate" then return first and "exit" or "back" end
    return action, typed
end

-- Every program whose name, description or keywords hold every word typed,
-- best first: a name that starts with it, then a word in the name that does,
-- then anywhere at all. Nothing typed is every program, in the usual order.
local function search(query)
    local results = {}
    for order, program in ipairs(PROGRAMS) do
        if not program.hidden then
            local name = string.lower(program.name)
            local everything = string.lower(program.name .. " " .. program.detail
                .. " " .. (program.words or "") .. " " .. program.id)
            local score = 0
            for word in string.lower(query):gmatch("%S+") do
                if name:sub(1, #word) == word then
                    score = score + 3
                elseif (" " .. name):find(" " .. word, 1, true) then
                    score = score + 2
                elseif everything:find(word, 1, true) then
                    score = score + 1
                else
                    score = nil
                    break
                end
            end
            if score then
                results[#results + 1] = { program = program, score = score,
                    order = order }
            end
        end
    end
    table.sort(results, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.order < b.order
    end)
    return results
end

-- The search box. Results change with every key; up/down move through them,
-- Enter or a tap opens one, and up from the top (or backspace on an empty
-- box) goes back to the PUMPE. Returns a program, "back" or "exit", and
-- what was in the box, so coming back from a program finds it still there.
local function searchScreen(installed, query)
    query = query or ""
    local selected, top = 1, 1
    while true do
        local width, height = target.getSize()
        local results = search(query)
        selected = math.max(1, math.min(selected, #results))
        local rows = height >= 16 and 2 or 1
        local listTop = 6
        local visible = math.max(1, math.floor((height - listTop) / rows))
        if selected < top then top = selected end
        if selected >= top + visible then top = selected - visible + 1 end

        clear()
        fill(1, 1, width, 1, theme.panel)
        writeAt(2, 1, "FIND A PROGRAM", theme.ink, theme.panel)
        local hits = {}
        button(hits, "back", width - 8, 1, 9, 1, "^ PUMPE", theme.accentDark)
        fill(2, 3, width - 2, 1, theme.panelAlt)
        local room = width - 6
        local shown = #query > room and query:sub(-room) or query
        writeAt(3, 3, "> " .. shown .. "_", colors.black, theme.panelAlt)
        center(4, #results == 0 and "Nothing matches" or (query:match("%S")
            and (#results .. (#results == 1 and " program" or " programs"))
            or "Type to search"), theme.muted)
        for index = top, math.min(#results, top + visible - 1) do
            local program = results[index].program
            local y = listTop + (index - top) * rows
            local background = index == selected and theme.accentDark or theme.background
            fill(1, y, width, rows, background)
            local name = program.name .. (installed == program.id and "  *" or "")
            writeAt(2, y, truncate(name, width - 2), theme.ink, background)
            if rows == 2 then
                local detail = installed == program.id and "Installed here"
                    or (program.detail .. (program.code and " - code" or ""))
                writeAt(2, y + 1, truncate(detail, width - 2), theme.muted, background)
            end
            hits[#hits + 1] = { id = index, x1 = 1, y1 = y, x2 = width,
                y2 = y + rows - 1 }
        end

        local event = { os.pullEvent() }
        local kind = event[1]
        if kind == "char" or kind == "paste" then
            query, selected, top = query .. event[2], 1, 1
        elseif kind == "key" and type(keys) == "table" then
            local key = event[2]
            if key == keys.backspace then
                if query == "" then return "back", query end
                query, selected, top = query:sub(1, -2), 1, 1
            elseif enterKey(key) then
                if results[selected] then return results[selected].program, query end
            elseif key == keys.down then
                selected = math.min(#results, selected + 1)
            elseif key == keys.up then
                if selected <= 1 then return "back", query end
                selected = selected - 1
            end
        elseif kind == "mouse_scroll" then
            selected = math.max(1, math.min(#results, selected + event[2]))
        elseif kind == "mouse_click" or kind == "monitor_touch" then
            for index = #hits, 1, -1 do
                local hit = hits[index]
                if event[3] >= hit.x1 and event[3] <= hit.x2
                    and event[4] >= hit.y1 and event[4] <= hit.y2 then
                    if hit.id == "back" then return "back", query end
                    return results[hit.id].program, query
                end
            end
        elseif kind == "terminate" then
            return "exit", query
        end
    end
end

-- Installing from the menu: the code where one is needed, the download,
-- the boot entry, and a restart into the program.
local function installChosen(program)
    if program.code then
        local code = operatorCode()
        if not code then return end
        if code ~= PROTECTED_CODE then
            message("error", "WRONG CODE", "Nothing was installed", 1.4)
            return
        end
    end
    if not httpReady() then
        message("error", "HTTP IS OFF", "Easy Deployment downloads from GitHub."
            .. " Switch http on in ComputerCraft's server config.", 3)
        return
    end
    local manifest, manifestError = readManifest()
    if not manifest then
        message("error", "RELEASE UNREACHABLE", manifestError, 2.2)
        return
    end
    local ok, err = install(program, INSTALL_ROOT, manifest)
    if not ok then
        message("error", "INSTALL FAILED", err, 2.4)
        return
    end
    local booting, note = writeStartup(program)
    message("success", string.upper(program.name) .. " READY", booting
        and ("v" .. manifest.version .. " - starting it now") or note, 1.2)
    if booting then
        os.reboot()
    else
        shell.run(fs.combine(INSTALL_ROOT, program.file))
    end
    return true
end

local function openProgram(program)
    local path = fs.combine(INSTALL_ROOT, program.file)
    if not fs.exists(path) then
        message("error", "NOT INSTALLED", "Install " .. program.name .. " first", 1.6)
        return false
    end
    clear()
    shell.run("/" .. path)
    return true
end

-- Booting ----------------------------------------------------------------------

-- Starts the program beside this copy, after updating it when the release
-- is newer. /startup.lua is never rewritten here: it already points at this
-- copy, and this copy is wherever the program is.
local function bootProgram(program)
    local home = homeDir()
    local root = fs.exists(fs.combine(home, program.file)) and home or INSTALL_ROOT
    local manifest = httpReady() and readManifest()
    if manifest then
        updateSelf(manifest)
        if (newerVersion(manifest.version, installedVersion(root)) and not program.byCore)
            or not fs.exists(fs.combine(root, program.file)) then
            if install(program, root, manifest) then
                message("success", "UPDATED TO v" .. manifest.version,
                    "Restarting " .. program.name, 0.6)
                os.reboot()
                return
            end
        end
    end
    local path = fs.combine(root, program.file)
    if not fs.exists(path) then
        message("error", "PROGRAM MISSING", "Run Easy Deployment again", 2)
        return
    end
    shell.run("/" .. path)
    -- A locked counter never ends on purpose. If it ended anyway, start
    -- again rather than leave the shell open at a public counter.
    if keyboardLocked() then
        sleep(3)
        os.reboot()
    end
end

if mode == "--auto" then
    -- lib/net asks this when a program cannot update itself. Quietly: only
    -- a newer release is installed, and then the computer restarts into it.
    local program = programById(modeProgram)
    local manifest = program and httpReady() and readManifest()
    if manifest and newerVersion(manifest.version, installedVersion(homeDir())) then
        if install(program, homeDir(), manifest) then
            os.reboot()
            return true
        end
    end
    return false
end

if mode == "--boot" then
    local program = programById(modeProgram)
    if program then return bootProgram(program) end
    message("error", "UNKNOWN PROGRAM", modeProgram .. " - pick one instead", 2)
end

-- The menu ------------------------------------------------------------------------

do
    local width, height = target.getSize()
    clear()
    center(math.floor(height / 2) - 1, "PUMPE EASY DEPLOYMENT", theme.ink)
    center(math.floor(height / 2) + 1, "v" .. INSTALLER_VERSION, theme.muted)
    if httpReady() and readManifest() then updateSelf(release.manifest) end
end

local pumpe = programById("pumpe")
local screen, chosen, searched = "pumpe", nil, nil
while true do
    local installed = installedProgram()
    local action
    if screen == "pumpe" then
        -- Whatever was typed here starts the search.
        action, searched = programScreen(pumpe, installed, true)
        chosen = pumpe
    elseif screen == "search" then
        local found
        found, searched = searchScreen(installed, searched)
        if type(found) == "table" then
            chosen, screen = found, "program"
        else
            action = found
        end
    else
        action = programScreen(chosen, installed, false)
    end
    if action == "exit" then
        break
    elseif action == "search" then
        screen = "search"
    elseif action == "back" then
        screen = screen == "program" and "search" or "pumpe"
    elseif action == "install" then
        if installChosen(chosen) then break end
    elseif action == "open" then
        if openProgram(chosen) then break end
    elseif action == "start" then
        if openProgram(programById(installed)) then break end
    end
end

clear()
print("PUMPE Easy Deployment closed.")
