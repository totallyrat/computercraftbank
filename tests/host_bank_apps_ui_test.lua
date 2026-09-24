-- Revolution and BuckApp on a 26x20 PUMPE, each against a real 3rd Party
-- Bank Server running its bank.
--
-- 11.0 moved both from a grid of buttons onto the bottom tab bar every app
-- uses. This walks every tab of each, bounds checked, and every button a tab
-- shows has to be one a person can actually reach.

package.path = "../?.lua;../?/init.lua;" .. package.path

local harness = require("bank_pair_harness")
local bank = harness.pair()
local phone = require("phone_app_harness")

-- A 3rd Party Bank Server, loaded for real, hosting one bank app.
local function bankServer(appId, name)
    local saved = {}
    for moduleName in pairs(package.loaded) do
        if moduleName:find("^lib%.") or moduleName == "config" then
            package.loaded[moduleName] = nil
        end
    end
    local util = require("lib.util")
    util.loadTable = function(path, fallback)
        return saved[path] or util.copy(fallback)
    end
    util.saveTable = function(path, value) saved[path] = util.copy(value) end
    package.loaded["lib.ui"] = setmetatable({ theme = {} }, {
        __index = function() return function() end end,
    })
    term = { current = function()
        return { getSize = function() return 51, 19 end }
    end }
    rednet = { host = function() end, unhost = function() end,
        lookup = function() return nil end, receive = function() return nil end,
        send = function() return true end }
    package.loaded["lib.net"] = {
        openModems = function() return { "modem" } end,
        host = function() end, reply = function() end,
        locate = function() return nil end, autoUpdate = function() end,
        client = function()
            return { request = function() return nil, "not wired" end,
                discover = function() return nil end }
        end,
    }
    PUMPE_TEST_MODE = true
    local server = assert(loadfile("../bank_app_server.lua"))()
    PUMPE_TEST_MODE = nil
    server.adopt({ app_id = appId, bank_name = name })
    return function(action, payload)
        local handler = server.actions[action]
        if not handler then return nil, "Unknown", "UNKNOWN_ACTION" end
        local ok, result = pcall(handler, payload or {}, 9)
        if ok then return result end
        if type(result) == "table" and result.pumpe then
            return nil, result.message, result.code
        end
        error(result, 0)
    end
end

local kit = bank.register("Kit Wolf", "5678")

local function walk(file, appId, name, tabs, check)
    local server = bankServer(appId, name)
    assert(server("TPB_REGISTER", { name = "Kit Wolf", pin = "4321" }))
    local script = phone.script()
    phone.push(script.actions, "in")
    phone.push(script.inputs, "Kit Wolf")
    phone.push(script.pins, "4321")
    for _, tab in ipairs(tabs) do
        phone.push(script.actions, function(seen)
            local frame = phone.last(seen)
            for _, label in ipairs(check[tab.before] or {}) do
                assert(phone.has(frame, label), name .. ": " .. label
                    .. " is on the " .. tab.before .. " tab")
            end
            return tab.tap
        end)
    end
    phone.push(script.actions, "home")
    phone.run({ bank = bank, who = kit, file = file, script = script,
        app_id = appId, bank_app = server })
end

-- Revolution opens on Take, the reason it exists.
walk("../revolution.lua", "REVO", "Revolution", {
    { before = "take", tap = "tab:pay" },
    { before = "pay", tap = "tab:account" },
    { before = "account", tap = "tab:take" },
}, {
    take = { "Take a payment", "Clearing", "Take", "Pay", "Account" },
    pay = { "Pay nearby", "Pay kiosk by code" },
    account = { "My Account ID", "Bring money in", "Move money out" },
})

-- BuckApp opens on Money.
walk("../buckapp.lua", "BUCK", "BuckApp", {
    { before = "money", tap = "tab:account" },
    { before = "account", tap = "tab:money" },
}, {
    money = { "Send", "Activity", "Money", "Account" },
    account = { "My Account ID", "Move money out", "Sign out" },
})

print("host_bank_apps_ui_test: OK")
