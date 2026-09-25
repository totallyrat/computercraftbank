-- The Company app on a 26x20 PUMPE, against a real Bank Core and Vault.
--
-- Starting a company, adding and changing products, opening its store,
-- selling at a pickup point, and Delivery Mode -- each driven by taps and
-- checked against what the Bank ended up holding. Then the other side: a
-- company is only its owner's, and only the Company app may run it.

package.path = "../?.lua;../?/init.lua;" .. package.path

local harness = require("bank_pair_harness")
local rejected = harness.rejected
local bank = harness.pair()
local phone = require("phone_app_harness")

local ana = bank.register("Ana Fox", "1234")
local kit = bank.register("Kit Wolf", "5678")
bank.fund(kit, 1000)

local function run(who, script, extra)
    extra = extra or {}
    return phone.run({ bank = bank, who = who, file = "../company.lua",
        script = script, wanted = extra.wanted, app_id = "COMPANY",
        position = extra.position })
end
local function companyNamed(name)
    for _, company in pairs(bank.state.companies) do
        if company.name == name then return company end
    end
end

-- Ana starts a company and sets it up ------------------------------------------------

local script = phone.script()
phone.push(script.actions, function(seen)
    assert(phone.has(phone.last(seen), "+ Start a company"))
    return "start"
end)
phone.push(script.inputs, "Fox Goods")
-- Straight into it, on Products: a lamp, one-time.
phone.push(script.actions, "add")
phone.push(script.inputs, "Lamp", "12")
phone.push(script.actions, "pick:1")
-- Into the Shop app, with a line under its name.
phone.push(script.actions, function(seen)
    assert(phone.has(phone.last(seen), "Lamp  $12"), "the product is listed")
    return "item:1"
end, "pick:4", "item:1", "pick:5")
phone.push(script.inputs, "Warm light")
-- The store: open it, let buyers cancel, a week of returns.
phone.push(script.actions, "tab:store", "open", "cancel")
phone.push(script.confirms, true)
phone.push(script.actions, "returns")
phone.push(script.inputs, "7")
phone.push(script.actions, function(seen)
    assert(phone.has(phone.last(seen), "Returns: 7 days"))
    assert(phone.has(phone.last(seen), "Close the store"), "it is open")
    return "home"
end, function(seen)
    assert(phone.has(phone.last(seen), "Fox Goods"),
        "back on the list of companies")
    return "home"
end)
local seen = run(ana, script)
assert(phone.said(seen, "Company started").body == "Fox Goods")
local company = assert(companyNamed("Fox Goods"))
assert(company.owner_account_id == ana.id)
local lamp = company.quick_items[1]
assert(lamp.name == "Lamp" and lamp.price == 12 and lamp.kind == "one_time")
assert(lamp.online == true and lamp.blurb == "Warm light",
    "put in the Shop app from the phone")
assert(company.shop.open == true and company.shop.cancel == true
    and company.shop.return_days == 7, "the store, set up from the phone")
for _, input in ipairs(seen.inputs) do
    if input.title == "Company name" then
        assert(input.mode == "text", "a name gets a keyboard that types one")
    end
end

-- A pickup point, set up on a Delivery Terminal, sells from the phone ---------------------

local depot = bank.request("KIOSK_REGISTER", { name = "North Point" })
local function at(extra)
    extra = extra or {}
    extra.terminal_id, extra.terminal_token = depot.terminal_id,
        depot.terminal_token
    return extra
end
local login = bank.request("KIOSK_OWNER_LOGIN",
    at({ name = "Ana Fox", pin = "1234" }))
bank.request("LINK_TERMINAL", at({ owner_session = login.owner_session,
    company_id = company.company_id }))
bank.request("PICKUP_REGISTER", at({ name = "North Point", x = 10, y = 64,
    z = -20 }))
bank.request("COMPANY_SHOP_SETUP", bank.as(ana, {
    company_id = company.company_id, pickup = true }))

