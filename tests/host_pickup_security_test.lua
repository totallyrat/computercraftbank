-- Foxy Security at pickup points, 11.1, against a real Bank Core and Vault.
--
-- A parcel waiting at a pickup point opens to its code only once the buyer
-- has said, with their PIN, that it is them. The questions that matter: a
-- "not me" keeps it in and changes the code; nobody answering keeps it in;
-- a yes given ahead of time lasts half an hour and can be taken back; and
-- only the buyer, from Foxy, at this point, can say any of it.

package.path = "../?.lua;../?/init.lua;" .. package.path

local harness = require("bank_pair_harness")
local rejected = harness.rejected
local bank = harness.pair()
local phone = require("phone_app_harness")

local ana = bank.register("Ana Fox", "1234")
local kit = bank.register("Kit Wolf", "5678")
local rob = bank.register("Rob Hare", "9999")
bank.fund(kit, 1000)

-- Ana's store, two pickup points.
local function terminal(name)
    local made = bank.request("KIOSK_REGISTER", { name = name })
    local function as(extra)
        extra = extra or {}
        extra.terminal_id, extra.terminal_token = made.terminal_id,
            made.terminal_token
        return extra
    end
    return made, as
end
local till, atTill = terminal("Till")
local login = bank.request("KIOSK_OWNER_LOGIN",
    atTill({ name = "Ana Fox", pin = "1234" }))
local company = bank.request("CREATE_COMPANY", atTill({
    owner_session = login.owner_session, company_name = "Fox Goods" })).company
local depot, atDepot = terminal("North Point")
local other, atOther = terminal("South Point")
for _, link in ipairs({ atTill, atDepot, atOther }) do
    bank.request("LINK_TERMINAL", link({ owner_session = login.owner_session,
        company_id = company.company_id }))
end
bank.request("PICKUP_REGISTER", atDepot({ name = "North Point" }))
bank.request("PICKUP_REGISTER", atOther({ name = "South Point" }))
local lamp = bank.request("ADD_PRODUCT", atTill({ name = "Lamp", price = 5,
    kind = "one_time" })).item
bank.request("SHOP_PRODUCT", atTill({ item_id = lamp.item_id, online = true }))
bank.request("SHOP_SETUP", atTill({ pickup = true, open = true }))

local orders = bank.vault_state.orders
local function parcel()
    local bought = bank.request("SHOP_CHECKOUT", bank.as(kit, {
        company_id = company.company_id, pin = "5678",
        items = { { item_id = lamp.item_id, quantity = 1 } },
        delivery = { kind = "pickup", point_id = depot.terminal_id } }))
    local order = orders[bought.order_id]
    return bought.order_id, order
end
local function stock(orderId, locker)
    local order = orders[orderId]
    local courier = bank.request("PICKUP_CODE",
        atDepot({ code = order.delivery_code }))
    assert(courier.kind == "deliver")
    bank.request("PICKUP_STOCK", atDepot({ order_id = orderId,
        locker = locker, code = order.delivery_code }))
end
local function fromFoxy(who, extra)
    local payload = bank.as(who, extra)
    payload.app_id = "FOXY"
    return payload
end

-- Not me ----------------------------------------------------------------------------------

local firstId, first = parcel()
rejected(bank.request, "NOT_HERE_YET", "SECURITY_CONFIRM", fromFoxy(kit, {
    order_id = firstId, pin = "5678" }))
stock(firstId, "minecraft:chest_1")
local oldCode = first.code
local asked = bank.request("PICKUP_CODE", atDepot({ code = oldCode }))
assert(asked.waiting, "the code asks first")
local polled = bank.request("PUMPE_POLL", bank.as(kit)).latest
assert(polled.security_order == firstId and polled.style == "fullscreen",
    "the phone's poll carries the question, so it can be answered there")
local listed = bank.request("SECURITY_LIST", fromFoxy(kit)).parcels
assert(#listed == 1 and listed[1].security.status == "asked"
    and listed[1].point_name == "North Point",
    "Foxy lists the question, and where")
