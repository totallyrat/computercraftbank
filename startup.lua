-- PUMPE EASY DEPLOYMENT
-- This file is intentionally standalone. It downloads every other required
-- script and library from the active Bank Server's /updates/ directory.

local DEPLOY_PROTOCOL = "PUMPE_DEPLOY_V5"
local DEPLOY_HOSTNAME = "PUMPE_UPDATES"
local PROTECTED_CODE = "4040"
local INSTALL_ROOT = "/pumpe"
local STAGING_ROOT = fs.combine(INSTALL_ROOT, ".deploy_tmp")
local BACKUP_ROOT = fs.combine(INSTALL_ROOT, ".deploy_backup")
local arguments = { ... }
local automaticRoleId = arguments[1] == "--auto"
    and string.lower(tostring(arguments[2] or "")) or nil

local target = term.current()
local bankId
local running = true

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
    { id = "bank", label = "BANK SERVER", detail = "Protected download", protected = true },
    { id = "tax", label = "TAX CONTROLLER", detail = "Protected download", protected = true },
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

local function roleMenu()
    local width, height = target.getSize()
    while running do
        clear()
        header("EASY DEPLOYMENT", "Choose this computer's role")
        local buttons = {}
        local startY = 4
        local rowHeight = math.max(2, math.floor((height - 4) / #roles))
        for index, role in ipairs(roles) do
            local y = startY + (index - 1) * rowHeight
            local label = role.label
            if width >= 38 then label = label .. "\n" .. role.detail end
            button(buttons, "role:" .. role.id, 2, y, width - 2,
                math.max(1, rowHeight - 1), label,
                role.protected and theme.warning
                    or index == 1 and theme.accentDark or theme.panel,
                role.protected and colors.black or colors.white)
            if role.protected and width < 38 then
                writeAt(width - 7, y, "[4040]", colors.black, theme.warning)
            end
        end
        button(buttons, "exit", 1, height, 6, 1, "EXIT", theme.panel)
        local bindings = {}
        for index, role in ipairs(roles) do
            bindings[tostring(index)] = "role:" .. role.id
        end
        local action = waitForButton(buttons, bindings)
        if action == "exit" or action == "__terminate" then
            running = false
            return nil
        end
        local id = action and action:match("^role:(.+)$")
        if id then
            for _, role in ipairs(roles) do
                if role.id == id then return role end
            end
        end
    end
end

local function checksum(body)
    local hash = 5381
    for index = 1, #body do
        hash = (hash * 33 + string.byte(body, index)) % 4294967296
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

local function formatBytes(value)
    if value >= 1024 then return string.format("%.1f KiB", value / 1024) end
    return value .. " B"
end

local function renderProgress(role, file, completed, total, fileIndex, fileCount)
    local width, height = target.getSize()
    clear()
    header("INSTALLING " .. role.label, fileIndex .. "/" .. fileCount .. " files")
    center(6, truncate(file.path, width - 4), theme.ink)
    center(8, formatBytes(completed) .. " / " .. formatBytes(total), theme.muted)
    local barWidth = math.max(8, width - 6)
    fill(4, 11, barWidth, 2, theme.panel)
    local filled = total > 0 and math.floor(barWidth * completed / total) or 0
    fill(4, 11, filled, 2, theme.accent)
    local percent = total > 0 and math.floor(completed / total * 100) or 0
    center(14, percent .. "%", theme.accent)
    center(height - 1, "Receiving from Bank Server...", theme.muted)
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

local function writeStartup(role)
    local startupPath = "/startup.lua"
    local marker = "-- PUMPE EASY DEPLOYMENT"
    local body = marker .. "\n"
        .. "shell.run(\"/pumpe/launcher.lua\", \"" .. role.id .. "\")\n"
    if not fs.exists(startupPath) then
        local handle = fs.open(startupPath, "w")
        if not handle then return false, "Could not create /startup.lua" end
        handle.write(body)
        handle.close()
        return true, "Startup created"
    end
    local existing = readFile(startupPath) or ""
    if existing:find(marker, 1, true) then
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
    local accessCode
    if role.protected then
        accessCode = automatic and PROTECTED_CODE or protectedCode()
        if not accessCode then return end
        if accessCode ~= PROTECTED_CODE then
            message("error", "ACCESS DENIED", "The download code is incorrect", 1.2)
            return
        end
    end

    if not automatic then
        clear()
        header("FINDING BANK SERVER", role.label)
        center(8, "Searching Rednet...", theme.accent)
    end
    if not discoverBank() then
        if automatic then return false end
        local detail = role.id == "bank"
            and "First Bank Server must be copied locally"
            or "Start the Bank Server and check the modem"
        message("error", "BANK SERVER NOT FOUND", detail, 1.8)
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
if automaticRoleId then
    if openModems() then
        local role = roleById(automaticRoleId)
        if role then installRole(role, true) end
    end
    return
end

boot()
if not openModems() then
    message("error", "NO MODEM", "Attach a wireless or Ender modem", 2)
    clear()
    return
end

while running do
    local role = roleMenu()
    if role then installRole(role) end
end

clear()
print("PUMPE installer closed.")
