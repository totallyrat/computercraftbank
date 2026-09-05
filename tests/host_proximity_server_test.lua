-- Proximity ticket scanning, Proximity Visa, and Portable Mode on the Bank.
-- All three ask the nearest PUMPE holding the right thing up, rather than
-- anybody reading a code out loud.

package.path = "../?.lua;../?/init.lua;" .. package.path

colors = {
    white = 1, orange = 2, magenta = 4, lightBlue = 8,
    yellow = 16, lime = 32, pink = 64, gray = 128,
    lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
    brown = 4096, green = 8192, red = 16384, black = 32768,
}

local currentDay, clock = 100, 1000000
os.day = function() return currentDay end
os.time = function() return 12 end
os.epoch = function() return clock end
os.getComputerID = function() return 1 end

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

local util = require("lib.util")
util.loadTable = function(_, fallback) return util.copy(fallback) end
util.saveTable = function() end
package.loaded["lib.util"] = util

PUMPE_TEST_MODE = true
local bank = assert(loadfile("../bank_server.lua"))()
PUMPE_TEST_MODE = nil
local actions = bank.actions

local function rejected(action, expectedCode, payload)
    local ok, result = pcall(action, payload)
    assert(not ok, "request should have been rejected")
    assert(type(result) == "table" and result.code == expectedCode,
        "expected " .. expectedCode .. ", got " .. tostring(result.code))
end

local function register(name)
    return actions.REGISTER({ name = name, pin = "1234", gender = "Not set" })
end

local organizer = register("Venue Owner")
local guest = register("Ticket Holder")
local stranger = register("Passer By")
local at = function(x, z) return { x = x, y = 64, z = z } end

-- Proximity ticket scanning --------------------------------------------------

local event = actions.CREATE_EVENT({
    session_token = organizer.session_token,
    title = "Riverside Festival",
    event_day = currentDay + 5,
    event_time = "18:30",
    location = "Riverside Arena",
})
local ticketType = actions.ADD_TICKET_TYPE({
    session_token = organizer.session_token,
    event_id = event.event.event_id,
    name = "General Admission",
    price = 10,
    quantity = 50,
})
local bought = actions.BUY_TICKETS({
    session_token = guest.session_token,
    event_id = event.event.event_id,
    ticket_type_id = ticketType.ticket_type.ticket_type_id,
    quantity = 1,
    pin = "1234",
})
local ticketId = bought.tickets[1].ticket_id

-- Nobody has a ticket on screen yet, so the door finds no one.
local quiet = actions.TICKET_SCAN({
    session_token = organizer.session_token,
    event_id = event.event.event_id,
    position = at(0, 0),
})
assert(quiet.scan.status == "nobody_nearby",
    "a ticket that is not held up must not be scannable")

-- The guest opens the ticket. That, plus a GPS fix, is what makes them
-- findable; the stranger standing closer is ignored.
actions.PRESENT({
    session_token = guest.session_token,
    kind = "ticket", ref = ticketId, position = at(4, 0),
})
actions.REPORT_POSITION({
    session_token = stranger.session_token, position = at(1, 0),
})
local scan = actions.TICKET_SCAN({
    session_token = organizer.session_token,
    event_id = event.event.event_id,
    position = at(0, 0),
}).scan
assert(scan.status == "offered", "the door finds the held-up ticket")
assert(scan.target_name == "Ticket Holder",
    "it asks the ticket holder, not whoever is nearest")
assert(scan.distance == 4)

-- Only the person being asked can answer it.
rejected(actions.SCAN_ACCEPT, "NOT_YOURS", {
    session_token = stranger.session_token, request_id = scan.request_id,
})

local admitted = actions.SCAN_ACCEPT({
    session_token = guest.session_token, request_id = scan.request_id,
}).scan
assert(admitted.status == "accepted")
assert(admitted.result:find("Ticket Holder", 1, true))
assert(admitted.result:find("General Admission", 1, true))
assert(bank.state.tickets[ticketId].used, "the ticket is stamped used")

-- The organiser sees the same result on their own screen.
local seen = actions.TICKET_SCAN_STATUS({
    session_token = organizer.session_token,
    request_id = scan.request_id,
}).scan
assert(seen.status == "accepted" and seen.result == admitted.result)

-- A used ticket is no longer held up, so the next scan finds nobody.
local again = actions.TICKET_SCAN({
    session_token = organizer.session_token,
    event_id = event.event.event_id,
    position = at(0, 0),
})
assert(again.scan.status == "nobody_nearby",
    "a used ticket must not be scannable twice")

-- Somebody else's event is not scannable from this session.
local outsider = register("Other Venue")
rejected(actions.TICKET_SCAN, "NOT_OWNER", {
    session_token = outsider.session_token,
    event_id = event.event.event_id,
    position = at(0, 0),
})

-- Proximity Visa ------------------------------------------------------------

local traveller = register("Border Crosser")
local territoryOwner = register("Territory Owner")
local territory = actions.CUSTOMS_CREATE_TERRITORY({
    session_token = territoryOwner.session_token,
    name = "Fox Republic",
    pin = "1234",
})
local citizenship = actions.CUSTOMS_ISSUE_CITIZENSHIP({
    session_token = territoryOwner.session_token,
    territory_id = territory.territory.territory_id,
    username = "Border Crosser",
    pin = "1234",
})
local gate = actions.BORDER_REGISTER({
    session_token = territoryOwner.session_token,
    territory_id = territory.territory.territory_id,
    label = "South Gate",
})
local gateAuth = {
    controller_id = gate.controller_id,
    controller_token = gate.controller_token,
}

local function gateScan()
    local payload = { position = at(0, 0) }
    for key, value in pairs(gateAuth) do payload[key] = value end
    return actions.VISA_SCAN(payload).scan
