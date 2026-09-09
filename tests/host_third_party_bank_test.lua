-- A bank that is not Foxy.
--
-- A real Foxy Bank and a real 3rd Party Bank Server are loaded into one host
-- process with a table for a radio between them, so the transfers here are
-- the actual code on both sides rather than a mock of either. What the test
-- is really watching is the total amount of money in the world, across two
-- banks that share nothing but an Account ID format.

package.path = "../?.lua;../?/init.lua;" .. package.path

colors = setmetatable({}, { __index = function() return 1 end })
os.day = function() return 500 end
os.time = function() return 12 end
os.epoch = function() return 20000000 end

local wire = { hosts = {}, servers = {} }
function wire.host(computer, protocol, hostname)
    wire.hosts[protocol .. "/" .. hostname] = computer
end
function wire.deliver(toComputer, action, payload)
    local server = wire.servers[toComputer]
    if not server then return nil, "Bank server is offline" end
    -- Foxy keeps its settlement actions apart from its banking ones; the
    -- third-party server has only the one table. Both are reachable here.
    local handler = server.actions[action]
        or (server.ledger and server.ledger.actions
            and server.ledger.actions[action])
    if not handler then return nil, "Unknown action", "UNKNOWN_ACTION" end
    local ok, result = pcall(handler, payload or {})
    if ok then return result end
    if type(result) == "table" and result.pumpe then
        return nil, result.message, result.code
    end
    return nil, tostring(result), "SERVER_ERROR"
end

local saved = {}
local function environment(computerId)
    os.getComputerID = function() return computerId end
    fs = {
        getDir = function() return "/pumpe" end,
        combine = function(left, right)
            return tostring(left):gsub("/+$", "") .. "/"
                .. tostring(right):gsub("^/+", "")
        end,
        exists = function() return false end,
        isDir = function() return false end,
        makeDir = function() end,
    }
    shell = { getRunningProgram = function() return "/pumpe/x.lua" end }
    term = { current = function()
        return { getSize = function() return 51, 19 end }
    end }
    package.loaded["lib.ui"] = setmetatable({ theme = {} }, {
        __index = function() return function() end end,
    })
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
    rednet = {
        host = function(p, h) wire.host(computerId, p, h) end,
        unhost = function() end,
        lookup = function(p, h) return wire.hosts[p .. "/" .. h] end,
        receive = function() return nil end,
        send = function() return true end,
    }
    package.loaded["lib.net"] = {
        openModems = function() return { "modem" } end,
        host = function(p, h) wire.host(computerId, p, h) end,
        reply = function() end,
        locate = function() return nil end,
        autoUpdate = function() end,
        client = function(spec)
            local client = {}
            function client:discover()
                self.serverId = wire.hosts[spec.protocol .. "/" .. spec.hostname]
                return self.serverId
            end
            function client:request(action, payload)
                if not self.serverId then self:discover() end
                if not self.serverId then
                    return nil, "Bank server is offline"
                end
                return wire.deliver(self.serverId, action, payload)
            end
            return client
        end,
    }
    return util
end

-- Foxy, on computer 1.
environment(1)
PUMPE_TEST_MODE = true
local foxy = assert(loadfile("../bank_server.lua"))()
PUMPE_TEST_MODE = nil
wire.servers[1] = foxy
local foxyConfig = require("config")
foxy.state.bank_code = foxyConfig.foxy_bank_code
wire.host(1, foxyConfig.ledger_protocol,
    foxy.ledger.hostFor(foxyConfig.foxy_bank_code))

-- BuckApp's own bank, on computer 2.
local util = environment(2)
PUMPE_TEST_MODE = true
local buck = assert(loadfile("../bank_app_server.lua"))()
PUMPE_TEST_MODE = nil
wire.servers[2] = buck
buck.adopt({ app_id = "APP00001", bank_name = "BuckApp" })
wire.host(2, foxyConfig.ledger_protocol,
    buck.ledger.hostFor(buck.state.bank_code))

local function rejected(action, expectedCode, payload)
    local ok, result = pcall(action, payload)
    assert(not ok, "should have been rejected")
    assert(type(result) == "table" and result.code == expectedCode,
        "expected " .. expectedCode .. ", got " .. tostring(
            type(result) == "table" and result.code or result))
end

-- Its own bank, its own code -------------------------------------------------

assert(buck.state.bank_name == "BuckApp")
assert(buck.state.bank_code:match("^%d%d%d%d$"),
    "a bank code is four digits: " .. tostring(buck.state.bank_code))
assert(buck.state.bank_code ~= foxyConfig.foxy_bank_code,
    "and is never Foxy's")
assert(util.ledger.codeFor("BuckApp") == buck.state.bank_code,
    "derived from the name, so the same bank always gets the same code")

-- Its own logins, deliberately nothing to do with Foxy -----------------------------

local ana = foxy.actions.REGISTER({ name = "Ana Fox", pin = "1234",
    gender = "Not set" })
local anaFoxyId = ana.account.bank_account_id
local startingBalance = foxy.state.accounts[ana.account.account_id].balance

local anaBuck = buck.actions.TPB_REGISTER({ name = "Ana Fox", pin = "9999" })

-- A Foxy session is not a BuckApp session. Checked after an account exists
-- here, because a bank with no accounts rejects everything anyway -- which
-- is what made an earlier version of this assertion pass no matter what.
rejected(buck.actions.TPB_SUMMARY, "SESSION_EXPIRED",
    { session_token = ana.session_token })
rejected(buck.actions.TPB_SUMMARY, "SESSION_EXPIRED",
    { session_token = "made up" })
assert(buck.actions.TPB_SUMMARY({
    session_token = anaBuck.session_token }).account.name == "Ana Fox",
    "and its own session does work")
