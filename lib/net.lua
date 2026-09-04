local util = require("lib.util")

local net = {}
local lastAutoUpdateCheck = {}

function net.openModems()
    local opened = {}
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "modem" and not rednet.isOpen(name) then
            rednet.open(name)
            opened[#opened + 1] = name
        elseif peripheral.getType(name) == "modem" then
            opened[#opened + 1] = name
        end
    end
    if #opened == 0 then
        error("No modem found. Attach a wireless or Ender modem.")
    end
    return opened
end

function net.host(protocol, hostname)
    net.openModems()
    pcall(rednet.unhost, protocol)
    rednet.host(protocol, hostname)
end

local Client = {}
Client.__index = Client

function net.client(config)
    net.openModems()
    return setmetatable({
        protocol = config.protocol,
        hostname = config.hostname,
        serverId = nil,
        onPush = nil,
    }, Client)
end

function Client:discover()
    self.serverId = rednet.lookup(self.protocol, self.hostname)
    return self.serverId
end

function Client:isOnline()
    return self.serverId ~= nil
end

function Client:request(action, payload, timeout)
    timeout = timeout or 5
    if not self.serverId and not self:discover() then
        return nil, "Bank server is offline"
    end

    local requestId = util.token("REQ")
    local packet = {
        version = 5,
        kind = "request",
        request_id = requestId,
        action = action,
        payload = payload or {},
        sent_at = util.nowMs(),
    }

    if not rednet.send(self.serverId, packet, self.protocol) then
        self.serverId = nil
        return nil, "Could not reach bank server"
    end

    local deadline = util.nowMs() + timeout * 1000
    while util.nowMs() < deadline do
        local remaining = math.max(0.05, (deadline - util.nowMs()) / 1000)
        local sender, message = rednet.receive(self.protocol, remaining)
        if sender and type(message) == "table" then
            if message.kind == "response" and message.request_id == requestId then
                if message.ok then return message.data end
                return nil, message.error or "Request rejected", message.code
            elseif message.kind == "push" and self.onPush then
                pcall(self.onPush, message)
            end
        end
    end
    self.serverId = nil
    return nil, "Bank server timed out"
end

function net.reply(recipient, protocol, requestId, ok, data, err, code)
    rednet.send(recipient, {
        version = 5,
        kind = "response",
        request_id = requestId,
        ok = ok == true,
        data = data,
        error = err,
        code = code,
        sent_at = util.nowMs(),
    }, protocol)
end

-- GPS ----------------------------------------------------------------------
-- ComputerCraft resolves a position by trilaterating four hosts, so a network
-- with no constellation cannot locate anything until anchors exist.
local CHANNEL_GPS = 65534
local lastFix, lastFixAt

function net.locate(timeout, maxAgeMs)
    if type(gps) ~= "table" or type(gps.locate) ~= "function" then return nil end
    local now = util.nowMs()
    if lastFix and lastFixAt and now - lastFixAt < (maxAgeMs or 10000) then
        return lastFix
    end
    local ok, x, y, z = pcall(gps.locate, timeout or 2)
    if not ok or type(x) ~= "number" then return nil end
    lastFix = { x = x, y = y, z = z }
    lastFixAt = now
    return lastFix
end

function net.gpsChannel() return CHANNEL_GPS end

-- Answers the same PING that ComputerCraft's own `gps host` answers, so any
-- vanilla program locating itself sees these anchors too.
function net.gpsHost(position, isRunning)
    local modems = {}
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "modem" then
            local modem = peripheral.wrap(name)
            if modem and modem.isWireless and modem.isWireless() then
                modem.open(CHANNEL_GPS)
                modems[#modems + 1] = modem
            end
        end
    end
    if #modems == 0 then return 0 end
    local served = 0
    while isRunning == nil or isRunning() do
        local event, _, channel, replyChannel, message =
            os.pullEvent("modem_message")
        if channel == CHANNEL_GPS and message == "PING" then
            for _, modem in ipairs(modems) do
                modem.transmit(replyChannel, CHANNEL_GPS,
                    { position.x, position.y, position.z })
            end
            served = served + 1
        end
    end
    return served
end

local function versionParts(value)
    local major, minor, patch = tostring(value or ""):match(
        "^(%d+)%.(%d+)%.(%d+)")
    if not major then return nil end
    return tonumber(major), tonumber(minor), tonumber(patch)
end

function net.isNewerVersion(candidate, current)
    local a, b, c = versionParts(candidate)
    local x, y, z = versionParts(current)
    if not a or not x then return false end
    if a ~= x then return a > x end
    if b ~= y then return b > y end
    return c > z
end

-- Every role updates itself straight from the public manifest, downloading
-- only the files it needs. The Bank Server's rednet depot stays as a fallback
-- for devices whose ComputerCraft HTTP access is switched off.
local function loadUpdater()
    local ok, updater = pcall(require, "lib.update")
    if ok and type(updater) == "table"
        and type(updater.selfUpdate) == "function" then
        return updater
    end
    return nil
end

local function depotUpdate(config, role, root, client)
    if type(shell) ~= "table" or type(shell.run) ~= "function" then return false end
    if client then
        local ping = client:request("PING", {}, 3)
        if not ping or not net.isNewerVersion(ping.version, config.version) then
            return false
        end
    end
    local installer = fs.combine(root or "/pumpe", "installer.lua")
    if not fs.exists(installer) or fs.isDir(installer) then return false end
    local ok, result = pcall(shell.run, installer, "--auto", role)
    return ok and result ~= false
end

function net.autoUpdate(config, role, root, client, options)
    options = options or {}
    if type(config) ~= "table" or config.auto_update == false then return false end
    role = string.lower(tostring(role or ""))
    if role == "" then return false end

    -- A program from one release running beside a config.lua from another is
    -- a partial install. Do not wait for the manifest to move on: repair it
    -- at once, whatever the check interval says.
    local mismatched = options.programVersion
        and options.programVersion ~= "0.0.0"
        and options.programVersion ~= config.version
    local interval = math.max(5,
        math.floor(tonumber(config.client_update_check_seconds)
            or config.update_check_seconds or 30)) * 1000
    local now = util.nowMs()
    if not options.force and not mismatched and lastAutoUpdateCheck[role]
        and now - lastAutoUpdateCheck[role] < interval then
        return false
    end
    lastAutoUpdateCheck[role] = now

    if mismatched then
        net.lastUpdateError = "installed " .. tostring(options.programVersion)
            .. " beside config " .. tostring(config.version)
        -- The release is not newer, so only a fresh install repairs this.
        if depotUpdate(config, role, root, nil) then return true end
    end

    local updater = loadUpdater()
    if updater then
        local updated, detail = updater.selfUpdate({
            config = config,
            role = role,
            root = root,
            requiredPaths = options.requiredPaths,
            optionalPaths = options.optionalPaths,
            onProgress = options.onProgress,
        })
        if updated then
            if options.onInstalled then pcall(options.onInstalled, detail) end
            os.reboot()
            return true
        end
        -- "current" and "disabled" are settled answers; anything else means
        -- the internet was unreachable, so try the Bank's depot instead.
        if detail == "current" or detail == "disabled" then return false end
        net.lastUpdateError = detail
    end
    return depotUpdate(config, role, root, client)
end

return net