script = phone.script()
phone.push(script.actions, "company:1", "tab:points", function(seen)
    assert(phone.has(phone.last(seen), "North Point"))
    assert(phone.has(phone.last(seen), "Parcels only"))
    return "point:1"
end, "open")
-- Nothing to sell yet, so it will not open. Add the lamp, as lanterns.
phone.push(script.actions, "add", "pick:1")
phone.push(script.inputs, "lantern", "2", function(seen)
    local last = seen.inputs[#seen.inputs]
    assert(last.initial == "12", "the price starts at the product's")
    return "15"
end)
phone.push(script.actions, "open", function(seen)
    assert(phone.has(phone.last(seen), "2 Lamp  $15"))
    assert(phone.has(phone.last(seen), "Store open"))
    return "offer:1"
end, "pick:1")
phone.push(script.inputs, function(seen)
    local last = seen.inputs[#seen.inputs]
    assert(last.initial == "minecraft:lantern" and last.mode == "email",
        "the game name, on a keyboard with _ and . on it")
    return last.initial
end, "3", "16")
phone.push(script.actions, "back", function(seen)
    assert(phone.has(phone.last(seen), "Selling 1 things"))
    return "home"
end, "home")
seen = run(ana, script)
assert(phone.said(seen, "Not changed"), "a store with nothing in it stays shut")
local point = bank.vault_state.pickup_points[depot.terminal_id]
assert(point.store.open == true, "open from the phone")
local offer = point.store.offers[1]
assert(offer.name == "Lamp" and offer.item == "minecraft:lantern"
    and offer.count == 3 and offer.price == 16, "and changed from it")

-- Delivery Mode -------------------------------------------------------------------------

local function buy(delivery)
    return bank.request("SHOP_CHECKOUT", bank.as(kit, {
        company_id = company.company_id, pin = "5678",
        items = { { item_id = lamp.item_id, quantity = 1 } },
        delivery = delivery }))
end
local homeOrder = buy({ kind = "home", x = 100, y = 64, z = -30,
    label = "Home" })
local pickupOrder = buy({ kind = "pickup", point_id = depot.terminal_id })
local stillPacking = buy({ kind = "home", x = 1, y = 64, z = 1 })
for _, order in ipairs({ homeOrder, pickupOrder }) do
    bank.request("DELIVERY_STAGE", at({ order_id = order.order_id, stage = 4 }))
end
local courierCode = bank.vault_state.orders[pickupOrder.order_id].delivery_code

script = phone.script()
phone.push(script.actions, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "2 out for delivery"),
        "only what is out for delivery")
    assert(phone.has(frame, "Code " .. courierCode),
        "a pickup parcel shows the courier's code")
    assert(phone.has(frame, "To 100 64 -30"), "a home one where it goes")
    return "order:2"
end, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "DELIVERY CODE"))
    assert(phone.has(frame, courierCode:sub(1, 3) .. " " .. courierCode:sub(4)))
    assert(phone.has(frame, "At North Point"))
    return "back"
end, "order:1", function(seen)
    assert(phone.has(phone.last(seen), "20 blocks N"),
        "how far, and which way: north is -z")
    return "done"
end)
phone.push(script.confirms, true)
phone.push(script.inputs, "By the door")
phone.push(script.actions, function(seen)
    assert(phone.has(phone.last(seen), "1 out for delivery"))
    return "home"
end)
seen = run(ana, script, { wanted = "delivery",
    position = { x = 100, y = 64, z = -10 } })
local delivered = bank.vault_state.orders[homeOrder.order_id]
assert(delivered.status == "done" and delivered.note == "By the door",
    "marked delivered from the phone")
assert(bank.vault_state.orders[stillPacking.order_id].status == "open")

-- Only the owner, and only this app ---------------------------------------------------------

local theirs = { company_id = company.company_id }
rejected(bank.request, "NOT_OWNER", "COMPANY_STATE", bank.as(kit, theirs))
rejected(bank.request, "NOT_OWNER", "COMPANY_PRODUCT_REMOVE", bank.as(kit, {
    company_id = company.company_id, item_id = lamp.item_id }))
rejected(bank.request, "NOT_OWNER", "DELIVERY_OUT", bank.as(kit, theirs))
rejected(bank.request, "NOT_OWNER", "DELIVERY_DONE", bank.as(kit, {
    company_id = company.company_id, order_id = stillPacking.order_id }))
rejected(bank.request, "NOT_OWNER", "STORE_OFFER_SET", bank.as(kit, {
    company_id = company.company_id, point_id = depot.terminal_id,
    name = "Free", item = "diamond", count = 64, price = 1 }))
assert(#bank.request("COMPANY_LIST", bank.as(kit)).companies == 0,
    "somebody else's companies are not listed")

-- Every other app on Ana's phone rides her session. None of them may run
-- her company.
local otherApp = { app_id = "APP00001", company_id = company.company_id }
rejected(bank.request, "WRONG_APP", "COMPANY_LIST", bank.as(ana, otherApp))
rejected(bank.request, "WRONG_APP", "COMPANY_PRODUCT_REMOVE", bank.as(ana, {
    app_id = "APP00001", company_id = company.company_id,
    item_id = lamp.item_id }))
rejected(bank.request, "WRONG_APP", "DELIVERY_OUT", bank.as(ana, otherApp))
rejected(bank.request, "WRONG_APP", "STORE_OPEN", bank.as(ana, {
    app_id = "APP00001", company_id = company.company_id,
    point_id = depot.terminal_id, open = false }))