assert(orders[firstId].code == oldCode)
local denied = bank.request("SECURITY_DENY", fromFoxy(kit,
    { order_id = firstId }))
assert(denied.denied and denied.code ~= oldCode and #denied.code == 6,
    "not me changes the code")
assert(bank.request("PICKUP_WAIT", atDepot({ order_id = firstId }))
    .status == "denied", "the counter is told")
assert(bank.state.accounts[kit.id].notifications[1].body:find(denied.code, 1,
    true), "the buyer is told the new code")
rejected(bank.request, "NO_SUCH_CODE", "PICKUP_CODE",
    atDepot({ code = oldCode }))
rejected(bank.request, "NOT_CONFIRMED", "PICKUP_RELEASE",
    atDepot({ order_id = firstId }))
assert(orders[firstId].status == "open" and orders[firstId].locker,
    "and the parcel stays where it is")

-- Nobody answers ----------------------------------------------------------------------------

bank.request("PICKUP_CODE", atDepot({ code = denied.code }))
bank.advanceMs(121 * 1000)
assert(bank.request("PICKUP_WAIT", atDepot({ order_id = firstId }))
    .status == "expired", "two minutes without an answer is a no")
rejected(bank.request, "NOT_CONFIRMED", "PICKUP_RELEASE",
    atDepot({ order_id = firstId }))
assert(bank.request("SECURITY_LIST", fromFoxy(kit)).parcels[1].security == nil,
    "and the question is gone from Foxy")

-- Only the buyer, only Foxy, only with the PIN, only at this point ----------------------------

rejected(bank.request, "NO_SUCH_ORDER", "SECURITY_CONFIRM", fromFoxy(rob, {
    order_id = firstId, pin = "9999" }))
rejected(bank.request, "BAD_PIN", "SECURITY_CONFIRM", fromFoxy(kit, {
    order_id = firstId, pin = "0000" }))
local stranger = bank.as(kit, { order_id = firstId, pin = "5678",
    app_id = "APP00001" })
rejected(bank.request, "WRONG_APP", "SECURITY_CONFIRM", stranger)
rejected(bank.request, "WRONG_APP", "SECURITY_LIST",
    bank.as(kit, { app_id = "COMPANY" }))
rejected(bank.request, "NO_SUCH_ORDER", "PICKUP_WAIT",
    atOther({ order_id = firstId }))
rejected(bank.request, "NO_SUCH_CODE", "PICKUP_CODE",
    atOther({ code = denied.code }))

-- Ahead of time -----------------------------------------------------------------------------

local ahead = bank.request("SECURITY_CONFIRM", fromFoxy(kit, {
    order_id = firstId, pin = "5678" }))
assert(not ahead.answered and ahead.security.status == "confirmed"
    and ahead.security.expires_in_ms == 30 * 60 * 1000,
    "a yes with no question waiting holds for half an hour")
local before = #bank.state.accounts[kit.id].notifications
local straight = bank.request("PICKUP_CODE", atDepot({ code = denied.code }))
assert(straight.confirmed and not straight.waiting,
    "so the code opens it without asking")
assert(#bank.state.accounts[kit.id].notifications == before,
    "and nobody's phone rings")
local handed = bank.request("PICKUP_RELEASE", atDepot({ order_id = firstId }))
assert(handed.locker == "minecraft:chest_1")
assert(orders[firstId].status == "collected")

-- A yes that runs out, and a yes taken back.
local secondId, second = parcel()
stock(secondId, "minecraft:chest_2")
bank.request("SECURITY_CONFIRM", fromFoxy(kit, { order_id = secondId,
    pin = "5678" }))
bank.advanceMs(31 * 60 * 1000)
assert(bank.request("PICKUP_CODE", atDepot({ code = second.code })).waiting,
    "after half an hour it asks again")
bank.advanceMs(121 * 1000)
bank.request("SECURITY_CONFIRM", fromFoxy(kit, { order_id = secondId,
    pin = "5678" }))
local takenBack = bank.request("SECURITY_DENY", fromFoxy(kit,
    { order_id = secondId }))
