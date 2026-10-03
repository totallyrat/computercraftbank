-- PUMPE APP: Shop
-- PUMPE APP ACTION: delivery | My deliveries | Where my orders are
-- PUMPE APP ACTION: stores | Browse stores | Order something home



















return function(api)
local ui, util, target = api.ui, api.util, api.target
local colors, money = api.colors, api.money

local SHOP = colors.orange

local DARK = { red = true, green = true, blue = true, purple = true,
brown = true, gray = true }
local MAX_PLACES = 6
local WORDS = {
open = "On its way", done = "Delivered", collected = "Collected",
cancelled = "Cancelled",
}
local RETURN_WORDS = {
requested = "Return asked for", refunded = "Return refunded",
declined = "Return declined",
}

local saved = type(api.load) == "function" and api.load() or {}
saved.places = type(saved.places) == "table" and saved.places or {}

local function running() return api.running() end
local function ask(action, payload, silent)
return api.request(action, payload or {}, silent)
end
local function keep()
if type(api.save) == "function" then api.save(saved) end
end


local function paint(colorName)
local background = colors[tostring(colorName or "")] or SHOP
return background, DARK[colorName] and colors.white or colors.black
end


local function span(hours)
local minutes = math.max(0, math.floor((tonumber(hours) or 0) * 60))
if minutes >= 1440 then
return math.floor(minutes / 1440) .. "d "
.. math.floor((minutes % 1440) / 60) .. "h"
elseif minutes >= 60 then
return math.floor(minutes / 60) .. "h " .. (minutes % 60) .. "m"
end
return minutes .. "m"
end



local function terms(store, full)
local days, hours = tostring(store.return_days or 5),
tostring(store.confirm_hours or 2)
if full then
return "Returns within " .. days .. " days of arriving"
.. (store.cancel and ("; cancel within " .. hours .. "h")
or "; no cancelling")
end
return "Returns " .. days .. "d" .. (store.cancel
and (", cancel " .. hours .. "h") or "")
end


