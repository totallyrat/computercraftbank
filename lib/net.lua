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

-- Clients ask the Bank Server for its version over the connection they already
-- hold and only launch Easy Deployment when a newer release actually exists.
-- Shelling the installer on every dashboard tick used to cost a full program
-- load, a public HTTPS request, and a deployment manifest round trip.
function net.autoUpdate(config, role, root, client)
    if type(config) ~= "table" or config.auto_update == false then return false end
    if type(shell) ~= "table" or type(shell.run) ~= "function" then return false end
    role = string.lower(tostring(role or ""))
    if role == "" or role == "bank" then return false end

    local interval = math.max(5,
        math.floor(tonumber(config.client_update_check_seconds)
            or config.update_check_seconds or 30)) * 1000
    local now = util.nowMs()
    if lastAutoUpdateCheck[role]
        and now - lastAutoUpdateCheck[role] < interval then
        return false
    end
    lastAutoUpdateCheck[role] = now

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

return net
