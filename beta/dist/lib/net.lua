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




net.updateTarget = nil

local function autoUpdateOnce(config, role, root, client, options)
if type(config) ~= "table" or config.auto_update == false then return false end
role = string.lower(tostring(role or ""))
if role == "" then return false end





local elsewhere = type(options.manifestUrl) == "string"
and options.manifestUrl ~= ""
local checkKey = elsewhere and (role .. "@" .. options.manifestUrl) or role




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

if depotUpdate(config, role, root, nil) then return true end
end

local updater = loadUpdater()



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


local updating = type(options.updating) == "function" and options.updating
or ui.updating
return updating(target, function(progress)
return work(progressOf(progress), progress)
end, options.note or found.label
or ("FoxyOS " .. tostring(found.version)))
end






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




if found == false and (why == "current" or why == "beta") then
return false
end
if not found and elsewhere then
net.lastUpdateError = why
return false
end
if not found then



local ping = client and client:request("PING", {}, 3)
if not ping or not net.isNewerVersion(ping.version, config.version)
then
return false
end

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

return false
else

net.lastUpdateError = why
end
end
if elsewhere then return false end
return depotUpdate(config, role, root, client)
end

function net.autoUpdate(config, role, root, client, options)
options = options or {}
local done = autoUpdateOnce(config, role, root, client, options)
if done then return done end




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


function net.cloud.shared(request, code, protocol, progress)
local plan, err, errCode = request("CLOUD_SHARED", { code = code })
if not plan then return nil, err, errCode end
local body, getError, getCode = net.cloud.get(plan, protocol, progress)
if not body then return nil, getError, getCode end
plan.file.owner_name = plan.owner_name
return body, plan.file
end




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

return net
