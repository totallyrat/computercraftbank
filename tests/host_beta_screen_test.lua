-- Beta Updates on every device, FoxyOS 15.1, drawn by the real lib/ui.
--
-- One screen, shared by every server, kiosk, terminal and console: whether
-- this device is signed up, what it runs, and Sign up or Leave -- each asked
-- first. Every server's Server tab reaches it; the Bank's warns that a beta
-- there is a beta for everybody. The choice is a file beside the programs.

package.path = "../?.lua;../?/init.lua;" .. package.path
local screen = dofile("screen_harness.lua")

local disk = {}
fs = {
    combine = function(a, b) return tostring(a):gsub("/+$", "") .. "/" .. tostring(b):gsub("^/+", "") end,
    getDir = function(path) return tostring(path):match("^(.*)/[^/]+$") or "" end,
    exists = function(path) return disk[path] ~= nil end,
    isDir = function() return false end,
    makeDir = function() end,
    delete = function(path) disk[path] = nil end,
    move = function(from, to) disk[to], disk[from] = disk[from], nil end,
    open = function(path, mode)
        if mode == "r" then
            if not disk[path] then return nil end
            return { readAll = function() return disk[path] end, close = function() end }
        end
        local chunks = {}
        return { write = function(v) chunks[#chunks + 1] = tostring(v) end,
            close = function() disk[path] = table.concat(chunks) end }
    end,
}
textutils = textutils or {}
textutils.serialize = function(value)
    return "{ joined = " .. tostring(value.joined) .. " }"
end
textutils.unserialize = function(body)
    local built = load("return " .. body)
    return built and built()
end
local util = require("lib.util")

-- A kiosk: sign up, then leave ------------------------------------------------------

local display = screen.terminal(51, 19)
local steps = {}
local ui = screen.install({ display = display, steps = steps, event = "mouse_click" })
screen.push(steps, function()
    assert(display.has("BETA UPDATES") and display.has("Not signed up"))
    assert(display.has("Running v15.1.0"), "what it runs")
    return "join"
end, function()
    assert(display.has("SIGN UP?"), "asked first")
    return "yes"
end, function()
    assert(util.betaJoined("/pumpe"), "signed up, on disk")
    assert(disk["/pumpe/beta_updates.dat"], "beside the programs")
    assert(display.has("Signed up") and display.has("installs each beta by itself"))
    return "leave"
end, "no", function()
    assert(util.betaJoined("/pumpe"), "staying is staying")
    return "leave"
end, "yes", function()
    assert(not util.betaJoined("/pumpe"), "left")
    return "back"
end)
ui.betaUpdates(display, "/pumpe", { kind = "kiosk", version = "15.1.0" })
assert(#steps == 0, "the whole screen was walked")

-- On a beta, leaving says it keeps the beta until the full release.
util.setBetaJoined("/pumpe", true)
steps = {}
ui = screen.install({ display = display, steps = steps, event = "mouse_click" })
screen.push(steps, function()
    assert(display.has("Running v15.5.0  (a beta)"), "a beta says so")
    return "leave"
end, function()
    assert(display.has("keeps this beta until the full release"))
    return "yes"
end, "back")
ui.betaUpdates(display, "/pumpe", { kind = "console", version = "15.5.0" })

-- A server: on its Server tab, with the Bank's warning --------------------------------

steps = {}
ui = screen.install({ display = display, steps = steps, event = "mouse_click" })
local running = true
screen.push(steps, "tab:server", function()
    assert(display.has("BETA UPDATES"), "every server has it on its Server tab")
    return "__beta"
end, function()
    assert(display.has("a beta here is a beta for everybody"), "the Bank warns first")
    return "join"
end, "yes", "back", function()
    assert(display.has("BETA: ON"), "and shows it is on")
    running = false
    return { tick = true }
end)
ui.serverTabs({ target = display, title = "BANK SERVER", version = "15.1.0",
    betaRoot = "/bank", betaWarning = "Every Pocket uses this Bank, and the Vault"
        .. " follows it: a beta here is a beta for everybody.",
    running = function() return running end })
assert(util.betaJoined("/bank"), "the Bank signed up")

-- A server that follows another -- the Vault -- has no button of its own.
steps = {}
ui = screen.install({ display = display, steps = steps, event = "mouse_click" })
running = true
screen.push(steps, "tab:server", function()
    assert(not display.has("BETA"), "the Vault follows its Core")
    running = false
    return { tick = true }
end)
ui.serverTabs({ target = display, title = "VAULT", running = function() return running end })

print("host_beta_screen_test: OK")
