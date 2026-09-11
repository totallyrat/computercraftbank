-- Pair Mode: two Bank Servers, one bank, joined by a cable.
--
-- Both halves start as bank_server.lua -- a Vault is not a thing you install,
-- it is what one of them becomes -- so the handshake is between two copies of
-- the same program. Two whole Banks are loaded into one host process, each
-- with its own globals, and the network between them is a table. That is
-- enough to run the real handshake rather than a mock of it.
--
-- What this is really guarding is the wire. Since 9.3 the two halves answer
-- parts of the same request, so pairing over the air is not an inconvenience
-- but a wrong answer waiting to happen, and the way that is enforced is by
-- shutting the wireless modems for the length of the handshake. A test that
-- let a wireless peer answer would let that guarantee rot.

package.path = "../?.lua;../?/init.lua;" .. package.path

colors = setmetatable({}, { __index = function() return 1 end })
local currentDay = 500
os.day = function() return currentDay end
os.time = function() return 12 end
os.epoch = function() return 20000000 end

-- The network. A computer is reachable on a protocol only through modems it
-- has open, and a wireless modem that has been closed is a computer nobody
-- on this cable can hear.
local wire = { hosts = {}, servers = {}, modems = {}, open = {} }

function wire.attach(computer, sides)
    wire.modems[computer] = sides
    wire.open[computer] = {}
    for _, side in ipairs(sides) do wire.open[computer][side.name] = true end
end

-- Which links a computer is currently reachable on. A computer with both
-- modems open is on both, which is the whole reason pairing shuts the
-- wireless one: leaving it open is exactly how a Bank Server that is not on
-- the cable gets heard anyway.
function wire.linksOf(computer)
    local links = {}
    for _, side in ipairs(wire.modems[computer] or {}) do
        if wire.open[computer][side.name] then
            links[side.wireless and "wireless" or "wired"] = true
        end
    end
    return links
end

function wire.canHear(asker, other)
    local mine, theirs = wire.linksOf(asker), wire.linksOf(other)
    for link in pairs(mine) do
        if theirs[link] then return true end
    end
    return false
end

function wire.host(computer, protocol, hostname)
    wire.hosts[protocol .. "/" .. hostname] = computer
end

