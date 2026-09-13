-- Fast Bank Transfer, end to end.
--
-- Two real banks -- a Foxy Bank Server and a 3rd Party Bank Server hosting
-- Revolution -- with a real PUMPE between them, so the money actually moves
-- and the test can count it on both sides.
--
-- The two rules worth holding on to are about who is allowed to do what. The
-- phone moves the Foxy account itself, behind its own confirmation and its
-- own PIN prompt, and the app is told an amount and nothing else. The far
-- side the phone does not move at all: it opens the bank holding the money
-- and lets that bank push it, because the bank holding money is the only one
-- that can authorise it leaving.

package.path = "../?.lua;../?/init.lua;" .. package.path

colors = setmetatable({}, { __index = function() return 1 end })
os.day = function() return 500 end
os.time = function() return 12 end
local clock = 20000000
os.epoch = function() return clock end
sleep = function() end

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
local function serverEnvironment(computerId)
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

serverEnvironment(1)
PUMPE_TEST_MODE = true
local foxy = assert(loadfile("../bank_server.lua"))()
PUMPE_TEST_MODE = nil
wire.servers[1] = foxy
local bankConfig = require("config")
foxy.state.bank_code = bankConfig.foxy_bank_code
wire.host(1, bankConfig.protocol, bankConfig.hostname)
wire.host(1, bankConfig.ledger_protocol,
    foxy.ledger.hostFor(bankConfig.foxy_bank_code))

serverEnvironment(2)
PUMPE_TEST_MODE = true
local revo = assert(loadfile("../bank_app_server.lua"))()
PUMPE_TEST_MODE = nil
wire.servers[2] = revo
revo.adopt({ app_id = "APP00009", bank_name = "Revolution" })
wire.host(2, bankConfig.tpb_protocol, "TPBANK_APP00009")
wire.host(2, bankConfig.ledger_protocol,
    foxy.ledger.hostFor(revo.state.bank_code))

foxy.actions.REGISTER({ name = "Ana Fox", pin = "1234", gender = "Not set" })

-- The phone ------------------------------------------------------------------

local WIDTH, HEIGHT = 26, 20
local probes, probeIndex = {}, 0
local pins, inputs = {}, {}
local actions, actionIndex = {}, 0

local util = serverEnvironment(3)
term = { current = function()
    return { getSize = function() return WIDTH, HEIGHT end }
end }
fs = {
    getDir = function() return "/pumpe" end,
    combine = function(left, right)
        return tostring(left):gsub("/+$", "") .. "/"
            .. tostring(right):gsub("^/+", "")
    end,
    exists = function() return true end,
    isDir = function() return false end,
    makeDir = function() end,
    delete = function() end,
    getFreeSpace = function() return 500000 end,
    getSize = function() return 100 end,
}
shell = { getRunningProgram = function() return "/pumpe/pumpe.lua" end }

util.loadTable = function(path, fallback)
    if tostring(path):find("apps", 1, true) then
        return { list = {
            { app_id = "FOXY", name = "Foxy", version = 1, author = "Foxy",
              description = "Your bank", bank_name = "Foxy" },
            { app_id = "APP00009", name = "Revolution", version = 1,
              author = "Kit", description = "Take payments",
              bank_name = "Revolution" },
        } }
    end
    return { last_name = "Ana Fox", onboarding_complete = true,
        modem_on = true, update_mode = "ask" }
end
util.saveTable = function() end
-- Every installed app here is a stand-in whose whole job is to call the API
-- the way its real counterpart does. The app screens themselves are covered
-- by host_third_party_bank_test; what is under test here is the API and the
-- two servers behind it.
local realLoadfile = loadfile
loadfile = function(path)
    if tostring(path):find("/apps/", 1, true) then
        return function()
            return function(api)
                probeIndex = probeIndex + 1
                local probe = probes[probeIndex]
                assert(probe, "an app opened with no probe left to run")
                probe(api)
            end
        end
    end
    return realLoadfile(path)
end

