local ROOT = fs.getDir(shell.getRunningProgram())
if ROOT == "" then ROOT = "." end
package.path = package.path .. ";" .. fs.combine(ROOT, "?.lua")
    .. ";" .. fs.combine(ROOT, "?/init.lua")

-- Stamped by tools/build_release_manifest.js. A program running beside a
-- config.lua from a different release means a partial install.
local PROGRAM_VERSION = "8.2.0"
local config = require("config")
local util = require("lib.util")
local net = require("lib.net")
local ui = require("lib.ui")

local target = term.current()
local client = net.client(config)
local deviceFile = fs.combine(ROOT, "border_device.dat")
local device = util.loadTable(deviceFile, {})
local running = true

local function saveDevice()
    util.saveTable(deviceFile, device)
end

local function request(action, payload, silent)
    local result, err, code = client:request(action, payload or {})
    if not result and not silent then ui.networkError(target, err) end
    return result, err, code
end

local function controllerPayload()
    return {
        controller_id = device.controller_id,
        controller_token = device.controller_token,
    }
end

local function chooseTerritory(territories)
    local page = 1
    while true do
        local width, height = target.getSize()
        local visible, current, pages = util.page(territories, page, 3)
        page = current
        ui.clear(target)
        ui.header(target, "BORDER SETUP", "Choose the territory")
        local scene = ui.scene(target)
        for index, territory in ipairs(visible) do
            local y = 5 + (index - 1) * 4
            scene:button("territory:" .. territory.territory_id,
                2, y, width - 2, 3,
                territory.name .. "\n"
                    .. territory.citizen_count .. " citizen(s)", {
                    background = index == 1
                        and ui.theme.accentDark or ui.theme.panel,
                    shadow = true,
                })
        end
        if pages > 1 then
            ui.center(target, height - 2, page .. " / " .. pages,
                ui.theme.muted)
            scene:button("prev", 1, height, 7, 1, "< PREV", {
                background = ui.theme.panel,
                disabled = page == 1,
            })
            scene:button("next", width - 6, height, 7, 1, "NEXT >", {
                background = ui.theme.panel,
                disabled = page == pages,
            })
        else
            scene:button("back", 1, height, 8, 1, "< BACK", {
                background = ui.theme.panel,
            })
        end
        local action = scene:wait()
        local territoryId = action
            and action:match("^territory:(.+)$")
        if territoryId then
            for _, territory in ipairs(territories) do
                if territory.territory_id == territoryId then
                    return territory
                end
            end
        elseif action == "prev" then
            page = math.max(1, page - 1)
        elseif action == "next" then
            page = math.min(pages, page + 1)
        elseif action == "back" or action == "__terminate" then
            return nil
        end
    end
end

local function setupController()
    while running do
        local ownerName = ui.input(target, "BORDER SETUP", {
            hint = "Territory owner Foxy Account",
            maxLength = 20,
            minLength = 2,
            allowSpace = true,
        })
        if not ownerName then return false end
        local pin = ui.pin(target, "OWNER PIN", true)
        if not pin then return false end
        local login, loginError = request("LOGIN", {
            name = ownerName,
            pin = pin,
        }, true)
        if not login then
            ui.message(target, "error", "SIGN IN FAILED",
                loginError or "Check the account and PIN", 1.2)
        else
            local overview, overviewError = request("CUSTOMS_OVERVIEW", {
                session_token = login.session_token,
            }, true)
            if not overview then
                ui.message(target, "error", "CUSTOMS UNAVAILABLE",
                    overviewError or "Try again", 1.2)
            elseif #overview.territories == 0 then
                ui.message(target, "warning", "NO TERRITORY",
                    "Create one in the PUMPE Customs app first", 1.8)
                return false
            else
                local territory = chooseTerritory(overview.territories)
                if not territory then return false end
                local registered, registerError = request("BORDER_REGISTER", {
                    session_token = login.session_token,
                    territory_id = territory.territory_id,
                    label = "Border #" .. os.getComputerID(),
                }, true)
                if registered then
                    device = {
                        controller_id = registered.controller_id,
                        controller_token = registered.controller_token,
                        territory_id = registered.territory_id,
                        territory_name = registered.territory_name,
                        label = registered.label,
                    }
                    saveDevice()
                    ui.message(target, "success", "BORDER READY",
                        registered.territory_name, 1.2)
                    return true
                end
                ui.message(target, "error", "SETUP FAILED",
                    registerError or "Try again", 1.2)
            end
        end
    end
    return false
