-- A pickup point's Me tab and its Store's discounts, 12.0 Final, against a
-- real Bank Core and Vault.
--
-- Me: somebody types their name at the counter, their PUMPE asks whether it
-- is them, and a yes with their PIN shows the counter their orders for that
-- point -- what has arrived comes out, what is coming can be made ready.
-- The questions that matter: nobody else's yes counts, a name cannot be
-- used to keep lighting up somebody's phone, only this counter's token
-- opens anything, and a parcel made ready opens to its code without asking
-- again when it comes.
--
-- The Store: the same sale and codes the Shop app uses, worked out by the
-- Core, and a code used at the counter counts like one used online.

package.path = "../?.lua;../?/init.lua;" .. package.path

local harness = require("bank_pair_harness")
local rejected = harness.rejected
local bank = harness.pair()

local ana = bank.register("Ana Fox", "1234")
local kit = bank.register("Kit Wolf", "5678")
local rob = bank.register("Rob Hare", "9999")
bank.fund(kit, 1000)

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
local lamp = bank.request("ADD_PRODUCT", atTill({ name = "Lamp", price = 20,
    kind = "one_time" })).item
bank.request("SHOP_PRODUCT", atTill({ item_id = lamp.item_id, online = true }))
bank.request("SHOP_SETUP", atTill({ pickup = true, open = true }))

local orders = bank.vault_state.orders
local function parcel(pointId)
    local bought = bank.request("SHOP_CHECKOUT", bank.as(kit, {
        company_id = company.company_id, pin = "5678",
        items = { { item_id = lamp.item_id, quantity = 1 } },
        delivery = { kind = "pickup", point_id = pointId or depot.terminal_id } }))
    return bought.order_id
end
local function stock(orderId, locker)
    local order = orders[orderId]
    bank.request("PICKUP_STOCK", atDepot({ order_id = orderId,
        locker = locker, code = order.delivery_code }))
end
local function fromFoxy(who, extra)
    local payload = bank.as(who, extra)
    payload.app_id = "FOXY"
    return payload
end

-- Kit has one parcel waiting at North Point, one on its way there, and one
-- going to South Point.
local waiting = parcel()
stock(waiting, "minecraft:chest_1")
-- And Rob has one waiting there too, which Kit's yes does not open.
bank.fund(rob, 100)
local robs = bank.request("SHOP_CHECKOUT", bank.as(rob, {
    company_id = company.company_id, pin = "9999",
    items = { { item_id = lamp.item_id, quantity = 1 } },
    delivery = { kind = "pickup", point_id = depot.terminal_id } })).order_id
stock(robs, "minecraft:chest_3")
local coming = parcel()
local elsewhere = parcel(other.terminal_id)

-- Asking ------------------------------------------------------------------------------

rejected(bank.request, "NO_SUCH_PERSON", "PICKUP_ME_ASK", atDepot({ name = "Nobody" }))
local asked = bank.request("PICKUP_ME_ASK", atDepot({ name = "kit wolf" }))
assert(asked.name == "Kit Wolf" and asked.request_id, "found by name, however it is typed")
local latest = bank.request("PUMPE_POLL", bank.as(kit)).latest
assert(latest.security_lookup == asked.request_id and latest.style == "fullscreen",
    "their PUMPE asks, over whatever is open, and knows what it is answering")
assert(latest.body:find("North Point", 1, true), "and says where")
rejected(bank.request, "TRY_LATER", "PICKUP_ME_ASK", atOther({ name = "Kit Wolf" }))
assert(bank.request("PICKUP_ME_WAIT", atDepot({ request_id = asked.request_id }))
    .status == "asked", "the counter waits")

-- Only Kit can answer, with Kit's PIN, from the phone or Foxy.
rejected(bank.request, "EXPIRED", "SECURITY_LOOKUP_CONFIRM",
    bank.as(rob, { request_id = asked.request_id, pin = "9999" }))
rejected(bank.request, "BAD_PIN", "SECURITY_LOOKUP_CONFIRM",
    bank.as(kit, { request_id = asked.request_id, pin = "0000" }))
local notFoxy = bank.as(kit, { request_id = asked.request_id, pin = "5678" })
notFoxy.app_id = "APP00001"
rejected(bank.request, "WRONG_APP", "SECURITY_LOOKUP_CONFIRM", notFoxy)
rejected(bank.request, "NOT_CONFIRMED", "PICKUP_ME_ORDERS",
    atDepot({ me_token = "guess" }))
local yes = bank.request("SECURITY_LOOKUP_CONFIRM",
    bank.as(kit, { request_id = asked.request_id, pin = "5678" }))
assert(yes.confirmed and yes.point_name == "North Point")

-- What the counter shows ------------------------------------------------------------

