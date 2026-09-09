-- Pair Mode: two Bank Servers, one bank.
--
-- Two whole Banks are loaded into one host process, each with its own
-- globals, and the rednet between them is a table. That is enough to run
-- the real pairing handshake and the real forwarding, rather than a mock of
-- either.

package.path = "../?.lua;../?/init.lua;" .. package.path

colors = setmetatable({}, { __index = function() return 1 end })
local currentDay = 500
os.day = function() return currentDay end
os.time = function() return 12 end
os.epoch = function() return 20000000 end

-- The network. Every server registers its handler; a lookup finds whoever
-- hosts a name, and a request runs their handler directly.
local wire = { hosts = {}, servers = {}, nextId = 1 }
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
function wire.lookup(protocol, hostname)
    return wire.hosts[protocol .. "/" .. hostname]
end
-- Delivered straight to the other server's pair handler, which is what a
-- rednet round trip amounts to here.
function wire.deliver(toComputer, protocol, action, payload, fromComputer)
    local server = wire.servers[toComputer]
    if not server then return nil, "Bank server is offline" end
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
local function loadBank(computerId)
    -- Each Bank gets its own view of the world: its own computer id, its own
    -- files, its own require cache.
    os.getComputerID = function() return computerId end
    fs = {
        getDir = function() return "/pumpe" end,
        combine = function(left, right)
            return tostring(left):gsub("/+$", "") .. "/"
                .. tostring(right):gsub("^/+", "")
        end,
        exists = function(path) return saved[computerId .. path] ~= nil end,
        isDir = function() return false end,
    }
    shell = { getRunningProgram = function() return "/pumpe/bank_server.lua" end }

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

    -- rednet and lib.net, wired to the table above.
    rednet = {
        host = function(protocol, hostname)
            wire.host(computerId, protocol, hostname)
        end,
        unhost = function(protocol) wire.unhost(computerId, protocol) end,
        lookup = function(protocol, hostname)
            return wire.lookup(protocol, hostname)
        end,
        receive = function() return nil end,
        send = function() return true end,
    }
    package.loaded["lib.net"] = {
        openModems = function() return { "modem" } end,
        host = function(protocol, hostname)
            wire.host(computerId, protocol, hostname)
        end,
        reply = function() end,
        locate = function() return nil end,
        autoUpdate = function() end,
        client = function(spec)
            local client = { serverId = nil, protocol = spec.protocol }
            function client:discover()
                self.serverId = wire.lookup(spec.protocol, spec.hostname)
                return self.serverId
            end
            function client:request(action, payload)
                if not self.serverId then self:discover() end
                if not self.serverId then return nil, "Bank server is offline" end
                return wire.deliver(self.serverId, spec.protocol, action,
                    payload, computerId)
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

local alpha = loadBank(11)
local beta = loadBank(22)

local function register(bank, name)
    return bank.actions.REGISTER({ name = name, pin = "1234",
        gender = "Not set" })
end
local function as(who, extra)
    local payload = { session_token = who.session_token }
    for key, value in pairs(extra or {}) do payload[key] = value end
    return payload
end
local function rejected(action, expectedCode, ...)
    local ok, result = pcall(action, ...)
    assert(not ok, "should have been rejected")
    assert(type(result) == "table" and result.code == expectedCode,
        "expected " .. expectedCode .. ", got " .. tostring(
            type(result) == "table" and result.code or result))
end

-- Alpha is the bank that has been running. Beta is the new computer.
local ana = register(alpha, "Ana Fox")
assert(alpha.pair.role == "solo" and beta.pair.role == "solo",
    "a Bank is solo until it is told otherwise")

-- Pairing ---------------------------------------------------------------------

-- Alpha shows a code; beta types it in.
alpha.pair.newCode()
wire.host(11, "PUMPE_PAIR_V1", "PAIRING_" .. alpha.pair.code)

assert(not beta.pair.claim("123"), "a code is six digits")
assert(not beta.pair.claim("999999"), "and has to be one somebody is showing")

assert(beta.pair.claim(alpha.pair.code), "the codes match, so they pair")
assert(alpha.pair.role == "core", "the server holding the accounts is the Core")
assert(beta.pair.role == "vault", "and the new one becomes the Vault")
assert(alpha.pair.partner == 22 and beta.pair.partner == 11,
    "each knows the other")

-- Which half is which is decided by where the data is, not by who typed. A
-- fresh server claiming a live one must not turn the live one into a Vault.
local gamma = loadBank(33)
local delta = loadBank(44)
register(gamma, "Bo Wolf")
register(gamma, "Cy Hare")
delta.pair.newCode()
wire.host(44, "PUMPE_PAIR_V1", "PAIRING_" .. delta.pair.code)
assert(gamma.pair.claim(delta.pair.code),
    "the server with the accounts types the empty one's code")
assert(gamma.pair.role == "core",
    "and still ends up the Core, because that is where the ledger is")
assert(delta.pair.role == "vault")

-- A server cannot be claimed twice.
alpha.pair.code = "555555"
wire.host(11, "PUMPE_PAIR_V1", "PAIRING_555555")
rejected(alpha.pair.actions.PAIR_CLAIM, "ALREADY_PAIRED",
    { code = "555555" }, 99)

-- The work is actually split ------------------------------------------------------

-- App records go to the Vault, and the Core keeps none of them.
alpha.actions.FOXY_LOGIN_APPROVE(as(ana, { app_id = "yap", app_name = "Yap" }))
local written = alpha.actions.APP_DATA_PUT(as(ana, {
    app_id = "yap", collection = "posts", data = { body = "hello" },
})).record
assert(written.author_name == "Ana Fox", "the record was written")

local function collections(bank)
    local count = 0
    for _, perApp in pairs(bank.state.app_data or {}) do
        for _ in pairs(perApp) do count = count + 1 end
    end
    return count
end
assert(collections(alpha) == 0,
    "the Core holds no app records at all -- that is the point of the split")
assert(collections(beta) == 1, "the Vault holds them")

local listed = alpha.actions.APP_DATA_LIST(as(ana, {
    app_id = "yap", collection = "posts",
})).records
assert(#listed == 1 and listed[1].data.body == "hello",
    "and reading them back through the Core works exactly as before")

-- Banking stays on the Core. A balance never crosses the wire.
local before = #wire.servers[22].state.transactions
local bo = register(alpha, "Bo Wolf")
alpha.actions.SEND_MONEY(as(ana, { recipient = "Bo Wolf", amount = 10,
    pin = "1234" }))
assert(#wire.servers[22].state.transactions == before,
    "the Vault sees no banking traffic: it is not in that path")
assert(alpha.state.accounts[bo.account.account_id].balance > 0)

-- Only the Core it is paired to can reach the Vault's store.
rejected(beta.pair.actions.VAULT_APP_DATA, "NOT_MY_CORE",
    { op = "list", app_id = "yap", payload = { collection = "posts" },
      caller = { account_id = ana.account.account_id } }, 99)

-- And the Vault will not take a request that does not say who is asking.
rejected(beta.pair.actions.VAULT_APP_DATA, "NO_CALLER",
    { op = "list", app_id = "yap", payload = { collection = "posts" } }, 11)

-- A Vault that goes away is reported rather than silently losing records.
wire.servers[22] = nil
rejected(alpha.actions.APP_DATA_LIST, "VAULT_OFFLINE", as(ana, {
    app_id = "yap", collection = "posts",
}))
wire.servers[22] = beta

-- Pairing survives a restart ---------------------------------------------------------

local betaAgain = loadBank(22)
assert(betaAgain.pair.role == nil or betaAgain.pair.role == "solo",
    "role is read from disk by pair.load, not guessed at load time")
betaAgain.pair.load()
assert(betaAgain.pair.role == "vault" and betaAgain.pair.partner == 11,
    "a restarted Vault comes back up as a Vault, still paired")

print("host_pair_mode_test: OK")
