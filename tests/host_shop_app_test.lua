-- The Shop app on a 26x20 PUMPE, against a real Bank Core and Vault.
--
-- The app is handed the same api table the phone gives every installed app,
-- with its Bank calls going to the real Core as the buyer. Another bank is
-- the one thing stood in for: host_shop_test.lua runs Revolution for real,
-- and here only its answers matter -- yes, or nothing at all.

package.path = "../?.lua;../?/init.lua;" .. package.path

local harness = require("bank_pair_harness")
local bank = harness.pair()
local core = bank.core
local util = require("lib.util")
-- Lua has an os.time of its own, so the harness leaves it be, and every real
-- second of this run would count as an in-game hour -- enough to confirm an
-- order before the test gets round to cancelling it.
os.time = function() return harness.time end

local WIDTH, HEIGHT = 26, 20
-- The real ui library, for the one piece of it apps share: the tab bar.
local realUi = dofile("../lib/ui.lua")

-- A store, and the terminal that delivers for it ----------------------------------

bank.register("Ana Fox", "1234")
local kit = bank.register("Kit Wolf", "5678")
bank.fund(kit, 1000)

local function terminal(name)
    local made = bank.request("KIOSK_REGISTER", { name = name })
    return function(extra)
        extra = extra or {}
        extra.terminal_id, extra.terminal_token =
            made.terminal_id, made.terminal_token
        return extra
    end, made.terminal_id
end
local till = terminal("Fox Goods Till")
local owner = bank.request("KIOSK_OWNER_LOGIN", till({ name = "Ana Fox",
    pin = "1234" }))
local company = bank.request("CREATE_COMPANY", till({
    owner_session = owner.owner_session, company_name = "Fox Goods" })).company
bank.request("LINK_TERMINAL", till({ owner_session = owner.owner_session,
    company_id = company.company_id }))
local function product(name, price, blurb)
    local item = bank.request("ADD_PRODUCT", till({ name = name, price = price,
        kind = "one_time" })).item
    bank.request("SHOP_PRODUCT", till({ item_id = item.item_id, online = true,
        blurb = blurb }))
    return item
end
product("Lamp", 20, "Bright")
product("Rug", 35)
product("Candle", 2.5, "Smells of pine")
bank.request("SHOP_SETUP", till({ color = "cyan", tagline = "Lamps and rugs",
    home = true, pickup = true, fee = 5, open = true }))

local warehouse, warehouseId = terminal("Warehouse")
bank.request("LINK_TERMINAL", warehouse({ owner_session = owner.owner_session,
    company_id = company.company_id }))
bank.request("PICKUP_REGISTER", warehouse({ name = "North Point", x = 10,
    y = 64, z = -20 }))

