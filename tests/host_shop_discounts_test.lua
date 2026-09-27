-- Shop discounts, 12.0, against a real Bank Core and Vault.
--
-- A store can put everything on sale, make delivery free above an amount,
-- and hand out codes: a percentage or an amount off, free delivery, a number
-- of uses. All of it is worked out on the Core from the store's own settings
-- -- a phone never says what anything costs -- and the order keeps what was
-- taken off, so a receipt and a refund both know.

package.path = "../?.lua;../?/init.lua;" .. package.path

local harness = require("bank_pair_harness")
local rejected = harness.rejected
local bank = harness.pair()

local ana = bank.register("Ana Fox", "1234")
local kit = bank.register("Kit Wolf", "5678")
bank.fund(kit, 1000)

-- Ana's store: a lamp, a rug, delivery at 5.
local kiosk = bank.request("KIOSK_REGISTER", { name = "Fox Goods Till" })
local function atTill(extra)
    extra = extra or {}
    extra.terminal_id, extra.terminal_token = kiosk.terminal_id, kiosk.terminal_token
    return extra
end
local owner = bank.request("KIOSK_OWNER_LOGIN", atTill({ name = "Ana Fox", pin = "1234" }))
local company = bank.request("CREATE_COMPANY", atTill({
    owner_session = owner.owner_session, company_name = "Fox Goods" })).company
bank.request("LINK_TERMINAL", atTill({ owner_session = owner.owner_session,
    company_id = company.company_id }))
local lamp = bank.request("ADD_PRODUCT", atTill({ name = "Lamp", price = 20,
    kind = "one_time" })).item
local rug = bank.request("ADD_PRODUCT", atTill({ name = "Rug", price = 35,
    kind = "one_time" })).item
bank.request("SHOP_PRODUCT", atTill({ item_id = lamp.item_id, online = true }))
bank.request("SHOP_PRODUCT", atTill({ item_id = rug.item_id, online = true }))
bank.request("SHOP_SETUP", atTill({ home = true, pickup = true, fee = 5, open = true }))

-- From the Company app, as its owner.
local function companyApp(who, extra)
    local payload = bank.as(who, extra)
    payload.app_id = "COMPANY"
    payload.company_id = company.company_id
    return payload
