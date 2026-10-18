-- Subscriptions every 1, 2, 5, 10 or 15 days, FoxyOS 16.3, on a real Bank Core
-- and Vault. Before, everything was charged daily. Now a product at a till and
-- a subscription sold in an app each say how often -- and are charged exactly
-- that often, no sooner and no later. Saying nothing is still every day, and
-- an app that still asks for period = "day" still gets one.

package.path = "../?.lua;../?/init.lua;" .. package.path
local harness = require("bank_pair_harness")
local rejected = harness.rejected
local bank = harness.pair()
local util = require("lib.util")

local owner = bank.register("Cafe Owner", "1234")
local fan = bank.register("Coffee Fan", "2468")
bank.fund(fan, 1000)

local kiosk = bank.request("KIOSK_REGISTER", { name = "Fox Cafe" })
local function till(extra)
    extra.terminal_id, extra.terminal_token = kiosk.terminal_id, kiosk.terminal_token
    return extra
end

-- Products ------------------------------------------------------------------------------

rejected(bank.request, "INVALID_PERIOD", "ADD_PRODUCT", till({
    name = "Odd Pass", price = 30, kind = "subscription", every_days = 3 }))
local weekly = bank.request("ADD_PRODUCT", till({
    name = "Coffee Pass", price = 40, kind = "subscription", every_days = 5 })).item
assert(weekly.every_days == 5)
local daily = bank.request("ADD_PRODUCT", till({
    name = "Daily Cup", price = 3, kind = "subscription" })).item
assert(daily.every_days == 1, "saying nothing is every day")
local muffin = bank.request("ADD_PRODUCT", till({
    name = "Muffin", price = 2, kind = "one_time", every_days = 5 })).item
assert(muffin.every_days == nil, "a one-off is not charged again at all")

-- Paying for a five-day subscription ------------------------------------------------------

rejected(bank.request, "INVALID_PERIOD", "CREATE_PAY_CODE", till({
    amount = 40, purchase_type = "subscription", every_days = 7 }))
local code = bank.request("CREATE_PAY_CODE", till({ amount = 40,
    purchase_type = "subscription", description = "Coffee Pass", every_days = 5 }))
assert(code.every_days == 5)
local start = bank.balanceOf(fan)
local preview = bank.request("PAY_CODE_PREVIEW", bank.as(fan, { code = code.code }))
assert(preview.every_days == 5, "the customer sees how often before paying")
local paid = bank.request("PAY_CODE_CONFIRM", bank.as(fan, { code = code.code, pin = "2468" }))
assert(paid.kind == "subscription" and bank.balanceOf(fan) == start - 40,
    "the first five days are paid now")
local today = util.ingameDay()
local mine = bank.request("LIST_SUBSCRIPTIONS", bank.as(fan)).subscriptions[1]
assert(mine.every_days == 5 and mine.next_charge_day == today + 5)
local told = false
for _, note in ipairs(bank.notifications(fan)) do
    if note.title == "Subscription started" and note.body:find("every 5 days", 1, true) then
        told = true
    end
end
assert(told, "and the notification says every 5 days, not /day")

-- A one-day one beside it, from a till that said nothing about a period.
local dailyCode = bank.request("CREATE_PAY_CODE", till({ amount = 3,
    purchase_type = "subscription", description = "Daily Cup" }))
assert(bank.request("PAY_CODE_PREVIEW", bank.as(fan, { code = dailyCode.code })).every_days == 1)
bank.request("PAY_CODE_CONFIRM", bank.as(fan, { code = dailyCode.code, pin = "2468" }))
local both = start - 43
assert(bank.balanceOf(fan) == both)

-- Four days: the daily one four times, the five-day one not at all. The
-- fifth day: both.
for _ = 1, 4 do
    bank.advanceDays(1)
    bank.process_subscriptions()
end
assert(bank.balanceOf(fan) == both - 4 * 3, "daily, four times; the pass not yet")
bank.advanceDays(1)
bank.process_subscriptions()
assert(bank.balanceOf(fan) == both - 5 * 3 - 40, "and the pass on its fifth day")
for _, row in ipairs(bank.request("LIST_SUBSCRIPTIONS", bank.as(fan)).subscriptions) do
    if row.every_days == 5 then
        assert(row.next_charge_day == util.ingameDay() + 5, "then five days on again")
    end
end
-- Running the same day twice charges nothing twice.
local before = bank.balanceOf(fan)
bank.state.last_subscription_day = nil
bank.process_subscriptions()
assert(bank.balanceOf(fan) == before, "a day's pass charges each one once")

-- App subscriptions ----------------------------------------------------------------------

bank.request("FOXY_LOGIN_APPROVE", bank.as(fan, { app_id = "yap", app_name = "Yap" }))
rejected(bank.request, "INVALID_PERIOD", "APP_PURCHASE_QUOTE", bank.as(fan, {
    app_id = "yap", product_id = "pro", name = "Yap Pro", amount = 10, every_days = 4 }))
local quote = bank.request("APP_PURCHASE_QUOTE", bank.as(fan, {
    app_id = "yap", product_id = "pro", name = "Yap Pro", amount = 10, every_days = 2 }))
assert(quote.every_days == 2 and quote.period == "days")
local bought = bank.request("APP_PURCHASE", bank.as(fan, {
    app_id = "yap", product_id = "pro", name = "Yap Pro", amount = 10,
    every_days = 2, pin = "2468" })).bought
assert(bought.subscription and bought.every_days == 2
    and bought.next_charge_day == util.ingameDay() + 2)
-- Before 16.3 an app asked for period = "day". It still gets every day.
local legacy = bank.request("APP_PURCHASE", bank.as(fan, {
    app_id = "yap", product_id = "boost", name = "Boost", amount = 1,
    period = "day", pin = "2468" })).bought
assert(legacy.period == "day" and legacy.every_days == 1)

start = bank.balanceOf(fan)
local day = util.ingameDay()
bank.appstore.chargeSubscriptions(day + 1)
assert(bank.balanceOf(fan) == start - 1, "the daily boost on day one; Pro not yet")
bank.appstore.chargeSubscriptions(day + 2)
assert(bank.balanceOf(fan) == start - 2 - 10, "Pro on its second day")
bank.appstore.chargeSubscriptions(day + 3)
assert(bank.balanceOf(fan) == start - 3 - 10, "and not again the day after")

print("host_subscription_periods_test: OK")
