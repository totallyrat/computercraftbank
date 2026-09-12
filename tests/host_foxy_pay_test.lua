-- How you pay, after 9.4.
--
-- A Foxy account pays a shop in person: the kiosk finds the phone standing
-- in front of it and the phone confirms. It cannot type a code any more.
-- An account at Revolution or another third-party bank does the opposite --
-- it has no Foxy Pay, so a code is its way in, and the money crosses two
-- banks to get to the merchant.
--
-- Both halves of that are enforced on the Bank rather than in the phone.
-- The screens are gone from the PUMPE either way, and a rule that only
-- exists in the client is a rule that holds until somebody edits the client.

package.path = "../?.lua;../?/init.lua;" .. package.path

colors = setmetatable({}, { __index = function() return 1 end })
os.day = function() return 500 end
os.time = function() return 12 end
local clock = 20000000
os.epoch = function() return clock end

local wire = { hosts = {}, servers = {} }
function wire.host(computer, protocol, hostname)
    wire.hosts[protocol .. "/" .. hostname] = computer
end
function wire.deliver(toComputer, action, payload)
    local server = wire.servers[toComputer]
    if not server then return nil, "Bank server is offline" end
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

environment(1)
PUMPE_TEST_MODE = true
local foxy = assert(loadfile("../bank_server.lua"))()
PUMPE_TEST_MODE = nil
wire.servers[1] = foxy
local foxyConfig = require("config")
foxy.state.bank_code = foxyConfig.foxy_bank_code
wire.host(1, foxyConfig.ledger_protocol,
    foxy.ledger.hostFor(foxyConfig.foxy_bank_code))

environment(2)
PUMPE_TEST_MODE = true
local revo = assert(loadfile("../bank_app_server.lua"))()
PUMPE_TEST_MODE = nil
wire.servers[2] = revo
revo.adopt({ app_id = "APP00009", bank_name = "Revolution" })
wire.host(2, foxyConfig.ledger_protocol,
    foxy.ledger.hostFor(revo.state.bank_code))

local function rejected(fn, expectedCode, ...)
    local ok, result = pcall(fn, ...)
    assert(not ok, "that should have been refused, but it worked")
    assert(type(result) == "table" and result.code == expectedCode,
        "expected " .. expectedCode .. ", got "
            .. tostring(type(result) == "table" and result.code or result))
end

local function register(name, pin)
    local made = foxy.actions.REGISTER({ name = name, pin = pin,
        gender = "Not set" })
    return { token = made.session_token, id = made.account.account_id,
        name = name }
end

local shopper = register("Sam Fox", "1111")
local owner = register("Kit Wolf", "2222")
local kiosk = foxy.actions.KIOSK_REGISTER({ name = "Corner Shop" })
local auth = { terminal_id = kiosk.terminal_id,
    terminal_token = kiosk.terminal_token }

local function saleCode(amount)
    return foxy.actions.CREATE_PAY_CODE({
        terminal_id = auth.terminal_id, terminal_token = auth.terminal_token,
        amount = amount, description = "Bread",
    })
end

-- A Foxy account and a code -------------------------------------------------

local sale = saleCode(20)
rejected(foxy.actions.PAY_CODE_PREVIEW, "FOXY_PAY_ONLY",
    { session_token = shopper.token, code = sale.code })
rejected(foxy.actions.PAY_CODE_CONFIRM, "FOXY_PAY_ONLY",
    { session_token = shopper.token, code = sale.code, pin = "1111" })

-- The two kinds of code that are not a one-off purchase still work, because
-- neither has a Foxy Pay equivalent: a kiosk offers a basket in person, not
-- a daily billing agreement, and certainly not cash out of its own till.
-- A kiosk can only hand out money it has taken.
foxy.state.terminals[auth.terminal_id].balance = 100
local cashOut = foxy.actions.CREATE_WITHDRAWAL_CODE({
    terminal_id = auth.terminal_id, terminal_token = auth.terminal_token,
    amount = 15,
})
assert(foxy.actions.PAY_CODE_PREVIEW({ session_token = shopper.token,
    code = cashOut.code }).kind == "withdrawal",
    "a kiosk handing you money is not paying, so the code still works")

local pass = foxy.actions.CREATE_PAY_CODE({
    terminal_id = auth.terminal_id, terminal_token = auth.terminal_token,
    amount = 5, purchase_type = "subscription", description = "Bread club",
})
assert(foxy.actions.PAY_CODE_PREVIEW({ session_token = shopper.token,
    code = pass.code }).kind == "subscription",
    "and a subscription is an arrangement you can see and cancel in Subs")

-- Foxy Pay ------------------------------------------------------------------
-- The same settlement, reached the way the kiosk intended: it picked this
-- account by standing next to it.

