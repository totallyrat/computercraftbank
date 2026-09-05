-- PUMPE EASY DEPLOYMENT
-- This file is intentionally standalone. It downloads every other required
-- script and library from the active Bank Server's /updates/ directory.

local DEPLOY_PROTOCOL = "PUMPE_DEPLOY_V5"
local DEPLOY_HOSTNAME = "PUMPE_UPDATES"
local PROTECTED_CODE = "4040"
local INSTALLER_VERSION = "8.1.1"
local PUBLIC_MANIFEST_URL =
    "https://raw.githubusercontent.com/totallyrat/computercraftbank/main/release_manifest.json"
local INSTALL_ROOT = "/pumpe"
local UPDATES_ROOT = "/updates"
local STAGING_ROOT = fs.combine(INSTALL_ROOT, ".deploy_tmp")
local BACKUP_ROOT = fs.combine(INSTALL_ROOT, ".deploy_backup")
local arguments = { ... }
local automaticRoleId = arguments[1] == "--auto"
    and string.lower(tostring(arguments[2] or "")) or nil
local bootRoleId = arguments[1] == "--boot"
    and string.lower(tostring(arguments[2] or "")) or nil

local target = term.current()
local bankId
local running = true
local publicManifest
local WATCHDOG_YIELD_EVENT = "pumpe_installer_work_slice"
local CHECKSUM_SLICE_BYTES = 2048

local theme = {
    background = colors.black,
    panel = colors.gray,
    panelAlt = colors.lightGray,
    ink = colors.white,
    muted = colors.lightGray,
    accent = colors.cyan,
    accentDark = colors.blue,
    success = colors.lime,
    warning = colors.orange,
    danger = colors.red,
}

local roles = {
    { id = "pumpe", label = "PERSONAL PUMPE", detail = "Pocket banking" },
    { id = "service", label = "SERVICE KIOSK", detail = "Shop checkout" },
    { id = "event", label = "EVENT KIOSK", detail = "Tickets + door check" },
    { id = "border", label = "BORDER CONTROLLER", detail = "Visa entry gate" },
    { id = "bank", label = "BANK SERVER", detail = "Bank operator", protected = true },
    { id = "admin", label = "ADMIN TERMINAL", detail = "Government use", protected = true },
    -- Retired in 7.1. Still bootable so an installed Tax Controller can say
    -- so instead of failing with an unknown role.
    { id = "tax", label = "TAX CONTROLLER", detail = "Retired", protected = true, hidden = true },
    { id = "ccg", label = "CCG BET CONSOLE", detail = "ComputerCraftGaming" },
    { id = "anchor", label = "GPS ANCHOR", detail = "Positioning beacon" },
}

