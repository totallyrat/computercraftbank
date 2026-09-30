-- The Event Kiosk, 12.0: three tabs -- Home, Events, Door -- and More.
--
-- An organizer signs in, the kiosk asks for its colour once, and every page
-- is reached from the tab bar: the numbers on Home, the list on Events, the
-- two ways in at the Door. More lists all of it, with the colour and the
-- way out. Every screen is bounds checked on an Advanced Computer.

local kiosk = require("kiosk_harness")

local events = {
    { event_id = "EVT1", title = "Fox Fest", status = "active", event_day = 50,
      event_time = "18:00", ticket_types = { { name = "Entry", price = 5,
        sold_quantity = 3, total_quantity = 10 } } },
}
local verified
local function bank(action, payload)
    if action == "LOGIN" then
        assert(payload.name == "Ana Fox" and payload.pin == "1234")
        return { session_token = "S1", account = { name = "Ana Fox" } }
    elseif action == "EVENT_DASHBOARD" then
        return { active_events = 1, tickets_sold = 3, revenue = 15 }
    elseif action == "MY_EVENTS" then
        return { events = events }
    elseif action == "VERIFY_TICKET" then
        verified = payload.code
        return nil, "No such ticket", "NOT_FOUND"
    end
    error("unexpected request " .. action)
end

local script = kiosk.script()
kiosk.push(script.actions, "login")
kiosk.push(script.inputs, "Ana Fox")
kiosk.push(script.pins, "1234")
kiosk.push(script.actions, function(seen)
    local frame = seen.frames[#seen.frames]
    assert(kiosk.has(frame, "EVENT DASHBOARD") and kiosk.has(frame, "REVENUE"))
    assert(kiosk.has(frame, "Home") and kiosk.has(frame, "Events")
        and kiosk.has(frame, "Door") and not kiosk.has(frame, "More"),
        "the three tabs, and no More")
    assert(kiosk.has(frame, "COLOUR") and kiosk.has(frame, "LOG OUT")
        and kiosk.has(frame, "CLOSE"), "the kiosk's own controls are on Home")
    return "tab:events"
end, function(seen)
    assert(kiosk.has(seen.frames[#seen.frames], "Fox Fest"), "the Events tab lists them")
    return "tab:door"
end, "verify")
kiosk.push(script.inputs, "ABCD2345")
kiosk.push(script.actions, "tab:home", "color", "exit")

local seen = kiosk.run({ file = "event_kiosk.lua", bank = bank, script = script,
    device = { last_name = "" } })
assert(seen.picked == 2, "the colour is picked when the kiosk is set up, and again from Home")
assert(verified == "ABCD2345", "the Door verifies by entry code")
assert(kiosk.said(seen, "TICKET REJECTED"))

-- And on a pocket-sized screen nothing leaves it either.
script = kiosk.script()
kiosk.push(script.actions, "login", "tab:events", "tab:door", "tab:home", "exit")
kiosk.push(script.inputs, "Ana Fox")
kiosk.push(script.pins, "1234")
kiosk.run({ file = "event_kiosk.lua", bank = bank, script = script, width = 39,
    height = 13, device = { last_name = "Ana Fox" }, color = { color = "orange" } })

print("host_event_kiosk_test: OK")
