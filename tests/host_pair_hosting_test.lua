-- What each half of a pair claims on the network.
--
-- This is the test that was missing when 9.0 shipped. host_pair_mode_test
-- loads both Banks in test mode, which returns before any hosting happens,
-- and host_bank_bootstrap_test stubbed rednet.host as a no-op that could
-- never fail. Between them nothing exercised the startup block against
-- ComputerCraft's actual behaviour: rednet.host throws "Hostname in use"
-- when another computer already holds the name.
--
-- So both halves of a pair claimed LEDGER_0001 -- they are one bank and
-- share one bank code -- and whichever started second died on the spot.
-- A stub more permissive than the real thing is a test that cannot fail.

package.path = "../?.lua;../?/init.lua;" .. package.path

colors = setmetatable({}, { __index = function() return 1 end })

-- The network, with ComputerCraft's rule about names.
local net = { hosts = {} }
function net.reset() net.hosts = {} end
function net.lookup(protocol, hostname)
    return net.hosts[protocol .. "/" .. hostname]
end
function net.claim(computer, protocol, hostname)
    local key = protocol .. "/" .. hostname
    local holder = net.hosts[key]
    if holder and holder ~= computer then
        -- Word for word what ComputerCraft raises.
        error("Hostname in use", 2)
    end
    net.hosts[key] = computer
