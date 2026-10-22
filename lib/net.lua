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

local function autoUpdateOnce(config, role, root, client, options)
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
                -- FoxyOS 18.2: a device that used to update unattended still
                -- fetches the files its role lacks -- asking first now.
                repair = options.asked_by_default or nil,
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
        -- No manifest: the installer's own way round, which asks too.
        if not found and options.asked_by_default then
            net.lastUpdateError = why
            return depotUpdate(config, role, root, client)
        end
        -- FoxyOS 18.2: a release somebody said no to (or nobody answered
        -- about) is not downloaded again for half an hour, except at start-up.
        local declinedUntil = found and net.declined[tostring(found.version)]
        if declinedUntil and not options.force and util.nowMs() < declinedUntil then
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
            -- FoxyOS 15.1: a Bank on a beta is not a release to follow.
            if util.isBetaVersion(ping.version) and not options.beta then
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
            net.declined[tostring(found.version)] = util.nowMs() + 30 * 60 * 1000
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
                    -- FoxyOS 15.2: a Pocket that installs by itself can
                    -- make room too (Prioritize Updates).
                    onSpaceNeeded = options.onSpaceNeeded,
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

-- FoxyOS 18.2: what a device asks when it was handed no question of its
-- own -- which was every device but the Pocket. On its own screen, never a
-- customer's monitor; a device with no lib/ui new enough to ask installs as
-- it always did.
net.declined = {}
function net.askUpdate(found, options)
    local okUi, ui = pcall(require, "lib.ui")
    if not okUi or type(ui) ~= "table" or type(ui.askUpdate) ~= "function" then return true end
    local target = options.target or (type(term) == "table" and type(term.current) == "function"
        and term.current()) or nil
    if not target then return true end
    local size = tonumber(found.bytes)
    return ui.askUpdate(target, { word = "FOXY", title = found.label or "FoxyOS",
        version = found.version, what = size and (math.ceil(size / 1024) .. " KiB, downloaded")
            or "Downloaded" },
        { banner = not options.force, timeout = options.force and 60 or 600 })
end

function net.autoUpdate(config, role, root, client, options)
    options = options or {}
    if options.confirm == nil then
        local asked = {}
        for key, value in pairs(options) do asked[key] = value end
        asked.confirm = function(found) return net.askUpdate(found, asked) end
        asked.asked_by_default = true
        options = asked
    end
    local done = autoUpdateOnce(config, role, root, client, options)
    if done then return done end
    -- FoxyOS 15.1: every device signed up to Beta Updates looks at the beta
    -- manifest too, after the release, and takes a beta by itself the way
    -- it takes a release. The Pocket asks for itself: it says beta = ...,
    -- from its own Settings, and names the manifest.
    local url = type(config) == "table" and tostring(config.beta_manifest_url or "") or ""
    if options.manifestUrl == nil and options.beta == nil and url ~= ""
        and util.betaJoined(root) then
        local betaOptions = {}
        for key, value in pairs(options) do betaOptions[key] = value end
        betaOptions.manifestUrl, betaOptions.channel, betaOptions.beta = url, "beta", true
        betaOptions.programVersion = nil
        return autoUpdateOnce(config, role, root, client, betaOptions)
    end
    return done
end

-- FoxyCloud, FoxyOS 16.3 ------------------------------------------------------
-- A request to one computer in particular, rather than whichever answers a
-- name: a Cloud Server holds pieces nobody else has.
function net.ask(computerId, protocol, action, payload, timeout)
    timeout = timeout or 4
    local requestId = util.token("REQ")
    if not computerId or not rednet.send(computerId, {
        version = 5, kind = "request", request_id = requestId,
        action = action, payload = payload or {}, sent_at = util.nowMs(),
    }, protocol) then
        return nil, "Could not reach that computer", "UNREACHABLE"
    end
    local deadline = util.nowMs() + timeout * 1000
    while util.nowMs() < deadline do
        local remaining = math.max(0.05, (deadline - util.nowMs()) / 1000)
        local sender, message = rednet.receive(protocol, remaining)
        if sender == computerId and type(message) == "table"
            and message.kind == "response" and message.request_id == requestId then
            if message.ok then return message.data end
            return nil, message.error or "Request rejected", message.code
        end
    end
    return nil, "It did not answer", "TIMEOUT"
