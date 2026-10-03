-- An organizer sets up a sale at the Event Kiosk, FoxyOS 13, against a real
-- Bank Core and Vault: an event whose tickets go on sale later, a limit per
-- person, a presale, and invitations sent by FoxMail -- one by address, one
-- by name, one taken back. Then the Bank is asked what it ended up holding.

package.path = "../?.lua;../?/init.lua;" .. package.path

local harness = require("bank_pair_harness")
local bank = harness.pair()
local kiosk = require("kiosk_harness")

local organizer = bank.register("Ana Fox", "1234")
local kit = bank.register("Kit Wolf", "5678")
local sam = bank.register("Sam Hare", "4321")
bank.request("MAIL_CLAIM", bank.as(organizer, { name = "ana" }))
bank.request("MAIL_CLAIM", bank.as(kit, { name = "kit" }))

-- The kiosk talks to the real Bank; a refusal comes back the way the
-- network hands it over.
local function real(action, payload)
    local ok, result = pcall(bank.request, action, payload)
    if ok then return result end
    if type(result) == "table" and result.pumpe then
        return nil, result.message, result.code
    end
    error(result, 0)
end

local script = kiosk.script()
kiosk.push(script.actions, "login")
kiosk.push(script.inputs, "Ana Fox")
kiosk.push(script.pins, "1234")
-- A new event: on sale later, three each.
kiosk.push(script.actions, "create")
kiosk.push(script.inputs, "Fox Fest", "Loud", "The Den", "50", "2000")
kiosk.push(script.confirms, false)                -- not now: later
kiosk.push(script.inputs, "48", "1800", "3")      -- on sale day 48 18:00, 3 each
kiosk.push(script.confirms, true)                 -- create it
kiosk.push(script.confirms, true)                 -- add a ticket type
kiosk.push(script.inputs, "General", "Standing", "10", "100")
kiosk.push(script.confirms, false)                -- that is all
-- Its page: a presale, and invitations.
kiosk.push(script.actions, "tab:events", "event:EVT000001", function(seen)
    local frame = seen.frames[#seen.frames]
    assert(kiosk.has(frame, "ON SALE DAY 48 18:00"), "when the sale opens")
    assert(kiosk.has(frame, "3 per person"), "and the limit")
    return "presale"
end)
kiosk.push(script.inputs, "47", "1200")           -- presale day 47 12:00
kiosk.push(script.actions, "add")
kiosk.push(script.inputs, "kit@foxy.com")
kiosk.push(script.actions, "add")
kiosk.push(script.inputs, "Sam Hare")
kiosk.push(script.actions, "add")
kiosk.push(script.inputs, "nobody@foxy.com")      -- refused
kiosk.push(script.actions, function(seen)
    local frame = seen.frames[#seen.frames]
    assert(kiosk.has(frame, "2 invited"), "two on the list")
    assert(kiosk.has(frame, "no FoxMail"), "and who could not be mailed")
    return "invite:2"
end)
kiosk.push(script.confirms, true)                 -- take Sam's back
kiosk.push(script.actions, "back", function(seen)
    local frame = seen.frames[#seen.frames]
    assert(kiosk.has(frame, "PRESALE DAY 47 12:00"), "the presale, on the event")
    assert(kiosk.has(frame, "1 invited"))
    return "back"
end, "tab:home", "exit")

local seen = kiosk.run({ file = "event_kiosk.lua", bank = real, script = script,
    device = { last_name = "" }, color = { color = "orange" } })
assert(kiosk.said(seen, "EVENT CREATED"))
assert(kiosk.said(seen, "INVITE MAILED").body == "Kit Wolf")
assert(kiosk.said(seen, "INVITED").body == "Sam Hare",
    "Sam has no FoxMail address: invited, not mailed")
assert(kiosk.said(seen, "NOT INVITED").body:find("nobody@foxy.com", 1, true))

-- What the Bank holds.
local event
for _, candidate in pairs(bank.vault_state.events) do event = candidate end
assert(event.title == "Fox Fest" and event.release_day == 48
    and event.release_time == "18:00" and event.limit == 3)
assert(event.presale_day == 47 and event.presale_time == "12:00")
assert(event.invites[kit.id] and event.invites[kit.id].mailed)
assert(not event.invites[sam.id], "Sam's invite was taken back")
local inbox = bank.request("MAIL_LIST", bank.as(kit, { address = "kit@foxy.com" }))
assert(inbox.messages[1].from == "ana@foxy.com", "the invite, from the organizer")

print("host_event_presale_test: OK")
