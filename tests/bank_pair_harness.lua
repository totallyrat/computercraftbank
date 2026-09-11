-- A Bank, both halves of it.
--
-- Since 9.3 a request can be answered by either computer, and the two answer
-- differently: the Core knows who you are and what your money is, the Vault
-- knows everything else. A test that stands up only one half, or that fakes
-- the other with a table of canned replies, tests neither. Worse, a fake is
-- always more forgiving than the real thing -- that is exactly how the "app
-- has no id" bug reached a player in 9.4.2: the test's Bank accepted a
-- payload the real Bank rejects.
--
-- So this loads both real programs and wires their two ends of the cable to
-- each other. Anything that would be refused in the game is refused here.

local harness = {}

function harness.stubWorld(computerId)
    colors = {
        white = 1, orange = 2, magenta = 4, lightBlue = 8,
        yellow = 16, lime = 32, pink = 64, gray = 128,
        lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
        brown = 4096, green = 8192, red = 16384, black = 32768,
    }
    -- A test that runs its own clock keeps it. Several of these were written
    -- against a single Bank and advance time by hand to watch something
    -- expire; taking that away from them would be the harness quietly
    -- changing what they test.
    harness.day = harness.day or 300
    harness.time = harness.time or 12
    harness.epoch = harness.epoch or 1000000
    if type(os.day) ~= "function" then
        os.day = function() return harness.day end
    end
    if type(os.time) ~= "function" then
        os.time = function() return harness.time end
    end
    if type(os.epoch) ~= "function" then
        os.epoch = function() return harness.epoch end
    end
    os.getComputerID = function() return computerId or 1 end
    fs = {
        getDir = function() return "/pumpe" end,
        combine = function(left, right)
            return tostring(left):gsub("/+$", "") .. "/"
                .. tostring(right):gsub("^/+", "")
        end,
        exists = function() return false end,
        isDir = function() return false end,
    }
    shell = { getRunningProgram = function() return "/pumpe/bank_server.lua" end }
end

-- One end of the cable. Calling straight into the other half's handler is
-- what a wired modem amounts to: no loss, no reordering, and an error that
-- arrives as an error.
local function link(handlers, fromId)
    return function(action, payload, timeout)
        local handler = handlers[action]
        if not handler then
            return nil, "Unknown pair action", "UNKNOWN_ACTION"
        end
        local ok, result = pcall(handler, payload or {}, fromId)
        if ok then return result end
        if type(result) == "table" and result.pumpe then
            return nil, result.message, result.code
        end
        error(result, 0)
    end
end

-- Loads both programs and pairs them. `coreId` and `vaultId` are the two
-- computer ids, which is all either half knows about the other.
function harness.pair(options)
    options = options or {}
    local coreId = options.core_id or 1
    local vaultId = options.vault_id or 2

    harness.stubWorld(coreId)
    -- Neither half writes to disk in a test, and each gets its own state
    -- because loadTable hands back a fresh copy of the fallback.
    local util = require("lib.util")
    util.loadTable = function(_, fallback) return util.copy(fallback) end
    util.saveTable = function() end
    package.loaded["lib.util"] = util

    PUMPE_TEST_MODE = true
    local core = assert(loadfile("../bank_server.lua"))()
    local vault = assert(loadfile("../bank_vault.lua"))()
    PUMPE_TEST_MODE = nil

    core.pair.role = "core"
    core.pair.partner = vaultId
    core.pair.wired = true
    vault.core.id = coreId

    core.pair.ask = link(vault.vault, coreId)
    vault.core.ask = link(core.pair.actions, vaultId)

    -- Anything the Core exports and this harness does not override -- the
    -- ledger, the app store, the sweeps -- reads straight through, so a test
    -- written against a single Bank still reaches what it reached before.
    local bank = setmetatable({
        core = core, vault = vault,
        state = core.state,
        vault_state = vault.state,
        core_id = coreId, vault_id = vaultId,
    }, { __index = core })

    -- Every action the Bank answers, whichever half ends up answering it,
    -- under the names a client uses. A test says actions.CHAT_SEND and does
    -- not have to know -- or keep up with -- which computer that now lands on.
    bank.actions = setmetatable({}, {
        __index = function(_, name)
            local spec = core.routes[name]
            if spec then
                return function(payload)
                    return core.route_to_vault(name, spec, payload or {})
                end
            end
            return core.actions[name]
        end,
    })

    -- Exactly what the server loop does with an incoming request: answer it
    -- here, or apply this Bank's rule for it and pass it down the cable.
    function bank.request(action, payload)
        local spec = core.routes[action]
        if spec then
            return core.route_to_vault(action, spec, payload or {})
        end
        local handler = core.actions[action]
        assert(handler, "no such bank action: " .. tostring(action))
        return handler(payload or {})
    end

    -- Time, for the tests that need tomorrow or a call that rang out.
    function bank.advanceMs(milliseconds)
        harness.epoch = harness.epoch + milliseconds
    end

    function bank.advanceDays(days)
        harness.day = harness.day + days
    end

    -- Time passing. Both halves have a sweep now, and a test that advances
    -- the clock means both of them to run.
    function bank.cleanup()
        core.cleanup()
        vault.sweep_travel()
        vault.cleanup_calls()
    end

    -- Cutting the cable, for the tests that care what happens then.
    function bank.unplug()
        core.pair.ask = function()
            return nil, "The Vault is not answering", nil
        end
    end

    function bank.replug()
        core.pair.ask = link(vault.vault, coreId)
    end

    -- The Vault pushes unread counts and ringing calls up to the Core on a
    -- timer in the game. Tests step it by hand so they never depend on one.
    function bank.sync()
        vault.push_badges()
        vault.sync_waiting()
    end

    function bank.register(name, pin)
        local created = bank.request("REGISTER",
            { name = name, pin = pin, gender = "Not set" })
        return {
            token = created.session_token,
            id = created.account.account_id,
            name = name, pin = pin,
        }
    end

    function bank.as(who, extra)
        local payload = { session_token = who.token }
        for key, value in pairs(extra or {}) do payload[key] = value end
        return payload
    end

    -- Money has to come from somewhere in a test, and only the government
    -- can make it. This is the same route an admin terminal uses.
    function bank.fund(who, amount)
        core.state.government_key = "TESTKEY"
        local session = bank.request("GOVERNMENT_LOGIN", { key = "TESTKEY" })
        bank.request("ADMIN_CREDIT", {
            government_token = session.government_token,
            account_id = who.id, amount = amount, reason = "Test funding",
        })
        return session.government_token
    end

    function bank.balanceOf(who)
        return core.state.accounts[who.id].balance
    end

    return bank
end

-- Every refusal in this system is a coded error, so a test that only checks
-- "it failed" would pass on the wrong failure.
function harness.rejected(fn, expectedCode, ...)
    local ok, result = pcall(fn, ...)
    assert(not ok, "that should have been refused, but it worked")
    assert(type(result) == "table" and result.code == expectedCode,
        "expected " .. expectedCode .. ", got "
            .. tostring(type(result) == "table" and result.code or result))
    return result
end

return harness