end

local function refreshStatus(silent)
    if not device.controller_id or not device.controller_token then return nil end
    local status, err, code = request("BORDER_STATUS", controllerPayload(), true)
    if status then
        device.territory_id = status.territory_id
        device.territory_name = status.territory_name
        device.label = status.label
        saveDevice()
        return status
    end
    if code == "BORDER_AUTH" or code == "BORDER_INACTIVE"
        or code == "TERRITORY_NOT_FOUND" then
        device = {}
        saveDevice()
    elseif not silent then
        ui.networkError(target, err)
    end
    return nil
end

local function checkingAnimation(direction)
    local width, height = target.getSize()
    for frame = 1, 4 do
        ui.clear(target)
        ui.header(target, direction == "exit" and "CHECKING EXIT"
            or "CHECKING ENTRY", device.territory_name)
        ui.center(target, math.floor(height / 2) - 1,
            "Contacting the border system", ui.theme.ink)
        ui.center(target, math.floor(height / 2) + 1,
            string.rep(".", frame), ui.theme.accent)
        ui.progress(target, 4, math.floor(height / 2) + 4, width - 7,
            frame, 4, ui.theme.accent, ui.theme.panel)
        sleep(0.08)
    end
end

local function authorizationLabel(kind)
    if kind == "citizenship" then return "CITIZENSHIP" end
    if kind == "free_roam" then return "FREE ROAM" end
    return "TEMPORARY VISA"
end

local function approvedScreen(result)
    local width, height = target.getSize()
    local function render(signalSeconds)
        ui.clear(target)
        local leaving = result.direction == "exit"
        ui.header(target, leaving and "EXIT APPROVED" or "ENTRY APPROVED",
            result.territory_name,
            util.formatClock())
        ui.card(target, 2, 5, width - 2, height - 8, ui.theme.success)
        ui.text(target, 4, 6, ui.truncate(result.traveler_name, width - 7),
            ui.theme.ink, ui.theme.panel)
        ui.text(target, 4, 8, authorizationLabel(result.authorization),
            ui.theme.success, ui.theme.panel)
        if leaving then
            ui.text(target, 4, 10, "VISIT CLOSED",
                ui.theme.ink, ui.theme.panel)
            ui.text(target, 4, 11, result.permanent
                and "PERMANENT CODE COOLDOWN ACTIVE"
                or "TEMPORARY VISA NOW LOCKED",
                ui.theme.muted, ui.theme.panel)
        elseif result.permanent then
            ui.text(target, 4, 10, "STAY  Permanent",
                ui.theme.ink, ui.theme.panel)
            ui.text(target, 4, 11, "NO DEPARTURE DATE",
                ui.theme.muted, ui.theme.panel)
        else
            ui.text(target, 4, 10,
                "STAY  " .. result.stay_days .. " day(s)",
                ui.theme.ink, ui.theme.panel)
            ui.text(target, 4, 11,
                "LEAVE BY DAY  " .. result.due_day,
                ui.theme.warning, ui.theme.panel)
        end
        if signalSeconds then
            ui.text(target, 4, height - 4,
                "GATE OPEN  " .. signalSeconds .. "s",
                colors.black, ui.theme.success)
        end
    end

    local signalOk, signalError = pcall(function()
        redstone.setOutput("back", true)
        for remaining = 5, 1, -1 do
            render(remaining)
            sleep(1)
        end
    end)
    pcall(redstone.setOutput, "back", false)
    if not signalOk then
        ui.message(target, "warning",
            result.direction == "exit" and "EXIT RECORDED" or "ENTRY RECORDED",
            "Back redstone failed: " .. tostring(signalError), 1.6)
    end

    while true do
        render()
        local scene = ui.scene(target)
        scene:button("done", width - 12, height - 1, 11, 1,
            "DONE", { background = ui.theme.accentDark })
        local action = scene:wait()
        if action == "done" or action == "__terminate" then return end
    end
