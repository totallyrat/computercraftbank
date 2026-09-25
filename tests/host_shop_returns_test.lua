-- Shop refunds and returns, 11.0, across a real Bank Core and Vault.
--
-- Three ways money comes back from an order: the buyer cancels one that is
-- not yet confirmed (if the store takes cancellations), the store cancels one
-- it cannot fill, or the store refunds a return it has in its hands. The
-- Vault decides who may; the Core moves the money. Every path is checked for
-- where the money came from and where it went, not only that it moved.

package.path = "../?.lua;../?/init.lua;" .. package.path

local harness = require("bank_pair_harness")
local rejected = harness.rejected
local bank = harness.pair()
local core, vault = bank.core, bank.vault
local orders = bank.vault_state.orders

-- Lua 5.3 has an os.time of its own, so the harness leaves it alone and the
-- in-game hour would be the real clock. This test needs to move hours.
os.time = function() return harness.time end

local function hoursPass(hours)
    harness.time = harness.time + hours
    while harness.time >= 24 do
        harness.time = harness.time - 24
        harness.day = harness.day + 1
    end
end

-- Another bank, as far as the Core can tell. It can be made to stop
-- answering, or to refuse outright.
local credits, charges, otherBank = {}, {}, "yes"
core.ledger.ask = function(_, action, payload)
    if action == "LEDGER_CHARGE" then
        charges[#charges + 1] = payload
        return { charged = payload.amount }
    end
    if action == "LEDGER_CREDIT" then
        credits[#credits + 1] = payload
        if otherBank == "silent" then return nil, "No answer" end
        if otherBank == "no" then return nil, "Account closed", "CLOSED" end
        return { credited = payload.amount }
    end
    if action == "LEDGER_STATUS" then return { applied = false } end
    return nil, "No answer"
end

-- A store and its terminals ----------------------------------------------------------

local ana = bank.register("Ana Fox", "1234")
local kit = bank.register("Kit Wolf", "5678")
bank.fund(kit, 1000)

local function terminal(name)
    local made = bank.request("KIOSK_REGISTER", { name = name })
    return function(extra)
        extra = extra or {}
        extra.terminal_id, extra.terminal_token =
            made.terminal_id, made.terminal_token
        return extra
    end
end
local till = terminal("Till")
local owner = bank.request("KIOSK_OWNER_LOGIN", till({ name = "Ana Fox",
    pin = "1234" }))
local company = bank.request("CREATE_COMPANY", till({
    owner_session = owner.owner_session, company_name = "Fox Goods" })).company
bank.request("LINK_TERMINAL", till({ owner_session = owner.owner_session,
    company_id = company.company_id }))
local lamp = bank.request("ADD_PRODUCT", till({ name = "Lamp", price = 20,
    kind = "one_time" })).item
bank.request("SHOP_PRODUCT", till({ item_id = lamp.item_id, online = true }))
bank.request("SHOP_SETUP", till({ home = true, fee = 5, open = true }))

local depot = terminal("Warehouse")
bank.request("LINK_TERMINAL", depot({ owner_session = owner.owner_session,
    company_id = company.company_id }))

-- A rival company's terminal, for everything it must not be able to do.
local rivalTill = terminal("Rival")
local kitOwner = bank.request("KIOSK_OWNER_LOGIN", rivalTill({ name = "Kit Wolf",
    pin = "5678" }))
local rival = bank.request("CREATE_COMPANY", rivalTill({
    owner_session = kitOwner.owner_session, company_name = "Wolf Pack" })).company
bank.request("LINK_TERMINAL", rivalTill({ owner_session = kitOwner.owner_session,
    company_id = rival.company_id }))

local function buy(extra)
    local payload = bank.as(kit, { company_id = company.company_id,
        pin = "5678", items = { { item_id = lamp.item_id, quantity = 1 } },
        delivery = { kind = "home", x = 1, y = 2, z = 3 } })
    for key, value in pairs(extra or {}) do payload[key] = value end
    return bank.request("SHOP_CHECKOUT", payload)
end
local function view(orderId)
    return bank.request("SHOP_ORDER", bank.as(kit, { order_id = orderId })).order
end

-- The store's terms -------------------------------------------------------------------

local settings = bank.request("SHOP_STATE", till()).settings
assert(settings.cancel == false, "cancelling is the store's choice, off at first")
assert(settings.return_days == 5, "and returns start at the minimum")
rejected(bank.request, "RETURNS_TOO_SHORT", "SHOP_SETUP", till({ return_days = 3 }))
assert(bank.request("SHOP_SETUP", till({ return_days = 99 })).settings.return_days
    == 30, "a long window is capped rather than refused")
bank.request("SHOP_SETUP", till({ return_days = 7 }))

-- No cancelling at a store that does not take it ------------------------------------

local anaBefore, kitBefore = bank.balanceOf(ana), bank.balanceOf(kit)
local firm = buy()
assert(bank.balanceOf(ana) == anaBefore + 25,
    "without cancelling, the store is paid at once")
assert(view(firm.order_id).cancellable == false)
rejected(bank.request, "NOT_CANCELLABLE", "SHOP_CANCEL",
    bank.as(kit, { order_id = firm.order_id }))

-- Cancelling ----------------------------------------------------------------------

bank.request("SHOP_SETUP", till({ cancel = true }))
anaBefore, kitBefore = bank.balanceOf(ana), bank.balanceOf(kit)
local soft = buy()
assert(bank.balanceOf(kit) == kitBefore - 25, "the buyer pays at checkout")
assert(bank.balanceOf(ana) == anaBefore,
    "but a cancellable order's money waits until it is confirmed")
assert(bank.request("SHOP_STATE", till()).held == 25, "the kiosk can see it waiting")
local shown = view(soft.order_id)
assert(shown.cancellable and not shown.confirmed and shown.confirms_in == 2,
    "the order says it can be cancelled for two more hours")
assert(orders[soft.order_id].return_days == 7, "with the store's terms at checkout")

-- Somebody else's order is not theirs to cancel.
local ana2 = bank.register("Ana Two", "1111")
rejected(bank.request, "NO_SUCH_ORDER", "SHOP_CANCEL",
    bank.as(ana2, { order_id = soft.order_id }))

local cancelled = bank.request("SHOP_CANCEL", bank.as(kit, { order_id = soft.order_id }))
assert(cancelled.refunded == 25 and cancelled.to == "Foxy")
assert(bank.balanceOf(kit) == kitBefore, "the buyer has all of it back")
assert(bank.balanceOf(ana) == anaBefore, "and the store never had it")
assert(orders[soft.order_id].status == "cancelled")
assert(bank.request("SHOP_STATE", till()).held == 0)
rejected(bank.request, "ORDER_CLOSED", "SHOP_CANCEL",
    bank.as(kit, { order_id = soft.order_id }))

-- After two hours an order is confirmed: the store is paid, and it can only
-- be returned now.
anaBefore = bank.balanceOf(ana)
local late = buy()
hoursPass(1)
core.shop.release()
assert(bank.balanceOf(ana) == anaBefore, "not yet")
hoursPass(1.5)
core.shop.release()
assert(bank.balanceOf(ana) == anaBefore + 25, "confirmed, and paid out")
assert(view(late.order_id).confirmed and not view(late.order_id).cancellable)
rejected(bank.request, "CONFIRMED", "SHOP_CANCEL",
    bank.as(kit, { order_id = late.order_id }))

-- The Core pays the store on its own schedule. Once it has, the order is
-- confirmed as far as money goes, whatever the Vault's clock still says.
local raced = buy()
core.state.shop_held[raced.order_id] = nil
rejected(bank.request, "CONFIRMED", "SHOP_CANCEL",
    bank.as(kit, { order_id = raced.order_id }))
bank.request("DELIVERY_REFUND", depot({ order_id = raced.order_id }))

-- If the Vault will not mark the order, nothing moves ---------------------------------

local real = vault.actions.VAULT_SHOP_REFUNDED
vault.actions.VAULT_SHOP_REFUNDED = function() error({ pumpe = true,
    code = "VAULT_BUSY", message = "Try again" }, 0) end
local stuck = buy()
kitBefore = bank.balanceOf(kit)
rejected(bank.request, "VAULT_BUSY", "SHOP_CANCEL",
    bank.as(kit, { order_id = stuck.order_id }))
assert(bank.balanceOf(kit) == kitBefore, "no refund for an order still open")
assert(core.state.shop_held[stuck.order_id], "and the money is still held")
anaBefore = bank.balanceOf(ana)
rejected(bank.request, "VAULT_BUSY", "DELIVERY_REFUND",
    depot({ order_id = firm.order_id }))
assert(bank.balanceOf(ana) == anaBefore,
    "a store refund puts the owner's money back when the Vault says no")
vault.actions.VAULT_SHOP_REFUNDED = real

-- The store cancels an order it cannot fill -----------------------------------------------

rejected(bank.request, "NO_SUCH_ORDER", "DELIVERY_REFUND",
    rivalTill({ order_id = firm.order_id }))
anaBefore, kitBefore = bank.balanceOf(ana), bank.balanceOf(kit)
local byStore = bank.request("DELIVERY_REFUND", depot({ order_id = firm.order_id,
    note = "Sold out" }))
assert(byStore.refunded == 25)
assert(bank.balanceOf(ana) == anaBefore - 25, "paid out already, so from the owner")
assert(bank.balanceOf(kit) == kitBefore + 25)
assert(orders[firm.order_id].status == "cancelled"
    and orders[firm.order_id].note == "Sold out")

-- A store that has spent the money cannot refund what it does not have.
local poor = buy({ })
hoursPass(3)
core.shop.release()
core.state.accounts[ana.id].balance = 1
rejected(bank.request, "STORE_SHORT", "DELIVERY_REFUND",
    depot({ order_id = poor.order_id }))
assert(orders[poor.order_id].status == "open", "and the order is left alone")
core.state.accounts[ana.id].balance = 1000

-- Returns ---------------------------------------------------------------------------

rejected(bank.request, "NOT_ARRIVED", "SHOP_RETURN",
    bank.as(kit, { order_id = poor.order_id, reason = "Broken" }))
bank.request("DELIVERY_DONE", depot({ order_id = poor.order_id }))
local arrived = view(poor.order_id)
assert(arrived.returnable and arrived.returns_left == 7 * 24,
    "seven days from the moment it arrived, as the store set")
rejected(bank.request, "NO_REASON", "SHOP_RETURN",
    bank.as(kit, { order_id = poor.order_id }))
rejected(bank.request, "NO_SUCH_ORDER", "SHOP_RETURN",
    bank.as(ana2, { order_id = poor.order_id, reason = "Mine now" }))
bank.request("SHOP_RETURN", bank.as(kit, { order_id = poor.order_id,
    reason = "The lamp flickers" }))
rejected(bank.request, "ALREADY_ASKED", "SHOP_RETURN",
    bank.as(kit, { order_id = poor.order_id, reason = "Again" }))
local told = false
for _, note in ipairs(bank.notifications(ana)) do
    if note.title == "Return requested" then told = true end
end
assert(told, "the store owner hears about it")

-- It is at the top of the board, after the open orders.
local board = bank.request("DELIVERY_ORDERS", depot()).orders
local sawReturn, sawOpenAfter = false, false
for _, order in ipairs(board) do
    if order.order_id == poor.order_id then sawReturn = true
    elseif sawReturn and order.status == "open" then sawOpenAfter = true end
end
assert(sawReturn and not sawOpenAfter, "open orders, then returns, then the rest")

-- Only this store can refund it, and only once.
rejected(bank.request, "NO_SUCH_ORDER", "DELIVERY_REFUND",
    rivalTill({ order_id = poor.order_id, why = "return" }))
anaBefore, kitBefore = bank.balanceOf(ana), bank.balanceOf(kit)
bank.request("DELIVERY_REFUND", depot({ order_id = poor.order_id, why = "return" }))
assert(bank.balanceOf(ana) == anaBefore - 25 and bank.balanceOf(kit) == kitBefore + 25)
assert(view(poor.order_id).return_request.status == "refunded")
rejected(bank.request, "NO_RETURN", "DELIVERY_REFUND",
    depot({ order_id = poor.order_id, why = "return" }))

-- Declined, with a reason the buyer is told.
local kept = buy()
hoursPass(3)
core.shop.release()
bank.request("DELIVERY_DONE", depot({ order_id = kept.order_id }))
bank.request("SHOP_RETURN", bank.as(kit, { order_id = kept.order_id,
    reason = "Changed my mind" }))
rejected(bank.request, "NO_REASON", "DELIVERY_RETURN_DECLINE",
    depot({ order_id = kept.order_id }))
rejected(bank.request, "NO_SUCH_ORDER", "DELIVERY_RETURN_DECLINE",
    rivalTill({ order_id = kept.order_id, reason = "No" }))
bank.request("DELIVERY_RETURN_DECLINE", depot({ order_id = kept.order_id,
    reason = "Never came back to us" }))
local declined = view(kept.order_id).return_request
assert(declined.status == "declined" and declined.answer == "Never came back to us")

-- The window closes.
local old = buy()
hoursPass(3)
core.shop.release()
bank.request("DELIVERY_DONE", depot({ order_id = old.order_id }))
bank.advanceDays(8)
assert(view(old.order_id).returnable == false)
rejected(bank.request, "RETURNS_CLOSED", "SHOP_RETURN",
    bank.as(kit, { order_id = old.order_id, reason = "Too late" }))

-- A long window keeps its order long enough to be used.
bank.request("SHOP_SETUP", till({ return_days = 30 }))
local long = buy()
hoursPass(3)
core.shop.release()
bank.request("DELIVERY_DONE", depot({ order_id = long.order_id }))
bank.advanceDays(20)
vault.sweep_orders()
assert(orders[long.order_id] and view(long.order_id).returnable,
    "twenty days into a thirty day window, the order is still there")
bank.request("SHOP_SETUP", till({ return_days = 7 }))

-- A return still waiting on the store is never swept away, however old.
local waiting = buy()
hoursPass(3)
core.shop.release()
bank.request("DELIVERY_DONE", depot({ order_id = waiting.order_id }))
bank.request("SHOP_RETURN", bank.as(kit, { order_id = waiting.order_id,
    reason = "Wrong colour" }))
bank.advanceDays(60)
vault.sweep_orders()
assert(orders[waiting.order_id], "a waiting return keeps its order")
assert(not orders[old.order_id], "while a finished one is cleared a week past its window")

-- Paid from another bank ------------------------------------------------------------------

local function buyElsewhere()
    return bank.request("SHOP_CHECKOUT", bank.as(kit, {
        company_id = company.company_id, bank_account_id = "0042123412341234",
        pin = "4321", items = { { item_id = lamp.item_id, quantity = 1 } },
        delivery = { kind = "home", x = 1, y = 2, z = 3 } }))
end

kitBefore = bank.balanceOf(kit)
local elsewhere = buyElsewhere()
bank.request("SHOP_CANCEL", bank.as(kit, { order_id = elsewhere.order_id }))
local credit = credits[#credits]
assert(credit.bank_account_id == "0042123412341234" and credit.amount == 25
    and credit.transfer_id == "SHOPREF" .. elsewhere.order_id,
    "the refund goes back to the account that paid")
assert(bank.balanceOf(kit) == kitBefore, "not to Foxy")

-- Their bank is silent: the refund waits and is asked again.
otherBank = "silent"
local quiet = buyElsewhere()
local answer = bank.request("SHOP_CANCEL", bank.as(kit, { order_id = quiet.order_id }))
assert(answer.to == "their bank, soon")
assert(core.state.shop_refunds["SHOPREF" .. quiet.order_id], "parked")
core.shop.release()
assert(core.state.shop_refunds["SHOPREF" .. quiet.order_id], "still silent, still parked")
otherBank = "yes"
core.shop.release()
assert(not core.state.shop_refunds["SHOPREF" .. quiet.order_id], "and sent once it answers")

-- Their bank refuses it: the money lands in the buyer's Foxy account instead.
otherBank = "no"
kitBefore = bank.balanceOf(kit)
local refused = buyElsewhere()
answer = bank.request("SHOP_CANCEL", bank.as(kit, { order_id = refused.order_id }))
assert(answer.to == "Foxy" and bank.balanceOf(kit) == kitBefore + 25,
    "a bank that will not take the refund does not lose it")
otherBank = "yes"

print("host_shop_returns_test: OK")
