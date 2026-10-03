-- The till, FoxyOS 13: the Service Kiosk as the Company app's Sell tab, on
-- a 26x20 Pocket and on a 51x19 standing computer with a customer screen,
-- against a real Bank Core and Vault.
--
-- The device becomes one of the company's tills on the Bank, so a sale is
-- paid the way a kiosk's always was: Foxy Pay to whoever is nearest -- never
-- the owner, whose own Pocket is usually the nearest of all -- or a code for
-- somebody who banks elsewhere. The Bank says what was paid.

package.path = "../?.lua;../?/init.lua;" .. package.path
sleep = function() end

local harness = require("bank_pair_harness")
local bank = harness.pair()
local phone = require("phone_app_harness")

local ana = bank.register("Ana Fox", "1234")
local kit = bank.register("Kit Wolf", "5678")
bank.fund(kit, 500)

local company = bank.request("COMPANY_CREATE", bank.as(ana, {
    company_name = "Fox Goods", app_id = "COMPANY" })).company
local function product(name, price, kind, favorite)
    local added = bank.request("COMPANY_PRODUCT_ADD", bank.as(ana, {
        app_id = "COMPANY", company_id = company.company_id, name = name,
        price = price, kind = kind or "one_time" }))
    if favorite then
        local items = added.products or bank.state.companies[company.company_id].quick_items
        bank.request("COMPANY_PRODUCT_SET", bank.as(ana, { app_id = "COMPANY",
            company_id = company.company_id, item_id = items[#items].item_id,
            favorite = true }))
    end
end
product("Lamp", 12, "one_time", true)
product("Rug", 30)
product("Tea Club", 5, "subscription")

-- Positions: the till stands at 0,0 and Ana's own Pocket says it is right
-- there too. Kit is three blocks away.
local at = function(x, z) return { x = x, y = 64, z = z } end
bank.request("REPORT_POSITION", bank.as(ana, { position = at(0, 0) }))
bank.request("REPORT_POSITION", bank.as(kit, { position = at(3, 0) }))

local kept = {}
local function run(script, extra)
    extra = extra or {}
    return phone.run({ bank = bank, who = ana, file = "../company.lua",
        script = script, wanted = extra.wanted or "sell", app_id = "COMPANY",
        position = at(0, 0), kept = kept, width = extra.width,
        height = extra.height, screens = extra.screens })
end
local function tills()
    local found = {}
    for _, terminal in pairs(bank.state.terminals) do
        if terminal.kind == "till" then found[#found + 1] = terminal end
    end
    return found
end

-- On the Pocket: ring up, Foxy Pay to the nearest -----------------------------------------

local paidOffer
local script = phone.script()
phone.push(script.actions, function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "Lamp"), "Point of Sale opens on the till, favourites first")
    assert(phone.has(frame, "Sell") and phone.has(frame, "Products"))
    return "product:1"
end, "cat:items", "product:1", "product:2", function(seen)
    assert(phone.has(phone.last(seen), "Bag 3"), "three things in the bag")
    return "basket"
end, "less:1", function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "1x Lamp") and phone.has(frame, "1x Rug"),
        "the basket, line by line: one lamp taken back out")
    return "back"
end, function(seen)
    assert(phone.has(phone.last(seen), "Charge\n$42"), "the total, on Charge")
    return "charge"
end, "pick:1", function(seen)
    local frame = phone.last(seen)
    assert(phone.has(frame, "Kit Wolf"), "offered to Kit, not to Ana herself")
    -- Kit says yes on their Pocket, with Foxy Pay.
    local offer
    for _, candidate in pairs(bank.state.proximity_offers) do offer = candidate end
    paidOffer = offer
    bank.request("FOXY_PAY_CONFIRM", bank.as(kit, { offer_id = offer.offer_id,
        pin = "5678" }))
    return "__tick"
end, function(seen)
    assert(phone.said(seen, "Paid $42"), "the till sees it paid")
    assert(phone.has(phone.last(seen), "Empty"), "and the bag is empty again")
    return "home"
