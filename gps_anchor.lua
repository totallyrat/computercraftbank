-- PUMPE GPS Anchor.
-- ComputerCraft can only work out where something is by trilaterating four
-- hosts with known coordinates. A network with no constellation cannot locate
-- anything at all, so these anchors are the foundation Proximity Pay stands
-- on: place at least four, spread out, with at least one at a different
-- height, and every other device can then find itself.

local ROOT = fs.getDir(shell.getRunningProgram())
if ROOT == "" then ROOT = "." end
package.path = package.path .. ";" .. fs.combine(ROOT, "?.lua")
    .. ";" .. fs.combine(ROOT, "?/init.lua")

-- Stamped by tools/build_release_manifest.js. A program running beside a
-- config.lua from a different release means a partial install.
local PROGRAM_VERSION = "7.0.0"
local config = require("config")
local util = require("lib.util")
local net = require("lib.net")
local ui = require("lib.ui")

local target = term.current()
local devicePath = fs.combine(ROOT, "gps_anchor.dat")
local device = util.loadTable(devicePath, { x = nil, y = nil, z = nil })
local running = true
local served = 0

ui.usePhoneStyle(false)

local function saveDevice()
    util.saveTable(devicePath, device)
end

local function askCoordinate(label, hint)
    local raw = ui.input(target, label, {
        hint = hint,
        mode = "integer",
        maxLength = 7,
        minLength = 1,
    })
    if not raw then return nil end
    return tonumber(raw)
end

-- An anchor is only as good as the coordinates it is told. Read them from the
-- block's own position where a constellation already exists, otherwise ask.
local function setupAnchor()
    local fix = net.locate(2)
    if fix then
        if ui.confirm(target, "USE THIS POSITION",
            "Found " .. fix.x .. ", " .. fix.y .. ", " .. fix.z
                .. " from the existing constellation. Use it?",
            "USE", "TYPE IT") then
            device.x, device.y, device.z = fix.x, fix.y, fix.z
            saveDevice()
            return true
        end
    end
    ui.clear(target)
    ui.header(target, "ANCHOR POSITION", "Press F3 in game to read them")
    ui.wrappedText(target, 2, 5,
        "Enter this computer's own block coordinates. They must be exact, or"
        .. " every device that trusts this anchor will be wrong too.",
        select(1, target.getSize()) - 2, 6, ui.theme.muted)
    sleep(1.4)
    local x = askCoordinate("ANCHOR X", "Block X coordinate")
    if not x then return false end
    local y = askCoordinate("ANCHOR Y", "Block Y coordinate")
    if not y then return false end
    local z = askCoordinate("ANCHOR Z", "Block Z coordinate")
    if not z then return false end
    device.x, device.y, device.z = x, y, z
    saveDevice()
    return true
end

local function hostLoop()
    net.gpsHost(device, function() return running end)
end

local function screenLoop()
    local blink, tick = true, 0
    while running do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "PUMPE GPS ANCHOR", "v" .. config.version,
            util.formatClock(blink))
        ui.card(target, 2, 5, width - 2, 4, ui.theme.success)
        ui.text(target, 4, 6, "SERVING POSITION", ui.theme.muted, ui.theme.panel)
        ui.text(target, 4, 7,
            device.x .. ", " .. device.y .. ", " .. device.z,
            ui.theme.ink, ui.theme.panel)
        ui.text(target, 2, 10, "Answered " .. served .. " location requests",
            ui.theme.muted)
        ui.wrappedText(target, 2, 12,
            "Four anchors in range, spread apart and not all at the same"
            .. " height, let any device locate itself.",
            width - 2, 3, ui.theme.muted)

        local scene = ui.scene(target)
        scene:button("move", 2, height - 3, math.max(10,
            math.floor((width - 3) / 2)), 2, "SET POSITION",
            { background = ui.theme.panel })
        scene:button("stop", width - math.max(10,
            math.floor((width - 3) / 2)), height - 3,
            math.max(10, math.floor((width - 3) / 2)), 2, "SHUT DOWN",
            { background = ui.theme.danger })
        local action = scene:wait({ tickRate = 1 })
        blink = not blink
        tick = tick + 1
        if action == "__tick" then
            net.autoUpdate(config, "anchor", ROOT, nil,
                { programVersion = PROGRAM_VERSION })
        elseif action == "move" then
            if setupAnchor() then
                ui.message(target, "success", "POSITION UPDATED", nil, 1)
            end
        elseif action == "stop" or action == "__terminate" then
            running = false
            return
        end
    end
end

ui.boot(target, "GPS ANCHOR", "PUMPE POSITIONING v" .. config.version)
net.autoUpdate(config, "anchor", ROOT, nil,
    { force = true, programVersion = PROGRAM_VERSION })

local wireless = false
for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then
        local modem = peripheral.wrap(name)
        if modem and modem.isWireless and modem.isWireless() then wireless = true end
    end
end
if not wireless then
    ui.message(target, "error", "NEEDS A WIRELESS MODEM",
        "GPS only works over wireless or Ender modems", 3)
    return
end

if not device.x and not setupAnchor() then
    ui.clear(target)
    print("GPS Anchor cancelled.")
    return
end

parallel.waitForAny(hostLoop, screenLoop)
ui.clear(target)
print("GPS Anchor stopped.")