end

assert(gateScan().status == "nobody_nearby",
    "a border finds nobody until a document is on screen")

actions.PRESENT({
    session_token = traveller.session_token,
    kind = "visa", ref = citizenship.document.visa_id, position = at(2, 0),
})
local crossing = gateScan()
assert(crossing.status == "offered")
assert(crossing.target_name == "Border Crosser")

local entered = actions.SCAN_ACCEPT({
    session_token = traveller.session_token,
    request_id = crossing.request_id,
}).scan
assert(entered.status == "accepted")
assert(entered.result:find("entered", 1, true),
    "the first crossing is an entry: " .. tostring(entered.result))

-- Holding it up again while inside reads as leaving, with no Enter/Exit
-- buttons for anybody to press.
clock = clock + 60 * 1000
actions.PRESENT({
    session_token = traveller.session_token,
    kind = "visa", ref = citizenship.document.visa_id, position = at(2, 0),
})
local leaving = gateScan()
local exited = actions.SCAN_ACCEPT({
    session_token = traveller.session_token,
    request_id = leaving.request_id,
}).scan
assert(exited.result:find("exited", 1, true),
    "already inside means the next crossing is an exit: "
        .. tostring(exited.result))

-- Portable Mode --------------------------------------------------------------

local kiosk = actions.KIOSK_REGISTER({ name = "Market Cart" })
local cart = {
    terminal_id = kiosk.terminal_id, terminal_token = kiosk.terminal_token,
}
local buyer = register("Market Buyer")
-- Everyone else's fix goes stale first, so this is about the two-step sale
-- rather than about who happens to be standing closest.
clock = clock + 200 * 1000
actions.REPORT_POSITION({
    session_token = buyer.session_token, position = at(3, 0),
})

local claim = actions.PROXIMITY_CLAIM({
    terminal_id = cart.terminal_id, terminal_token = cart.terminal_token,
    position = at(0, 0),
}).offer
assert(claim.portable and claim.status == "claiming",
    "the sale looks for a customer before anything is rung up")
assert(claim.amount == nil, "there is no basket yet")
assert(claim.target_name == "Market Buyer")

-- The basket cannot be sent before somebody takes the sale.
rejected(actions.PROXIMITY_BILL, "NO_CUSTOMER", {
    terminal_id = cart.terminal_id, terminal_token = cart.terminal_token,
    offer_id = claim.offer_id, amount = 12,
})

local taken = actions.PROXIMITY_ACCEPT({
    session_token = buyer.session_token, offer_id = claim.offer_id,
}).offer
assert(taken.status == "claimed")

local billed = actions.PROXIMITY_BILL({
    terminal_id = cart.terminal_id, terminal_token = cart.terminal_token,
    offer_id = claim.offer_id,
    amount = 12,
    items = { { name = "Apple", price = 4, quantity = 3 } },
    description = "Apple",
}).offer
assert(billed.status == "offered" and billed.amount == 12)
assert(billed.items[1].name == "Apple" and billed.items[1].quantity == 3,
    "the customer sees what they are paying for")

-- It stays with the customer who took it, even as the code lands.
local waiting = actions.PUMPE_POLL({ session_token = buyer.session_token })
assert(waiting.offer and waiting.offer.offer_id == billed.offer_id)
assert(waiting.offer.portable and waiting.offer.code == billed.code)

local balanceBefore = actions.ACCOUNT_SUMMARY({
    session_token = buyer.session_token,
}).account.balance
actions.PAY_CODE_CONFIRM({
    session_token = buyer.session_token, code = billed.code, pin = "1234",
})
local settled = actions.PROXIMITY_STATUS({
    terminal_id = cart.terminal_id, terminal_token = cart.terminal_token,
    offer_id = billed.offer_id,
}).offer
assert(settled.status == "paid", "the cart sees the sale settle")
assert(actions.ACCOUNT_SUMMARY({
    session_token = buyer.session_token,
}).account.balance == balanceBefore - 12)

-- A rung-up basket never changes hands. Somebody standing closer must not
-- inherit a sale, and its pay code dies with it.
local rival = register("Closer Rival")
actions.REPORT_POSITION({
    session_token = rival.session_token, position = at(1, 0),
})
local second = actions.PROXIMITY_CLAIM({
    terminal_id = cart.terminal_id, terminal_token = cart.terminal_token,
    position = at(0, 0),
}).offer
assert(second.target_name == "Closer Rival",
    "an unclaimed sale goes to whoever is nearest")

-- The rival is not the customer, so it passes along to the buyer.
local passed = actions.PROXIMITY_DECLINE({
    session_token = rival.session_token, offer_id = second.offer_id,
}).offer
assert(passed.status == "claiming" and passed.target_name == "Market Buyer",
    "a sale nobody has taken is offered to the next person")

actions.PROXIMITY_ACCEPT({
    session_token = buyer.session_token, offer_id = second.offer_id,
})
local secondBill = actions.PROXIMITY_BILL({
    terminal_id = cart.terminal_id, terminal_token = cart.terminal_token,
    offer_id = second.offer_id, amount = 8,
    items = { { name = "Pear", price = 8, quantity = 1 } },
}).offer
local backOut = actions.PROXIMITY_DECLINE({
    session_token = buyer.session_token, offer_id = second.offer_id,
}).offer
assert(backOut.status == "declined",
    "backing out of a basket ends the sale rather than passing it on")
assert(bank.state.active_pay_codes[secondBill.code] == nil,
    "and its pay code goes with it")
assert(actions.PUMPE_POLL({
    session_token = rival.session_token,
}).offer == nil, "the rival is never handed somebody else's shopping")

print("host_proximity_server_test: OK")
