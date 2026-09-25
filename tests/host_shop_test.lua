-- Shop, end to end, across three real machines: a Bank Core, its Vault, and
-- a 3rd Party Bank Server hosting Revolution.
--
-- The split is the design, so the test keeps it. The Core takes money -- a
-- Foxy account with its PIN, or an account at another bank with that bank's
-- own PIN, pulled across the ledger. The Vault keeps orders, pickup points
-- and delivery stages, and never touches a balance. Each is tested against
-- the real other half, because a stub is always more forgiving than the
-- thing it stands for.

package.path = "../?.lua;../?/init.lua;" .. package.path

local harness = require("bank_pair_harness")
local rejected = harness.rejected
local bank = harness.pair()
local core = bank.core

-- Revolution, loaded for real ------------------------------------------------

local revo
do
    local saved = {}
    os.getComputerID = function() return 3 end
    for name in pairs(package.loaded) do
        if name:find("^lib%.") or name == "config" then
            package.loaded[name] = nil
        end
    end
    local util = require("lib.util")
    util.loadTable = function(path, fallback)
        return saved[path] or util.copy(fallback)
    end
    util.saveTable = function(path, value) saved[path] = util.copy(value) end
    package.loaded["lib.util"] = util
    package.loaded["lib.ui"] = setmetatable({ theme = {} }, {
        __index = function() return function() end end,
    })
    term = { current = function()
        return { getSize = function() return 51, 19 end }
    end }
    rednet = {
        host = function() end, unhost = function() end,
        -- The Core is computer 1 and holds Foxy's ledger name. The charge
        -- action answers only whoever holds that name.
        lookup = function() return 1 end,
        receive = function() return nil end,
        send = function() return true end,
    }
    package.loaded["lib.net"] = {
        openModems = function() return { "modem" } end,
        host = function() end, reply = function() end,
        locate = function() return nil end, autoUpdate = function() end,
        client = function()
            return { request = function() return nil, "not wired" end,
                discover = function() return nil end }
        end,
    }
    PUMPE_TEST_MODE = true
    revo = assert(loadfile("../bank_app_server.lua"))()
    PUMPE_TEST_MODE = nil
    revo.adopt({ app_id = "APP00009", bank_name = "Revolution" })
end

-- The Core's ledger reaches Revolution the way a rednet message would: the
-- handler runs with the sender set to the Core's own computer id.
local ledgerAnswers = true
local realAsk = core.ledger.ask
core.ledger.ask = function(bankCode, action, payload, timeout)
    if bankCode == revo.state.bank_code then
        if not ledgerAnswers then return nil, "No answer" end
        local handler = revo.actions[action]
        if not handler then return nil, "Unknown", "UNKNOWN_ACTION" end
        local ok, result = pcall(handler, payload or {}, 1)
        if ok then return result end
        if type(result) == "table" and result.pumpe then
            return nil, result.message, result.code
        end
        error(result, 0)
    end
    return realAsk(bankCode, action, payload, timeout)
end

-- A company with a store --------------------------------------------------------

local ana = bank.register("Ana Fox", "1234")
local kit = bank.register("Kit Wolf", "5678")
bank.fund(kit, 1000)

local kiosk = bank.request("KIOSK_REGISTER", { name = "Fox Goods Till" })
local till = { terminal_id = kiosk.terminal_id,
    terminal_token = kiosk.terminal_token }
local function as(terminal, extra)
    local payload = { terminal_id = terminal.terminal_id,
        terminal_token = terminal.terminal_token }
    for key, value in pairs(extra or {}) do payload[key] = value end
    return payload
end

-- A store belongs to a company, so an unlinked kiosk cannot open one.
rejected(bank.request, "NOT_LINKED", "SHOP_STATE", as(till))

local owner = bank.request("KIOSK_OWNER_LOGIN",
    as(till, { name = "Ana Fox", pin = "1234" }))
local company = bank.request("CREATE_COMPANY", as(till,
    { owner_session = owner.owner_session, company_name = "Fox Goods" })).company
bank.request("LINK_TERMINAL", as(till,
    { owner_session = owner.owner_session, company_id = company.company_id }))

local lamp = bank.request("ADD_PRODUCT", as(till,
    { name = "Lamp", price = 20, kind = "one_time" })).item
local rug = bank.request("ADD_PRODUCT", as(till,
    { name = "Rug", price = 35, kind = "one_time" })).item
local club = bank.request("ADD_PRODUCT", as(till,
    { name = "Lamp Club", price = 5, kind = "subscription" })).item