-- Another bank, as far as the Core can tell: it answers a charge with yes,
-- or it does not answer at all.
local charges, otherBankAnswers = {}, true
core.ledger.ask = function(_, action, payload)
    if action == "LEDGER_CHARGE" then
        charges[#charges + 1] = util.copy(payload)
        if not otherBankAnswers then return nil, "No answer" end
        return { charged = payload.amount, name = "Kit Wolf" }
    end
    if action == "LEDGER_STATUS" then return { applied = false } end
    return nil, "No answer"
end

-- The phone ------------------------------------------------------------------------

local kept = {}
local position = { x = 120.6, y = 70.2, z = -45.9 }

local function wrap(value, width)
    value, width = tostring(value or ""), math.max(1, width)
    local lines = {}
    for line in (value .. "\n"):gmatch("(.-)\n") do
        while #line > width do
            lines[#lines + 1] = line:sub(1, width)
            line = line:sub(width + 1)
        end
        lines[#lines + 1] = line
    end
    return lines
end

local function runApp(script, wanted)
    local seen = { frames = {}, messages = {} }
    local frame = {}
    local surface = { getSize = function() return WIDTH, HEIGHT end }
    local function take(queue, what)
        local entry = table.remove(queue, 1)
        assert(entry ~= nil, "the app asked for an unexpected " .. what)
        if type(entry) == "function" then entry = entry(seen) end
        return entry
    end
    local function box(label, x, y, width, height)
        assert(x >= 1 and y >= 1, label .. " starts outside the screen")
        assert(x + width - 1 <= WIDTH, label .. " is wider than the screen")
        assert(y + height - 1 <= HEIGHT, label .. " is below the screen")
    end
    local function draw(value) frame[#frame + 1] = tostring(value) end

    local ui = { theme = {
        background = colors.black, panel = colors.gray,
        panelAlt = colors.lightGray, ink = colors.white,
        muted = colors.lightGray, accent = colors.cyan,
        accentDark = colors.blue, success = colors.lime,
        danger = colors.red, warning = colors.orange, shadow = colors.gray,
    } }
    function ui.clear()
        frame = {}
        seen.frames[#seen.frames + 1] = frame
    end
    function ui.fill(_, x, y, width, height) box("fill", x, y, width, height) end
    function ui.truncate(value, maximum)
        return tostring(value or ""):sub(1, math.max(0, maximum))
    end
    function ui.header(_, title, subtitle)
        -- The phone's own header: its title and subtitle each get a row.
        assert(#tostring(title) <= WIDTH - 3, "title clipped: " .. tostring(title))
        assert(#tostring(subtitle or "") <= WIDTH - 3,
            "subtitle clipped: " .. tostring(subtitle))
        draw(title)
        draw(subtitle or "")
    end
    function ui.text(_, x, y, value)
        box("text " .. tostring(value), x, y, math.max(1, #tostring(value)), 1)
        draw(value)
    end
    function ui.center(_, y, value)
        assert(y >= 1 and y <= HEIGHT and #tostring(value) <= WIDTH,
            "centred text off the screen: " .. tostring(value))
        draw(value)
    end
    function ui.wrappedText(_, x, y, value, width, lines)
        box("wrapped text", x, y, width, lines)
        draw(value)
    end
    function ui.message(_, kind, title, body)
        seen.messages[#seen.messages + 1] = { kind = kind, title = title,
            body = body }
    end
    function ui.input(_, title)
        draw("input:" .. title)
        return take(script.inputs, "text box: " .. title)
    end
    function ui.pin(_, title)
        draw("pin:" .. title)
        return take(script.pins, "PIN pad: " .. title)
    end
    function ui.confirm(_, title, body, yes, no)
        draw("confirm:" .. title .. " " .. tostring(body))
        local buttonWidth = math.max(8, math.floor((WIDTH - 6) / 2))
        assert(#(yes or "YES") <= buttonWidth - 2
            and #(no or "NO") <= buttonWidth - 2, "confirm label clipped")
        return take(script.confirms, "confirmation: " .. title)
    end
    -- The real tab bar, run against this stub scene, so its layout is
    -- bounds checked here like everything else the app draws.
    ui.tabBar = realUi.tabBar
    function ui.scene()
        local scene, tappable = {}, {}
        function scene:button(id, x, y, width, height, label, options)
            box("button " .. tostring(label), x, y, width, height)
            assert(#wrap(label, math.max(1, width - 2)) <= height,
                "button label clipped: " .. tostring(label))
            draw(label)
            if not (options and options.disabled) then tappable[id] = true end
        end
        function scene:hotspot(id, x, y, width, height)
            box("hotspot " .. tostring(id), x, y, width, height)
            tappable[id] = true
        end
        function scene:wait(options)
            local action = take(script.actions, "tap")
            -- A tick only ever reaches a screen that asked for a timer:
            -- that is the whole of how a page is live.
            assert(action ~= "__tick" or (options and options.tickRate),
                "a tick reached a screen that never asked to refresh")
            -- And a tap only lands on something that is there to tap.
            assert(action:sub(1, 2) == "__" or tappable[action],
                "tapped " .. action .. ", which is not on the screen")
            return action
        end
        return scene
    end

    local api = {
        ui = ui, util = util, target = surface, colors = colors,
        money = function(value) return util.money(value, "$") end,
        -- As the phone does it: stamped with the app, sent as the buyer.
        request = function(action, payload)
            local scoped = {}
            for key, value in pairs(payload or {}) do scoped[key] = value end
            scoped.app_id, scoped.session_token = "SHOP", kit.token
            local ok, result = pcall(bank.request, action, scoped)
            if ok then return result end
            if type(result) == "table" and result.pumpe then
                return nil, result.message, result.code
            end
            error(result, 0)
        end,
        account = function() return core.state.accounts[kit.id] end,
        refresh = function() end,
        running = function() return true end,
        position = function() return position end,
        save = function(value) kept = util.copy(value) return true end,
        load = function() return util.copy(kept) end,
        action = function() return wanted end,
    }
    assert(loadfile("../shop.lua"))()(api)
    for name, queue in pairs(script) do
        assert(#queue == 0, #queue .. " scripted " .. name .. " never used")
    end
    return seen
end

local function has(frame, wanted)
    for _, value in ipairs(frame) do
        if tostring(value):find(wanted, 1, true) then return true end
    end
    return false
end
local function anyFrame(seen, wanted)
    for _, frame in ipairs(seen.frames) do
        if has(frame, wanted) then return frame end
    end
    return nil
end
local function said(seen, title)
    for _, message in ipairs(seen.messages) do
        if message.title == title then return message end
    end
    return nil
end

local function newScript()
    return { actions = {}, inputs = {}, pins = {}, confirms = {} }
end
local function push(queue, ...)
    for _, entry in ipairs({ ... }) do queue[#queue + 1] = entry end
end

-- A first visit: search, a basket, home by GPS, Foxy -----------------------------

local orders = bank.vault_state.orders
local firstOrder, secondOrder, pickupCode
local script = newScript()

-- Stores: search by what a store sells, by something nobody sells, then
-- everything again.
push(script.actions, "pick:1", "pick:1", "pick:1")
push(script.inputs, "rugs", "boats", "")
-- Into Fox Goods: two lamps and a rug, and the rug taken back out.
push(script.actions, "pick:2", "add:1", "add:1", "add:2", "basket", "less:2",
    "checkout")
-- Deliver to "My address", from GPS, kept as Home. Pay with Foxy.
push(script.actions, "pick:1", "pick:1", "pick:1")
push(script.confirms, true)
push(script.inputs, "Home")
push(script.confirms, true)
push(script.pins, "5678")
-- The order's page. While it is open, the warehouse moves the order on,
-- and the page catches up without a tap.
push(script.actions, function(seen)
    local latest
    for id in pairs(orders) do latest = id end
    firstOrder = latest
    assert(has(seen.frames[#seen.frames], "Order received"))
    -- The place was kept the moment it was named, in whole blocks. The
    -- Vault rounds an order's address itself; a kept place is only ever
    -- rounded here.
    assert(#kept.places == 1 and kept.places[1].label == "Home"
        and kept.places[1].x == 120 and kept.places[1].z == -46,
        "Home is kept on the phone, in whole blocks")
    bank.request("DELIVERY_STAGE", warehouse({ order_id = firstOrder,
        stage = 2 }))
    return "__tick"
end, function(seen)
    assert(has(seen.frames[#seen.frames], "Packing"),
        "the Delivery page updated by itself")
    return "back"
end)
-- The Delivery tab, which ticks too; the order is in it.
push(script.actions, "__tick", "pick:1", "back")
-- Places: add one by typing, then forget Home.
push(script.actions, "tab:places", "pick:2", "pick:2")
push(script.inputs, "-300", "72", "999", "Farm")
push(script.actions, "pick:1")
push(script.confirms, true)
-- Back to the store: a candle and a rug, to a pickup point, from another
-- bank. A candle makes the total 37.50, and another bank pays whole
-- amounts, so the app says so before asking for anything.
push(script.actions, function()
    assert(#kept.places == 1 and kept.places[1].label == "Farm",
        "forgetting Home is saved at once, not with the next thing kept")
    return "tab:stores"
end, "pick:2", "add:2", "add:3", "basket",
    "checkout", "pick:3", "pick:2")
-- Without the candle it is 35, and it goes through.
push(script.actions, "less:2", "checkout", "pick:3", "pick:2")
push(script.inputs, "0042123412341234")
push(script.confirms, true)
push(script.pins, "4321")
push(script.actions, function(seen)
    for id, order in pairs(orders) do
        if id ~= firstOrder then secondOrder, pickupCode = id, order.code end
    end
    assert(has(seen.frames[#seen.frames], pickupCode),
        "the pickup code is on the order's page")
    return "back"
end)
-- Straight to the Delivery tab after ordering. Both orders are there.
push(script.actions, "__terminate")

local startBalance = bank.balanceOf(kit)
local seen = runApp(script)

assert(anyFrame(seen, "1 stores open"), "search finds a store by its tagline")
assert(anyFrame(seen, "0 stores open"), "and nothing for what nobody sells")
assert(anyFrame(seen, "Fox Goods"))

local home = orders[firstOrder]
assert(home.total == 45, "two lamps and the delivery fee: " .. tostring(home.total))
assert(bank.balanceOf(kit) == startBalance - 45, "paid from Foxy: "
    .. tostring(bank.balanceOf(kit)))
-- In whole blocks. The block under z = -45.9 is -46: rounding towards zero
-- would send the parcel to the block next door.
assert(home.delivery.kind == "home" and home.delivery.x == 120
    and home.delivery.y == 70 and home.delivery.z == -46,
    "delivered to where the phone was, in whole blocks")
assert(home.delivery.label == "Home")
assert(said(seen, "Ordered"))

assert(said(seen, "Whole amounts only"),
    "another bank is told about whole amounts before any PIN")
assert(#charges == 1, "and only the whole amount was ever charged")
assert(charges[1].amount == 35 and charges[1].pin == "4321"
    and charges[1].bank_account_id == "0042123412341234",
    "the other bank was asked with its own Account ID and PIN")
local pickup = orders[secondOrder]
assert(pickup.delivery.kind == "pickup"
    and pickup.delivery.point_id == warehouseId)
local ordered = said(seen, "Ordered")
for _, message in ipairs(seen.messages) do
    if message.title == "Ordered" then ordered = message end
end
assert(ordered.body:find(pickupCode, 1, true),
    "a pickup order says its code straight away")
assert(bank.balanceOf(kit) == startBalance - 45, "and did not touch Foxy")

-- What is kept on the phone, and only there.
assert(#kept.places == 1 and kept.places[1].label == "Farm"
    and kept.places[1].x == -300 and kept.places[1].z == 999,
    "Home was forgotten and Farm kept")
assert(kept.bank_account_id == "0042123412341234",
    "the Account ID is remembered for next time")
for key, value in pairs(kept) do
    assert(not tostring(value):find("4321", 1, true) and key ~= "pin",
        "a PIN is never kept")
end

-- A bank that does not answer ---------------------------------------------------------
-- Nothing is ordered, and nothing about the attempt is remembered.

otherBankAnswers = false
local before = util.copy(orders)
script = newScript()
-- The rug again, to the pickup point, from the other bank.
push(script.actions, "pick:2", "add:2", "basket", "checkout", "pick:3", "pick:2")
push(script.inputs, "0042999999999999")
push(script.confirms, true)
push(script.pins, "4321")
push(script.actions, "back", "back")
push(script.confirms, true)
push(script.actions, "__terminate")
seen = runApp(script, "stores")
assert(said(seen, "Not ordered"), "the buyer is told")
assert(said(seen, "Not ordered").body:find("did not answer", 1, true))
assert(kept.bank_account_id == "0042123412341234",
    "a failed payment does not replace the remembered Account ID")
local count, countBefore = 0, 0
for _ in pairs(orders) do count = count + 1 end
for _ in pairs(before) do countBefore = countBefore + 1 end
assert(count == countBefore, "and no order is left behind")

-- Opened from search as "My deliveries" --------------------------------------------------

script = newScript()
-- Leaving by the top-left mark, the way home every tabbed app has since
-- 11.0. Shop 10.2 had no way out but Ctrl+T.
push(script.actions, "home")
seen = runApp(script, "delivery")
assert(has(seen.frames[1], "Delivery") and has(seen.frames[1], "2 on the way"),
    "the app opens on the Delivery page, with both orders on their way")

-- Cancelling, from the order's own page (11.0) -------------------------------------

bank.request("SHOP_SETUP", till({ cancel = true, return_days = 5 }))
local cancelledOrder
local balanceBefore = bank.balanceOf(kit)
script = newScript()
-- Fox Goods, a lamp, to Farm, with Foxy.
push(script.actions, "pick:2", function(seen)
    assert(has(seen.frames[#seen.frames], "Returns 5d, cancel 2h"),
        "the store says its terms before anybody buys")
    return "add:1"
end, "basket", "checkout", "pick:1", "pick:1")
push(script.confirms, true)
push(script.pins, "5678")
push(script.actions, function(seen)
    -- The newest order: ids count up, and pairs() has no order of its own.
    for id in pairs(orders) do
        if not cancelledOrder or id > cancelledOrder then cancelledOrder = id end
    end
    assert(has(seen.frames[#seen.frames], "Cancel order (2h 0m)"),
        "a new order says how long it can be cancelled for")
    return "cancel"
end)
push(script.confirms, true)
push(script.actions, "back", "__terminate")
seen = runApp(script)
assert(said(seen, "Cancelled"), "the buyer is told")
assert(orders[cancelledOrder].status == "cancelled")
assert(bank.balanceOf(kit) == balanceBefore, "with every coin back")

-- Returning, once it has arrived ---------------------------------------------------------

bank.request("DELIVERY_DONE", warehouse({ order_id = firstOrder }))
script = newScript()
-- Open first, then newest: the pickup order, the cancelled one, then this.
push(script.actions, "pick:3", function(seen)
    assert(has(seen.frames[#seen.frames], "Return it (5d 0h)"),
        "a delivered order says how long it can be returned for")
    return "return"
end)
push(script.inputs, "It flickers")
push(script.actions, function(seen)
    assert(has(seen.frames[#seen.frames], "Return asked for"),
        "and then where the return stands")
    return "back"
end, "__terminate")
seen = runApp(script, "delivery")
assert(said(seen, "Return asked for"))
assert(orders[firstOrder].return_request.reason == "It flickers")

print("host_shop_app_test: OK")