-- A ui that answers from scripts instead of from a screen.
local ui = setmetatable({
    theme = setmetatable({}, { __index = function() return 1 end }),
}, { __index = function() return function() end end })
ui.wrap = function(value, width)
    local lines, line = {}, ""
    for word in tostring(value or ""):gmatch("%S+") do
        if #line + #word + 1 > width and line ~= "" then
            lines[#lines + 1] = line
            line = word
        else
            line = line == "" and word or (line .. " " .. word)
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return lines
end
ui.truncate = function(value, width)
    value = tostring(value or "")
    if #value <= width then return value end
    return value:sub(1, math.max(0, width - 1)) .. "."
end
ui.idleForMs = function() return 0 end
ui.confirm = function() return true end
ui.input = function() return table.remove(inputs, 1) end
pinsAsked = 0
ui.pin = function()
    pinsAsked = pinsAsked + 1
    return table.remove(pins, 1)
end
ui.scene = function()
    local scene = { width = WIDTH, height = HEIGHT }
    local live = {}
    function scene:button(id, _, _, _, _, _, options)
        if not (options and options.disabled) then live[id] = true end
    end
    function scene:hotspot(id) live[id] = true end
    function scene:wait()
        actionIndex = actionIndex + 1
        local action = actions[actionIndex]
        assert(action, "the phone asked for more actions than the test has")
        if action ~= "__terminate" then
            assert(live[action],
                "tapped '" .. action .. "' but no such button is on screen")
        end
        return action
    end
    return scene
end
package.loaded["lib.ui"] = ui

-- What each app does when the phone opens it -----------------------------------

local seen = {}
local revolutionAccount

-- What both banks hold, right now. Read at the moments that matter rather
-- than at the end, because by the end the money has been to Revolution and
-- back and every balance is where it started.
local function snapshot()
    local held
    for _, account in pairs(foxy.state.accounts) do
        if account.name == "Ana Fox" then held = account end
    end
    local away = revolutionAccount
        and revo.state.accounts[revolutionAccount.account_id] or nil
    return {
        foxy = held and held.balance or nil,
        closed = held and held.bank_closed == true or false,
        moved_to_name = held and held.moved_to_name or nil,
        revolution = away and away.balance or nil,
    }
end

probes[1] = function(api)
    -- Revolution, freshly opened: the account is made here, then the phone
    -- is asked where else its owner keeps money.
    local made = assert(api.bank("TPB_REGISTER",
        { name = "Ana Fox", pin = "4321" }))
    revolutionAccount = made.account
    seen.revoSession = made.session_token
    seen.banks = api.banks()
    seen.moved, seen.moveError = api.transfer({
        account_id = made.account.bank_account_id,
        bank_name = "Revolution",
    })
    -- The app is handed an amount. Nothing else on the table it was given
    -- is the session token that authorised the move.
    seen.leaked = nil
    for key, value in pairs(api) do
        if type(value) == "string" and value:find("SESSION", 1, true) then
            seen.leaked = key
        end
    end
end

probes[2] = function(api)
    -- Foxy, coming back to an account whose money has moved out. It cannot
    -- reach into Revolution, so it asks the phone to open it.
    local identity = assert(api.request("BANK_IDENTITY", {}, true))
    seen.identity = identity
    seen.afterOut = snapshot()
    seen.foxyBanks = api.banks()
    seen.home, seen.homeError = api.handoff({
        bank = "APP00009",
        account_id = identity.bank_account_id,
        bank_name = identity.bank_name,
    })
end

probes[3] = function(api)
    -- Revolution again, opened by the phone with one job to do.
    local intent = api.intent()
    seen.intent = intent
    assert(intent, "the bank being opened must be told what it is for")
    -- Nesting is refused: an app the phone opened cannot open another one
    -- and hand the money round in a circle.
    seen.nested = { api.handoff({ bank = "FOXY", account_id = "1", }) }
    local moved = assert(api.bank("TPB_TRANSFER_CONFIRM", {
        session_token = seen.revoSession,
        bank_account_id = intent.bank_account_id,
        pin = "4321",
    }))
    api.transferred(moved.moved)
end

actions = {
    "login",
    "open:ext:APP00009",               -- open an account and bring it over
    "go",                              -- the phone's own confirmation sheet
    "open:ext:FOXY",                   -- then go back to Foxy for it
    "__terminate",
}
inputs = { "Ana Fox" }
pins = { "1234", "1234" }

package.loaded["lib.net"].autoUpdate = function() end
local realNet = package.loaded["lib.net"]
realNet.modemsOpen = function() return true end
realNet.closeModems = function() return {} end

local ok, err = pcall(assert(realLoadfile("../pumpe.lua")))
assert(ok or tostring(err):find("more actions", 1, true), tostring(err))

-- What the phone told the app it was opening ------------------------------------

assert(seen.banks, "a bank app can ask the phone where else money is kept")
local offered = {}
for _, bank in ipairs(seen.banks) do offered[bank.id] = bank end
assert(offered.FOXY, "and Foxy is one of the answers")
local foxyEntries = 0
for _, bank in ipairs(seen.banks) do
    if bank.id == "FOXY" then foxyEntries = foxyEntries + 1 end
end
assert(foxyEntries == 1,
    "exactly once: the Foxy app is a window onto the Foxy account, not a"
        .. " second bank standing beside it")
assert(offered.FOXY.balance == bankConfig.starting_balance,
    "with the balance, so the app can show what is there to move")
assert(offered.FOXY.account_id and #offered.FOXY.account_id == 16,
    "and the one address every bank on the network understands")
assert(not offered.APP00009,
    "the app asking is never in its own list; offering a bank a transfer to"
        .. " itself is the start of a loop")
assert(seen.leaked == nil,
    "the app was handed a session token in api." .. tostring(seen.leaked))
-- One for signing in and one for the transfer. An app asking the phone to
-- move an account must not be able to move it without the owner typing the
-- PIN, whoever happens to be holding the phone.
assert(pinsAsked == 2,
    "the phone asked for a PIN " .. pinsAsked .. " time(s); moving an"
        .. " account on an app's say-so is not something to do quietly")

-- The money actually moved ------------------------------------------------------

assert(seen.moved, "the transfer failed: " .. tostring(seen.moveError))
assert(seen.moved.moved == bankConfig.starting_balance,
    "everything moved, because a bank transfer moves an account rather than"
        .. " an amount")
local out = seen.afterOut
assert(out.foxy == 0 and out.closed,
    "the Foxy account is empty and closed behind it")
assert(out.moved_to_name == "Revolution", "and says where the money went")
assert(out.revolution == bankConfig.starting_balance,
    "and the same money is at Revolution, not a copy of it")

-- And came home the same way -----------------------------------------------------

assert(seen.identity and seen.identity.bank_closed,
    "Foxy knows its own account has moved out")
assert(seen.identity.moved_to_name == "Revolution",
    "and which bank to open to get it back")
assert(seen.foxyBanks and #seen.foxyBanks > 0,
    "Foxy is offered the banks its owner holds")
for _, bank in ipairs(seen.foxyBanks) do
    assert(bank.id ~= "FOXY",
        "including never itself, whether as an app or as the account")
end
assert(seen.intent, "the bank being opened is told what it was opened for")
assert(seen.intent.bank_account_id == seen.identity.bank_account_id,
    "and the destination is the phone's, not the app's: a bank being opened"
        .. " does not get to choose where the money goes")
assert(seen.nested[1] == nil,
    "an app the phone opened cannot open another one; two banks handing the"
        .. " same money to each other would never come back")
assert(seen.home, "the money came home: " .. tostring(seen.homeError))
assert(seen.home.moved == bankConfig.starting_balance,
    "all of it, and the app that asked is told the amount and nothing else")
local home = snapshot()
assert(home.revolution == 0, "Revolution is empty again")
assert(home.foxy == bankConfig.starting_balance and not home.closed,
    "and the Foxy account is open, with the money back in it")

print("host_fast_transfer_test: OK")