-- A store cannot open with nothing to sell, or no way to deliver it.
rejected(bank.request, "NOTHING_TO_SELL", "SHOP_SETUP",
    as(till, { open = true }))
bank.request("SHOP_PRODUCT", as(till, { item_id = lamp.item_id, online = true,
    blurb = "Bright" }))
bank.request("SHOP_PRODUCT", as(till, { item_id = rug.item_id, online = true }))
rejected(bank.request, "NOT_FOR_SALE_ONLINE", "SHOP_PRODUCT",
    as(till, { item_id = club.item_id, online = true }))
rejected(bank.request, "BAD_COLOR", "SHOP_SETUP",
    as(till, { color = "chartreuse" }))
bank.request("SHOP_SETUP", as(till, { color = "cyan", tagline = "Lamps and rugs",
    home = true, pickup = true, fee = 5, open = true }))

-- A Delivery Terminal is a terminal of the same company. It becomes a pickup
-- point by registering as one.
local dt = bank.request("KIOSK_REGISTER", { name = "Warehouse" })
local depot = { terminal_id = dt.terminal_id, terminal_token = dt.terminal_token }
local depotOwner = bank.request("KIOSK_OWNER_LOGIN",
    as(depot, { name = "Ana Fox", pin = "1234" }))
bank.request("LINK_TERMINAL", as(depot, { owner_session =
    depotOwner.owner_session, company_id = company.company_id }))
bank.request("PICKUP_REGISTER", as(depot,
    { name = "Spawn Lockers", x = 10, y = 64, z = -20 }))

-- Browsing ----------------------------------------------------------------------

local listed = bank.request("SHOP_LIST", bank.as(kit))
assert(#listed.stores == 1 and listed.stores[1].name == "Fox Goods",
    "an open store with something online is listed")
assert(listed.stores[1].color == "cyan", "in its own colours")
assert(#bank.request("SHOP_LIST", bank.as(kit, { query = "rugs" })).stores == 1,
    "and it can be searched by its tagline")