assert(takenBack.denied == false and orders[secondId].code == second.code,
    "taking back a yes is not a not-me: the code stays")
assert(bank.request("PICKUP_CODE", atDepot({ code = second.code })).waiting,
    "and the code asks again")

-- The Security tab in Foxy ------------------------------------------------------------------
-- The question from the counter above is still waiting. Kit answers it in
-- the app; the parcel is released at the counter.

local script = phone.script()
phone.push(script.actions, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "Fox Goods, North Point"))
    assert(phone.has(frame, "Somebody is there now"))
    return "parcel:1"
end)
phone.push(script.confirms, true)
phone.push(script.pins, "5678")
phone.push(script.actions, "home")
local seen = phone.run({ bank = bank, who = kit, file = "../foxy.lua",
    script = script, app_id = "FOXY", wanted = "security" })
assert(phone.said(seen, "Confirmed"))
assert(bank.request("PICKUP_WAIT", atDepot({ order_id = secondId }))
    .status == "confirmed")
bank.request("PICKUP_RELEASE", atDepot({ order_id = secondId }))

-- Pre-confirming from the tab, and saying not me.
local thirdId, third = parcel()
stock(thirdId, "minecraft:chest_3")
local fourthId, fourth = parcel()
stock(fourthId, "minecraft:chest_4")
local fourthCode = fourth.code
bank.request("PICKUP_CODE", atDepot({ code = fourthCode }))
script = phone.script()
phone.push(script.actions, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "2 at pickup points"))
    assert(phone.has(frame, "Tap to pre-confirm"))
    return "parcel:1"
end)
-- The waiting question comes first; this time it is not them.
phone.push(script.confirms, false)
-- Then both wait quietly, oldest first. Pre-confirm the first.
phone.push(script.actions, "parcel:1")
phone.push(script.confirms, true)
phone.push(script.pins, "5678")
phone.push(script.actions, function(seen)
    assert(phone.has(phone.last(seen), "Pre-confirmed, 30 min"))
    return "home"
end)
seen = phone.run({ bank = bank, who = kit, file = "../foxy.lua",
    script = script, app_id = "FOXY", wanted = "security" })
assert(phone.said(seen, "Kept it in").body:find(orders[fourthId].code, 1, true),
    "not me, and the new code is shown")
assert(orders[fourthId].code ~= fourthCode)
assert(phone.said(seen, "Pre-confirmed").body == "For 30 minutes")
assert(bank.request("PICKUP_CODE", atDepot({ code = third.code })).confirmed)

-- Orders from before 11.1 -------------------------------------------------------------------
-- They have no courier's code. A Vault starting on 11.1 gives them one.

local util = require("lib.util")
local oldState = util.copy(bank.vault_state)
oldState.orders.OLD1 = { order_id = "OLD1", company_id = company.company_id,
    status = "open", code = "111111", history = {},
    delivery = { kind = "pickup", point_id = depot.terminal_id,
        point_name = "North Point" }, lines = {} }
oldState.orders.OLD2 = { order_id = "OLD2", company_id = company.company_id,
    status = "open", code = "222222", history = {}, locker = "chest_9",
    delivery = { kind = "pickup", point_id = depot.terminal_id,
        point_name = "North Point" }, lines = {} }
local realLoad = util.loadTable
util.loadTable = function(path, fallback)
    if tostring(path):find("bank_vault_v1", 1, true) then
        return util.copy(oldState)
    end
    return util.copy(fallback)
end
PUMPE_TEST_MODE = true
local restarted = assert(loadfile("../bank_vault.lua"))()
PUMPE_TEST_MODE = nil
util.loadTable = realLoad
local migrated = restarted.state.orders
assert(type(migrated.OLD1.delivery_code) == "string"
    and #migrated.OLD1.delivery_code == 6
    and migrated.OLD1.delivery_code ~= "111111",
    "a parcel still on its way gets a courier's code")
assert(migrated.OLD2.delivery_code == nil,
    "one already in a locker does not need one")

print("host_pickup_security_test: OK")