assert(#company.quick_items == 1 and point.store.open == true,
    "and nothing they tried happened")

-- An owner is not a pickup point: the counter's own actions stay the
-- terminal's.
rejected(bank.request, "TERMINAL_AUTH", "PICKUP_CODE", bank.as(ana, {
    company_id = company.company_id, code = courierCode }))

-- A company can start from a kiosk and be run from the phone, and the
-- other way round: they are one list of products.
local fromPhone = bank.request("COMPANY_PRODUCT_ADD", bank.as(ana, {
    company_id = company.company_id, name = "Oil", price = 3,
    kind = "one_time" })).item
local till = bank.request("KIOSK_STATE", at())
local onTill = false
for _, item in ipairs(till.products) do
    if item.item_id == fromPhone.item_id then onTill = true end
end
assert(onTill, "a product added on the phone is on the company's tills")

-- What a pickup point sells, checked by the Vault -------------------------------------------

local function offerAs(extra)
    extra.company_id, extra.point_id = company.company_id, depot.terminal_id
    return bank.as(ana, extra)
end
local saved = bank.request("STORE_OFFER_SET", offerAs({ name = "Logs",
    item = "  Oak_Log ", count = 16, price = 9.5 }))
assert(saved.offer.item == "minecraft:oak_log",
    "a bare game name is a minecraft one")
assert(bank.request("STORE_OFFER_SET", offerAs({ name = "Cogs",
    item = "create:cogwheel", count = 4, price = 3 })).offer.item
    == "create:cogwheel", "and a modded one keeps its own")
for _, bad in ipairs({ "", "a", "oak log", "minecraft:", ":oak", "a:b:c d" }) do
    rejected(bank.request, "BAD_ITEM", "STORE_OFFER_SET", offerAs({
        name = "Bad", item = bad, count = 1, price = 1 }))
end
rejected(bank.request, "BAD_COUNT", "STORE_OFFER_SET", offerAs({
    name = "None", item = "dirt", count = 0, price = 1 }))
rejected(bank.request, "INVALID_AMOUNT", "STORE_OFFER_SET", offerAs({
    name = "Free", item = "dirt", count = 1, price = 0 }))
local store = bank.vault_state.pickup_points[depot.terminal_id].store
while #store.offers < 12 do
    bank.request("STORE_OFFER_SET", offerAs({ name = "Filler",
        item = "dirt", count = 1, price = 1 }))
end
rejected(bank.request, "TOO_MANY_OFFERS", "STORE_OFFER_SET", offerAs({
    name = "One more", item = "dirt", count = 1, price = 1 }))
-- Registering the point again -- a new name -- keeps what it sells.
bank.request("PICKUP_REGISTER", at({ name = "North Gate" }))
store = bank.vault_state.pickup_points[depot.terminal_id].store
assert(#store.offers == 12 and store.open, "set up again, still selling")
-- The counter sees the list it sells from.
local counter = bank.request("PICKUP_STORE", at())
assert(counter.open and #counter.offers == 12 and counter.name == "North Gate")
-- Emptied, it closes itself; and it cannot open with nothing in it.
while #store.offers > 0 do
    bank.request("STORE_OFFER_REMOVE", offerAs({
        offer_id = store.offers[1].offer_id }))
end
assert(store.open == false, "a store with nothing left in it closes")
rejected(bank.request, "NOTHING_TO_SELL", "STORE_OPEN", offerAs({ open = true }))
rejected(bank.request, "NO_SUCH_POINT", "STORE_OPEN", bank.as(ana, {
    company_id = company.company_id, point_id = "TERM999", open = false }))

-- Two companies, one owner: each sees its own points and its own orders.
local second = bank.request("COMPANY_CREATE", bank.as(ana,
    { company_name = "Ana Two" })).company
rejected(bank.request, "NO_SUCH_POINT", "STORE_OFFER_SET", bank.as(ana, {
    company_id = second.company_id, point_id = depot.terminal_id,
    name = "Stolen", item = "dirt", count = 1, price = 1 }))
assert(#bank.request("STORE_POINTS", bank.as(ana,
    { company_id = second.company_id })).points == 0)
bank.request("DELIVERY_STAGE", at({ order_id = stillPacking.order_id,
    stage = 4 }))
assert(#bank.request("DELIVERY_OUT", bank.as(ana,
    { company_id = company.company_id })).orders == 2)
assert(#bank.request("DELIVERY_OUT", bank.as(ana,
    { company_id = second.company_id })).orders == 0,
    "one company's deliveries are not another's")

print("host_company_app_test: OK")