end
local function basket(...)
    local items = {}
    for _, pair in ipairs({ ... }) do
        items[#items + 1] = { item_id = pair[1].item_id, quantity = pair[2] }
    end
    return items
end
local function quote(items, kind, code)
    return bank.request("SHOP_QUOTE", bank.as(kit, { company_id = company.company_id,
        items = items, delivery_kind = kind, code = code }))
end
local HOME = { kind = "home", x = 1, y = 2, z = 3, label = "Home" }
local function lines(who)
    return #bank.request("HISTORY", bank.as(who)).transactions
end

-- Setting it up ------------------------------------------------------------------------

rejected(bank.request, "BAD_SALE", "COMPANY_SHOP_SETUP", companyApp(ana, { sale = 95 }))
rejected(bank.request, "NOT_OWNER", "COMPANY_SHOP_SETUP", companyApp(kit, { sale = 10 }))
local notCompany = bank.as(ana, { company_id = company.company_id, sale = 10,
    app_id = "APP00001" })
rejected(bank.request, "WRONG_APP", "COMPANY_SHOP_SETUP", notCompany)
bank.request("COMPANY_SHOP_SETUP", companyApp(ana, { sale = 10, free_shipping = true,
    free_over = 50 }))

local function addCode(extra)
    return bank.request("COMPANY_SHOP_CODE", companyApp(ana, extra))
end
addCode({ code = "spring", percent = 20 })
addCode({ code = "FIVE", amount = 5, max_uses = 1 })
addCode({ code = "ShipFree", free_shipping = true })
addCode({ code = "GIFT", percent = 100, free_shipping = true })
rejected(bank.request, "BAD_CODE", "COMPANY_SHOP_CODE",
    companyApp(ana, { code = "BOTH", percent = 10, amount = 5 }))
rejected(bank.request, "BAD_CODE", "COMPANY_SHOP_CODE",
    companyApp(ana, { code = "NOTHING" }))
rejected(bank.request, "BAD_CODE", "COMPANY_SHOP_CODE",
    companyApp(ana, { code = "ab", percent = 5 }))
rejected(bank.request, "CODE_TAKEN", "COMPANY_SHOP_CODE",
    companyApp(ana, { code = "SPRING", percent = 5 }))
rejected(bank.request, "NOT_OWNER", "COMPANY_SHOP_CODE",
    companyApp(kit, { code = "MINE", percent = 50 }))

local state = bank.request("COMPANY_STATE", companyApp(ana))
assert(state.settings.codes.SPRING and state.settings.codes.SPRING.percent == 20,
    "codes are kept in capitals, whatever was typed")

-- What a buyer sees -------------------------------------------------------------------

local store = bank.request("SHOP_STORE", bank.as(kit, { company_id = company.company_id }))
assert(store.store.sale == 10 and store.store.free_shipping == true
    and store.store.free_over == 50, "the storefront says what is on offer")
assert(store.store.codes == nil, "but never lists the codes")

local q = quote(basket({ lamp, 1 }), "home")
assert(q.subtotal == 20 and q.sale == 2 and q.fee == 5 and q.total == 23,
    "ten percent off, delivery still due under 50: " .. q.total)
q = quote(basket({ lamp, 3 }), "home")
assert(q.subtotal == 60 and q.discount == 6 and q.fee == 0 and q.fee_waived
    and q.total == 54, "54 after the sale is over 50: delivery is free")
q = quote(basket({ lamp, 1 }, { rug, 1 }), "home")
assert(q.subtotal == 55 and q.fee == 5 and q.total == 54.5,
    "55 is 49.50 after the sale: free delivery counts what is paid")
q = quote(basket({ lamp, 1 }), "home", "spring")
assert(q.promo == "SPRING" and q.code_discount == 3.6 and q.total == 19.4,
    "a code takes its share of what the sale left: " .. q.total)
q = quote(basket({ lamp, 1 }), "home", "shipfree")
assert(q.fee == 0 and q.total == 18, "a free-delivery code")
q = quote(basket({ lamp, 1 }), "pickup")
assert(q.fee == 0 and q.total == 18, "pickup never had a fee")
q = quote(basket({ lamp, 1 }), "home", "NOPE")
assert(q.code_error and q.total == 23, "a code that does not work says so")

-- Paying ------------------------------------------------------------------------------

local kitBefore, anaBefore = bank.balanceOf(kit), bank.balanceOf(ana)
rejected(bank.request, "BAD_CODE", "SHOP_CHECKOUT", bank.as(kit, {
    company_id = company.company_id, pin = "5678", code = "NOPE",
    items = basket({ rug, 1 }), delivery = HOME }))
assert(bank.balanceOf(kit) == kitBefore, "a bad code moves nothing")

local paid = bank.request("SHOP_CHECKOUT", bank.as(kit, {
    company_id = company.company_id, pin = "5678", code = "five",
    items = basket({ rug, 1 }), delivery = HOME }))
-- 35, 3.50 off in the sale, 5 off with the code, 5 delivery.
assert(paid.total == 31.5, "the Core charges what it quoted: " .. paid.total)
assert(bank.balanceOf(kit) == kitBefore - 31.5 and bank.balanceOf(ana) == anaBefore + 31.5,
    "and that is what moves")
local mine = bank.request("SHOP_ORDERS", bank.as(kit)).orders
local order
for _, item in ipairs(mine) do if item.order_id == paid.order_id then order = item end end
assert(order and order.discount == 8.5 and order.promo == "FIVE" and order.total == 31.5,
    "the order keeps what was taken off, and with which code")
rejected(bank.request, "BAD_CODE", "SHOP_CHECKOUT", bank.as(kit, {
    company_id = company.company_id, pin = "5678", code = "FIVE",
    items = basket({ rug, 1 }), delivery = HOME }))

-- A code that makes it free: no money moves, and the order is still real.
kitBefore, anaBefore = bank.balanceOf(kit), bank.balanceOf(ana)
local kitLines, anaLines = lines(kit), lines(ana)
-- Nobody's bank is asked for nothing: an Account ID from another bank is
-- ignored when there is nothing to take from it.
local gift = bank.request("SHOP_CHECKOUT", bank.as(kit, {
    company_id = company.company_id, pin = "5678", code = "gift",
    bank_account_id = "12", items = basket({ lamp, 1 }), delivery = HOME }))
assert(gift.total == 0, "everything off and free delivery is free")
assert(bank.balanceOf(kit) == kitBefore and bank.balanceOf(ana) == anaBefore,
    "and not a coin moves either way")
assert(lines(kit) == kitLines and lines(ana) == anaLines,
    "nor does a line of $0 land in anybody's history")
local giftOrder = bank.request("SHOP_ORDER", bank.as(kit, { order_id = gift.order_id })).order
assert(giftOrder.promo == "GIFT" and giftOrder.discount == 20
    and giftOrder.paid_with == "Discount"
    and giftOrder.status == "open", "the order is open like any other: "
    .. tostring(giftOrder.status))
local board = bank.request("DELIVERY_ORDERS", atTill())
local onBoard = false
for _, item in ipairs(board.orders) do
    if item.order_id == gift.order_id then onBoard = true end
end
assert(onBoard, "and the store has to deliver it")

-- A code switched off stops working, and comes back when switched on.
addCode({ code = "spring", op = "toggle" })
q = quote(basket({ lamp, 1 }), "home", "SPRING")
assert(q.code_error, "a code switched off does not work")
addCode({ code = "spring", op = "toggle" })
assert(not quote(basket({ lamp, 1 }), "home", "SPRING").code_error)
addCode({ code = "spring", op = "remove" })
assert(quote(basket({ lamp, 1 }), "home", "SPRING").code_error, "and a removed one is gone")
rejected(bank.request, "NO_SUCH_CODE", "COMPANY_SHOP_CODE",
    companyApp(ana, { code = "spring", op = "remove" }))
local uses = bank.request("COMPANY_STATE", companyApp(ana)).settings.codes
assert(uses.FIVE.uses == 1 and uses.GIFT.uses == 1 and uses.SHIPFREE.uses == 0,
    "each code counts what it paid for, and a quote is not a use")

-- A free order can be called off like any other while the store lets it,
-- and nothing moves then either.
bank.request("COMPANY_SHOP_SETUP", companyApp(ana, { cancel = true }))
kitBefore, anaBefore = bank.balanceOf(kit), bank.balanceOf(ana)
local second = bank.request("SHOP_CHECKOUT", bank.as(kit, {
    company_id = company.company_id, pin = "5678", code = "GIFT",
    items = basket({ rug, 1 }), delivery = HOME }))
assert(second.total == 0)
local cancelled = bank.request("SHOP_CANCEL", bank.as(kit, { order_id = second.order_id }))
assert(cancelled.refunded == 0, "nothing to give back")
assert(bank.balanceOf(kit) == kitBefore and bank.balanceOf(ana) == anaBefore)
local third = bank.request("SHOP_CHECKOUT", bank.as(kit, {
    company_id = company.company_id, pin = "5678", code = "GIFT",
    items = basket({ rug, 1 }), delivery = HOME }))
bank.advanceDays(1)
bank.core.shop.release()
rejected(bank.request, "CONFIRMED", "SHOP_CANCEL", bank.as(kit, { order_id = third.order_id }))
assert(bank.balanceOf(ana) == anaBefore, "confirmed, it pays the store nothing")
assert(lines(ana) == anaLines, "and writes nothing down for it")
bank.request("COMPANY_SHOP_SETUP", companyApp(ana, { cancel = false }))

-- A sale of nothing is no sale.
bank.request("COMPANY_SHOP_SETUP", companyApp(ana, { sale = 0, free_shipping = false }))
q = quote(basket({ lamp, 3 }), "home")
assert(q.discount == 0 and q.fee == 5 and q.total == 65, "back to full price")

print("host_shop_discounts_test: OK")