assert(anaBuck.account.balance == 0,
    "a third-party bank mints no money: an account opens empty")
assert(anaBuck.account.bank_account_id:sub(1, 4) == buck.state.bank_code,
    "its Account IDs carry its own bank code")
assert(anaBuck.session_token ~= ana.session_token)

-- The PIN here is this bank's, not Foxy's.
rejected(buck.actions.TPB_LOGIN, "BAD_LOGIN",
    { name = "Ana Fox", pin = "1234" })
assert(buck.actions.TPB_LOGIN({ name = "Ana Fox", pin = "9999" }).account,
    "and its own PIN works")
rejected(buck.actions.TPB_REGISTER, "NAME_TAKEN",
    { name = "Ana Fox", pin = "1111" })

-- Money across two banks ------------------------------------------------------
-- Neither bank can see the other's ledger. The only invariant either can
-- keep is that the total is unchanged, so that is what is checked.

local function worldTotal()
    local total = 0
    for _, account in pairs(foxy.state.accounts) do
        total = total + (account.balance or 0)
    end
    for _, account in pairs(buck.state.accounts) do
        total = total + (account.balance or 0)
    end
    return total
end
local before = worldTotal()

local quote = foxy.actions.BANK_TRANSFER_QUOTE({
    session_token = ana.session_token,
    bank_account_id = anaBuck.account.bank_account_id,
})
assert(quote.bank_name == "BuckApp" and quote.name == "Ana Fox",
    "Foxy can see who it would be sending to, and at which bank")

local moved = foxy.actions.BANK_TRANSFER_CONFIRM({
    session_token = ana.session_token,
    bank_account_id = anaBuck.account.formatted,
    pin = "1234",
})
assert(moved.moved == startingBalance)
assert(worldTotal() == before,
    "the money crossed banks without any being made or lost")
assert(buck.state.accounts[anaBuck.account.account_id].balance
    == startingBalance, "it is at BuckApp now")
assert(foxy.state.accounts[ana.account.account_id].balance == 0,
    "and not at Foxy")
assert(foxy.state.accounts[ana.account.account_id].bank_closed,
    "and the Foxy bank account closed behind it")

-- Sending between two accounts at the third-party bank.
local bo = buck.actions.TPB_REGISTER({ name = "Bo Wolf", pin = "2222" })
buck.actions.TPB_SEND({ session_token = anaBuck.session_token,
    recipient = "Bo Wolf", amount = 100, pin = "9999" })
assert(buck.state.accounts[bo.account.account_id].balance == 100)
assert(worldTotal() == before, "sending inside one bank changes no total")
rejected(buck.actions.TPB_SEND, "INSUFFICIENT_FUNDS", {
    session_token = bo.session_token, recipient = "Ana Fox",
    amount = 999999, pin = "2222",
})
rejected(buck.actions.TPB_SEND, "BAD_PIN", {
    session_token = bo.session_token, recipient = "Ana Fox",
    amount = 1, pin = "0000",
})

-- Going home ------------------------------------------------------------------
-- The same feature from the other side, addressed to the Foxy Account ID
-- the Foxy app shows.

local homeQuote = buck.actions.TPB_TRANSFER_QUOTE({
    session_token = anaBuck.session_token,
    bank_account_id = anaFoxyId,
})
assert(homeQuote.bank_name == "Foxy" and homeQuote.name == "Ana Fox")

local wentHome = buck.actions.TPB_TRANSFER_CONFIRM({
    session_token = anaBuck.session_token,
    bank_account_id = util.ledger.format(anaFoxyId),
    pin = "9999",
})
assert(wentHome.bank_name == "Foxy")
assert(worldTotal() == before, "and back again, still the same money")
assert(foxy.state.accounts[ana.account.account_id].balance
    == startingBalance - 100, "it is at Foxy again, less what Bo was sent")
assert(not foxy.state.accounts[ana.account.account_id].bank_closed,
    "and the Foxy bank account reopened when the money arrived")
assert(buck.state.accounts[anaBuck.account.account_id].balance == 0)

-- An Account ID that belongs to nobody, at a bank that is not there.
rejected(buck.actions.TPB_TRANSFER_QUOTE, "BANK_UNREACHABLE", {
    session_token = bo.session_token,
    bank_account_id = "9999000000000001",
})
rejected(buck.actions.TPB_TRANSFER_QUOTE, "BAD_ACCOUNT_ID", {
    session_token = bo.session_token, bank_account_id = "12",
})
rejected(buck.actions.TPB_TRANSFER_CONFIRM, "SAME_ACCOUNT", {
    session_token = bo.session_token, pin = "2222",
    bank_account_id = bo.account.bank_account_id,
})

-- Applying once, at this bank too ------------------------------------------------

local credited = buck.actions.LEDGER_CREDIT({
    bank_account_id = bo.account.bank_account_id, amount = 50,
    transfer_id = "XFER_ONCE_ONLY", from_bank_name = "Foxy",
})
assert(credited.credited == 50)
local repeated = buck.actions.LEDGER_CREDIT({
    bank_account_id = bo.account.bank_account_id, amount = 50,
    transfer_id = "XFER_ONCE_ONLY", from_bank_name = "Foxy",
})
assert(repeated.repeated and buck.state.accounts[bo.account.account_id]
    .balance == 150, "a retried credit is not applied twice")
assert(buck.actions.LEDGER_STATUS({ transfer_id = "XFER_ONCE_ONLY" }).applied)
assert(not buck.actions.LEDGER_STATUS({ transfer_id = "XFER_NEVER" }).applied)

print("host_third_party_bank_test: OK")
