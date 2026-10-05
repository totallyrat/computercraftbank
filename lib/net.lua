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

-- Turning the radio off. Settings on the PUMPE uses this to take the device
-- off the network entirely: everything that needs the Bank stops, and
-- nothing on the network can see the device either.
function net.closeModems()
    local closed = {}
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "modem" and rednet.isOpen(name) then
            rednet.close(name)
            closed[#closed + 1] = name
        end
    end
    return closed
end

function net.modemsOpen()
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "modem" and rednet.isOpen(name) then
            return true
        end
    end
    return false
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

-- Where the FoxyOS update screen is drawn when a call does not say: the
-- computer's own screen, unless the program sets this -- the CCG console
-- sets its monitor, where people are looking.
net.updateTarget = nil

function net.autoUpdate(config, role, root, client, options)
    options = options or {}
    if type(config) ~= "table" or config.auto_update == false then return false end
    role = string.lower(tostring(role or ""))
    if role == "" then return false end

    -- FoxyOS 14.1: a check against another manifest -- the beta one. It is
    -- timed on its own, and it never falls back to the Bank's depot: the
    -- Bank holds the release, not a beta, so asking it would install the
    -- release instead of what was looked for.
    local elsewhere = type(options.manifestUrl) == "string"
        and options.manifestUrl ~= ""
    local checkKey = elsewhere and (role .. "@" .. options.manifestUrl) or role

    -- A program from one release running beside a config.lua from another is
    -- a partial install. Do not wait for the manifest to move on: repair it
    -- at once, whatever the check interval says.
    local mismatched = not elsewhere and options.programVersion
        and options.programVersion ~= "0.0.0"
        and options.programVersion ~= config.version
    local interval = math.max(5,
        math.floor(tonumber(config.client_update_check_seconds)
            or config.update_check_seconds or 30)) * 1000
    local now = util.nowMs()
    if not options.force and not mismatched and lastAutoUpdateCheck[checkKey]
        and now - lastAutoUpdateCheck[checkKey] < interval then
        return false
    end
    lastAutoUpdateCheck[checkKey] = now

    if mismatched then
        net.lastUpdateError = "installed " .. tostring(options.programVersion)
            .. " beside config " .. tostring(config.version)
        -- The release is not newer, so only a fresh install repairs this.
        if depotUpdate(config, role, root, nil) then return true end
    end

    local updater = loadUpdater()

    -- FoxyOS 12: every device shows the same screen while a release comes
    -- down (lib/ui's, when it has one new enough). The bar follows the files.
    local function underScreen(found, work)
        local okUi, ui = pcall(require, "lib.ui")
        local target = options.target or net.updateTarget
            or (type(term) == "table" and type(term.current) == "function"
                and term.current()) or nil
        local function progressOf(progress)
            return function(file, index, count)
                if progress then progress((index - 1) / math.max(1, count)) end
                if options.onProgress then
                    pcall(options.onProgress, file, index, count)
                end
            end
        end
        if not okUi or type(ui) ~= "table" or type(ui.updating) ~= "function"
            or not target or options.screen == false then
            return work(progressOf(nil), nil)
        end
        -- FoxyOS 14: a device can bring a screen of its own (the Pocket's
        -- circles). It takes the same arguments as ui.updating.
        local updating = type(options.updating) == "function" and options.updating
            or ui.updating
        return updating(target, function(progress)
            return work(progressOf(progress), progress)
        end, options.note or found.label
            or ("FoxyOS " .. tostring(found.version)))
    end

    -- Ask-first. A device with somebody in front of it installs nothing until
    -- they say so. FoxyOS 12 downloads first and asks after -- Install, or
    -- Cancel & Delete -- so the question is about something that is already
    -- here. Unattended roles pass no confirm and keep updating themselves,
    -- because there is nobody there to ask.
    if options.confirm then
        local found, why = nil, nil
        if updater and type(updater.check) == "function" then
            found, why = updater.check({
                config = config, role = role, root = root,
                requiredPaths = options.requiredPaths,
                optionalPaths = options.optionalPaths,
                manifestUrl = elsewhere and options.manifestUrl or nil,
                channel = options.channel, beta = options.beta,
            })
        end
        -- Already on the newest release is a settled answer, and so is a
        -- beta this device did not sign up for. Anything else means the
        -- manifest could not be read, which is the one case worth spending
        -- a request on the Bank over.
        if found == false and (why == "current" or why == "beta") then
            return false
        end
        if not found and elsewhere then
            net.lastUpdateError = why
            return false
        end
        if not found then
            -- No manifest, so nothing to download first. The Bank still
            -- knows what release it is running, and asking about a version
            -- is better than not asking at all.
            local ping = client and client:request("PING", {}, 3)
            if not ping or not net.isNewerVersion(ping.version, config.version)
            then
                return false
            end
            found = { version = ping.version, changes = {}, depot = true }
        end
        local stages = not found.depot and updater
            and type(updater.stage) == "function"
        if stages then
            local staged, detail = underScreen(found, function(onProgress, progress)
                local ok, why = updater.stage(found, {
                    config = config, role = role, root = root,
                    onProgress = onProgress,
                    onSpaceNeeded = options.onSpaceNeeded,
                })
                if ok and progress then progress(1) end
                return ok, why
            end)
            if not staged then
                net.lastUpdateError = detail
                return false
            end
        end
        -- A crash while asking is not a yes. Wrapped so a broken screen
        -- cannot take the device down, and so the answer it failed to give
        -- throws the download away rather than installing it.
        local askedOk, wanted = pcall(options.confirm, found)
        if not askedOk or not wanted then
            if stages then updater.discard(root) end
            return false
        end
        if stages then
            local committed, detail = updater.commit(found, { root = root })
            if committed then
                if options.onInstalled then pcall(options.onInstalled, detail) end
                os.reboot()
                return true
            end
            net.lastUpdateError = detail
            updater.discard(root)
            return false
        end
        return depotUpdate(config, role, root, nil)
    end

    if updater then
        local found, why = updater.check({
            config = config,
            role = role,
            root = root,
            -- Unattended, a device also fetches files its role lacks (see
            -- update.missingFiles). A phone is not asked: nothing is new.
            repair = true,
            requiredPaths = options.requiredPaths,
            optionalPaths = options.optionalPaths,
            manifestUrl = elsewhere and options.manifestUrl or nil,
            channel = options.channel, beta = options.beta,
        })
        if found then
            local updated, detail = underScreen(found, function(onProgress, progress)
                local ok, result = updater.apply(found, {
                    config = config, role = role, root = root,
                    onProgress = onProgress,
                })
                if ok and progress then progress(1) end
                return ok, result
            end)
            if updated then
                if options.onInstalled then pcall(options.onInstalled, detail) end
                os.reboot()
                return true
            end
            net.lastUpdateError = detail
        elseif why == "current" or why == "disabled" or why == "beta" then
            -- Settled answers.
            return false
        else
            -- The internet was unreachable: try the Bank's depot instead.
            net.lastUpdateError = why
        end
    end
    if elsewhere then return false end
    return depotUpdate(config, role, root, client)
end

return net