local seen = bank.request("PICKUP_ME_WAIT", atDepot({ request_id = asked.request_id }))
assert(seen.status == "confirmed" and seen.me_token and seen.name == "Kit Wolf")
assert(#seen.orders == 2, "this point's orders only: " .. #seen.orders)
assert(seen.orders[1].order_id == waiting and seen.orders[1].arrived,
    "what has arrived comes first")
assert(seen.orders[2].order_id == coming and not seen.orders[2].arrived
    and not seen.orders[2].ready)
local token = seen.me_token
-- Another counter cannot use this one's token.
rejected(bank.request, "NOT_CONFIRMED", "PICKUP_ME_RELEASE",
    atOther({ order_id = waiting, me_token = token }))
rejected(bank.request, "NOT_CONFIRMED", "PICKUP_ME_RELEASE",
    atDepot({ order_id = waiting, me_token = "guess" }))
rejected(bank.request, "NO_SUCH_ORDER", "PICKUP_ME_RELEASE",
    atDepot({ order_id = robs, me_token = token }))
assert(orders[robs].locker == "minecraft:chest_3", "Rob's parcel stays in")

-- Taking what has arrived: no second question, it was just answered.
local handed = bank.request("PICKUP_ME_RELEASE",
    atDepot({ order_id = waiting, me_token = token }))
assert(handed.locker == "minecraft:chest_1" and orders[waiting].status == "collected",
    "it comes out of its locker")
rejected(bank.request, "NO_SUCH_ORDER", "PICKUP_ME_RELEASE",
    atDepot({ order_id = coming, me_token = token }))
rejected(bank.request, "NO_SUCH_ORDER", "PICKUP_ME_READY",
    atDepot({ order_id = elsewhere, me_token = token }))

-- Getting ready for what is coming.
assert(bank.request("PICKUP_ME_READY", atDepot({ order_id = coming, me_token = token })).ready)
local listed = bank.request("PICKUP_ME_ORDERS", atDepot({ me_token = token })).orders
assert(#listed == 1 and listed[1].ready, "it shows as ready")

-- Signing out, and the token is spent.
bank.request("PICKUP_ME_END", atDepot())
rejected(bank.request, "NOT_CONFIRMED", "PICKUP_ME_ORDERS", atDepot({ me_token = token }))

-- It arrives: the code opens it without asking Kit again.
stock(coming, "minecraft:chest_2")
assert(bank.notifications(kit)[1].body:find("without asking", 1, true),
    "Kit is told it is waiting, and ready")
local collect = bank.request("PICKUP_CODE", atDepot({ code = orders[coming].code }))
assert(collect.kind == "collect" and collect.confirmed and not collect.waiting,
    "no question at the counter")
assert(bank.request("PICKUP_RELEASE", atDepot({ order_id = coming })).locker
    == "minecraft:chest_2")

-- Not me, and nobody answering --------------------------------------------------------

bank.advanceMs(61 * 1000)
local again = bank.request("PICKUP_ME_ASK", atDepot({ name = "Kit Wolf" }))
bank.request("SECURITY_LOOKUP_DENY", bank.as(kit, { request_id = again.request_id }))
assert(bank.request("PICKUP_ME_WAIT", atDepot({ request_id = again.request_id }))
    .status == "denied", "a no shows the counter nothing")
rejected(bank.request, "NO_SUCH_REQUEST", "PICKUP_ME_WAIT",
    atDepot({ request_id = again.request_id }))
local robAsked = bank.request("PICKUP_ME_ASK", atDepot({ name = "Rob Hare" }))
bank.advanceMs(121 * 1000)
assert(bank.request("PICKUP_ME_WAIT", atDepot({ request_id = robAsked.request_id }))
    .status == "expired", "two minutes without an answer is a no")
rejected(bank.request, "EXPIRED", "SECURITY_LOOKUP_CONFIRM",
    bank.as(rob, { request_id = robAsked.request_id, pin = "9999" }))

-- Guessing names is guessing codes: five misses and the counter waits.
for _ = 1, 4 do
    rejected(bank.request, "NO_SUCH_PERSON", "PICKUP_ME_ASK", atOther({ name = "Nobody" }))
end
rejected(bank.request, "NO_SUCH_PERSON", "PICKUP_ME_ASK", atOther({ name = "Nobody" }))
rejected(bank.request, "TRY_LATER", "PICKUP_ME_ASK", atOther({ name = "Rob Hare" }))

-- The Store's discounts ----------------------------------------------------------------

local function companyApp(who, extra)
    local payload = bank.as(who, extra)
    payload.app_id = "COMPANY"
    payload.company_id = company.company_id
    return payload
end
assert(bank.request("STORE_DEALS", atDepot()).sale == 0)
local plain = bank.request("STORE_PRICE", atDepot({ price = 20 }))
assert(plain.total == 20 and plain.discount == 0, "no sale, full price")
bank.request("COMPANY_SHOP_SETUP", companyApp(ana, { sale = 10 }))
bank.request("COMPANY_SHOP_CODE", companyApp(ana, { code = "spring", percent = 20 }))
bank.request("COMPANY_SHOP_CODE", companyApp(ana, { code = "ONCE", amount = 5, max_uses = 1 }))
assert(bank.request("STORE_DEALS", atDepot()).sale == 10, "the counter knows the sale")
local sale = bank.request("STORE_PRICE", atDepot({ price = 20 }))
assert(sale.total == 18 and sale.promo == nil, "the sale, as online")
local spring = bank.request("STORE_PRICE", atDepot({ price = 20, code = "Spring" }))
assert(spring.total == 14.4 and spring.promo == "SPRING",
    "a code takes its share of what the sale left: " .. spring.total)
rejected(bank.request, "BAD_CODE", "STORE_PRICE", atDepot({ price = 20, code = "NOPE" }))
local once = bank.request("STORE_PRICE", atDepot({ price = 20, code = "once" }))
assert(once.total == 13)
bank.request("STORE_PROMO_USED", atDepot({ code = "once" }))
rejected(bank.request, "BAD_CODE", "STORE_PRICE", atDepot({ price = 20, code = "ONCE" }))
local codes = bank.request("COMPANY_STATE", companyApp(ana)).settings.codes
assert(codes.ONCE.uses == 1 and codes.SPRING.uses == 0,
    "a code used at the counter counts, and a price asked for is not a use")
-- Only a linked terminal of the store asks.
rejected(bank.request, "NOT_LINKED", "STORE_PRICE",
    (function()
        local loose = bank.request("KIOSK_REGISTER", { name = "Loose" })
        return { terminal_id = loose.terminal_id, terminal_token = loose.terminal_token,
            price = 20 }
    end)())

print("host_pickup_me_test: OK")