foxy.actions.REPORT_POSITION({ session_token = shopper.token,
    position = { x = 100, y = 64, z = 100 } })
local offered = foxy.actions.PROXIMITY_OFFER({
    terminal_id = auth.terminal_id, terminal_token = auth.terminal_token,
    amount = 20, description = "Bread",
    position = { x = 101, y = 64, z = 100 },
}).offer
assert(offered.target_name == "Sam Fox",
    "the kiosk found the phone standing in front of it")

-- Somebody else cannot pay an offer addressed to this account, even holding
-- its code -- which is the reason this is a route of its own rather than a
-- flag on the code route. A flag would be the client's word for how it got
-- here; an addressed offer is the kiosk's.
rejected(foxy.actions.FOXY_PAY_PREVIEW, "NOT_YOURS",
    { session_token = owner.token, offer_id = offered.offer_id })

local before = foxy.state.accounts[shopper.id].balance
assert(foxy.actions.FOXY_PAY_PREVIEW({ session_token = shopper.token,
    offer_id = offered.offer_id }).amount == 20)
foxy.actions.FOXY_PAY_CONFIRM({ session_token = shopper.token,
    offer_id = offered.offer_id, pin = "1111" })
assert(foxy.state.accounts[shopper.id].balance == before - 20,
    "and paying it works exactly as the typed code used to")

-- Paying a Foxy kiosk from another bank --------------------------------------

local function worldTotal()
    local total = 0
    for _, account in pairs(foxy.state.accounts) do
        total = total + (account.balance or 0)
    end
    for _, account in pairs(revo.state.accounts) do
        total = total + (account.balance or 0)
    end
    for _, terminal in pairs(foxy.state.terminals) do
        total = total + (terminal.balance or 0)
    end
    return total
end

local visitor = revo.actions.TPB_REGISTER({ name = "Ada Hare",
    pin = "3333" })
revo.state.accounts[visitor.account.account_id].balance = 200
local visitorToken = visitor.session_token
local worldBefore = worldTotal()

local basket = saleCode(35)
local quoted = revo.actions.TPB_PAY_CODE_QUOTE({
    session_token = visitorToken, code = basket.code })
assert(quoted.amount == 35 and quoted.merchant == "Corner Shop",
    "Revolution can see what the code is worth and who it pays")

rejected(revo.actions.TPB_PAY_CODE, "BAD_PIN",
    { session_token = visitorToken, code = basket.code, pin = "0000" })

local paid = revo.actions.TPB_PAY_CODE({ session_token = visitorToken,
    code = basket.code, pin = "3333" })
assert(paid.paid == 35, "and paying it moves the money across two banks")
assert(revo.state.accounts[visitor.account.account_id].balance == 200 - 35,
    "the payer is charged at their own bank")
assert(foxy.state.accounts[owner.id] ~= nil)
assert(worldTotal() == worldBefore,
    "and nothing was created or destroyed on the way: " .. worldBefore
        .. " -> " .. worldTotal())

-- The same code cannot be paid twice, and neither can an expired one.
rejected(revo.actions.TPB_PAY_CODE, "BAD_CODE",
    { session_token = visitorToken, code = basket.code, pin = "3333" })

-- Asking Foxy to settle the same payment twice under one id pays the shop
-- once. This is the case a lost reply creates, and it must be safe.
local replay = saleCode(10)
local shopBefore = worldTotal()
for _ = 1, 2 do
    foxy.ledger.actions.LEDGER_CODE_SETTLE({
        code = replay.code, transfer_id = "REPLAYTEST01", amount = 10,
        from_name = "Ada Hare", from_bank_name = "Revolution",
        from_bank_code = revo.state.bank_code,
    })
end
assert(worldTotal() == shopBefore + 10,
    "a repeated settle credits the merchant once, not twice")

-- And a third-party bank cannot reach the two kinds of code that belong to
-- an account at Foxy itself.
local otherCashOut = foxy.actions.CREATE_WITHDRAWAL_CODE({
    terminal_id = auth.terminal_id, terminal_token = auth.terminal_token,
    amount = 15,
})
rejected(foxy.ledger.actions.LEDGER_CODE_QUOTE, "NOT_PAYABLE",
    { code = otherCashOut.code })
local otherPass = foxy.actions.CREATE_PAY_CODE({
    terminal_id = auth.terminal_id, terminal_token = auth.terminal_token,
    amount = 5, purchase_type = "subscription", description = "Bread club",
})
rejected(foxy.ledger.actions.LEDGER_CODE_QUOTE, "NOT_PAYABLE",
    { code = otherPass.code })

print("host_foxy_pay_test: OK")