end
function net.release(computer, protocol)
    for key, holder in pairs(net.hosts) do
        if holder == computer and key:sub(1, #protocol + 1) == protocol .. "/" then
            net.hosts[key] = nil
        end
    end
end
function net.claimedBy(computer)
    local names = {}
    for key, holder in pairs(net.hosts) do
        if holder == computer then names[#names + 1] = key end
    end
    table.sort(names)
    return names
end

local files, directories = {}, { ["/"] = true, ["/pumpe"] = true }
local drawn

fs = {
    getDir = function(path)
        return (tostring(path):match("^(.*)/[^/]*$")) or ""
    end,
    combine = function(left, right)
        left = tostring(left or ""):gsub("/+$", "")
        right = tostring(right or ""):gsub("^/+", "")
        if left == "" then return right end
        return left .. "/" .. right
    end,
    exists = function(path)
        return files[path] ~= nil or directories[path] == true
    end,
    isDir = function(path) return directories[path] == true end,
    makeDir = function(path) directories[path] = true end,
    delete = function(path) files[path] = nil directories[path] = nil end,
    move = function(from, to) files[to] = files[from] files[from] = nil end,
    getSize = function(path) return #(files[path] or "") end,
    getFreeSpace = function() return 500000 end,
    list = function() return {} end,
    open = function(path, mode)
        if mode:find("r") then
            if not files[path] then return nil end
            local body = files[path]
            return { readAll = function() return body end,
                     read = function() return nil end,
                     close = function() end }
        end
        local chunks = {}
        return { write = function(value) chunks[#chunks + 1] = tostring(value) end,
                 close = function() files[path] = table.concat(chunks) end }
    end,
}

local display = {
    getSize = function() return 51, 19 end,
    isColor = function() return true end,
    setBackgroundColor = function() end, setTextColor = function() end,
    setCursorBlink = function() end, clear = function() end,
    setCursorPos = function() end,
    write = function(value) drawn[#drawn + 1] = tostring(value) end,
}
term = { current = function() return display end }
shell = { getRunningProgram = function() return "/pumpe/bank_server.lua" end }
sleep = function() end
os.day = function() return 7 end
os.time = function() return 12 end
os.epoch = function() return 1000 end
os.startTimer = function() return 1 end
os.queueEvent = function() end

local scriptedTaps, ticks = {}, 0
os.pullEvent = function()
    local tap = table.remove(scriptedTaps, 1)
    if tap then return "mouse_click", 1, tap[1], tap[2] end
    -- A screen waiting for a tap that never comes would otherwise spin
    -- forever. Fail loudly instead of hanging the suite.
    ticks = ticks + 1
    if ticks > 200 then
        error("the Bank is still waiting for input after 200 ticks", 0)
    end
    return "timer", 1
end

peripheral = { getNames = function() return {} end,
    getType = function() return "modem" end }
textutils = {
    serialize = function(value)
        local function render(item)
            if type(item) ~= "table" then
                return string.format("%q", tostring(item))
            end
            local parts = {}
            for key, entry in pairs(item) do
                parts[#parts + 1] = ("[%q] = %s"):format(tostring(key),
                    render(entry))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
        return render(value)
    end,
    unserialize = function(body)
        local loader = (loadstring or load)("return " .. tostring(body))
        if not loader then return nil end
        local ok, value = pcall(loader)
        -- Everything comes back as a string through the serializer above,
        -- so put the two shapes the Bank actually reads back.
        if ok and type(value) == "table" then
            for key, item in pairs(value) do
                if item == "true" then value[key] = true
                elseif item == "false" then value[key] = false
                elseif tonumber(item) then value[key] = tonumber(item) end
            end
            return value
        end
        return nil
    end,
    unserializeJSON = function() return nil end,
}

-- The Bank runs forever once it is up; stop it the moment it gets there.
parallel = { waitForAny = function() error("__BANK_STARTED__", 0) end }

-- Boot one Bank Server as `computer`, with `pairing` already on its disk.
local function boot(computer, pairing, taps, options)
    options = options or {}
    drawn = {}
    files, directories = {}, { ["/"] = true, ["/pumpe"] = true,
        ["/updates"] = true }
    -- The marker line is what the Bank looks for to accept this as its
    -- copy of Easy Deployment.
    files["/pumpe/installer.lua"] =
        "-- PUMPE EASY DEPLOYMENT\n-- This file is intentionally standalone.\n"
    files["/updates/public/config.lua"] = "-- public config\n"
    -- The Bank stops on its depot check if its own runtime is not beside
    -- it, and never gets as far as hosting anything.
    for _, name in ipairs({ "bank_server.lua", "config.lua", "lib/net.lua",
        "lib/ui.lua", "lib/update.lua", "lib/util.lua" }) do
        files["/pumpe/" .. name] = "-- installed " .. name .. "\n"
    end
    -- startup.lua is installed as installer.lua, and the depot serves it
    -- under its published name.
    files["/updates/startup.lua"] = "-- PUMPE EASY DEPLOYMENT\n"
    for _, name in ipairs({ "pumpe.lua", "service_kiosk.lua",
        "event_kiosk.lua", "tax_controller.lua", "admin_terminal.lua",
        "border_controller.lua", "ccg.lua", "gps_anchor.lua",
        "app_server.lua", "foxy.lua", "bank_app_server.lua",
        "buckapp.lua" }) do
        files["/updates/" .. name] = "-- depot " .. name .. "\n"
    end
    if pairing then
        files["/pumpe/bank_pair_v1.dat"] = textutils.serialize(pairing)
    end
    scriptedTaps, ticks = taps or {}, 0
    os.getComputerID = function() return computer end
    -- A computer that has been made the Vault restarts into bank_vault.lua
    -- rather than carrying on as a Bank Server, so a reboot here is an
    -- outcome to assert rather than a crash.
    os.reboot = function() error("__REBOOTED__", 0) end
    rednet = {
        host = function(protocol, hostname)
            net.claim(computer, protocol, hostname)
        end,
        unhost = function(protocol) net.release(computer, protocol) end,
        lookup = function(protocol, hostname)
            return net.lookup(protocol, hostname)
        end,
        isOpen = function() return true end,
        open = function() end,
        receive = function() return nil end,
        send = function() return true end,
    }
    for name in pairs(package.loaded) do
        if name:find("^lib%.") or name == "config" then
            package.loaded[name] = nil
        end
    end
    package.loaded["lib.net"] = {
        host = function(protocol, hostname)
            -- lib/net unhosts its own name first, which is how a restart of
            -- the same computer is not a clash with itself.
            net.release(computer, protocol)
            net.claim(computer, protocol, hostname)
        end,
        unhost = function(protocol) net.release(computer, protocol) end,
        openModems = function() return { "modem" } end,
        receive = function() return nil end,
        reply = function() end, send = function() end,
        locate = function() return nil end,
        autoUpdate = function() end,
        client = function() return {
            discover = function() return nil end,
            request = function() return nil, "offline" end,
        } end,
    }
    local ok, err = pcall(assert(loadfile("../bank_server.lua")))
    assert(not ok, "the Bank should have reached its main loop")
    if options.expect_reboot then
        assert(tostring(err) == "__REBOOTED__",
            "computer #" .. computer .. " should have restarted into"
                .. " bank_vault.lua, but got: " .. tostring(err))
        return true
    end
    if tostring(err) ~= "__BANK_STARTED__" then
        print("---- screen for #" .. computer .. " ----")
        print(table.concat(drawn, "|"))
    end
    assert(tostring(err) == "__BANK_STARTED__",
        "computer #" .. computer .. " failed before its main loop: "
            .. tostring(err))
end

local function has(computer, name)
    for _, claimed in ipairs(net.claimedBy(computer)) do
        if claimed == name then return true end
    end
    return false
end

-- A Bank with no Vault yet claims everything ------------------------------------

net.reset()
-- Tapping BANK ONLY on the launch screen.
boot(11, nil, { { 40, 17 } })
assert(has(11, "PUMPE_BANK_V5/BANK_SERVER"),
    "a Bank with no Vault is still the bank")
assert(has(11, "PUMPE_DEPLOY_V5/PUMPE_UPDATES"), "and serves its own depot")
assert(has(11, "PUMPE_LEDGER_V1/LEDGER_0001"),
    "and answers for bank 0001, so transfers can reach it")

-- A pair claims each name exactly once -------------------------------------------

net.reset()
boot(11, { role = "core", partner = "22" })
assert(has(11, "PUMPE_BANK_V5/BANK_SERVER"), "the Core does the banking")
assert(has(11, "PUMPE_LEDGER_V1/LEDGER_0001"),
    "and is the half that answers the ledger, because it is the half that"
        .. " runs ledgerLoop")
assert(has(11, "PUMPE_DEPLOY_V5/PUMPE_UPDATES"),
    "Easy Deployment stays on the Core: a Vault that holds the installer is"
        .. " a Vault you cannot reinstall once it breaks")

-- A computer whose pairing file says it is a Vault is not running the right
-- program. Since 9.3 a Vault runs bank_vault.lua, so bank_server.lua's job
-- on such a computer is to fetch it, point startup at it and restart --
-- never to come up as half a Bank Server and start claiming names.
local becameVault = boot(22, { role = "vault", partner = "11" },
    nil, { expect_reboot = true })
assert(becameVault, "a Vault reboots into bank_vault.lua")
assert(#net.claimedBy(22) == 0,
    "and claims nothing on the way out: it is not the Bank, and a name it"
        .. " held would be a name its own Core could not have")

-- The bug that made this rule: both halves are one bank and share one bank
-- code, so a Vault claiming the ledger name took the one its Core needed and
-- killed whichever started second with "Hostname in use".
assert(net.lookup("PUMPE_LEDGER_V1", "LEDGER_0001") == 11,
    "LEDGER_0001 still resolves to the Core")
assert(net.lookup("PUMPE_DEPLOY_V5", "PUMPE_UPDATES") == 11)
assert(net.lookup("PUMPE_BANK_V5", "BANK_SERVER") == 11)

print("host_pair_hosting_test: OK")