local rolePrograms = {
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

local function roleById(id)
    for _, role in ipairs(roles) do
        if role.id == id then return role end
    end
    return nil
end

local function clear(background)
    target.setBackgroundColor(background or theme.background)
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
        if row >= 1 and row <= screenHeight then
            target.setCursorPos(x, row)
            target.write(line)
        end
    end
end

local function writeAt(x, y, value, foreground, background, maxWidth)
    local screenWidth, screenHeight = target.getSize()
    if x < 1 or x > screenWidth or y < 1 or y > screenHeight then return end
    value = tostring(value or "")
    if maxWidth then value = value:sub(1, math.max(0, maxWidth)) end
    value = value:sub(1, screenWidth - x + 1)
    if background then target.setBackgroundColor(background) end
    target.setTextColor(foreground or theme.ink)
    target.setCursorPos(x, y)
    target.write(value)
end

local function truncate(value, width)
    value = tostring(value or "")
    if #value <= width then return value end
    if width <= 2 then return value:sub(1, width) end
    return value:sub(1, width - 2) .. ".."
end

local function center(y, value, foreground, background)
    local width = target.getSize()
    value = truncate(value, width - 2)
    writeAt(math.floor((width - #value) / 2) + 1, y,
        value, foreground, background)
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

-- A 3x5 block face so the PUMPE panel gets a title you can read across the
-- room. Returns false when the screen cannot hold it, so the caller can fall
-- back to ordinary centred text.
local BIG_GLYPHS = {
    P = { "###", "# #", "###", "#  ", "#  " },
    U = { "# #", "# #", "# #", "# #", "###" },
    M = { "# #", "###", "###", "# #", "# #" },
    E = { "###", "#  ", "###", "#  ", "###" },
}

local function wordmark(y, word, color)
    local width, height = target.getSize()
    local span = #word * 4 - 1
    if span > width or y < 1 or y + 4 > height then return false end
    for index = 1, #word do
        if not BIG_GLYPHS[word:sub(index, index)] then return false end
    end
    local left = math.floor((width - span) / 2) + 1
    for index = 1, #word do
        local glyph = BIG_GLYPHS[word:sub(index, index)]
        for row = 1, 5 do
            for column = 1, 3 do
                if glyph[row]:sub(column, column) == "#" then
                    fill(left + (index - 1) * 4 + column - 1,
                        y + row - 1, 1, 1, color)
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
    background = background or theme.panel
    foreground = foreground or theme.ink
    fill(x, y, width, height, background)
    local lines = {}
    for line in tostring(label):gmatch("[^\n]+") do lines[#lines + 1] = line end
    if #lines == 0 then lines[1] = "" end
    local firstY = y + math.floor((height - #lines) / 2)
    for index, line in ipairs(lines) do
        line = truncate(line, width - 2)
        writeAt(x + math.max(0, math.floor((width - #line) / 2)),
            firstY + index - 1, line, foreground, background)
    end
    buttons[#buttons + 1] = {
        id = id, x1 = x, y1 = y,
        x2 = x + width - 1, y2 = y + height - 1,
    }
end

local function waitForButton(buttons, keyBindings)
    while true do
        local event = { os.pullEvent() }
        if event[1] == "mouse_click" then
            local x, y = event[3], event[4]
            for index = #buttons, 1, -1 do
                local item = buttons[index]
                if x >= item.x1 and x <= item.x2
                    and y >= item.y1 and y <= item.y2 then
                    fill(item.x1, item.y1, item.x2 - item.x1 + 1,
                        item.y2 - item.y1 + 1, theme.accentDark)
                    sleep(0.04)
                    return item.id
                end
            end
        elseif event[1] == "key" and keyBindings
            and keyBindings[event[2]] then
            return keyBindings[event[2]]
        elseif event[1] == "char" and keyBindings
            and keyBindings[event[2]] then
            return keyBindings[event[2]]
        elseif event[1] == "terminate" then
            return "__terminate"
        end
    end
end

local function message(kind, title, body, duration)
    local width, height = target.getSize()
    local color = kind == "success" and theme.success
        or kind == "warning" and theme.warning
        or kind == "error" and theme.danger
        or theme.accent
    clear()
    local y = math.max(3, math.floor(height / 2) - 2)
    fill(math.floor(width / 2) - 3, y, 7, 3, color)
    center(y + 1, kind == "success" and "OK" or "!", colors.black, color)
    center(y + 4, title, color)
    center(y + 6, body or "", theme.muted)
    sleep(duration or 1.2)
end

local function boot()
    local width, height = target.getSize()
    for frame = 1, 5 do
        clear()
        center(math.floor(height / 2) - 2, "PUMPE", theme.ink)
        center(math.floor(height / 2), "EASY DEPLOYMENT", theme.accent)
        local barWidth = math.max(8, math.min(width - 6, 28))
        fill(math.floor((width - barWidth) / 2) + 1,
            math.floor(height / 2) + 3, barWidth, 1, theme.panel)
        fill(math.floor((width - barWidth) / 2) + 1,
            math.floor(height / 2) + 3, math.floor(barWidth * frame / 5),
            1, theme.accent)
        sleep(0.08)
    end
end

local function openModems()
    local opened = 0
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "modem" then
            if not rednet.isOpen(name) then rednet.open(name) end
            opened = opened + 1
        end
    end
    return opened > 0
end

local function nowMs()
    if os.epoch then return os.epoch("utc") end
    return math.floor(os.clock() * 1000)
end

local function requestId()
    return tostring(os.getComputerID()) .. "_" .. tostring(nowMs())
        .. "_" .. tostring(math.random(1000, 9999))
end

local function discoverBank()
    bankId = rednet.lookup(DEPLOY_PROTOCOL, DEPLOY_HOSTNAME)
    return bankId
end

local function deployRequest(action, payload, timeout)
    timeout = timeout or 8
    if not bankId and not discoverBank() then
        return nil, "No PUMPE Bank Server was found"
    end
    local id = requestId()
    local sent = rednet.send(bankId, {
        version = 1,
        kind = "deploy_request",
        request_id = id,
        action = action,
        payload = payload,
    }, DEPLOY_PROTOCOL)
    if not sent then
        bankId = nil
        return nil, "Could not reach the Bank Server"
    end
    local deadline = nowMs() + timeout * 1000
    while nowMs() < deadline do
        local remaining = math.max(0.05, (deadline - nowMs()) / 1000)
        local sender, response = rednet.receive(DEPLOY_PROTOCOL, remaining)
        if sender == bankId and type(response) == "table"
            and response.kind == "deploy_response"
            and response.request_id == id then
            if response.ok then return response.data end
            return nil, response.error or "Deployment request was rejected",
                response.code
        end
    end
    bankId = nil
    return nil, "Bank Server timed out"
end

local function protectedCode()
    local width, height = target.getSize()
    local value = ""
    local layout = {
        { "1", "2", "3" },
        { "4", "5", "6" },
        { "7", "8", "9" },
        { "C", "0", "<" },
    }
    while true do
        clear()
        header("PROTECTED DOWNLOAD", "Enter the four-digit access code")
        center(5, string.rep("* ", #value) .. string.rep("- ", 4 - #value),
            theme.accent)
        local buttons = {}
        local buttonWidth = math.max(5, math.min(10, math.floor((width - 6) / 3)))
        local gridWidth = buttonWidth * 3 + 2
        local startX = math.floor((width - gridWidth) / 2) + 1
        local startY = math.max(7, math.floor((height - 8) / 2) + 5)
        for row = 1, 4 do
            for column = 1, 3 do
                local label = layout[row][column]
                button(buttons, "pin:" .. label,
                    startX + (column - 1) * (buttonWidth + 1),
                    startY + (row - 1) * 2, buttonWidth, 1, label,
                    label == "C" and theme.danger
                        or label == "<" and theme.panel
                        or theme.panelAlt,
                    label:match("%d") and colors.black or colors.white)
            end
        end
        button(buttons, "cancel", 1, height, 7, 1, "< BACK", theme.panel)
        local keyBindings = {}
        if keys and keys.backspace then keyBindings[keys.backspace] = "pin:<" end
        if keys and keys.escape then keyBindings[keys.escape] = "cancel" end
        for digit = 0, 9 do keyBindings[tostring(digit)] = "pin:" .. digit end
        local action = waitForButton(buttons, keyBindings)
        if action == "cancel" or action == "__terminate" then return nil end
        local digit = action and action:match("^pin:(.)$")
        if digit == "C" then
            value = ""
        elseif digit == "<" then
            value = value:sub(1, -2)
        elseif digit and digit:match("%d") and #value < 4 then
            value = value .. digit
            if #value == 4 then return value end
        end
    end
end

local function cooperativeYield()
    if type(os) ~= "table"
        or type(os.queueEvent) ~= "function"
        or type(os.pullEvent) ~= "function" then
        return false
    end
    os.queueEvent(WATCHDOG_YIELD_EVENT)
    os.pullEvent(WATCHDOG_YIELD_EVENT)
    return true
end

local function checksum(body)
    local hash = 5381
    for index = 1, #body do
        hash = (hash * 33 + string.byte(body, index)) % 4294967296
        if index % CHECKSUM_SLICE_BYTES == 0 then
            cooperativeYield()
        end
    end
    local alphabet, output = "0123456789abcdef", {}
    for index = 8, 1, -1 do
        local digit = hash % 16
        output[index] = alphabet:sub(digit + 1, digit + 1)
        hash = math.floor(hash / 16)
    end
    return table.concat(output)
end

local function versionParts(value)
    local major, minor, patch = tostring(value or ""):match(
        "^(%d+)%.(%d+)%.(%d+)")
    if not major then return nil end
    return tonumber(major), tonumber(minor), tonumber(patch)
end

local function newerVersion(candidate, current)
    local candidateMajor, candidateMinor, candidatePatch =
        versionParts(candidate)
    local currentMajor, currentMinor, currentPatch = versionParts(current)
    if not candidateMajor or not currentMajor then return false end
    if candidateMajor ~= currentMajor then return candidateMajor > currentMajor end
    if candidateMinor ~= currentMinor then return candidateMinor > currentMinor end
    return candidatePatch > currentPatch
end

local function installedVersion()
    local loader = loadfile(fs.combine(INSTALL_ROOT, "config.lua"))
    if not loader then return "0.0.0" end
    local ok, installedConfig = pcall(loader)
    if not ok or type(installedConfig) ~= "table" then return "0.0.0" end
    return tostring(installedConfig.version or "0.0.0")
end

local function readFile(path)
    local handle = fs.open(path, "r")
    if not handle then return nil end
    local body = handle.readAll()
    handle.close()
    return body
end

local function safeRelativePath(path)
    return type(path) == "string"
        and path ~= ""
        and path:sub(1, 1) ~= "/"
        and not path:find("\\", 1, true)
        and not path:find("..", 1, true)
        and path:match("^[%w_%-/%.]+$") ~= nil
end

local function ensureParent(path)
    local directory = fs.getDir(path)
    if directory ~= "" and not fs.exists(directory) then fs.makeDir(directory) end
end

local function writeFile(path, body)
    ensureParent(path)
    local handle = fs.open(path, "w")
    if not handle then return nil, "Could not write " .. path end
    handle.write(body)
    handle.close()
    return true
end

-- The role this computer already boots into, taken from the marked
-- /startup.lua Easy Deployment writes after every installation.
local function installedRole()
    if not fs.exists("/startup.lua") then return nil end
    local body = readFile("/startup.lua")
    local id = body and body:match('--boot",%s*"(%w+)"')
    return id and roleById(id) and id or nil
end

-- The PUMPE gets the whole first screen. Everything else lives one press of
-- the down arrow away, because most computers being set up are phones.
local function pumpeScreen(installed)
    local width, height = target.getSize()
    local buttons = {}
    clear()
    if not wordmark(2, "PUMPE", theme.accent) then
        center(3, "PUMPE", theme.accent)
    end
    center(8, "PERSONAL PUMPE", theme.ink)
    local installY = height - 5
    local body = wrapText("Money, friends, tickets and travel papers, all in"
        .. " one pocket computer.", width - 4)
    for index, line in ipairs(body) do
        local y = 9 + index
        if y <= installY - 2 then center(y, line, theme.muted) end
    end
    local mine = installed == "pumpe"
    button(buttons, mine and "start" or "install", 2, installY, width - 2, 3,
        mine and "START PUMPE" or "INSTALL PUMPE",
        theme.success, colors.black)
    button(buttons, "more", 2, height - 1, width - 2, 1,
        "v   OTHER ROLES", theme.accentDark)
    button(buttons, "exit", 2, height, 6, 1, "EXIT", theme.panel)
    if mine then
        button(buttons, "install", width - 11, height, 10, 1, "REINSTALL",
            theme.panel)
    end
    local bindings = { m = "more", M = "more", i = "install", I = "install" }
    if type(keys) == "table" then
        if keys.down then bindings[keys.down] = "more" end
        if keys.enter then bindings[keys.enter] = mine and "start" or "install" end
    end
    return waitForButton(buttons, bindings)
end

-- Everything that is not a PUMPE, behind the down arrow.
local function rolesScreen(installed)
    local width, height = target.getSize()
    clear()
    header("OTHER ROLES", "What is this computer?")
    local buttons = {}
    local visible = {}
    for _, role in ipairs(roles) do
        if not role.hidden and role.id ~= "pumpe" then
            visible[#visible + 1] = role
        end
    end
    local columns = width >= 40 and 2 or 1
    local rows = math.ceil(#visible / columns)
    local top, bottom = 5, height - 2
    local cardHeight = math.max(2, math.floor((bottom - top + 1) / rows))
    local cardWidth = math.floor((width - 2 - (columns - 1)) / columns)
    for index, role in ipairs(visible) do
        local column = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        local y = top + row * cardHeight
        if y + 1 <= bottom then
            local label = role.label
            if cardHeight >= 3 then
                label = label .. "\n" .. role.detail
                    .. (role.protected and " (4040)" or "")
            elseif role.protected then
                label = label .. " 4040"
            end
            button(buttons, "role:" .. role.id,
                2 + column * (cardWidth + 1), y, cardWidth,
                math.min(cardHeight - 1, bottom - y + 1), label,
                role.protected and theme.warning
                    or role.id == installed and theme.accentDark
                    or theme.panel,
                role.protected and colors.black or colors.white)
        end
    end
    local footer = installed
        and ("Installed: " .. string.upper(installed)
            .. "  -  v" .. installedVersion())
        or "Nothing installed yet"
    writeAt(2, height - 1, truncate(footer, width - 2), theme.muted,
        theme.background)
    button(buttons, "back", 2, height, 8, 1, "^ BACK", theme.accentDark)
    button(buttons, "exit", math.floor(width / 2) - 2, height, 6, 1,
        "EXIT", theme.panel)
    if installed and installed ~= "pumpe" then
        button(buttons, "start", width - 8, height, 7, 1, "START",
            theme.success, colors.black)
    end
    local bindings = {}
    for index, role in ipairs(visible) do
        bindings[tostring(index)] = "role:" .. role.id
    end
    if type(keys) == "table" and keys.up then bindings[keys.up] = "back" end
    return waitForButton(buttons, bindings)
end

local function roleMenu()
    local installed = installedRole()
    local screen = installed and installed ~= "pumpe" and "roles" or "pumpe"
    while running do
        local action = screen == "pumpe" and pumpeScreen(installed)
            or rolesScreen(installed)
        if action == "exit" or action == "__terminate" then
            running = false
            return nil
        elseif action == "more" then
            screen = "roles"
        elseif action == "back" then
            screen = "pumpe"
        elseif action == "install" then
            return roleById("pumpe")
        elseif action == "start" then
            return roleById(screen == "pumpe" and "pumpe" or installed), true
        else
            local id = action and action:match("^role:(.+)$")
            local role = id and roleById(id)
            if role then return role end
        end
    end
end

local function closeResponse(response)
    if response and type(response.close) == "function" then
        pcall(response.close)
    end
end

local function fetchHttps(url, maximumBytes)
    if type(http) ~= "table" or type(http.get) ~= "function" then
        return nil, "ComputerCraft HTTP is disabled"
    end
    if type(url) ~= "string" or not url:match("^https://") then
        return nil, "Online updates require HTTPS"
    end
    local separator = url:find("?", 1, true) and "&" or "?"
    local ok, response, err, errorResponse = pcall(http.get, {
        url = url .. separator .. "pumpe=" .. tostring(nowMs()),
        headers = {
            ["Accept"] = "application/json, text/plain",
            ["Cache-Control"] = "no-cache",
        },
        binary = false,
        redirect = false,
        timeout = 10,
    })
    if not ok then return nil, tostring(response) end
    if not response then
        closeResponse(errorResponse)
        return nil, tostring(err or "HTTP request failed")
    end
    local chunks, length = {}, 0
    while true do
        local chunk = response.read(8192)
        if not chunk then break end
        length = length + #chunk
        if length > maximumBytes then
            closeResponse(response)
            return nil, "Online update was too large"
        end
        chunks[#chunks + 1] = chunk
    end
    closeResponse(response)
    return table.concat(chunks)
end

local function manifestEntry(manifest, requestedPath)
    if type(manifest) ~= "table" or manifest.schema ~= 1
        or manifest.channel ~= "stable"
        or type(manifest.version) ~= "string"
        or type(manifest.files) ~= "table" then
        return nil
    end
    for _, file in ipairs(manifest.files) do
        if type(file) == "table" and file.path == requestedPath
            and safeRelativePath(file.source or file.path)
            and type(file.size) == "number" and file.size >= 1
            and file.size <= 1024 * 1024
            and type(file.checksum) == "string"
            and file.checksum:match("^[0-9a-fA-F]+$")
            and #file.checksum == 8 then
            return {
                path = file.path,
                source = file.source or file.path,
                size = file.size,
                checksum = string.lower(file.checksum),
                version = manifest.version,
            }
        end
    end
end

local function selfUpdateInstaller()
    local manifestBody = fetchHttps(PUBLIC_MANIFEST_URL, 256 * 1024)
    if not manifestBody then return false end
    local ok, manifest = pcall(textutils.unserializeJSON, manifestBody)
    if not ok then return false end
    publicManifest = manifest
    local entry = manifestEntry(manifest, "startup.lua")
    if not entry or not newerVersion(entry.version, INSTALLER_VERSION) then
        return false
    end
    local base = PUBLIC_MANIFEST_URL:gsub("[?#].*$", "")
        :match("^(https://.*/)[^/]+$")
    if not base then return false end
    local body = fetchHttps(base .. entry.source, entry.size + 1)
    if not body or #body ~= entry.size
        or checksum(body) ~= entry.checksum
        or not body:find("-- PUMPE EASY DEPLOYMENT", 1, true) then
        return false
    end
    -- Trust the downloaded file's own version, not the manifest's. A release
    -- published with a stale INSTALLER_VERSION would otherwise install the
    -- same file and reboot forever.
    local downloadedVersion = body:match('INSTALLER_VERSION = "([%d%.]+)"')
    if not downloadedVersion
        or not newerVersion(downloadedVersion, INSTALLER_VERSION) then
        return false
    end

    local runningPath = shell.getRunningProgram()
    if not runningPath or runningPath == "" then return false end
    local temporary = runningPath .. ".update"
    local backup = runningPath .. ".previous"
    if fs.exists(temporary) then fs.delete(temporary) end
    if fs.exists(backup) then fs.delete(backup) end
    local wrote, written = pcall(writeFile, temporary, body)
    if not wrote or not written then
        if fs.exists(temporary) then pcall(fs.delete, temporary) end
        return false
    end
    local moved, moveError = pcall(function()
        if fs.exists(runningPath) then fs.move(runningPath, backup) end
        fs.move(temporary, runningPath)
    end)
    if not moved then
        if fs.exists(runningPath) then fs.delete(runningPath) end
        if fs.exists(backup) then fs.move(backup, runningPath) end
        if fs.exists(temporary) then fs.delete(temporary) end
        return false, tostring(moveError)
    end
    if fs.exists(backup) then fs.delete(backup) end
    message("success", "EASY DEPLOYMENT UPDATED",
        "Installed v" .. downloadedVersion, 0.6)
    os.reboot()
    return true
end

local function replaceInstalledFile(entry, destination)
    if not entry then return false end
    local existing = readFile(destination)
    if existing and #existing == entry.size
        and checksum(existing) == entry.checksum then
        return true
    end

    local base = PUBLIC_MANIFEST_URL:gsub("[?#].*$", "")
        :match("^(https://.*/)[^/]+$")
    if not base then return false end
    local body = fetchHttps(base .. entry.source, entry.size + 1)
    if not body or #body ~= entry.size
        or checksum(body) ~= entry.checksum then
        return false
    end

    local temporary = destination .. ".watchdog_update"
    local backup = destination .. ".watchdog_previous"
    if fs.exists(temporary) then fs.delete(temporary) end
    if fs.exists(backup) then fs.delete(backup) end
    local wrote, written = pcall(writeFile, temporary, body)
    if not wrote or not written then
        if fs.exists(temporary) then pcall(fs.delete, temporary) end
        return false
    end
    local moved = pcall(function()
        if fs.exists(destination) then fs.move(destination, backup) end
        fs.move(temporary, destination)
    end)
    if not moved then
        if fs.exists(destination) then fs.delete(destination) end
        if fs.exists(backup) then fs.move(backup, destination) end
        if fs.exists(temporary) then fs.delete(temporary) end
        return false
    end
    if fs.exists(backup) then fs.delete(backup) end
    return true
end

local function cleanupLegacyBankDuplicates()
    local mappings = {
        { depot = "bank_server.lua", installed = "bank_server.lua" },
        { depot = "startup.lua", installed = "installer.lua" },
        { depot = "config.lua", installed = "config.lua" },
        { depot = "lib/net.lua", installed = "lib/net.lua" },
        { depot = "lib/ui.lua", installed = "lib/ui.lua" },
        { depot = "lib/update.lua", installed = "lib/update.lua" },
        { depot = "lib/util.lua", installed = "lib/util.lua" },
    }
    for _, mapping in ipairs(mappings) do
        local installed = fs.combine(INSTALL_ROOT, mapping.installed)
        local duplicate = fs.combine(UPDATES_ROOT, mapping.depot)
        if fs.exists(installed) and fs.exists(duplicate) then
            pcall(fs.delete, duplicate)
        end
    end
    for _, stale in ipairs({
        fs.combine(INSTALL_ROOT, ".easy_deployment_source.lua"),
        fs.combine(INSTALL_ROOT, ".online_update_stage"),
        fs.combine(INSTALL_ROOT, ".online_update_backup"),
    }) do
        if fs.exists(stale) then pcall(fs.delete, stale) end
    end
end

local function updateInstalledConfigVersion(version)
    local path = fs.combine(INSTALL_ROOT, "config.lua")
    local body = readFile(path)
    if not body then return false end
    local updated, replacements = body:gsub(
        '(version%s*=%s*)"[^"]+"', '%1"' .. tostring(version) .. '"', 1)
    if replacements ~= 1 then return false end
    if updated == body then return true end
    local temporary = path .. ".compact_update"
    if fs.exists(temporary) then fs.delete(temporary) end
    local wrote, written = pcall(writeFile, temporary, updated)
    if not wrote or not written then
        if fs.exists(temporary) then pcall(fs.delete, temporary) end
        return false
    end
    if fs.exists(path) then fs.delete(path) end
    fs.move(temporary, path)
    return true
end

-- v6.0 Banks filled the disk by keeping the release in both /pumpe and
-- /updates. Easy Deployment frees those safe duplicates first, then installs
-- the compact Bank program before launch so an affected Bank can recover even
-- when it cannot reach its own updater.
-- Every file the Bank runtime is built from. config.lua is deliberately not
-- here: it holds the government key and other local settings.
local BANK_RUNTIME_REPAIR = {
    { path = "lib/util.lua", source = "lib/util.lua" },
    { path = "lib/net.lua", source = "lib/net.lua" },
    { path = "lib/ui.lua", source = "lib/ui.lua" },
    { path = "lib/update.lua", source = "lib/update.lua" },
    { path = "installer.lua", source = "startup.lua" },
    { path = "bank_server.lua", source = "bank_server.lua" },
}

-- Repairs a Bank that cannot reach its own updater. This must replace the
-- whole runtime before claiming the new version: bumping config.lua while a
-- shared library stayed behind makes the Bank advertise a release it is not
-- running, and it then serves clients a new program beside an old library.
local function repairInstalledBankRuntime()
    if bootRoleId ~= "bank" or not publicManifest then return false end
    if newerVersion(installedVersion(), publicManifest.version) then return false end
    cleanupLegacyBankDuplicates()

    local needsVersionUpdate = newerVersion(
        publicManifest.version, installedVersion())
    local complete = true
    for _, file in ipairs(BANK_RUNTIME_REPAIR) do
        local entry = manifestEntry(publicManifest, file.source)
        if not replaceInstalledFile(entry, fs.combine(INSTALL_ROOT, file.path)) then
            complete = false
        end
    end
    if complete and needsVersionUpdate then
        updateInstalledConfigVersion(publicManifest.version)
    end
    return complete
end

local function formatBytes(value)
    if value >= 1024 then return string.format("%.1f KiB", value / 1024) end
    return value .. " B"
end

-- Only the changing rows are repainted. Clearing the whole screen for every
-- 6 KiB chunk made the install screen flicker and hid the progress bar.
local progressChrome
local progressSource
local function renderProgress(role, file, completed, total, fileIndex, fileCount)
    local width, height = target.getSize()
    local barWidth = math.max(8, width - 6)
    local barY = math.max(10, math.min(height - 4, 11))
    if progressChrome ~= role.label then
        progressChrome = role.label
        clear()
        header("INSTALLING " .. role.label,
            progressSource or "Receiving from the Bank Server")
        fill(4, barY, barWidth, 2, theme.panel)
    end
    fill(2, 6, width - 2, 1, theme.background)
    center(6, truncate(file.path, width - 4), theme.ink)
    fill(2, 8, width - 2, 1, theme.background)
    center(8, formatBytes(completed) .. " / " .. formatBytes(total), theme.muted)
    local filled = total > 0 and math.floor(barWidth * completed / total) or 0
    fill(4, barY, math.max(0, filled), 2, theme.accent)
    local percent = total > 0 and math.floor(completed / total * 100) or 0
    fill(2, barY + 3, width - 2, 1, theme.background)
    center(barY + 3, percent .. "%  -  file " .. fileIndex .. "/" .. fileCount,
        theme.accent)
end

local function retryDeployRequest(action, payload)
    local lastError, lastCode
    for _ = 1, 3 do
        local result, err, code = deployRequest(action, payload, 8)
        if result then return result end
        lastError, lastCode = err, code
        sleep(0.2)
    end
    return nil, lastError, lastCode
end

local function downloadManifestFile(role, accessCode, file,
    completedBefore, totalBytes, fileIndex, fileCount)
    if not safeRelativePath(file.path)
        or type(file.size) ~= "number" or file.size < 0
        or type(file.checksum) ~= "string" then
        return nil, "Bank Server returned an unsafe manifest"
    end
    local stagingPath = fs.combine(STAGING_ROOT, file.path)
    ensureParent(stagingPath)
    local handle = fs.open(stagingPath, "w")
    if not handle then return nil, "Could not create " .. file.path end
    local offset = 0
    while offset < file.size do
        renderProgress(role, file, completedBefore + offset,
            totalBytes, fileIndex, fileCount)
        local chunk, err = retryDeployRequest("FILE_CHUNK", {
            role = role.id,
            code = accessCode,
            path = file.path,
            offset = offset,
            limit = 6000,
        })
        if not chunk then
            handle.close()
            return nil, err
        end
        if chunk.path ~= file.path or chunk.offset ~= offset
            or type(chunk.data) ~= "string"
            or type(chunk.next_offset) ~= "number"
            or chunk.next_offset ~= offset + #chunk.data
            or chunk.next_offset > file.size
            or (#chunk.data == 0 and offset < file.size) then
            handle.close()
            return nil, "Bank Server returned an invalid file chunk"
        end
        handle.write(chunk.data)
        offset = chunk.next_offset
    end
    handle.close()
    local body = readFile(stagingPath)
    if not body or #body ~= file.size or checksum(body) ~= file.checksum then
        return nil, "Checksum failed for " .. file.path
    end
    return true
end

local function moveWithParent(source, destination)
    ensureParent(destination)
    fs.move(source, destination)
end

local function commitInstallation(manifest)
    if fs.exists(BACKUP_ROOT) then fs.delete(BACKUP_ROOT) end
    fs.makeDir(BACKUP_ROOT)
    local committed = {}
    local ok, err = pcall(function()
        for _, file in ipairs(manifest.files) do
            local destination = fs.combine(INSTALL_ROOT, file.path)
            local staged = fs.combine(STAGING_ROOT, file.path)
            if fs.exists(destination) then
                local backup = fs.combine(BACKUP_ROOT, file.path)
                moveWithParent(destination, backup)
            end
            moveWithParent(staged, destination)
            committed[#committed + 1] = file.path
        end
    end)
    if not ok then
        for _, path in ipairs(committed) do
            local destination = fs.combine(INSTALL_ROOT, path)
            if fs.exists(destination) then fs.delete(destination) end
        end
        for _, file in ipairs(manifest.files) do
            local backup = fs.combine(BACKUP_ROOT, file.path)
            local destination = fs.combine(INSTALL_ROOT, file.path)
            if fs.exists(backup) then moveWithParent(backup, destination) end
        end
        return nil, tostring(err)
    end
    fs.delete(STAGING_ROOT)
    fs.delete(BACKUP_ROOT)
    return true
end

local writeStartup

local BANK_LOCAL_FILES = {
    { path = "bank_server.lua", source = "bank_server.lua" },
    { path = "pumpe.lua", source = "pumpe.lua", depot = true },
    { path = "service_kiosk.lua", source = "service_kiosk.lua", depot = true },
    { path = "event_kiosk.lua", source = "event_kiosk.lua", depot = true },
    { path = "tax_controller.lua", source = "tax_controller.lua", depot = true },
    { path = "border_controller.lua", source = "border_controller.lua", depot = true },
    { path = "ccg.lua", source = "ccg.lua", depot = true },
    { path = "installer.lua", source = "startup.lua" },
    { path = "config.lua", source = "config.lua" },
    { path = "lib/net.lua", source = "lib/net.lua" },
    { path = "lib/ui.lua", source = "lib/ui.lua" },
    { path = "lib/update.lua", source = "lib/update.lua" },
    { path = "lib/util.lua", source = "lib/util.lua" },
}

local function localBankSourceRoot()
    local runningPath = shell.getRunningProgram() or ""
    local runningRoot = fs.getDir(runningPath)
    if runningRoot == "" then runningRoot = "." end
    local candidates = {
        runningRoot, ".", "/", "/disk", "/disk/pumpe", INSTALL_ROOT,
    }
    local seen = {}
    for _, candidate in ipairs(candidates) do
        if not seen[candidate] then
            seen[candidate] = true
            local complete = true
            for _, file in ipairs(BANK_LOCAL_FILES) do
                local source = fs.combine(candidate, file.source)
                if not fs.exists(source) or fs.isDir(source) then
                    complete = false
                    break
                end
            end
            if complete then return candidate end
        end
    end
    return nil
end

local function bankDestination(file)
    return fs.combine(file.depot and UPDATES_ROOT or INSTALL_ROOT, file.path)
end

local function bankStagePath(file, root)
    return fs.combine(root, (file.depot and "depot/" or "runtime/") .. file.path)
end

local function normalizedPath(path)
    return fs.combine("/", tostring(path or ""))
end

local function sameDrive(sourceRoot)
    if type(fs.getDrive) ~= "function" then return false end
    local sourceProbe = fs.combine(sourceRoot, BANK_LOCAL_FILES[1].source)
    local okSource, sourceDrive = pcall(fs.getDrive, sourceProbe)
    local okInstall, installDrive = pcall(fs.getDrive, INSTALL_ROOT)
    return okSource and okInstall and sourceDrive ~= nil
        and sourceDrive == installDrive
end

local function cleanEmptySourceFolders(sourceRoot)
    if type(fs.list) ~= "function" then return end
    local library = fs.combine(sourceRoot, "lib")
    if fs.exists(library) and fs.isDir(library) and #fs.list(library) == 0 then
        pcall(fs.delete, library)
    end
    if normalizedPath(sourceRoot) ~= "/" and fs.exists(sourceRoot)
        and fs.isDir(sourceRoot) and #fs.list(sourceRoot) == 0 then
        pcall(fs.delete, sourceRoot)
    end
end

local function installLocalBank(role)
    local sourceRoot = localBankSourceRoot()
    if not sourceRoot then
        message("error", "LOCAL BANK FILES MISSING",
            "Allow HTTP, or keep the release beside installer.lua", 2.2)
        return false
    end
    local manifest = { version = INSTALLER_VERSION, files = {} }
    local totalBytes = 0
    for _, file in ipairs(BANK_LOCAL_FILES) do
        local body = readFile(fs.combine(sourceRoot, file.source))
        if not body then
            message("error", "LOCAL INSTALL FAILED",
                "Could not read " .. file.source, 1.8)
            return false
        end
        local item = {
            path = file.path,
            size = #body,
            checksum = checksum(body),
            source = file.source,
            depot = file.depot == true,
        }
        manifest.files[#manifest.files + 1] = item
        totalBytes = totalBytes + #body
    end
    local configBody = readFile(fs.combine(sourceRoot, "config.lua")) or ""
    manifest.version = configBody:match('version%s*=%s*"([^"]+)"')
        or INSTALLER_VERSION
    renderProgress(role, { path = "Local release verified" },
        totalBytes, totalBytes, #manifest.files, #manifest.files)

    if not fs.exists(INSTALL_ROOT) then fs.makeDir(INSTALL_ROOT) end
    if not fs.exists(UPDATES_ROOT) then fs.makeDir(UPDATES_ROOT) end
    if fs.exists(STAGING_ROOT) then fs.delete(STAGING_ROOT) end
    if fs.exists(BACKUP_ROOT) then fs.delete(BACKUP_ROOT) end
    fs.makeDir(STAGING_ROOT)
    fs.makeDir(BACKUP_ROOT)

    local moveSourceFiles = sameDrive(sourceRoot)
    local installed = {}
    local committed, commitError = pcall(function()
        for _, file in ipairs(manifest.files) do
            local source = fs.combine(sourceRoot, file.source)
            local destination = bankDestination(file)
            if normalizedPath(source) == normalizedPath(destination) then
                installed[#installed + 1] = {
                    file = file, source = source, destination = destination,
                    unchanged = true,
                }
            else
                local backup = bankStagePath(file, BACKUP_ROOT)
                local item = {
                    file = file, source = source, destination = destination,
                    backup = backup, moved = moveSourceFiles,
                }
                installed[#installed + 1] = item
                if fs.exists(destination) then
                    moveWithParent(destination, backup)
                    item.backedUp = true
                end
                if moveSourceFiles then
                    moveWithParent(source, destination)
                else
                    local body = assert(readFile(source), "Missing " .. file.source)
                    local staged = bankStagePath(file, STAGING_ROOT)
                    local written, writeError = writeFile(staged, body)
                    assert(written, writeError)
                    moveWithParent(staged, destination)
                end
                item.newInstalled = true
                assert(readFile(destination)
                    and checksum(readFile(destination)) == file.checksum,
                    "Verification failed for " .. file.path)
            end
        end
    end)
    if not committed then
        for index = #installed, 1, -1 do
            local item = installed[index]
            if item.newInstalled and fs.exists(item.destination) then
                if item.moved then
                    moveWithParent(item.destination, item.source)
                else
                    fs.delete(item.destination)
                end
            end
            if item.backedUp and item.backup and fs.exists(item.backup) then
                moveWithParent(item.backup, item.destination)
            end
        end
        if fs.exists(STAGING_ROOT) then fs.delete(STAGING_ROOT) end
        if fs.exists(BACKUP_ROOT) then fs.delete(BACKUP_ROOT) end
        message("error", "LOCAL INSTALL ROLLED BACK", tostring(commitError), 2)
        return false
    end
    fs.delete(STAGING_ROOT)
    fs.delete(BACKUP_ROOT)

    local _, startupMessage = writeStartup(role)
    if moveSourceFiles then
        local extraInstaller = fs.combine(sourceRoot, "installer.lua")
        local installedInstaller = fs.combine(INSTALL_ROOT, "installer.lua")
        if normalizedPath(extraInstaller) ~= normalizedPath(installedInstaller)
            and fs.exists(extraInstaller) then
            local body = readFile(extraInstaller)
            if body and checksum(body) == checksum(readFile(installedInstaller) or "") then
                pcall(fs.delete, extraInstaller)
            end
        end
        cleanEmptySourceFolders(sourceRoot)
    end
    message("success", "BANK SERVER READY",
        startupMessage .. " - starting now", 0.8)
    return true
end

-- The first Bank in a world has nothing to download from, which used to mean
-- keeping the whole release on a disk beside the installer. The public
-- manifest is the same verified list of files, so fetch the Bank's runtime
-- straight from it. Depot programs are deliberately left out: the Bank pulls
-- each one on demand the first time somebody installs that role.
local BANK_MANIFEST_FILES = {
    { path = "bank_server.lua", source = "bank_server.lua" },
    { path = "installer.lua", source = "startup.lua" },
    { path = "config.lua", source = "config.lua" },
    { path = "lib/net.lua", source = "lib/net.lua" },
    { path = "lib/ui.lua", source = "lib/ui.lua" },
    { path = "lib/update.lua", source = "lib/update.lua" },
    { path = "lib/util.lua", source = "lib/util.lua" },
}

local function publicReleaseBase()
    local clean = PUBLIC_MANIFEST_URL:gsub("[?#].*$", "")
    return clean:match("^(https://.*/)[^/]+$")
end

local function loadPublicManifest()
    if publicManifest then return publicManifest end
    local body, err = fetchHttps(PUBLIC_MANIFEST_URL, 256 * 1024)
    if not body then return nil, err or "Could not reach the manifest" end
    local ok, manifest = pcall(textutils.unserializeJSON, body)
    if not ok or type(manifest) ~= "table" then
        return nil, "The release manifest is not valid JSON"
    end
    publicManifest = manifest
    return manifest
end

-- Returns the installed release, or nil plus a reason so the caller can fall
-- back to a local package.
local function installBankFromManifest(role)
    clear()
    header("BANK SERVER", "Checking the release")
    center(8, "Reading the manifest...", theme.accent)
    local manifest, manifestError = loadPublicManifest()
    if not manifest then return nil, manifestError end
    local base = publicReleaseBase()
    if not base then return nil, "The manifest URL has no release folder" end

    local files, totalBytes = {}, 0
    for _, file in ipairs(BANK_MANIFEST_FILES) do
        local entry = manifestEntry(manifest, file.source)
        if not entry then return nil, "Release is missing " .. file.source end
        entry.path = file.path
        files[#files + 1] = entry
        totalBytes = totalBytes + entry.size
    end

    if not fs.exists(INSTALL_ROOT) then fs.makeDir(INSTALL_ROOT) end
    if not fs.exists(UPDATES_ROOT) then fs.makeDir(UPDATES_ROOT) end
    if fs.exists(STAGING_ROOT) then fs.delete(STAGING_ROOT) end
    if fs.exists(BACKUP_ROOT) then fs.delete(BACKUP_ROOT) end
    fs.makeDir(STAGING_ROOT)

    local function fail(reason)
        if fs.exists(STAGING_ROOT) then fs.delete(STAGING_ROOT) end
        return nil, reason
    end

    progressChrome, progressSource = nil, "Downloading the release"
    local completed = 0
    for index, entry in ipairs(files) do
        renderProgress(role, entry, completed, totalBytes, index, #files)
        local body, err = fetchHttps(base .. entry.source, entry.size + 1)
        if not body then
            return fail(err or ("Could not download " .. entry.source))
        end
        cooperativeYield()
        if #body ~= entry.size or checksum(body) ~= entry.checksum then
            return fail("Verification failed for " .. entry.path)
        end
        local written, writeError =
            writeFile(fs.combine(STAGING_ROOT, entry.path), body)
        if not written then return fail(tostring(writeError)) end
        completed = completed + entry.size
        renderProgress(role, entry, completed, totalBytes, index, #files)
    end

    local release = { version = tostring(manifest.version), files = files }
    local committed, commitError = commitInstallation(release)
    if not committed then return fail(tostring(commitError)) end
    progressSource = nil
    return release
end

writeStartup = function(role)
    local startupPath = "/startup.lua"
    local installerMarker = "-- PUMPE EASY DEPLOYMENT"
    local roleMarker = "-- PUMPE ROLE STARTUP"
    local body = roleMarker .. "\n"
        .. "shell.run(\"/pumpe/installer.lua\", \"--boot\", \""
        .. role.id .. "\")\n"
    if not fs.exists(startupPath) then
        local handle = fs.open(startupPath, "w")
        if not handle then return false, "Could not create /startup.lua" end
        handle.write(body)
        handle.close()
        return true, "Startup created"
    end
    local existing = readFile(startupPath) or ""
    if existing:find(installerMarker, 1, true)
        or existing:find(roleMarker, 1, true) then
        local handle = fs.open(startupPath, "w")
        if not handle then return false, "Could not update /startup.lua" end
        handle.write(body)
        handle.close()
        return true, "Startup updated"
    end
    return false, "Existing startup preserved"
end

local function successScreen(role, manifest, startupMessage)
    local width, height = target.getSize()
    while true do
        clear()
        header("INSTALL COMPLETE", role.label)
        fill(3, 5, width - 5, 7, theme.success)
        center(6, "READY", colors.black, theme.success)
        center(8, #manifest.files .. " required files verified",
            colors.black, theme.success)
        center(10, "Version " .. tostring(manifest.version),
            colors.black, theme.success)
        center(14, startupMessage, theme.muted)
        local buttons = {}
        local buttonWidth = math.max(8, math.floor((width - 5) / 2))
        button(buttons, "menu", 2, height - 2, buttonWidth, 2,
            "BACK TO MENU", theme.panel)
        button(buttons, "reboot", width - buttonWidth, height - 2,
            buttonWidth, 2, "REBOOT NOW", theme.accentDark)
        local bindings = {}
        if keys and keys.enter then bindings[keys.enter] = "reboot" end
        local action = waitForButton(buttons, bindings)
        if action == "reboot" then os.reboot() end
        if action == "menu" or action == "__terminate" then return end
    end
end

local function installRole(role, automatic)
    progressChrome = nil
    local accessCode
    if role.protected then
        accessCode = automatic and PROTECTED_CODE or protectedCode()
        if not accessCode then return end
        if accessCode ~= PROTECTED_CODE then
            message("error", "ACCESS DENIED", "The download code is incorrect", 1.2)
            return
        end
    end

    if role.id == "bank" then
        if automatic then return false end
        local function launch()
            running = false
            shell.run(fs.combine(INSTALL_ROOT, rolePrograms.bank))
            return true
        end
        local release, onlineError = installBankFromManifest(role)
        if release then
            local _, startupMessage = writeStartup(role)
            message("success", "BANK SERVER v" .. release.version,
                startupMessage .. " - starting now", 0.9)
            return launch()
        end
        -- No internet, or a manifest that cannot be used. A release sitting
        -- beside the installer still works, so say what went wrong and try.
        message("warning", "NO ONLINE RELEASE",
            tostring(onlineError or "Manifest unreachable"), 1.6)
        if installLocalBank(role) then return launch() end
        return false
    end

    if not automatic then
        clear()
        header("FINDING BANK SERVER", role.label)
        center(8, "Searching Rednet...", theme.accent)
    end
    if not discoverBank() then
        if automatic then return false end
        message("error", "BANK SERVER NOT FOUND",
            "Start the Bank Server and check the modem", 1.8)
        return
    end

    local manifest, err = retryDeployRequest("MANIFEST", {
        role = role.id,
        code = accessCode,
    })
    if not manifest then
        if automatic then return false end
        message("error", "DOWNLOAD REJECTED", err, 1.6)
        return
    end
    if type(manifest.files) ~= "table" or #manifest.files == 0 then
        if automatic then return false end
        message("error", "BAD MANIFEST", "Bank Server returned no files", 1.4)
        return
    end
    if automatic and not newerVersion(manifest.version, installedVersion()) then
        return false
    end

    if not fs.exists(INSTALL_ROOT) then fs.makeDir(INSTALL_ROOT) end
    if fs.exists(STAGING_ROOT) then fs.delete(STAGING_ROOT) end
    fs.makeDir(STAGING_ROOT)
    local totalBytes = 0
    for _, file in ipairs(manifest.files) do
        totalBytes = totalBytes + (tonumber(file.size) or 0)
    end
    local completed = 0
    for index, file in ipairs(manifest.files) do
        local ok, downloadError = downloadManifestFile(role, accessCode, file,
            completed, totalBytes, index, #manifest.files)
        if not ok then
            if fs.exists(STAGING_ROOT) then fs.delete(STAGING_ROOT) end
            message("error", "INSTALL FAILED", downloadError, 1.8)
            return
        end
        completed = completed + file.size
    end
    local committed, commitError = commitInstallation(manifest)
    if not committed then
        if fs.exists(STAGING_ROOT) then fs.delete(STAGING_ROOT) end
        message("error", "INSTALL ROLLED BACK", commitError, 1.8)
        return
    end
    local _, startupMessage = writeStartup(role)
    if automatic then
        message("success", "UPDATED TO v" .. tostring(manifest.version),
            "Restarting " .. role.label, 0.6)
        os.reboot()
        return true
    end
    successScreen(role, manifest, startupMessage)
    return true
end

math.randomseed((nowMs() + os.getComputerID() * 7919) % 2147483647)

-- Only an unassigned installer and the Bank Server need the public manifest.
-- Every installed client role receives installer.lua from the Bank's verified
-- depot, so booting one never waits on an HTTPS round trip.

-- The menu never opens on a stale Easy Deployment. A newer one installs
-- itself and reboots here, so roles added by a release are on the menu the
-- first time it is drawn rather than the second.
local function updateCheckScreen()
    local _, height = target.getSize()
    local middle = math.max(2, math.floor(height / 2))
    clear()
    center(middle - 1, "CHECKING FOR UPDATES", theme.ink)
    center(middle + 1, "Easy Deployment v" .. INSTALLER_VERSION, theme.muted)
    selfUpdateInstaller()
    repairInstalledBankRuntime()
    clear()
    local release = publicManifest and tostring(publicManifest.version or "")
    if not release or release == "" then
        center(middle - 1, "UPDATE CHECK OFFLINE", theme.warning)
        center(middle + 1, "Running v" .. INSTALLER_VERSION, theme.muted)
    elseif newerVersion(release, installedVersion()) then
        center(middle - 1, "RELEASE v" .. release, theme.accent)
        center(middle + 1, "Roles update as they start", theme.muted)
    else
        center(middle - 1, "UP TO DATE", theme.success)
        center(middle + 1, "Release v" .. release, theme.muted)
    end
    sleep(0.7)
end

if bootRoleId == "bank" then
    selfUpdateInstaller()
    repairInstalledBankRuntime()
end

if bootRoleId then
    local role = roleById(bootRoleId)
    if not role then
        message("error", "UNKNOWN ROLE", bootRoleId, 1.4)
        return
    end
    -- A standalone copy dropped at the computer root seeds the permanent
    -- boot manager. When it is already the installed one, skip the rewrite.
    local runningPath = shell.getRunningProgram()
    local installedInstaller = fs.combine(INSTALL_ROOT, "installer.lua")
    if normalizedPath(runningPath) ~= normalizedPath(installedInstaller) then
        local runningBody = readFile(runningPath)
        if runningBody
            and runningBody:find("-- PUMPE EASY DEPLOYMENT", 1, true) then
            writeFile(installedInstaller, runningBody)
        end
    end
    openModems()
    if role.id ~= "bank" then installRole(role, true) end
    writeStartup(role)
    local program = fs.combine(INSTALL_ROOT, rolePrograms[role.id])
    if not fs.exists(program) then
        message("error", "ROLE FILE MISSING",
            "Run Easy Deployment again", 2)
        return
    end
    shell.run(program)
    return
end

if automaticRoleId then
    if openModems() then
        local role = roleById(automaticRoleId)
        if role then installRole(role, true) end
    end
    return
end

boot()
updateCheckScreen()
openModems()

while running do
    local role, launch = roleMenu()
    if role and launch then
        local program = fs.combine(INSTALL_ROOT, rolePrograms[role.id])
        if fs.exists(program) then
            running = false
            shell.run(program)
        else
            message("error", "ROLE FILE MISSING", "Install it again first", 1.6)
        end
    elseif role then
        installRole(role)
    end
end

clear()
print("PUMPE installer closed.")