local function offers(store)
local parts = {}
if (tonumber(store.sale) or 0) > 0 then
parts[#parts + 1] = store.sale .. "% off all"
end
if store.free_shipping and store.home then
parts[#parts + 1] = (tonumber(store.free_over) or 0) > 0
and ("free delivery " .. money(store.free_over) .. "+")
or "free delivery"
end
if #parts == 0 then return nil end
local text = table.concat(parts, ", ")
return string.upper(text:sub(1, 1)) .. text:sub(2)
end

local function where(delivery)
delivery = delivery or {}
local spot = delivery.x and (delivery.x .. " " .. delivery.y .. " "
.. delivery.z) or "no coordinates"
if delivery.kind == "pickup" then
return tostring(delivery.point_name or "Pickup point"), spot
end
return tostring(delivery.label or "Home"), spot
end



local function choose(title, subtitle, options, tabs)
local page = 1
while running() do
local width, height = target.getSize()
local bottom = tabs and height - 2 or height - 1
local per = math.max(1, math.floor((bottom - 4) / 3))
local pages = math.max(1, math.ceil(#options / per))
page = math.max(1, math.min(page, pages))
ui.clear(target)
ui.header(target, title, subtitle and ui.truncate(subtitle,
width - 3), util.formatClock())
local scene = ui.scene(target)
for slot = 1, per do
local index = (page - 1) * per + slot
local option = options[index]
if not option then break end
local background, foreground = option.color
or ui.theme.panel, option.ink or colors.white
scene:button("pick:" .. index, 2, 2 + slot * 3, width - 2, 2,
ui.truncate(option.label, width - 4) .. (option.detail
and ("\n" .. ui.truncate(option.detail, width - 4))
or ""),
{ background = background, foreground = foreground })
end
if #options == 0 and subtitle then
ui.wrappedText(target, 2, 6, tabs and tabs.empty
or "Nothing here yet.", width - 2, 4, ui.theme.muted)
end
if pages > 1 then
scene:button("prev", width - 9, bottom + 1, 4, 1, "<",
{ background = ui.theme.panel, disabled = page <= 1 })
scene:button("next", width - 4, bottom + 1, 4, 1, ">",
{ background = ui.theme.panel, disabled = page >= pages })
end
if tabs then
tabs.draw(scene)
else
scene:button("back", 1, height, 8, 1, "< Back",
{ background = ui.theme.panel })
end
local action = scene:wait(tabs and tabs.tick
and { tickRate = tabs.tick } or nil)
if action == "back" or action == "__terminate" then return nil end
if action == "prev" then
page = page - 1
elseif action == "next" then
page = page + 1
elseif action == "__tick" then
return "__tick"
elseif action == "home" or (action and action:match("^tab:")) then
return action
else
local index = tonumber(action and action:match("^pick:(%d+)$"))
if index and options[index] then return options[index] end
end
end
return nil
end



local function coordinate(axis, initial)
local typed = ui.input(target, axis .. " coordinate", {
hint = "A whole number", mode = "integer", maxLength = 8,
initial = initial and tostring(initial) or nil })
return typed and tonumber(typed) and math.floor(tonumber(typed)) or nil
end


local function findPlace()
local found = choose("Where to?", "Pick how to say where", {
{ id = "gps", label = "Where I am now",
detail = "Needs GPS anchors", color = SHOP,
ink = colors.black },
{ id = "type", label = "Type coordinates",
detail = "X, Y and Z from F3" },
})
if not found then return nil end
if found.id == "gps" then
local fix = type(api.position) == "function" and api.position()
if not fix then
ui.message(target, "warning", "No GPS here",
"Type the coordinates instead", 1.8)
return nil
end
return { x = math.floor(fix.x), y = math.floor(fix.y),
z = math.floor(fix.z) }
end
local x = coordinate("X")
if not x then return nil end
local y = coordinate("Y", 64)
if not y then return nil end
local z = coordinate("Z")
if not z then return nil end
return { x = x, y = y, z = z }
end

local function keepPlace(spot)
if #saved.places >= MAX_PLACES then
ui.message(target, "info", "Places are full",
"Remove one in Places to keep more", 1.8)
return spot
end
if not ui.confirm(target, "Keep this place?",
spot.x .. " " .. spot.y .. " " .. spot.z
.. ". Next time it is one tap.", "Keep", "Skip") then
return spot
end
local name = ui.input(target, "Call it", { hint = "Home, Farm, Shop",
maxLength = 12, allowSpace = true, initial = #saved.places == 0
and "Home" or nil })
if name then
spot.label = name
table.insert(saved.places, spot)
keep()
end
return spot
end



local function sorted(orders)
table.sort(orders, function(a, b)
if (a.status == "open") ~= (b.status == "open") then
return a.status == "open"
end
return tostring(a.order_id) > tostring(b.order_id)
end)
return orders
end


local function orderPage(orderId)
while running() do
local width, height = target.getSize()
local got = ask("SHOP_ORDER", { order_id = orderId }, true)
local order = got and got.order
ui.clear(target)
if not order then
ui.header(target, "Order", orderId, util.formatClock())
ui.wrappedText(target, 2, 6, "Cannot reach the Bank. This"
.. " page tries again by itself.", width - 2, 3,
ui.theme.muted)
else
local background, foreground = paint(order.color)
ui.header(target, ui.truncate(order.company_name, width - 9),
"Order " .. order.order_id, util.formatClock())

ui.fill(target, 1, 5, width, 2, background)
ui.text(target, 2, 5, ui.truncate(WORDS[order.status]
or order.status, width - 2), foreground, background)
ui.text(target, 2, 6, ui.truncate(order.stage or "",
width - 2), foreground, background)
local row = 8
local place, spot = where(order.delivery)
if order.delivery.kind == "pickup" and order.status == "open" then
ui.text(target, 2, row, "Code", ui.theme.muted)
ui.text(target, 7, row, tostring(order.code or "------"),
ui.theme.accent)

local check = order.security and order.security.status
ui.text(target, 14, row, ui.truncate(check == "asked"
and "check Foxy" or check == "confirmed" and "confirmed"
or order.stocked and "ready" or "not yet", width - 14),
check == "asked" and ui.theme.warning
or order.stocked and ui.theme.success or ui.theme.muted)
row = row + 1
end
ui.text(target, 2, row, ui.truncate(place .. "  " .. spot,
width - 2), ui.theme.ink)
row = row + 2
local shown = 0
for _, line in ipairs(order.lines or {}) do
if row > height - 7 then break end
ui.text(target, 2, row, ui.truncate(line.quantity .. " x "
.. line.name, width - 2), ui.theme.ink)
row, shown = row + 1, shown + 1
end
if shown < #(order.lines or {}) then
ui.text(target, 2, row, "+" .. (#order.lines - shown)
.. " more", ui.theme.muted)
row = row + 1
end
ui.text(target, 2, row, ui.truncate("Paid " .. money(order.total)
.. "  " .. tostring(order.paid_with or ""), width - 2),
ui.theme.muted)
if (tonumber(order.discount) or 0) > 0 then
row = row + 1
ui.text(target, 2, row, ui.truncate("Saved "
.. money(order.discount) .. (order.promo and (" with "
.. order.promo) or ""), width - 2), ui.theme.muted)
end
row = row + 2


local history = order.history or {}
local room = math.max(0, height - 3 - row)
for index = math.max(1, #history - room + 1), #history do
local step = history[index]
ui.text(target, 2, row, ui.truncate(tostring(step.time)
.. "  " .. tostring(step.label), width - 2),
index == #history and ui.theme.ink or ui.theme.muted)
row = row + 1
end
if order.note and row <= height - 3 then
ui.text(target, 2, row,
ui.truncate("Note: " .. order.note, width - 2),
ui.theme.accent)
end
end
local scene = ui.scene(target)
local request = order and order.return_request
if order and order.cancellable then
scene:button("cancel", 2, height - 2, width - 2, 1,
ui.truncate("Cancel order (" .. span(order.confirms_in)
.. ")", width - 4), { background = ui.theme.danger })
elseif order and order.returnable then
scene:button("return", 2, height - 2, width - 2, 1,
ui.truncate("Return it (" .. span(order.returns_left)
.. ")", width - 4), { background = ui.theme.panel })
elseif request then
ui.text(target, 2, height - 2, ui.truncate((RETURN_WORDS[
request.status] or "Return") .. (request.answer
and (": " .. request.answer) or ""), width - 2),
request.status == "declined" and ui.theme.warning
or ui.theme.accent)
end
scene:button("back", 1, height, 8, 1, "< Back",
{ background = ui.theme.panel })
local action = scene:wait({ tickRate = 4 })
if action == "back" or action == "__terminate" then return end
if action == "cancel" and order and ui.confirm(target,
"Cancel this order?", money(order.total)
.. " comes back to you, and the store is told.",
"Cancel", "Keep") then
local done, err = ask("SHOP_CANCEL", { order_id = orderId },
true)
if done then
ui.message(target, "success", "Cancelled", money(
done.refunded) .. " back to " .. tostring(done.to), 2)
else
ui.message(target, "error", "Not cancelled", err, 2)
end
elseif action == "return" and order then
local reason = ui.input(target, "Why send it back?", {
hint = "The store sees this", maxLength = 40,
allowSpace = true, minLength = 2 })
if reason then
local asked, err = ask("SHOP_RETURN",
{ order_id = orderId, reason = reason }, true)
if asked then
ui.message(target, "success", "Return asked for",
"You are refunded once the store has it back", 2.4)
else
ui.message(target, "error", "Not asked", err, 2)
end
end
end
end
end

local function deliveryPage(tabs)
while running() do
local listed = ask("SHOP_ORDERS", {}, true)
local options, open = {}, 0
for _, order in ipairs(sorted(listed and listed.orders or {})) do
if order.status == "open" then open = open + 1 end
local background, foreground = paint(order.color)
if order.status ~= "open" then
background, foreground = ui.theme.panel, colors.white
end
local request = order.return_request
options[#options + 1] = { id = order.order_id,
label = tostring(order.company_name),
detail = request and (RETURN_WORDS[request.status]
or "Return") or ((order.status == "open" and ""
or "Done: ") .. tostring(order.stage)),
color = background, ink = foreground }
end
tabs.empty = listed
and "Nothing ordered yet. Find something in Stores."
or "Cannot reach the Bank right now."
tabs.tick = 5
local picked = choose("Delivery", listed and (open
.. " on the way") or "Offline", options, tabs)
tabs.tick = nil
if type(picked) == "table" then
orderPage(picked.id)
elseif picked ~= "__tick" then
return picked
end
end
end



local function chooseDelivery(store, points)
local options = {}
if store.home then
for _, place in ipairs(saved.places) do
options[#options + 1] = { kind = "home", place = place,
label = place.label or "Home",
detail = place.x .. " " .. place.y .. " " .. place.z }
end
options[#options + 1] = { kind = "new",
label = #saved.places > 0 and "Somewhere else" or "My address",
detail = "GPS or coordinates" }
end
if store.pickup then
for _, point in ipairs(points or {}) do
options[#options + 1] = { kind = "pickup", point = point,
label = "Pickup: " .. point.name,
detail = point.x and (point.x .. " " .. point.y .. " "
.. point.z .. "  no fee") or "No delivery fee",
color = colors.purple }
end
end
local chosen = choose("Deliver to", store.home and (store.fee or 0) > 0
and ("Home delivery " .. money(store.fee)) or "Where should it go?",
options)
if not chosen then return nil end
if chosen.kind == "pickup" then
return { kind = "pickup", point_id = chosen.point.point_id },
chosen.label
end
local spot = chosen.place
if chosen.kind == "new" then
spot = findPlace()
if not spot then return nil end
spot = keepPlace(spot)
end
return { kind = "home", x = spot.x, y = spot.y, z = spot.z,
label = spot.label or "Home" }, (spot.label or "Home")
end


local function choosePayer(total)
local me = api.account() or {}
local options = { { id = "foxy", label = "Foxy",
detail = "Balance " .. money(me.balance or 0), color = SHOP,
ink = colors.black } }
options[2] = { id = "other", label = "Another bank",
detail = saved.bank_account_id and ("ID " .. saved.bank_account_id)
or "Account ID and its PIN" }
local chosen = choose("Pay with", money(total), options)
if not chosen then return nil end
if chosen.id == "foxy" then return { foxy = true } end
if total ~= math.floor(total) then
ui.message(target, "warning", "Whole amounts only",
"Another bank pays whole amounts. Use Foxy", 2)
return nil
end
local typed = ui.input(target, "Account ID", {
hint = "Sixteen digits, from your bank", mode = "integer",
maxLength = 16, minLength = 16, initial = saved.bank_account_id })
if not typed then return nil end
return { bank_account_id = typed }
end




local function review(store, items, delivery, label, subtotal)
local code
while running() do
local quote = ask("SHOP_QUOTE", { company_id = store.company_id,
items = items, delivery_kind = delivery.kind, code = code }, true)
if not quote then

local fee = delivery.kind == "home" and (store.fee or 0) or 0
quote = { subtotal = subtotal, discount = 0, fee = fee,
total = util.roundMoney(subtotal + fee), old = true }
end
if quote.code_error then
ui.message(target, "warning", "Code not taken", quote.code_error, 2)
code = nil
else
local width, height = target.getSize()
local background, foreground = paint(store.color)
ui.clear(target)
ui.header(target, "Checkout", ui.truncate(store.name .. ", to "
.. label, width - 3), util.formatClock())
local scene = ui.scene(target)
local rows = { { "Items", money(quote.subtotal) } }
if (quote.sale or 0) > 0 then
rows[#rows + 1] = { "Sale", "-" .. money(quote.sale) }
end
if quote.promo then
rows[#rows + 1] = { ui.truncate("Code " .. quote.promo, width - 12),
"-" .. money(quote.code_discount or 0) }
end
rows[#rows + 1] = { "Delivery", quote.fee_waived and "Free"
or (quote.fee > 0 and money(quote.fee) or "None") }
for index, row in ipairs(rows) do
ui.text(target, 2, 3 + index, row[1], ui.theme.muted)
ui.text(target, width - #row[2], 3 + index, row[2], ui.theme.ink)
end
local y = 4 + #rows
ui.text(target, 2, y + 1, "Total", ui.theme.ink)
local total = money(quote.total)
ui.text(target, width - #total, y + 1, total, ui.theme.ink)
ui.wrappedText(target, 2, y + 3, terms(store, true) .. ".",
width - 2, 3, ui.theme.muted)
if not quote.old then
scene:button("code", 2, height - 5, width - 2, 1,
ui.truncate(code and ("Code " .. code .. "  (change)")
or "Add a discount code", width - 4),
{ background = ui.theme.panel })
end
scene:button("pay", 2, height - 3, width - 2, 2, quote.total > 0
and ("Pay " .. money(quote.total)) or "Order, free",
{ background = background, foreground = foreground })
scene:button("back", 1, height, 8, 1, "< Back",
{ background = ui.theme.panel })
local action = scene:wait()
if action == "back" or action == "__terminate" then return nil end
if action == "pay" then return quote, code end
if action == "code" then
local typed = ui.input(target, "Discount code", {
hint = "Empty for none", mode = "text", maxLength = 12,
minLength = 0, initial = code })
if typed then
typed = string.upper(util.trim(typed))
code = typed ~= "" and typed or nil
end
end
end
end
return nil
end


local function checkout(store, points, basket, subtotal)
local delivery, label = chooseDelivery(store, points)
if not delivery then return nil end
local items = {}
for _, line in ipairs(basket) do
items[#items + 1] = { item_id = line.item_id,
quantity = line.quantity }
end
local quote, code = review(store, items, delivery, label, subtotal)
if not quote then return nil end
local total = quote.total


local payer = { foxy = true }
if total > 0 then
payer = choosePayer(total)
if not payer then return nil end
end
local pin = ui.pin(target, payer.foxy and "Foxy PIN"
or "Your bank's PIN", true)
if not pin then return nil end
ui.clear(target)
ui.center(target, 9, total > 0 and "Paying..." or "Ordering...", ui.theme.ink)
local placed, err = ask("SHOP_CHECKOUT", {
company_id = store.company_id, items = items,
delivery = delivery, bank_account_id = payer.bank_account_id,
pin = pin, code = code }, true)
if not placed then
ui.message(target, "error", "Not ordered", err, 2.4)
return nil
end
if payer.bank_account_id then
saved.bank_account_id = payer.bank_account_id
keep()
end
ui.message(target, "success", "Ordered", delivery.kind == "pickup"
and ("Your code is " .. tostring(placed.code))
or ((placed.total or 0) > 0 and (money(placed.total) .. " paid."
.. " Follow it in Delivery") or "Free. Follow it in Delivery"), 2)
if type(api.refresh) == "function" then api.refresh() end
return placed.order_id
end



local function basketScreen(store, points, basket)
while running() do
local width, height = target.getSize()
local background, foreground = paint(store.color)
local subtotal = 0
for _, line in ipairs(basket) do
subtotal = util.roundMoney(subtotal + line.price * line.quantity)
end
ui.clear(target)
ui.header(target, "Basket", ui.truncate(store.name, width - 3),
util.formatClock())
local scene = ui.scene(target)

for index, line in ipairs(basket) do
local y = 4 + index
if y > height - 6 then break end
ui.text(target, 2, y, ui.truncate(line.quantity .. " x "
.. line.name, width - 12), ui.theme.ink)
scene:button("less:" .. index, width - 8, y, 3, 1, "-",
{ background = ui.theme.panel })
scene:button("more:" .. index, width - 4, y, 3, 1, "+",
{ background = background, foreground = foreground })
end
if #basket == 0 then
ui.center(target, 8, "The basket is empty", ui.theme.muted)
end
ui.text(target, 2, height - 4, ui.truncate("Items "
.. money(subtotal) .. (store.home and (store.fee or 0) > 0
and ("  + " .. money(store.fee) .. " home") or ""),
width - 2), ui.theme.muted)
scene:button("checkout", 2, height - 3, width - 2, 2, "Checkout",
{ background = background, foreground = foreground,
disabled = #basket == 0 })
scene:button("back", 1, height, 8, 1, "< Back",
{ background = ui.theme.panel })
local action = scene:wait()
if action == "back" or action == "__terminate" then return nil end
local less = tonumber(action and action:match("^less:(%d+)$"))
local more = tonumber(action and action:match("^more:(%d+)$"))
if less and basket[less] then
basket[less].quantity = basket[less].quantity - 1
if basket[less].quantity <= 0 then table.remove(basket, less) end
elseif more and basket[more] then
basket[more].quantity = math.min(20, basket[more].quantity + 1)
elseif action == "checkout" and #basket > 0 then
local orderId = checkout(store, points, basket, subtotal)
if orderId then return orderId end
end
end
return nil
end

local function storePage(companyId)
local got = ask("SHOP_STORE", { company_id = companyId })
if not got then return nil end
local store, products, points = got.store, got.products or {},
got.points or {}
local basket, page = {}, 1
while running() do
local width, height = target.getSize()
local background, foreground = paint(store.color)
local per = math.max(1, math.floor((height - 8) / 3))
local pages = math.max(1, math.ceil(#products / per))
page = math.max(1, math.min(page, pages))
local count = 0
for _, line in ipairs(basket) do count = count + line.quantity end
ui.clear(target)
ui.header(target, ui.truncate(store.name, width - 9),
store.tagline ~= "" and store.tagline or "Online store",
util.formatClock())
ui.fill(target, 1, 4, width, 1, background)
local onOffer = offers(store)
if onOffer then
ui.text(target, 2, 4, ui.truncate(onOffer, width - 2), foreground,
background)
end
ui.text(target, 2, 5, ui.truncate(terms(store), width - 2),
ui.theme.muted)
local scene = ui.scene(target)
for slot = 1, per do
local index = (page - 1) * per + slot
local item = products[index]
if not item then break end
local inBasket = 0
for _, line in ipairs(basket) do
if line.item_id == item.item_id then inBasket = line.quantity end
end
local y = 3 + slot * 3
scene:button("add:" .. index, 2, y, width - 2, 2,
ui.truncate((inBasket > 0 and (inBasket .. " x ") or "")
.. item.name .. "  " .. money(item.price), width - 4)
.. "\n" .. ui.truncate(item.blurb or "Tap to add",
width - 4),
{ background = inBasket > 0 and background
or ui.theme.panel, foreground = inBasket > 0
and foreground or colors.white })
end
if pages > 1 then
scene:button("prev", 2, height - 2, 4, 1, "<",
{ background = ui.theme.panel, disabled = page <= 1 })
scene:button("next", width - 4, height - 2, 4, 1, ">",
{ background = ui.theme.panel, disabled = page >= pages })
end
scene:button("basket", 10, height, width - 10, 1,
"Basket " .. count, { background = background,
foreground = foreground, disabled = count == 0 })
scene:button("back", 1, height, 8, 1, "< Back",
{ background = ui.theme.panel })
local action = scene:wait()
if action == "back" or action == "__terminate" then
if count == 0 or ui.confirm(target, "Leave the store?",
"The basket is emptied.", "Leave", "Stay") then
return nil
end
elseif action == "prev" then
page = page - 1
elseif action == "next" then
page = page + 1
elseif action == "basket" and count > 0 then
local orderId = basketScreen(store, points, basket)
if orderId then return orderId end
else
local index = tonumber(action and action:match("^add:(%d+)$"))
local item = index and products[index]
if item then
local line
for _, existing in ipairs(basket) do
if existing.item_id == item.item_id then line = existing end
end
if line then
line.quantity = math.min(20, line.quantity + 1)
elseif #basket >= 10 then
ui.message(target, "info", "Basket is full",
"Ten different things at most", 1.4)
else
basket[#basket + 1] = { item_id = item.item_id,
name = item.name, price = item.price,
quantity = 1 }
end
end
end
end
return nil
end

local function storesPage(tabs)
local query = ""
while running() do
local listed = ask("SHOP_LIST", { query = query }, true)
local options = { { id = "__search", label = query == ""
and "Search stores" or ("Search: " .. query),
detail = query == "" and "By name or what they sell"
or "Tap to search again" } }
for _, store in ipairs(listed and listed.stores or {}) do
local background, foreground = paint(store.color)
options[#options + 1] = { id = store.company_id,
label = store.name, detail = offers(store)
or (store.tagline ~= "" and store.tagline)
or (store.products .. " products"),
color = background, ink = foreground }
end
tabs.empty = nil
local picked = choose("Shop", listed and (#options - 1
.. " stores open") or "Cannot reach the Bank", options, tabs)
if type(picked) ~= "table" then
if picked ~= "__tick" then return picked end
elseif picked.id == "__search" then
local typed = ui.input(target, "Search stores", {
hint = "Empty shows every store", maxLength = 16,
allowSpace = true, minLength = 0, initial = query })
if typed then query = typed end
else
local placed = storePage(picked.id)
if placed then
orderPage(placed)
return "tab:delivery"
end
end
end
end

local function placesPage(tabs)
while running() do
local options = {}
for index, place in ipairs(saved.places) do
options[#options + 1] = { id = index,
label = place.label or "Place",
detail = place.x .. " " .. place.y .. " " .. place.z }
end
if #saved.places < MAX_PLACES then
options[#options + 1] = { id = "__add", label = "Add a place",
detail = "Kept on this phone only", color = SHOP,
ink = colors.black }
end
tabs.empty = nil
local picked = choose("Places", #saved.places .. " of "
.. MAX_PLACES .. " kept", options, tabs)
if type(picked) ~= "table" then return picked end
if picked.id == "__add" then
local spot = findPlace()
if spot then
local name = ui.input(target, "Call it", {
hint = "Home, Farm, Shop", maxLength = 12,
allowSpace = true })
if name then
spot.label = name
table.insert(saved.places, spot)
keep()
end
end
elseif ui.confirm(target, "Forget " .. tostring(picked.label)
.. "?", "It is only on this phone, so it is gone for good.",
"Forget", "Keep") then
table.remove(saved.places, picked.id)
keep()
end
end
end





local tab = "stores"
local TABS = { { id = "stores", label = "Stores" },
{ id = "delivery", label = "Delivery" },
{ id = "places", label = "Places" } }
local tabs = {}
function tabs.draw(scene)
ui.tabBar(scene, target, TABS, tab, SHOP)
end


local wanted = type(api.action) == "function" and api.action()
if wanted == "delivery" or wanted == "stores" then tab = wanted end

while running() do
local switched
if tab == "delivery" then
switched = deliveryPage(tabs)
elseif tab == "places" then
switched = placesPage(tabs)
else
switched = storesPage(tabs)
end

local nextTab = type(switched) == "string"
and switched:match("^tab:(.+)$")
if not nextTab then return end
tab = nextTab
end
end