end

-- Moving a file's pieces, as the Bank's plan for it says. A Cloud Server
-- checking a ticket with the Bank is not listening for a moment, so a piece
-- that goes unanswered is asked for again before giving up.
net.cloud = { tries = 3 }

function net.cloud.ask(plan, serverId, action, payload, protocol)
    local host = type(plan.hosts) == "table" and plan.hosts[serverId]
    if not host then return nil, "A Cloud Server is missing", "CLOUD_OFFLINE" end
    local data, err, code
    for _ = 1, net.cloud.tries do
        data, err, code = net.ask(host, protocol, action, payload, 3)
        if data or code ~= "TIMEOUT" then break end
    end
    if not data and code == "TIMEOUT" then
        err, code = "A Cloud Server is not answering", "CLOUD_OFFLINE"
    end
    return data, err, code
end

-- Puts `body` where `plan` (CLOUD_PUT's answer) says, each piece on every
-- server it has a copy on.
function net.cloud.put(plan, body, protocol, progress)
    local offset = 0
    for index, chunk in ipairs(plan.chunks or {}) do
        local data = body:sub(offset + 1, offset + chunk.size)
        offset = offset + chunk.size
        for _, serverId in ipairs(chunk.servers) do
            local stored, err, code = net.cloud.ask(plan, serverId, "CHUNK_PUT",
                { ticket = plan.ticket, chunk_id = chunk.id, data = data }, protocol)
            if not stored then return nil, err, code end
        end
        if progress then progress(index, #plan.chunks) end
    end
    return true
end

-- Fetches what `plan` (CLOUD_GET's answer) points at, trying each copy of a
-- piece until one comes back whole.
function net.cloud.get(plan, protocol, progress)
    local parts = {}
    for index, chunk in ipairs(plan.chunks or {}) do
        local err, code
        for _, serverId in ipairs(chunk.servers) do
            local got
            got, err, code = net.cloud.ask(plan, serverId, "CHUNK_GET",
                { ticket = plan.ticket, chunk_id = chunk.id }, protocol)
            if got and type(got.data) == "string" and #got.data == chunk.size then
                parts[index] = got.data
                break
            elseif got then
                err, code = "A piece came back damaged", "CLOUD_DAMAGED"
            end
        end
        if not parts[index] then
            return nil, err or "A Cloud Server is not answering", code or "CLOUD_OFFLINE"
        end
        if progress then progress(index, #plan.chunks) end
    end
    return table.concat(parts)
end

-- The whole of saving and opening, given a way to ask the Bank:
-- request(action, payload) returning data, or nil, an error and a code.
-- `fields` is a name for a new file or the file_id of one to replace.
function net.cloud.save(request, fields, body, protocol, progress)
    body = tostring(body or "")
    local plan, err, code = request("CLOUD_PUT", { name = fields.name,
        file_id = fields.file_id, size = #body })
    if not plan then return nil, err, code end
    local ok, putError, putCode = net.cloud.put(plan, body, protocol, progress)
    if not ok then return nil, putError, putCode end
    return request("CLOUD_PUT_DONE", { file_id = plan.file_id,
        version = plan.version })
end

function net.cloud.load(request, fileId, protocol, progress)
    local plan, err, code = request("CLOUD_GET", { file_id = fileId })
    if not plan then return nil, err, code end
    local body, getError, getCode = net.cloud.get(plan, protocol, progress)
    if not body then return nil, getError, getCode end
    return body, plan.file
end

-- A shared file, by its code. Anybody with the code may open it.
function net.cloud.shared(request, code, protocol, progress)
    local plan, err, errCode = request("CLOUD_SHARED", { code = code })
    if not plan then return nil, err, errCode end
    local body, getError, getCode = net.cloud.get(plan, protocol, progress)
    if not body then return nil, getError, getCode end
    plan.file.owner_name = plan.owner_name
    return body, plan.file
end

-- What FoxyCloud is given on a Pocket, as api.cloud: saving, opening and
-- opening shared files, and the Pocket's own Downloads folder. `ask` asks the
-- Bank as the app; `offline()` is true while the modem is switched off.
function net.cloud.api(ask, protocol, offline, downloads)
    downloads = downloads or "/downloads"
    local function off()
        if offline and offline() then return nil, "Modem is off", "MODEM_OFF" end
        return true
    end
    local function here(name)
        return fs.combine(downloads, fs.getName(tostring(name or "")))
    end
    local api = {}
    function api.save(fields, body, progress)
        local ok, err, code = off()
        if not ok then return nil, err, code end
        return net.cloud.save(ask, type(fields) == "table" and fields or {},
            tostring(body or ""), protocol, progress)
    end
    function api.load(fileId, progress)
        local ok, err, code = off()
        if not ok then return nil, err, code end
        return net.cloud.load(ask, fileId, protocol, progress)
    end
    function api.shared(code, progress)
        local ok, err, errCode = off()
        if not ok then return nil, err, errCode end
        return net.cloud.shared(ask, code, protocol, progress)
    end
    function api.pocketFiles()
        local names = {}
        if fs.exists(downloads) and fs.isDir(downloads) then
            for _, name in ipairs(fs.list(downloads)) do
                if not fs.isDir(fs.combine(downloads, name)) then names[#names + 1] = name end
            end
        end
        table.sort(names)
        return names
    end
    function api.readPocket(name)
        local path = here(name)
        local file = fs.exists(path) and fs.open(path, "rb")
        if not file then return nil, "That file is not here" end
        local body = file.readAll()
        file.close()
        return body or ""
    end
    function api.keep(name, body)
        body = tostring(body or "")
        if type(fs.getFreeSpace) == "function" and fs.getFreeSpace("/") < #body + 4096 then
            return nil, "Not enough room on this Pocket"
        end
        if not fs.exists(downloads) then fs.makeDir(downloads) end
        local path = here(name)
        local file = fs.open(path, "wb")
        if not file then return nil, "Cannot write here" end
        file.write(body)
        file.close()
        return path
    end
    return api
end

-- What the Music app is given on a Pocket, as api.music, FoxyOS 17: asking
-- the Music Server as whoever is signed in, and sending a song's pieces to
-- the Cloud Servers for an upload. `where()` asks the Bank which computer is
-- the registered Music Server: a session goes there and nowhere else.
-- FoxyOS 18: `remember`, if given, keeps the computer `where` last named
-- (remember(id)) and says it again (remember()) while the Bank does not
-- answer -- the Music Server goes on without the Bank, and so does this.
function net.musicApi(config, session, offline, where, remember)
    local client
    local api = {}
    local function off()
        if offline and offline() then return nil, "Modem is off", "MODEM_OFF" end
        return true
    end
    function api.ask(action, payload)
        local ok, err, code = off()
        if not ok then return nil, err, code end
        if not client then
            client = net.client({ protocol = config.music_protocol or "PUMPE_MUSIC_V1",
                hostname = config.music_hostname or "MUSIC_SERVER" })
            function client:discover()
                local id = where()
                if remember and id then remember(id) end
                if remember and not id then id = remember() end
                self.serverId = id
                return self.serverId
            end
        end
        local scoped = {}
        for key, value in pairs(type(payload) == "table" and payload or {}) do
            scoped[key] = value
        end
        scoped.session_token, scoped.player_token = session(), nil
        local answer, askError, askCode = client:request(tostring(action), scoped, 6)
        if not answer and not askCode and not client.serverId then
            askError = "The Music Server is not running"
        end
        return answer, askError, askCode
    end
    function api.upload(plan, body, progress)
        local ok, err, code = off()
        if not ok then return nil, err, code end
        return net.cloud.put(plan, tostring(body or ""),
            config.cloud_protocol or "PUMPE_CLOUD_V1", progress)
    end
    return api
end

return net