end

local function checkVisa(direction)
    local entering = direction == "enter"
    local code = ui.input(target, entering and "ENTER TERRITORY"
        or "EXIT TERRITORY", {
        hint = "Eight characters",
        mode = "code",
        maxLength = 8,
        minLength = 8,
    })
    if not code then return end
    checkingAnimation(direction)
    local payload = controllerPayload()
    payload.code = code
    payload.direction = direction
    local result, err = request("BORDER_CHECK", payload, true)
    if not result then
        pcall(redstone.setOutput, "back", false)
        ui.message(target, "error", entering and "ENTRY DENIED" or "EXIT DENIED",
            err or "Travel document was rejected", 1.8)
        return
    end
    approvedScreen(result)
end

-- Proximity Visa. Left on, the gate keeps asking whoever is nearest with a
-- travel document on screen. Accepting runs the ordinary border check, so
-- entry rules are identical to typing the code in.
local function openGate(seconds)
    local ok, err = pcall(function()
        redstone.setOutput("back", true)
        sleep(seconds or 2)
    end)
    pcall(redstone.setOutput, "back", false)
    return ok, err
end

local function proximityVisaLoop()
    local requestId, status, detail, blink = nil, "SEARCHING", "", true
    local crossed = {}

    local function stop()
        if requestId then
            local payload = controllerPayload()
            payload.request_id = requestId
            request("VISA_SCAN_CANCEL", payload, true)
            requestId = nil
        end
    end

    local function beginScan()
        local payload = controllerPayload()
        payload.position = net.locate(1)
        local started, err = request("VISA_SCAN", payload, true)
        if not started then
            requestId, status = nil, "NOT SCANNING"
            detail = err or "No GPS fix at the gate"
            return
        end
        requestId = started.scan.request_id
        status = started.scan.status == "offered" and "ASKING" or "SEARCHING"
        detail = started.scan.target_name or "Nobody nearby with a visa up"
    end

    beginScan()
    while running and device.controller_id do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "PROXIMITY VISA",
            device.territory_name or "Territory", util.formatClock(blink))
        local accent = status == "CROSSED" and ui.theme.success
            or status == "REFUSED" and ui.theme.danger
            or status == "ASKING" and ui.theme.accent
            or ui.theme.panel
        ui.card(target, 2, 5, width - 2, 5, accent)
        ui.text(target, 4, 6, status, accent, ui.theme.panel, width - 6)
        ui.wrappedText(target, 4, 7, detail, width - 6, 2,
            ui.theme.ink, ui.theme.panel)
        ui.text(target, 2, 11, "CROSSINGS  " .. #crossed, ui.theme.muted)
        for index = 1, math.min(#crossed, height - 15) do
            ui.text(target, 2, 11 + index,
                ui.truncate(crossed[index], width - 3), ui.theme.ink)
        end
        local scene = ui.scene(target)
        scene:button("stop", 2, height - 2, width - 2, 2, "TURN OFF",
            { background = ui.theme.danger })
        local action = scene:wait({ tickRate = 1 })
        blink = not blink
        if action == "stop" or action == "__terminate" then
            stop()
            return
        end
        if action == "__tick" then
            net.autoUpdate(config, "border", ROOT, client)
            if not requestId then
                beginScan()
            else
                local payload = controllerPayload()
                payload.request_id = requestId
                local polled = request("VISA_SCAN_STATUS", payload, true)
                local scan = polled and polled.scan
                if not scan then
                    requestId = nil
                elseif scan.status == "accepted" then
                    status, detail = "CROSSED", scan.result or "Traveller through"
                    table.insert(crossed, 1, scan.result or "Traveller")
                    while #crossed > 6 do table.remove(crossed) end
                    requestId = nil
                    -- Two seconds of gate, as the PUMPE told them to expect.
                    openGate(2)
                elseif scan.status == "rejected" then
                    status, detail = "REFUSED", scan.result or "Document refused"
                    requestId = nil
                elseif scan.status == "nobody_nearby" then
                    status, detail = "SEARCHING",
                        "Nobody nearby has a visa up"
                    requestId = nil
                else
                    status = "ASKING"
                    detail = (scan.target_name or "Someone")
                        .. (scan.distance and ("  " .. scan.distance
                            .. " blocks") or "")
                end
            end
        end
    end
    stop()
end

local function ownerUnlock(reason)
    local pin = ui.pin(target, reason or "OWNER PIN", true)
    if not pin then return false end
    local payload = controllerPayload()
    payload.pin = pin
    local result, err = request("BORDER_OWNER_PIN", payload, true)
    if result then return true end
    ui.message(target, "error", "LOCKED",
        err or "Owner PIN is incorrect", 1.2)
    return false
end

local function dashboard()
    local blink, tick = true, 0
    while running and device.controller_id do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "BORDER CONTROLLER",
            device.territory_name or "Territory", util.formatClock(blink))
        ui.center(target, 4, "DAY " .. util.ingameDay(), ui.theme.muted)
        local scene = ui.scene(target)
        scene:button("enter", 3, 6, width - 5, 4,
            "ENTER TERRITORY\nScan VISA or Citizenship Code", {
                background = ui.theme.accentDark,
                shadow = true,
            })
        scene:button("exit", 3, 11, width - 5, 4,
            "EXIT TERRITORY\nClose the active visit", {
                background = ui.theme.success,
                foreground = colors.black,
                shadow = true,
            })
        scene:button("proximity", 3, 16, width - 5, 2,
            "PROXIMITY VISA  -  scan whoever walks up", {
                background = colors.purple,
            })
        scene:button("setup", 2, height - 1,
            math.max(12, math.floor((width - 6) / 2)), 2,
            "CHANGE TERRITORY", { background = ui.theme.panel })
        scene:button("stop", width - 11, height - 1, 10, 2,
            "CLOSE", { background = ui.theme.danger })
        local action = scene:wait({ tickRate = 1 })
        if action == "__tick" or action == "__idle" then
            blink = not blink
            tick = tick + 1
            net.autoUpdate(config, "border", ROOT, client)
            -- The clock blinks every second; visitor counts only need the
            -- Bank every five.
            if tick % 5 == 0 then refreshStatus(true) end
        elseif action == "enter" then
            checkVisa("enter")
        elseif action == "exit" then
            checkVisa("exit")
        elseif action == "proximity" then
            ui.wipe(target, "PROXIMITY VISA")
            proximityVisaLoop()
        elseif action == "setup" then
            if ownerUnlock("OWNER PIN TO CHANGE")
                and ui.confirm(target, "CHANGE TERRITORY",
                "Register this computer to a different territory?",
                "CHANGE", "BACK") then
                device = {}
                saveDevice()
                return
            end
        elseif action == "stop" or action == "__terminate" then
            if ownerUnlock("OWNER PIN TO CLOSE") then running = false end
        end
    end
end

pcall(redstone.setOutput, "back", false)
ui.boot(target, "PUMPE BORDER", "CUSTOMS GATE v" .. config.version)
-- Check for a new release at every restart, straight from the public
-- manifest. The Bank Server no longer has to hold a copy for us.
net.autoUpdate(config, "border", ROOT, client,
    { force = true, programVersion = PROGRAM_VERSION })
client:discover()

while running do
    if not refreshStatus(true) then
        if not setupController() then
            local width, height = target.getSize()
            ui.clear(target)
            ui.header(target, "BORDER CONTROLLER", "Setup required")
            local scene = ui.scene(target)
            scene:button("retry", 3, 7, width - 5, 4,
                "SET UP BORDER", {
                    background = ui.theme.accentDark,
                    shadow = true,
                })
            scene:button("stop", 3, 13, width - 5, 2,
                "CLOSE", { background = ui.theme.danger })
            local action = scene:wait({ tickRate = 2 })
            if action == "retry" then
                setupController()
            elseif action == "__tick" or action == "__idle" then
                net.autoUpdate(config, "border", ROOT, client)
            elseif action == "stop" or action == "__terminate" then
                running = false
            end
        end
    end
    if device.controller_id then dashboard() end
end

pcall(redstone.setOutput, "back", false)
ui.clear(target)
print("Border Controller closed safely.")