assert(#bank.request("SHOP_LIST", bank.as(kit, { query = "boats" })).stores == 0)

local store = bank.request("SHOP_STORE", bank.as(kit,
    { company_id = company.company_id }))
assert(#store.products == 2, "only what was put online is for sale online")
for _, product in ipairs(store.products) do
    assert(product.item_id ~= club.item_id,
        "a subscription is sold at a kiosk, never delivered")
end
assert(#store.points == 1 and store.points[1].name == "Spawn Lockers",
    "and the store's pickup points come with it, from the Vault")

-- Paying with Foxy, delivered home ---------------------------------------------------

local kitBefore, anaBefore = bank.balanceOf(kit), bank.balanceOf(ana)
rejected(bank.request, "BAD_PIN", "SHOP_CHECKOUT", bank.as(kit, {
    company_id = company.company_id, pin = "0000",
    items = { { item_id = lamp.item_id, quantity = 2 } },
    delivery = { kind = "home", x = 1, y = 2, z = 3, label = "Home" } }))
assert(bank.balanceOf(kit) == kitBefore, "a wrong PIN moves nothing")

local home = bank.request("SHOP_CHECKOUT", bank.as(kit, {
    company_id = company.company_id, pin = "5678",
    -- A basket is ids and quantities. A price in it is ignored: the store's
    -- own list says what a lamp costs.
    items = { { item_id = lamp.item_id, quantity = 2, price = 1 } },
    delivery = { kind = "home", x = 1, y = 2, z = 3, label = "Home" } }))
assert(home.total == 45, "two lamps at the store's price plus the delivery"
    .. " fee, whatever the basket claimed -- got " .. tostring(home.total))
assert(bank.balanceOf(kit) == kitBefore - 45, "the buyer paid it")
assert(bank.balanceOf(ana) == anaBefore + 45, "and the store's owner got it")
assert(home.order and home.order.stage == "Order received",
    "and the order is open at the Vault")

local mine = bank.request("SHOP_ORDERS", bank.as(kit))
assert(#mine.orders == 1 and mine.orders[1].order_id == home.order_id,
    "the buyer sees their order on the Deliveries page")
assert(#bank.request("SHOP_ORDERS", bank.as(ana)).orders == 0,
    "and nobody else does")

-- A store owner cannot buy from themselves: it would move money in a circle
-- and call it a sale.
rejected(bank.request, "OWN_STORE", "SHOP_CHECKOUT", bank.as(ana, {
    company_id = company.company_id, pin = "1234",
    items = { { item_id = lamp.item_id, quantity = 1 } },
    delivery = { kind = "home", x = 1, y = 2, z = 3 } }))

-- The order being opened and confirmed are the Core's business. A client
-- cannot reach either -- they are not routes.
assert(not core.routes.VAULT_SHOP_OPEN and not core.routes.VAULT_SHOP_PAID,
    "opening or confirming an order is not something a client can ask for")
assert(not core.actions.VAULT_SHOP_OPEN and not core.actions.VAULT_SHOP_PAID)

-- Delivering it ---------------------------------------------------------------------

local board = bank.request("DELIVERY_ORDERS", as(depot))
assert(#board.orders == 1 and board.orders[1].order_id == home.order_id,
    "the company's terminal sees the order")
assert(board.orders[1].code == nil,
    "without the buyer's code, which staff never need to deliver a parcel")
assert(#board.stages >= 4, "and the premade stages come with the board")

bank.request("DELIVERY_STAGE", as(depot, { order_id = home.order_id, stage = 2 }))
bank.request("DELIVERY_STAGE", as(depot,
    { order_id = home.order_id, label = "Stuck behind a creeper" }))
local followed = bank.request("SHOP_ORDER", bank.as(kit,
    { order_id = home.order_id })).order
assert(followed.stage == "Stuck behind a creeper",
    "a company's own words are a stage like any other")
assert(#followed.history == 3, "and the buyer sees every step it went through")

-- Another company's terminal sees none of it.
local other = bank.request("KIOSK_REGISTER", { name = "Rival" })
local rival = { terminal_id = other.terminal_id,
    terminal_token = other.terminal_token }
local rivalOwner = bank.request("KIOSK_OWNER_LOGIN",
    as(rival, { name = "Kit Wolf", pin = "5678" }))
local rivalCompany = bank.request("CREATE_COMPANY", as(rival, {
    owner_session = rivalOwner.owner_session,
    company_name = "Wolf Supplies" })).company
bank.request("LINK_TERMINAL", as(rival, { owner_session =
    rivalOwner.owner_session, company_id = rivalCompany.company_id }))
assert(#bank.request("DELIVERY_ORDERS", as(rival)).orders == 0,
    "a terminal sees its own company's orders and nobody else's")
rejected(bank.request, "NO_SUCH_ORDER", "DELIVERY_DONE",
    as(rival, { order_id = home.order_id }))

bank.request("DELIVERY_DONE", as(depot, { order_id = home.order_id,
    note = "Left by the door" }))
local delivered = bank.request("SHOP_ORDER", bank.as(kit,
    { order_id = home.order_id })).order
assert(delivered.status == "done" and delivered.stage == "Delivered")
assert(delivered.note == "Left by the door",
    "the buyer sees what the driver said, not only that it arrived")

-- Paying from another bank, collected at a pickup point ---------------------------------

local robAtRevo = revo.actions.TPB_REGISTER({ name = "Rob Hare", pin = "4321" })
local robAccount = revo.state.accounts[robAtRevo.account.account_id]
robAccount.balance = 100
local rob = bank.register("Rob Hare", "9999")
local anaMid = bank.balanceOf(ana)

rejected(bank.request, "BAD_PIN", "SHOP_CHECKOUT", bank.as(rob, {
    company_id = company.company_id,
    bank_account_id = robAccount.bank_account_id, pin = "0000",
    items = { { item_id = rug.item_id, quantity = 1 } },
    delivery = { kind = "pickup", point_id = depot.terminal_id } }))
assert(robAccount.balance == 100, "their bank refused, so nothing moved")
assert(bank.balanceOf(ana) == anaMid)
assert(#bank.request("SHOP_ORDERS", bank.as(rob)).orders == 0,
    "and there is no order to show for money that never moved")

local picked = bank.request("SHOP_CHECKOUT", bank.as(rob, {
    company_id = company.company_id,
    bank_account_id = robAccount.bank_account_id, pin = "4321",
    items = { { item_id = rug.item_id, quantity = 1 } },
    delivery = { kind = "pickup", point_id = depot.terminal_id } }))
assert(picked.total == 35, "no delivery fee to a pickup point")
assert(robAccount.balance == 65, "Revolution took it from Rob")
assert(bank.balanceOf(ana) == anaMid + 35, "and Foxy paid it to the store")
assert(type(picked.code) == "string" and #picked.code == 6,
    "the buyer gets a six digit code to collect with")

-- Asking twice about one order takes the money once.
revo.actions.LEDGER_CHARGE({ bank_account_id = robAccount.bank_account_id,
    pin = "4321", amount = 35, transfer_id = "SHOP" .. picked.order_id }, 1)
assert(robAccount.balance == 65, "a repeated charge is answered, not repeated")

-- Guessing PINs is locked out.
for _ = 1, 5 do
    pcall(revo.actions.LEDGER_CHARGE, { bank_account_id =
        robAccount.bank_account_id, pin = "0000", amount = 1,
        transfer_id = "SHOPGUESS" .. _ }, 1)
end
rejected(revo.actions.LEDGER_CHARGE, "CHARGES_LOCKED", {
    bank_account_id = robAccount.bank_account_id, pin = "4321", amount = 1,
    transfer_id = "SHOPAFTER1" }, 1)
robAccount.charge_misses = nil

-- And only the Foxy Bank may charge at all. Anybody on the network can send
-- a ledger message; not anybody holds Foxy's ledger name.
rejected(revo.actions.LEDGER_CHARGE, "NOT_A_BANK", {
    bank_account_id = robAccount.bank_account_id, pin = "4321", amount = 1,
    transfer_id = "SHOPSTRANGER" }, 77)

-- The Foxy Bank rebuilt on another computer keeps its ledger name. Revolution
-- finds it again rather than refusing it until somebody restarts Revolution
-- -- though not straight away: a lookup is a wait on the network, so a
-- stranger's charges are answered from memory for a minute at a time.
local realLookup = rednet.lookup
rednet.lookup = function() return 5 end
rejected(revo.actions.LEDGER_CHARGE, "NOT_A_BANK", {
    bank_account_id = robAccount.bank_account_id, pin = "4321", amount = 1,
    transfer_id = "SHOPMOVED01" }, 5)
bank.advanceMs(61 * 1000)
local robBeforeMove = robAccount.balance
local moved = revo.actions.LEDGER_CHARGE({
    bank_account_id = robAccount.bank_account_id, pin = "4321", amount = 1,
    transfer_id = "SHOPMOVED01" }, 5)
assert(moved.charged == 1 and robAccount.balance == robBeforeMove - 1,
    "the rebuilt Foxy Bank is found again")
rejected(revo.actions.LEDGER_CHARGE, "NOT_A_BANK", {
    bank_account_id = robAccount.bank_account_id, pin = "4321", amount = 1,
    transfer_id = "SHOPSTALE01" }, 1)
rednet.lookup = realLookup
bank.advanceMs(61 * 1000)
robAccount.balance = robAccount.balance + 1

-- The pickup point ------------------------------------------------------------------
-- 11.1: the courier stocks it with the order's delivery code, and the buyer
-- confirms it is them in Foxy before it comes out.

local waiting = bank.request("PICKUP_ORDERS", as(depot))
assert(#waiting.orders == 1 and not waiting.orders[1].locker,
    "the pickup point knows a parcel is on its way")
local deliveryCode = waiting.orders[1].delivery_code
assert(type(deliveryCode) == "string" and #deliveryCode == 6
    and deliveryCode ~= picked.code, "the company sees a courier's code")
local robsView = bank.request("SHOP_ORDER", bank.as(rob,
    { order_id = picked.order_id })).order
assert(robsView.code == picked.code and robsView.delivery_code == nil,
    "the buyer sees their own code and never the courier's")
assert(waiting.orders[1].code == nil, "and the company never the buyer's")
rejected(bank.request, "NOT_HERE_YET", "PICKUP_CODE",
    as(depot, { code = picked.code }))
rejected(bank.request, "UPDATE_TERMINAL", "PICKUP_COLLECT",
    as(depot, { code = picked.code }))
rejected(bank.request, "UPDATE_TERMINAL", "PICKUP_STOCK", as(depot, {
    order_id = picked.order_id, locker = "minecraft:chest_1" }))
rejected(bank.request, "BAD_CODE", "PICKUP_STOCK", as(depot, {
    order_id = picked.order_id, locker = "minecraft:chest_1",
    code = picked.code }))
local arriving = bank.request("PICKUP_CODE", as(depot, { code = deliveryCode }))
assert(arriving.kind == "deliver" and arriving.order_id == picked.order_id,
    "the delivery code says which parcel is being brought in")
bank.request("PICKUP_STOCK", as(depot, { order_id = picked.order_id,
    locker = "minecraft:chest_1", code = deliveryCode }))
assert(bank.request("SHOP_ORDER", bank.as(rob,
    { order_id = picked.order_id })).order.stage == "Ready for pickup",
    "stocking it tells the buyer it is ready")
rejected(bank.request, "ALREADY_HERE", "PICKUP_CODE",
    as(depot, { code = deliveryCode }))
assert(bank.request("PICKUP_ORDERS", as(depot)).orders[1].delivery_code == nil,
    "and the courier's code is spent")

for _ = 1, 4 do
    pcall(bank.request, "PICKUP_CODE", as(depot, { code = "000000" }))
end
local asking = bank.request("PICKUP_CODE", as(depot, { code = picked.code }))
assert(asking.kind == "collect" and asking.waiting and not asking.locker,
    "the right code asks the buyer first, and opens nothing yet")
local robAccountHere = core.state.accounts[rob.id]
assert(robAccountHere.notifications[1].security_order == picked.order_id
    and robAccountHere.notifications[1].style == "fullscreen",
    "the question lands on the buyer's PUMPE, full screen")
rejected(bank.request, "NOT_CONFIRMED", "PICKUP_RELEASE",
    as(depot, { order_id = picked.order_id }))
assert(bank.request("PICKUP_WAIT", as(depot,
    { order_id = picked.order_id })).status == "asked")
rejected(bank.request, "BAD_PIN", "SECURITY_CONFIRM", bank.as(rob, {
    order_id = picked.order_id, pin = "1111" }))
bank.request("SECURITY_CONFIRM", bank.as(rob, {
    order_id = picked.order_id, pin = "9999" }))
assert(bank.request("PICKUP_WAIT", as(depot,
    { order_id = picked.order_id })).status == "confirmed")
local handed = bank.request("PICKUP_RELEASE", as(depot,
    { order_id = picked.order_id }))
assert(handed.locker == "minecraft:chest_1",
    "confirmed, the right code opens the right locker")
assert(bank.request("SHOP_ORDER", bank.as(rob,
    { order_id = picked.order_id })).order.status == "collected")
rejected(bank.request, "NO_SUCH_CODE", "PICKUP_CODE",
    as(depot, { code = picked.code }))

for _ = 1, 5 do
    pcall(bank.request, "PICKUP_CODE", as(depot, { code = "111111" }))
end
rejected(bank.request, "TRY_LATER", "PICKUP_CODE",
    as(depot, { code = "222222" }))

-- When the other bank goes quiet ------------------------------------------------------
-- The one case that can create or lose money. The charge might have landed;
-- the order is called off either way, and the Core asks later rather than
-- guessing. If the money was taken, it goes back.

robAccount.balance = 100
local robBefore = robAccount.balance
local anaQuiet = bank.balanceOf(ana)
local quietCharge
local realCharge = revo.actions.LEDGER_CHARGE
revo.actions.LEDGER_CHARGE = function(payload, sender)
    -- It lands at Revolution; the answer never gets back.
    quietCharge = realCharge(payload, sender)
    error({ pumpe = false }, 0)
end
ledgerAnswers = true
local sameAsk = core.ledger.ask
core.ledger.ask = function(bankCode, action, payload, timeout)
    if bankCode == revo.state.bank_code and action == "LEDGER_CHARGE" then
        pcall(revo.actions.LEDGER_CHARGE, payload, 1)
        return nil, "No answer"
    end
    return sameAsk(bankCode, action, payload, timeout)
end
rejected(bank.request, "PAYMENT_PENDING", "SHOP_CHECKOUT", bank.as(rob, {
    company_id = company.company_id,
    bank_account_id = robAccount.bank_account_id, pin = "4321",
    items = { { item_id = rug.item_id, quantity = 1 } },
    delivery = { kind = "pickup", point_id = depot.terminal_id } }))
assert(quietCharge and robAccount.balance == robBefore - 35,
    "Revolution did take the money")
assert(bank.balanceOf(ana) == anaQuiet,
    "but the store was not paid for an order nobody could confirm")
revo.actions.LEDGER_CHARGE = realCharge
core.ledger.ask = sameAsk

core.shop.reconcile()
assert(robAccount.balance == robBefore,
    "and asking afterwards found it and sent it back")
assert(next(core.state.shop_charges or {}) == nil,
    "with nothing left parked")

-- The scheduler has to actually run it. The test above calls reconcile by
-- hand; a Core whose scheduler forgot it would park a quiet charge forever
-- and this file would never notice, so read the loop itself.
do
    local body = assert(io.open("../bank_server.lua")):read("a")
    local loop = body:match("local function schedulerLoop%(%)(.-)\nend")
    assert(loop and loop:find("shop.reconcile", 1, true),
        "the Core's scheduler must reconcile shop charges and unconfirmed"
            .. " orders, or a quiet charge is never refunded")
end

print("host_shop_test: OK")
