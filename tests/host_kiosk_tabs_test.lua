-- 12.0: every kiosk on three tabs and More, run whole on an Advanced
-- Computer against a scripted Bank. The Event Kiosk has its own test; this
-- one has the Admin Terminal and the Border Controller.

local kiosk = require("kiosk_harness")

-- Admin Terminal: Tax, People, Inbox ------------------------------------------------

local function government(action, payload)
    if action == "GOVERNMENT_LOGIN" then
        assert(payload.key == "Government1234")
        return { government_token = "G1" }
    elseif action == "GOVERNMENT_STATS" then
        return { tax_revenue = 120, accounts = 5 }
    elseif action == "ADMIN_MESSAGE_THREADS" then
        return { threads = { { account_id = "A1", name = "Ana Fox",
            last_body = "About my tax", waiting = true } } }
    elseif action == "ADMIN_ACCOUNTS" then
        assert(payload.pending_only == true)
        return { accounts = { { account_id = "A2", name = "Kit Wolf", balance = 10,
            approved = false } } }
    end
    error("unexpected request " .. action)
end

local script = kiosk.script()
kiosk.push(script.actions, "login")
kiosk.push(script.inputs, "Government1234", false)
kiosk.push(script.actions, function(seen)
    local frame = seen.frames[#seen.frames]
    assert(kiosk.has(frame, "TAX REVENUE") and kiosk.has(frame, "OPEN PERIOD")
        and kiosk.has(frame, "CLOSE PERIOD"), "Tax has the period controls")
    assert(kiosk.has(frame, "Tax") and kiosk.has(frame, "People")
        and kiosk.has(frame, "Inbox") and kiosk.has(frame, "More"))
    return "tab:people"
end, function(seen)
    assert(kiosk.has(seen.frames[#seen.frames], "FIND ACCOUNT"))
    -- Cancelling the search goes back; it does not list everybody.
    return "accounts"
end, "pending", function(seen)
    assert(kiosk.has(seen.frames[#seen.frames], "Kit Wolf"),
        "pending approval lists who is waiting")
    return "back"
end, "tab:inbox", function(seen)
    assert(kiosk.has(seen.frames[#seen.frames], "Ana Fox"), "the Inbox tab has the threads")
    return "tab:more"
end)
kiosk.push(script.more, function(seen)
    local ids = {}
    for _, entry in ipairs(seen.more[#seen.more].more) do ids[entry.id] = true end
    for _, id in ipairs({ "open", "rates", "close", "deposit", "revenue", "audit",
        "accounts", "pending", "announce", "controls", "stats", "system", "color",
        "lock" }) do
        assert(ids[id], "More has " .. id)
    end
    return "lock"
end)
kiosk.push(script.actions, "exit")
local seen = kiosk.run({ file = "admin_terminal.lua", bank = government, script = script })
assert(seen.picked == 1, "a new terminal picks its colour once it is unlocked")

-- Border Controller: Gate, Scan, Owner ----------------------------------------------

local pinTries = {}
local function border(action, payload)
    if action == "BORDER_STATUS" then
        return { controller_id = "B1", territory_id = "T1", territory_name = "Foxy Republic",
            label = "Border #77" }
    elseif action == "BORDER_OWNER_PIN" then
        pinTries[#pinTries + 1] = payload.pin
        if payload.pin == "1234" then return { authorized = true } end
        return nil, "Owner PIN is incorrect", "BAD_PIN"
    end
    error("unexpected request " .. action)
end
local device = { controller_id = "B1", controller_token = "T", territory_id = "T1",
    territory_name = "Foxy Republic", label = "Border #77" }
script = kiosk.script()
kiosk.push(script.actions, function(seen)
    local frame = seen.frames[#seen.frames]
    assert(kiosk.has(frame, "ENTER TERRITORY") and kiosk.has(frame, "Gate")
        and kiosk.has(frame, "Owner"))
    return "tab:owner"
end, "color", "color", "tab:scan", function(seen)
    assert(kiosk.has(seen.frames[#seen.frames], "TURN ON"))
    return "tab:more"
end)
kiosk.push(script.pins, "0000", "1234")
kiosk.push(script.more, "stop")
kiosk.push(script.pins, "1234")
seen = kiosk.run({ file = "border_controller.lua", bank = border, script = script,
    device = device, color = { color = "blue" } })
assert(kiosk.said(seen, "LOCKED"), "the colour is the owner's: a wrong PIN is refused")
assert(seen.picked == 1, "and the right one opens the picker")
assert(#pinTries == 3, "closing from More asks for the PIN too")

-- Delivery Terminal: Open, Done, Pickup ---------------------------------------------

local function deliveries(action)
    if action == "KIOSK_REGISTER" then
        return { terminal_id = "T9", terminal_token = "K", name = "Warehouse" }
    elseif action == "KIOSK_STATE" then
        return { company = { company_id = "C1", name = "Fox Goods" } }
    elseif action == "DELIVERY_ORDERS" then
        return { orders = {
            { order_id = "ORD1", buyer_name = "Kit Wolf", status = "open",
              stage = "Packing", delivery = { kind = "home", x = 1, y = 2, z = 3 } },
            { order_id = "ORD2", buyer_name = "Rob Hare", status = "done",
              stage = "Delivered", delivery = { kind = "home", x = 1, y = 2, z = 3 } },
        }, stages = {} }
    end
    error("unexpected request " .. action)
end
script = kiosk.script()
kiosk.push(script.actions, function(seen)
    local frame = seen.frames[#seen.frames]
    assert(kiosk.has(frame, "ORD1") and not kiosk.has(frame, "ORD2"), "Open is what is open")
    assert(kiosk.has(frame, "Open") and kiosk.has(frame, "Done") and kiosk.has(frame, "Pickup"))
    return "tab:done"
end, function(seen)
    local frame = seen.frames[#seen.frames]
    assert(kiosk.has(frame, "ORD2") and not kiosk.has(frame, "ORD1"), "and Done is the rest")
    return "tab:pickup"
end, function(seen)
    assert(kiosk.has(seen.frames[#seen.frames], "SET UP A PICKUP POINT"))
    return "tab:more"
end, "tab:more")
kiosk.push(script.more, "color", "close")
kiosk.push(script.confirms, true)
seen = kiosk.run({ file = "delivery_terminal.lua", bank = deliveries, script = script,
    device = { terminal_id = "T9", terminal_token = "K", name = "Warehouse",
        mode = "board" }, color = { color = "green" } })
assert(seen.picked == 1, "the colour is in More")

print("host_kiosk_tabs_test: OK")