end, "home")
local seen = run(script)
assert(#tills() == 1, "this Pocket became one till")
assert(bank.balanceOf(kit) == 1000 - 42, "Kit paid 42")
assert(bank.balanceOf(ana) == 500 + 42, "into the owner's account")
assert(paidOffer.declined[ana.id], "the owner was never asked")

-- Customer first: find them, ring them up, they pay on their own Pocket -------------------------

local function lastOffer()
    local newest
    for _, offer in pairs(bank.state.proximity_offers) do
        if not newest or offer.offer_id > newest.offer_id then newest = offer end
    end
    return newest
end
script = phone.script()
phone.push(script.actions, "customer", function(seen)
    assert(phone.has(phone.last(seen), "Kit Wolf"), "asking Kit, not Ana")
    bank.request("PROXIMITY_ACCEPT", bank.as(kit, { offer_id = lastOffer().offer_id }))
    return "__tick"
end, function(seen)
    assert(phone.said(seen, "Customer ready").body == "Kit Wolf")
    assert(phone.has(phone.last(seen), "For Kit Wolf"), "the till is ringing up for Kit")
    return "product:1"
end, "charge", function(seen)
    assert(phone.has(phone.last(seen), "SENT TO"), "the basket went to Kit's Pocket")
    bank.request("FOXY_PAY_CONFIRM", bank.as(kit, { offer_id = lastOffer().offer_id,
        pin = "5678" }))
    return "__tick"
end, function(seen)
    assert(phone.said(seen, "Paid $12"))
    return "customer"
end, function(seen)
    -- Found again, then the cashier walks off: the claim is let go.
    bank.request("PROXIMITY_ACCEPT", bank.as(kit, { offer_id = lastOffer().offer_id }))
    return "__tick"
end, "tab:products", "home", "home")
run(script)
assert(bank.balanceOf(kit) == 1000 - 42 - 12, "Kit paid for the lamp too")
assert(lastOffer().status == "cancelled", "leaving the till let Kit go")

-- A code for another bank, cancelled ------------------------------------------------------

script = phone.script()
phone.push(script.actions, "product:1", "charge", "pick:2", function(seen)
    assert(phone.has(phone.last(seen), "TYPE IN YOUR BANK"), "the code, to type in")
    return "cancel"
end, function(seen)
    assert(phone.said(seen, "Cancelled").body == "Nothing was charged")
    return "home"
end, "home")
run(script)
assert(#tills() == 1, "the same till, recognised")
local cancelled = 0
for _, payment in pairs(bank.state.active_pay_codes) do
    if payment.status == "cancelled" then cancelled = cancelled + 1 end
end
assert(cancelled == 1, "the code was cancelled on the Bank")

-- A standing computer with a customer screen --------------------------------------------------

local drawn = {}
local screen = {
    getSize = function() return 15, 10 end,
    isColor = function() return true end,
    setBackgroundColor = function() end, setTextColor = function() end,
    clear = function() end, setCursorPos = function() end,
    write = function(text) drawn[#drawn + 1] = text end,
    blit = function(text) drawn[#drawn + 1] = text end,
}
local function shown(text)
    for _, value in ipairs(drawn) do
        if tostring(value):find(text, 1, true) then return true end
    end
    return false
end
-- The phone harness draws to its own stub; the customer screen is drawn by
-- the real lib/ui, so the app's ui needs the real fill and text for it.
script = phone.script()
phone.push(script.actions, function(seen)
    assert(phone.has(phone.last(seen), "RECEIPT"), "a receipt column on a wide screen")
    assert(shown("WELCOME"), "the customer screen says hello")
    return "product:1"
end, function()
    assert(shown("YOUR ORDER"), "and shows the order as it is rung up")
    return "less:1"
end, "tools", "pick:2", function(seen)
    assert(phone.said(seen, "1 customer screens"), "the screen, found")
    return "back"
end, "home", "home")
run(script, { width = 51, height = 19, screens = { screen } })

-- Only the owner, and only through the Company app ----------------------------------------

local rejected = harness.rejected
rejected(bank.request, "NOT_OWNER", "COMPANY_TILL", bank.as(kit, {
    app_id = "COMPANY", company_id = company.company_id }))
rejected(bank.request, "WRONG_APP", "COMPANY_TILL", bank.as(ana, {
    app_id = "YAPCHAT", company_id = company.company_id }))
assert(#tills() == 1, "nobody else made a till of Ana's company")

-- Dev Mode moved to the Pocket's Settings: only the Pocket itself signs
-- somebody up as a developer, and only with their PIN.
rejected(bank.request, "WRONG_APP", "DEV_REGISTER", bank.as(kit, {
    app_id = "COMPANY", pin = "5678" }))
rejected(bank.request, "BAD_PIN", "DEV_REGISTER", bank.as(kit, { pin = "0000" }))
local developer = bank.request("DEV_REGISTER", bank.as(kit, { pin = "5678" }))
assert(developer.developer_id and developer.name == "Kit Wolf",
    "a developer without a company or a kiosk")

print("host_company_till_test: OK")
