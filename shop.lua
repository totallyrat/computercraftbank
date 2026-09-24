-- PUMPE APP: Shop
-- PUMPE APP ACTION: delivery | My deliveries | Where my orders are
-- PUMPE APP ACTION: stores | Browse stores | Order something home
--
-- Ordering from a store without walking to it. New in 10.2.
--
-- A store is a company that opened one from its Service Kiosk, in its own
-- colours. A basket goes to the buyer's door -- wherever they give the
-- coordinates of -- or to one of the store's pickup points, where the code
-- this app shows opens the locker.
--
-- Places are kept on this phone and nowhere else. Where somebody lives is
-- theirs to keep: the Bank sees an address once, on the order it belongs
-- to.
--
-- Paying is Foxy with the Foxy PIN, or any other bank by its Account ID and
-- that bank's own PIN. The Account ID is remembered for next time; the PIN
-- never is.
--
-- The Delivery page is live. It asks again every few seconds while it is
-- open, and every step the store takes arrives as a notification as well.

return function(api)
    local ui, util, target = api.ui, api.util, api.target
    local colors, money = api.colors, api.money

    local SHOP = colors.orange
    -- The store colours dark enough for white writing; the rest take black.
    local DARK = { red = true, green = true, blue = true, purple = true,
        brown = true, gray = true }
    local MAX_PLACES = 6
    local WORDS = {
        open = "On its way", done = "Delivered", collected = "Collected",
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

    -- A store's colour, and the colour that reads on it.
    local function paint(colorName)
        local background = colors[tostring(colorName or "")] or SHOP
        return background, DARK[colorName] and colors.white or colors.black
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

    -- One list screen for every choice: a store, a place, a way to pay.
    -- Each option is { label, detail, color, id }; paged to fit the phone.
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
            elseif action and action:match("^tab:") then
                return action
            else
                local index = tonumber(action and action:match("^pick:(%d+)$"))
                if index and options[index] then return options[index] end
            end
        end
        return nil
    end

    -- Places -----------------------------------------------------------------------

    local function coordinate(axis, initial)
        local typed = ui.input(target, axis .. " coordinate", {
            hint = "A whole number", mode = "integer", maxLength = 8,
            initial = initial and tostring(initial) or nil })
        return typed and tonumber(typed) and math.floor(tonumber(typed)) or nil
    end

    -- Coordinates from GPS, or typed. Nil when the buyer backed out.
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

    -- Delivery ---------------------------------------------------------------------

    local function sorted(orders)
        table.sort(orders, function(a, b)
            if (a.status == "open") ~= (b.status == "open") then
                return a.status == "open"
            end
            return tostring(a.order_id) > tostring(b.order_id)
        end)
        return orders
    end

    -- One order, live. The store moves it along and this page follows.
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
                -- The stage, big, in the store's colours.
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
                    ui.text(target, 14, row, ui.truncate(order.stocked
                        and "ready" or "not yet", width - 14),
                        order.stocked and ui.theme.success or ui.theme.muted)
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
                row = row + 2
                -- What happened, newest last, as much as fits.
                local history = order.history or {}
                local room = math.max(0, height - 2 - row)
                for index = math.max(1, #history - room + 1), #history do
                    local step = history[index]
                    ui.text(target, 2, row, ui.truncate(tostring(step.time)
                        .. "  " .. tostring(step.label), width - 2),
                        index == #history and ui.theme.ink or ui.theme.muted)
                    row = row + 1
                end
                if order.note and row <= height - 1 then
                    ui.text(target, 2, math.min(row, height - 1),
                        ui.truncate("Note: " .. order.note, width - 2),
                        ui.theme.accent)
                end
            end
            local scene = ui.scene(target)
            scene:button("back", 1, height, 8, 1, "< Back",
                { background = ui.theme.panel })
            local action = scene:wait({ tickRate = 4 })
            if action == "back" or action == "__terminate" then return end
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
                options[#options + 1] = { id = order.order_id,
                    label = tostring(order.company_name),
                    detail = (order.status == "open" and "" or "Done: ")
                        .. tostring(order.stage), color = background,
                    ink = foreground }
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

    -- Checkout ---------------------------------------------------------------------

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

    -- Foxy, or another bank by its Account ID.
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

    -- Returns the order id when an order was placed.
    local function checkout(store, points, basket, subtotal)
        local delivery, label = chooseDelivery(store, points)
        if not delivery then return nil end
        local fee = delivery.kind == "home" and (store.fee or 0) or 0
        local total = util.roundMoney(subtotal + fee)
        local payer = choosePayer(total)
        if not payer then return nil end
        if not ui.confirm(target, "Pay " .. money(total) .. "?",
            store.name .. ", to " .. label .. (fee > 0 and (". Includes "
                .. money(fee) .. " delivery") or "") .. ".", "Pay",
            "Not yet") then
            return nil
        end
        local pin = ui.pin(target, payer.foxy and "Foxy PIN"
            or "Your bank's PIN", true)
        if not pin then return nil end
        local items = {}
        for _, line in ipairs(basket) do
            items[#items + 1] = { item_id = line.item_id,
                quantity = line.quantity }
        end
        ui.clear(target)
        ui.center(target, 9, "Paying...", ui.theme.ink)
        local placed, err = ask("SHOP_CHECKOUT", {
            company_id = store.company_id, items = items,
            delivery = delivery, bank_account_id = payer.bank_account_id,
            pin = pin }, true)
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
            or (money(placed.total) .. " paid. Follow it in Delivery"), 2)
        if type(api.refresh) == "function" then api.refresh() end
        return placed.order_id
    end

    -- A store --------------------------------------------------------------------------

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
            -- One row a line, so all ten a basket can hold fit a pocket.
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
                    label = store.name, detail = store.tagline ~= ""
                        and store.tagline or (store.products .. " products"),
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

    -- The tab bar ------------------------------------------------------------------

    local tab = "stores"
    local tabs = {}
    function tabs.draw(scene)
        local width, height = target.getSize()
        local side = math.floor((width - 10) / 2)
        for _, spec in ipairs({
            { "stores", "Stores", 1, side },
            { "delivery", "Delivery", 1 + side, width - 2 * side },
            { "places", "Places", 1 + width - side, side },
        }) do
            scene:button("tab:" .. spec[1], spec[3], height, spec[4], 1,
                spec[2], { background = tab == spec[1] and SHOP
                    or ui.theme.panel, foreground = tab == spec[1]
                    and colors.black or colors.white })
        end
    end

    -- Opened from search by name: straight to what was asked for.
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