function wire.unhost(computer, protocol)
    for key, id in pairs(wire.hosts) do
        if id == computer and key:sub(1, #protocol + 1) == protocol .. "/" then
            wire.hosts[key] = nil
        end
    end
end

-- A lookup only finds computers that can hear the asker. Hostname given,
-- one answer; hostname omitted, everybody on the same kind of link.
function wire.lookup(asker, protocol, hostname)
    if not next(wire.linksOf(asker)) then return nil end
    local found = {}
    for key, id in pairs(wire.hosts) do
        local prefix, name = key:match("^([^/]+)/(.+)$")
        if prefix == protocol and wire.canHear(asker, id)
            and (not hostname or name == hostname) then
            found[#found + 1] = id
        end
    end
    if hostname then return found[1] end
    table.sort(found)
    return table.unpack(found)
end

function wire.deliver(toComputer, action, payload, fromComputer)
    local server = wire.servers[toComputer]
    if not server then return nil, "Bank server is offline" end
    if not wire.canHear(fromComputer, toComputer) then
        return nil, "Bank server is offline"
    end
    local handler = server.pair.actions[action]
    if not handler then return nil, "Unknown pair action", "UNKNOWN_ACTION" end
    local ok, result = pcall(handler, payload or {}, fromComputer)
    if ok then return result end
    if type(result) == "table" and result.pumpe then
        return nil, result.message, result.code
    end
    return nil, tostring(result), "PAIR_ERROR"
end

local saved = {}

-- Several Banks share one Lua state here, so the globals a Bank reads at run
-- time -- its own id, its modems -- have to follow whichever computer the
-- test is standing at. Anything else and a later Bank's modems answer for an
-- earlier one, which is exactly the confusion this file exists to rule out.
wire.current = nil

function wire.focus(computerId)
    wire.current = computerId
    return computerId
end

os.getComputerID = function() return wire.current end

-- rednet is a global a Bank reads at run time, so it belongs to whichever
-- computer the test is standing at rather than to the last one loaded.
rednet = {
    host = function(protocol, hostname)
        wire.host(wire.current, protocol, hostname)
    end,
    unhost = function(protocol) wire.unhost(wire.current, protocol) end,
    lookup = function(protocol, hostname)
        return wire.lookup(wire.current, protocol, hostname)
    end,
    isOpen = function(side)
        return wire.open[wire.current][side] == true
    end,
    open = function(side) wire.open[wire.current][side] = true end,
    close = function(side) wire.open[wire.current][side] = nil end,
    receive = function() return nil end,
    send = function() return true end,
}
fs = {
    getDir = function() return "/pumpe" end,
    combine = function(left, right)
        return tostring(left):gsub("/+$", "") .. "/"
            .. tostring(right):gsub("^/+", "")
    end,
    exists = function(path) return saved[wire.current .. path] ~= nil end,
    isDir = function() return false end,
}
shell = { getRunningProgram = function() return "/pumpe/bank_server.lua" end }
peripheral = {
    getNames = function()
        local names = {}
        for _, side in ipairs(wire.modems[wire.current] or {}) do
            names[#names + 1] = side.name
        end
        return names
    end,
    getType = function() return "modem" end,
    call = function(name, method)
        if method ~= "isWireless" then return nil end
        for _, side in ipairs(wire.modems[wire.current] or {}) do
            if side.name == name then return side.wireless end
        end
        return nil
    end,
}

local function loadBank(computerId, modems)
    wire.attach(computerId, modems or {
        { name = "back", wireless = false },
        { name = "top", wireless = true },
    })
    wire.focus(computerId)

    for name in pairs(package.loaded) do
        if name:find("^lib%.") or name == "config" then
            package.loaded[name] = nil
        end
    end
    local util = require("lib.util")
    util.loadTable = function(path, fallback)
        return saved[computerId .. path] or util.copy(fallback)
    end
    util.saveTable = function(path, value)
        saved[computerId .. path] = util.copy(value)
    end
    package.loaded["lib.util"] = util

    package.loaded["lib.net"] = {
        openModems = function()
            for _, side in ipairs(wire.modems[computerId]) do
                wire.open[computerId][side.name] = true
            end
            return { "modem" }
        end,
        closeModems = function() wire.open[computerId] = {} end,
        modemsOpen = function() return true end,
        host = function(protocol, hostname)
            wire.host(computerId, protocol, hostname)
        end,
        reply = function() end,
        locate = function() return nil end,
        autoUpdate = function() end,
        client = function(spec)
            local client = { serverId = nil, protocol = spec.protocol }
            function client:discover()
                self.serverId = wire.lookup(computerId, spec.protocol,
                    spec.hostname)
                return self.serverId
            end
            function client:request(action, payload)
                if not self.serverId then self:discover() end
                if not self.serverId then
                    return nil, "Bank server is offline"
                end
                return wire.deliver(self.serverId, action, payload, computerId)
            end
            return client
        end,
    }

    PUMPE_TEST_MODE = true
    local bank = assert(loadfile("../bank_server.lua"))()
    PUMPE_TEST_MODE = nil
    wire.servers[computerId] = bank
    return bank
end

local function register(bank, computerId, name)
    wire.focus(computerId)
    return bank.actions.REGISTER({ name = name, pin = "1234",
        gender = "Not set" })
end

local function rejected(action, expectedCode, ...)
    local ok, result = pcall(action, ...)
    assert(not ok, "should have been rejected")
    assert(type(result) == "table" and result.code == expectedCode,
        "expected " .. expectedCode .. ", got " .. tostring(
            type(result) == "table" and result.code or result))
end

-- Alpha is the bank that has been running. Beta is the new computer.
local alpha = loadBank(11)
local beta = loadBank(22)
register(alpha, 11, "Ana Fox")
assert(alpha.pair.role == "solo" and beta.pair.role == "solo",
    "a Bank has no Vault until it is given one")

-- The cable is the requirement ------------------------------------------------

-- A computer with nothing but a wireless modem cannot pair at all. This is
-- the whole point: the halves answer parts of one request, so the link
-- between them has to be as reliable as the disk.
local airOnly = loadBank(77, { { name = "top", wireless = true } })
wire.focus(77)
assert(airOnly.pair.wireAttached() == false,
    "a wireless modem is not a wired one")
assert(airOnly.pair.wiredOnly() == nil,
    "and there is nothing to shut the air off in favour of")

wire.focus(11)
assert(alpha.pair.wireAttached(), "alpha has a cable")
wire.focus(22)
assert(beta.pair.wireAttached(), "so does beta")

-- Finding each other -----------------------------------------------------------

-- Going into the pairing screen shuts the wireless modems and announces this
-- computer's own id, so a lookup returns the cable rather than a code
-- somebody has to carry between two keyboards.
wire.focus(11)
alpha.pair.wiredOnly()
alpha.pair.beacon()
alpha.pair.pairing = true
wire.focus(22)
beta.pair.wiredOnly()
beta.pair.beacon()
beta.pair.pairing = true

wire.focus(22)
local seen = beta.pair.discover()
assert(#seen == 1 and seen[1] == 11,
    "beta finds alpha on the cable and does not find itself")

-- The computer that is only on the air is not on anybody's cable, however
-- loudly it is beaconing.
wire.focus(77)
airOnly.pair.beacon()
airOnly.pair.pairing = true
wire.focus(22)
local stillSeen = beta.pair.discover()
assert(#stillSeen == 1 and stillSeen[1] == 11,
    "a wireless-only Bank Server is not on the cable and must not be offered")
local reached, why = beta.pair.claim(77)
assert(not reached, "a Bank Server on the air must not be pairable")
assert(why, "and the refusal says so rather than failing silently: " ..
    tostring(why))

-- Pairing ----------------------------------------------------------------------

wire.focus(22)
assert(not beta.pair.claim(0), "a computer id is a positive number")
assert(not beta.pair.claim(22), "and not this computer's own")

assert(beta.pair.claim(11), "one press, and they are paired")
assert(alpha.pair.role == "core", "the server holding the accounts is the Core")
assert(beta.pair.role == "vault", "and the new one becomes the Vault")
assert(alpha.pair.partner == 22 and beta.pair.partner == 11,
    "each knows the other")
assert(alpha.pair.wired and beta.pair.wired,
    "and both recorded that they met over a cable")

-- Which half is which is decided by where the data is, not by who pressed the
-- button. A fresh server claiming a live one must not turn the live one into
-- a Vault and strand its ledger.
local gamma = loadBank(33)
local delta = loadBank(44)
register(gamma, 33, "Bo Wolf")
register(gamma, 33, "Cy Hare")
wire.focus(44)
delta.pair.wiredOnly()
delta.pair.beacon()
delta.pair.pairing = true
wire.focus(33)
gamma.pair.wiredOnly()
gamma.pair.pairing = true
assert(gamma.pair.claim(44),
    "the server with the accounts presses the button")
assert(gamma.pair.role == "core",
    "and still ends up the Core, because that is where the ledger is")
assert(delta.pair.role == "vault")

-- A server that is not on its pairing screen is not up for grabs, and one
-- that is already paired cannot be claimed again.
wire.focus(11)
rejected(alpha.pair.actions.PAIR_CLAIM, "ALREADY_PAIRED", { accounts = 0 }, 99)
beta.pair.pairing = false
rejected(beta.pair.actions.PAIR_CLAIM, "NOT_PAIRING", { accounts = 0 }, 99)

-- Pairing survives a restart ---------------------------------------------------

local betaAgain = loadBank(22)
wire.focus(22)
assert(betaAgain.pair.role == "solo",
    "role is read from disk by pair.load, not guessed at load time")
betaAgain.pair.load()
assert(betaAgain.pair.role == "vault" and betaAgain.pair.partner == 11,
    "a restarted Vault comes back up as a Vault, still paired")
assert(betaAgain.pair.wired, "and still knows it is on a cable")

print("host_pair_mode_test: OK")
