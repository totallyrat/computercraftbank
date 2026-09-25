-- PUMPE APP: Company
-- PUMPE APP ACTION: companies | My companies | Start and run your companies
-- PUMPE APP ACTION: delivery | Delivery Mode | What is out for delivery
--
-- Running a company from your pocket, new in 11.1.
--
-- Everything a Service Kiosk does to manage a company is here: starting
-- one, its products, its online store, and what its pickup points sell on
-- the spot. What stays on the kiosk is what belongs to that machine --
-- linking it, taking cash out of it, Dev Mode.
--
-- And Delivery Mode: a Delivery Terminal cut down to the road. It lists
-- what is out for delivery, with the courier's code for a parcel going to
-- a pickup point, or where a home delivery is going and how far it is.
--
-- Only the owner sees a company here. The Bank checks, on every request,
-- that the person asking owns the company named.

return function(api)
    local ui, util, target, colors = api.ui, api.util, api.target, api.colors
    local money = api.money

    local ACCENT = colors.cyan
    local TABS = { { id = "companies", label = "Companies" },
        { id = "delivery", label = "Delivery" } }
    local COMPANY_TABS = { { id = "products", label = "Products" },
        { id = "store", label = "Store" }, { id = "points", label = "Points" } }
    local STORE_COLORS = { "orange", "red", "lime", "green", "cyan",
        "lightBlue", "blue", "purple", "magenta", "pink", "yellow", "brown",
        "gray" }

    local function running() return api.running() end
    local function ask(action, payload)
        return api.request(action, payload or {}, true)
    end
    local function failed(title, err)
        ui.message(target, "error", title, err or "The Bank is not answering",
            1.8)
    end

    -- One paged list of buttons, for every choice made in this app. Returns
    -- the chosen item, or nil for back.
    local function choose(title, subtitle, items, labelOf)
        local page = 1
        while running() do
            local width, height = target.getSize()
            local per = math.max(1, math.floor((height - 6) / 2))
            local pages = math.max(1, math.ceil(#items / per))
            page = math.max(1, math.min(page, pages))
            ui.clear(target)
            ui.header(target, ui.truncate(title, width - 9),
                ui.truncate(subtitle or "", width - 3), util.formatClock())
            local scene = ui.scene(target)
            for slot = 1, per do
                local index = (page - 1) * per + slot
                if not items[index] then break end
                scene:button("pick:" .. index, 2, 2 + slot * 2, width - 2, 1,
                    ui.truncate(labelOf(items[index]), width - 4),
                    { background = ui.theme.panel })
            end
            if pages > 1 then
                scene:button("prev", width - 8, height, 3, 1, "^",
                    { background = ui.theme.panel, disabled = page <= 1 })
                scene:button("next", width - 4, height, 3, 1, "v",
                    { background = ui.theme.panel, disabled = page >= pages })
            end
            scene:button("back", 1, height, 8, 1, "< Back",
                { background = ui.theme.panel })
            local action = scene:wait()
            if action == "back" or action == "__terminate" then return nil end
            if action == "prev" then
                page = page - 1
            elseif action == "next" then
                page = page + 1
            else
                local index = tonumber(action and action:match("^pick:(%d+)$"))
                if index and items[index] then return items[index] end
            end
        end
    end

    local function option(label, id) return { label = label, id = id } end
    -- A number to start a text box with: 12, not 12.0.
    local function plain(value)
        value = tonumber(value) or 0
        if value == math.floor(value) then return string.format("%d", value) end
        return tostring(value)
    end
    local function labelOf(item) return item.label end

    -- Products ---------------------------------------------------------------------

    local function addProduct(company)
        local name = ui.input(target, "New product", { hint = "Its name",
            mode = "text", maxLength = 20, allowSpace = true, minLength = 1 })
        if not name then return end
        local price = ui.input(target, "Price", { hint = name,
            mode = "number", maxLength = 9 })
        if not price then return end
        local kind = choose("What kind?", name, {
            option("One-time purchase", "one_time"),
            option("Subscription, daily", "subscription") }, labelOf)
        if not kind then return end
        local added, err = ask("COMPANY_PRODUCT_ADD", {
            company_id = company.company_id, name = name,
            price = tonumber(price), kind = kind.id })
        if not added then return failed("Not added", err) end
        ui.message(target, "success", "Added", name .. "  "
            .. money(added.item.price), 1.2)
    end

    local function editProduct(company, item)
        local change = function(fields)
            fields.company_id, fields.item_id = company.company_id, item.item_id
            local done, err = ask("COMPANY_PRODUCT_SET", fields)
            if not done then failed("Not changed", err) return false end
            return true
        end
        local choices = { option("Rename", "name"),
            option("Change the price", "price"),
            option(item.favorite and "Unfavourite" or "Favourite on the till",
                "favorite") }
        if item.kind ~= "subscription" then
            choices[#choices + 1] = option(item.online and "Take it offline"
                or "Sell it in the Shop app", "online")
            choices[#choices + 1] = option("Shop app line", "blurb")
        end
        choices[#choices + 1] = option("Delete", "delete")
        local chosen = choose(item.name, money(item.price)
            .. (item.kind == "subscription" and " a day" or ""), choices,
            labelOf)
        if not chosen then return end
        if chosen.id == "name" then
            local name = ui.input(target, "Rename", { mode = "text",
                initial = item.name, maxLength = 20, allowSpace = true,
                minLength = 1 })
            if name then change({ name = name }) end
        elseif chosen.id == "price" then
            local price = ui.input(target, "New price", { mode = "number",
                initial = plain(item.price), maxLength = 9 })
            if price then change({ price = tonumber(price) }) end
        elseif chosen.id == "favorite" then
            change({ favorite = not item.favorite })
        elseif chosen.id == "online" then
            change({ online = not item.online })
        elseif chosen.id == "blurb" then
            local blurb = ui.input(target, "Shop app line", {
                hint = "One line under its name", mode = "text",
                initial = item.blurb, maxLength = 40, allowSpace = true,
                minLength = 0 })
            if blurb then change({ blurb = blurb }) end
        elseif chosen.id == "delete" and ui.confirm(target, "Delete it?",
            item.name .. " goes from every till and the Shop app.", "Delete",
            "Keep") then
            local gone, err = ask("COMPANY_PRODUCT_REMOVE", {
                company_id = company.company_id, item_id = item.item_id })
            if not gone then failed("Not deleted", err) end
        end
    end

    local function productsPage(company)
        local page = 1
        while running() do
            local state, err = ask("COMPANY_STATE",
                { company_id = company.company_id })
            if not state then failed("Cannot open it", err) return "home" end
            local products = state.products or {}
            local width, height = target.getSize()
            local per = math.max(1, math.floor((height - 8) / 3))
            local pages = math.max(1, math.ceil(#products / per))
            page = math.max(1, math.min(page, pages))
            ui.clear(target)
            ui.header(target, ui.truncate(company.name, width - 9),
                #products .. " products", util.formatClock())
            local scene = ui.scene(target)
            for slot = 1, per do
                local index = (page - 1) * per + slot
                local item = products[index]
                if not item then break end
                local where = item.kind == "subscription" and "Daily, at kiosks"
                    or item.online and "Kiosks and Shop app" or "Kiosks only"
                scene:button("item:" .. index, 2, 2 + slot * 3, width - 2, 2,
                    ui.truncate((item.favorite and "* " or "") .. item.name
                        .. "  " .. money(item.price), width - 4) .. "\n"
                        .. ui.truncate(where, width - 4),
                    { background = item.online and ACCENT or ui.theme.panel,
                      foreground = item.online and colors.black or colors.white })
            end
            if #products == 0 then
                ui.wrappedText(target, 2, 5, "No products yet. Add what you"
                    .. " sell: it shows on every till of this company, and"
                    .. " can go in the Shop app.", width - 2, 5,
                    ui.theme.muted)
            end
            scene:button("add", 2, height - 3, pages > 1 and width - 12
                or width - 2, 1, "+ Add a product",
                { background = ui.theme.accentDark })
            if pages > 1 then
                scene:button("prev", width - 9, height - 3, 4, 1, "<",
                    { background = ui.theme.panel, disabled = page <= 1 })
                scene:button("next", width - 4, height - 3, 4, 1, ">",
                    { background = ui.theme.panel, disabled = page >= pages })
            end
            ui.tabBar(scene, target, COMPANY_TABS, "products", ACCENT)
            local action = scene:wait()
            if action == "home" or action == "__terminate" then return "home" end
            if action and action:match("^tab:") then return action end
            if action == "add" then
                addProduct(company)
            elseif action == "prev" then
                page = page - 1
            elseif action == "next" then
                page = page + 1
            else
                local index = tonumber(action and action:match("^item:(%d+)$"))
                if index and products[index] then
                    editProduct(company, products[index])
                end
            end
        end
        return "home"
    end

    -- The online store -------------------------------------------------------------

    local function storePage(company)
        while running() do
            local state, err = ask("COMPANY_STATE",
                { company_id = company.company_id })
            if not state then failed("Cannot open it", err) return "home" end
            local settings = state.settings
            local width, height = target.getSize()
            ui.clear(target)
            ui.header(target, "Online store", ui.truncate((settings.open
                and "Open" or "Closed") .. ((state.held or 0) > 0
                    and ("  " .. money(state.held) .. " held") or ""),
                width - 3), util.formatClock())
            local scene = ui.scene(target)
            local entries = {
                { "open", settings.open and "Close the store" or "Open the store",
                  settings.open and ui.theme.danger or ui.theme.success },
                { "color", "Colour: " .. settings.color,
                  colors[settings.color] or ACCENT },
                { "tagline", settings.tagline ~= "" and settings.tagline
                    or "Add a tagline", ui.theme.panel },
                { "delivery", settings.home and "Home delivery: on"
                    or "Home delivery: off", ui.theme.panel },
                { "fee", "Delivery fee " .. money(settings.fee or 0),
                  ui.theme.panel },
                { "pickup", settings.pickup and "Pickup points: on"
                    or "Pickup points: off", ui.theme.panel },
                { "cancel", settings.cancel and "Cancelling: on"
                    or "Cancelling: off", ui.theme.panel },
                { "returns", "Returns: " .. tostring(settings.return_days or 5)
                    .. " days", ui.theme.panel },
            }
            local gap = height >= 20 and 2 or 1
            for index, entry in ipairs(entries) do
                local y = 2 + index * gap
                if y <= height - 2 then
                    scene:button(entry[1], 2, y, width - 2, 1,
                        ui.truncate(entry[2], width - 4), {
                            background = entry[3],
                            foreground = (entry[1] == "open"
                                and settings.open == false or entry[1] == "color")
                                and colors.black or colors.white })
                end
            end
            ui.tabBar(scene, target, COMPANY_TABS, "store", ACCENT)
            local action = scene:wait()
            if action == "home" or action == "__terminate" then return "home" end
            if action and action:match("^tab:") then return action end
            local change
            if action == "open" then
                change = { open = not settings.open }
            elseif action == "color" then
                local following = 1
                for index, name in ipairs(STORE_COLORS) do
                    if name == settings.color then
                        following = index % #STORE_COLORS + 1
                    end
                end
                change = { color = STORE_COLORS[following] }
            elseif action == "tagline" then
                local typed = ui.input(target, "Tagline", {
                    hint = "One line under the name", mode = "text",
                    initial = settings.tagline, maxLength = 40,
                    allowSpace = true, minLength = 0 })
                if typed then change = { tagline = typed } end
            elseif action == "delivery" then
                change = { home = not settings.home }
            elseif action == "fee" then
                local typed = ui.input(target, "Delivery fee", {
                    hint = "Added to every home delivery", mode = "number",
                    maxLength = 4, initial = plain(settings.fee) })
                if typed then change = { fee = tonumber(typed) or 0 } end
            elseif action == "pickup" then
                change = { pickup = not settings.pickup }
            elseif action == "cancel" then
                if settings.cancel or ui.confirm(target, "Let buyers cancel?",
                    "For " .. tostring(state.store.confirm_hours or 2)
                        .. " in-game hours after ordering. The money waits"
                        .. " until then.", "Turn on", "Back") then
                    change = { cancel = not settings.cancel }
                end
            elseif action == "returns" then
                local typed = ui.input(target, "Return window", {
                    hint = "Days after arriving. 5 at least", mode = "integer",
                    maxLength = 2,
                    initial = plain(settings.return_days or 5) })
                if typed then change = { return_days = tonumber(typed) or 0 } end
            end
            if change then
                change.company_id = company.company_id
                local saved, saveError = ask("COMPANY_SHOP_SETUP", change)
                if not saved then failed("Not changed", saveError) end
            end
        end
        return "home"
    end

    -- Pickup points, and selling at them ------------------------------------------------

    local function addOffer(company, point, offer)
        local state = ask("COMPANY_STATE", { company_id = company.company_id })
        local name, price = offer and offer.name, offer and offer.price
        if not offer then
            local choices = {}
            for _, item in ipairs(state and state.products or {}) do
                if item.kind ~= "subscription" then
                    choices[#choices + 1] = { label = item.name .. "  "
                        .. money(item.price), item = item }
                end
            end
            choices[#choices + 1] = option("Something else", "other")
            local chosen = choose("Sell what?", point.name, choices, labelOf)
            if not chosen then return end
            if chosen.item then
                name, price = chosen.item.name, chosen.item.price
            else
                name = ui.input(target, "Its name", { mode = "text",
                    maxLength = 20, allowSpace = true, minLength = 2 })
                if not name then return end
            end
        end
        local item = ui.input(target, "Game item", {
            hint = "Like oak_log", mode = "email", maxLength = 48,
            minLength = 2, initial = offer and offer.item })
        if not item then return end
        local count = ui.input(target, "How many a sale", { hint = name,
            mode = "integer", maxLength = 3,
            initial = plain(offer and offer.count or 1) })
        if not count then return end
        local cost = ui.input(target, "Price here", {
            hint = "Often more than delivered", mode = "number", maxLength = 9,
            initial = price and plain(price) or nil })
        if not cost then return end
        local saved, err = ask("STORE_OFFER_SET", {
            company_id = company.company_id, point_id = point.point_id,
            offer_id = offer and offer.offer_id, name = name, item = item,
            count = tonumber(count), price = tonumber(cost) })
        if not saved then return failed("Not saved", err) end
        ui.message(target, "success", "On sale", saved.offer.count .. " "
            .. saved.offer.name .. " for " .. money(saved.offer.price), 1.4)
    end

    local function pointScreen(company, pointId)
        while running() do
            local listed, err = ask("STORE_POINTS",
                { company_id = company.company_id })
            local point
            for _, entry in ipairs(listed and listed.points or {}) do
                if entry.point_id == pointId then point = entry end
            end
            if not point then return failed("Cannot open it", err) end
            local width, height = target.getSize()
            local offers = point.offers or {}
            ui.clear(target)
            ui.header(target, ui.truncate(point.name, width - 9),
                point.open and "Store open" or "Store closed",
                util.formatClock())
            local scene = ui.scene(target)
            scene:button("open", 2, 4, width - 2, 1, point.open
                and "Close the store here" or "Open the store here",
                { background = point.open and ui.theme.danger
                    or ui.theme.success,
                  foreground = point.open and colors.white or colors.black })
            local per = math.max(1, height - 10)
            for index = 1, math.min(per, #offers) do
                local offer = offers[index]
                scene:button("offer:" .. index, 2, 5 + index, width - 2, 1,
                    ui.truncate(offer.count .. " " .. offer.name .. "  "
                        .. money(offer.price), width - 4),
                    { background = ui.theme.panel })
            end
            if #offers == 0 then
                ui.wrappedText(target, 2, 6, "Nothing on sale. Add things"
                    .. " people can buy here and take away at once, from"
                    .. " what is in the lockers.", width - 2, 4,
                    ui.theme.muted)
            end
            scene:button("add", 2, height - 2, width - 2, 1,
                "+ Sell something here", { background = ui.theme.accentDark,
                    disabled = #offers >= (listed.max_offers or 12) })
            scene:button("back", 1, height, 8, 1, "< Back",
                { background = ui.theme.panel })
            local action = scene:wait()
            if action == "back" or action == "__terminate" then return end
            if action == "open" then
                local done, openError = ask("STORE_OPEN", {
                    company_id = company.company_id, point_id = pointId,
                    open = not point.open })
                if not done then failed("Not changed", openError) end
            elseif action == "add" then
                addOffer(company, point)
            else
                local index = tonumber(action and action:match("^offer:(%d+)$"))
                local offer = index and offers[index]
                if offer then
                    local chosen = choose(offer.name, offer.count .. " for "
                        .. money(offer.price), { option("Change it", "edit"),
                        option("Stop selling it", "remove") }, labelOf)
                    if chosen and chosen.id == "edit" then
                        addOffer(company, point, offer)
                    elseif chosen and chosen.id == "remove" then
                        local gone, goneError = ask("STORE_OFFER_REMOVE", {
                            company_id = company.company_id,
                            point_id = pointId, offer_id = offer.offer_id })
                        if not gone then failed("Not removed", goneError) end
                    end
                end
            end
        end
    end

    local function pointsPage(company)
        while running() do
            local listed, err = ask("STORE_POINTS",
                { company_id = company.company_id })
            if not listed then failed("Cannot open it", err) return "home" end
            local points = listed.points or {}
            local width, height = target.getSize()
            local per = math.max(1, math.floor((height - 6) / 3))
            ui.clear(target)
            ui.header(target, "Pickup points", #points .. " of them",
                util.formatClock())
            local scene = ui.scene(target)
            for slot = 1, math.min(per, #points) do
                local point = points[slot]
                scene:button("point:" .. slot, 2, 2 + slot * 3, width - 2, 2,
                    ui.truncate(point.name, width - 4) .. "\n"
                        .. ui.truncate(point.open and ("Selling "
                            .. #point.offers .. " things") or "Parcels only",
                            width - 4),
                    { background = point.open and ACCENT or ui.theme.panel,
                      foreground = point.open and colors.black or colors.white })
            end
            if #points == 0 then
                ui.wrappedText(target, 2, 5, "No pickup points yet. Make one"
                    .. " on a Delivery Terminal of this company: PICKUP, on"
                    .. " its board.", width - 2, 5, ui.theme.muted)
            end
            ui.tabBar(scene, target, COMPANY_TABS, "points", ACCENT)
            local action = scene:wait()
            if action == "home" or action == "__terminate" then return "home" end
            if action and action:match("^tab:") then return action end
            local slot = tonumber(action and action:match("^point:(%d+)$"))
            if slot and points[slot] then
                pointScreen(company, points[slot].point_id)
            end
        end
        return "home"
    end

    local function companyScreen(company)
        local tab = "products"
        while running() do
            local switched
            if tab == "store" then
                switched = storePage(company)
            elseif tab == "points" then
                switched = pointsPage(company)
            else
                switched = productsPage(company)
            end
            local nextTab = type(switched) == "string"
                and switched:match("^tab:(.+)$")
            if not nextTab then return end
            tab = nextTab
        end
    end

    -- Your companies ---------------------------------------------------------------

    local function startCompany()
        local name = ui.input(target, "Company name", {
            hint = "2-28 characters", mode = "text", maxLength = 28,
            allowSpace = true, minLength = 2 })
        if not name then return nil end
        local made, err = ask("COMPANY_CREATE", { company_name = name })
        if not made then return failed("Not started", err) end
        ui.message(target, "success", "Company started", made.company.name,
            1.4)
        return made.company
    end

    local function companiesPage()
        local page = 1
        while running() do
            local listed, err = ask("COMPANY_LIST")
            local companies = listed and listed.companies or {}
            local width, height = target.getSize()
            local per = math.max(1, math.floor((height - 8) / 3))
            local pages = math.max(1, math.ceil(#companies / per))
            page = math.max(1, math.min(page, pages))
            ui.clear(target)
            ui.header(target, "Companies", listed and (#companies .. " yours")
                or "Offline", util.formatClock())
            local scene = ui.scene(target)
            for slot = 1, per do
                local index = (page - 1) * per + slot
                local company = companies[index]
                if not company then break end
                scene:button("company:" .. index, 2, 2 + slot * 3, width - 2,
                    2, ui.truncate(company.name, width - 4) .. "\n"
                        .. ui.truncate(company.products .. " products  "
                            .. (company.open and "Store open" or "Store closed"),
                            width - 4),
                    { background = ui.theme.panel })
            end
            if #companies == 0 then
                ui.wrappedText(target, 2, 5, listed and ("Start a company to"
                    .. " sell at Service Kiosks, in the Shop app and at"
                    .. " pickup points.") or tostring(err or
                        "Cannot reach the Bank."), width - 2, 5, ui.theme.muted)
            end
            scene:button("start", 2, height - 3, pages > 1 and width - 12
                or width - 2, 1, "+ Start a company",
                { background = ui.theme.accentDark })
            if pages > 1 then
                scene:button("prev", width - 9, height - 3, 4, 1, "<",
                    { background = ui.theme.panel, disabled = page <= 1 })
                scene:button("next", width - 4, height - 3, 4, 1, ">",
                    { background = ui.theme.panel, disabled = page >= pages })
            end
            ui.tabBar(scene, target, TABS, "companies", ACCENT)
            local action = scene:wait()
            if action == "home" or action == "__terminate" then return "home" end
            if action and action:match("^tab:") then return action end
            if action == "start" then
                local made = startCompany()
                if made then companyScreen(made) end
            elseif action == "prev" then
                page = page - 1
            elseif action == "next" then
                page = page + 1
            else
                local index = tonumber(action
                    and action:match("^company:(%d+)$"))
                if index and companies[index] then
                    companyScreen(companies[index])
                end
            end
        end
        return "home"
    end

    -- Delivery Mode --------------------------------------------------------------------

    -- Which way, roughly: north is -z in Minecraft, east is +x.
    local function heading(dx, dz)
        local ns = dz < -math.abs(dx) / 2 and "N"
            or dz > math.abs(dx) / 2 and "S" or ""
        local ew = dx > math.abs(dz) / 2 and "E"
            or dx < -math.abs(dz) / 2 and "W" or ""
        return ns .. ew
    end

    local function howFar(delivery)
        local here = api.position and api.position()
        if not here or not delivery.x or not delivery.z then return nil end
        local dx, dz = delivery.x - here.x, delivery.z - here.z
        local distance = math.floor(math.sqrt(dx * dx + dz * dz) + 0.5)
        if distance <= 3 then return "You are here" end
        return distance .. " blocks " .. heading(dx, dz)
    end

    local function where(delivery)
        return tostring(delivery.x) .. " " .. tostring(delivery.y) .. " "
            .. tostring(delivery.z)
    end

    local function onTheRoad()
        local listed = ask("COMPANY_LIST")
        if not listed then return nil end
        local orders = {}
        for _, company in ipairs(listed.companies or {}) do
            local out = ask("DELIVERY_OUT", { company_id = company.company_id })
            for _, order in ipairs(out and out.orders or {}) do
                orders[#orders + 1] = order
            end
        end
        table.sort(orders, function(a, b) return a.order_id < b.order_id end)
        return orders, #(listed.companies or {})
    end

    local function deliveryScreen(order)
        local delivery = order.delivery or {}
        local pickup = delivery.kind == "pickup"
        while running() do
            local width, height = target.getSize()
            ui.clear(target)
            ui.header(target, order.order_id, ui.truncate(tostring(
                order.company_name), width - 3), util.formatClock())
            ui.text(target, 2, 4, ui.truncate("For " .. tostring(
                order.buyer_name), width - 2), ui.theme.ink)
            local row = 5
            for _, line in ipairs(order.lines or {}) do
                if row > 7 then break end
                ui.text(target, 2, row, ui.truncate(line.quantity .. " x "
                    .. line.name, width - 2), ui.theme.muted)
                row = row + 1
            end
            ui.card(target, 2, 9, width - 2, 5, pickup and colors.purple
                or ACCENT)
            if pickup then
                ui.text(target, 4, 9, "DELIVERY CODE", ui.theme.muted,
                    ui.theme.panel)
                ui.text(target, 4, 10, tostring(order.delivery_code or "?")
                    :gsub("^(%d%d%d)", "%1 "), ui.theme.ink, ui.theme.panel)
                ui.text(target, 4, 11, ui.truncate("At " .. tostring(
                    delivery.point_name), width - 6), ui.theme.muted,
                    ui.theme.panel)
            else
                ui.text(target, 4, 9, ui.truncate(string.upper(tostring(
                    delivery.label or "Home")), width - 6), ui.theme.muted,
                    ui.theme.panel)
                ui.text(target, 4, 10, ui.truncate(where(delivery), width - 6),
                    ui.theme.ink, ui.theme.panel)
            end
            ui.text(target, 4, 12, ui.truncate(howFar(delivery)
                or "No GPS here", width - 6), ui.theme.muted, ui.theme.panel)
            local scene = ui.scene(target)
            if pickup then
                ui.wrappedText(target, 2, 15, "Type the code at the pickup"
                    .. " point and put the parcel in its chest.", width - 2,
                    2, ui.theme.muted)
            else
                scene:button("done", 2, height - 3, width - 2, 2, "Delivered",
                    { background = ui.theme.success, foreground = colors.black })
            end
            scene:button("back", 1, height, 8, 1, "< Back",
                { background = ui.theme.panel })
            local action = scene:wait({ tickRate = 2 })
            if action == "back" or action == "__terminate" then return end
            if action == "done" and ui.confirm(target, "Delivered?",
                tostring(order.buyer_name) .. " is told it has arrived.",
                "Done", "Not yet") then
                local note = ui.input(target, "A note for them?", {
                    hint = "Optional. Left by the door", mode = "text",
                    maxLength = 40, allowSpace = true, minLength = 0 })
                local finished, err = ask("DELIVERY_DONE", {
                    company_id = order.company_id, order_id = order.order_id,
                    note = note })
                if finished then
                    ui.message(target, "success", "Delivered",
                        tostring(order.buyer_name) .. " has been told", 1.4)
                    return
                end
                failed("Not marked", err)
            end
        end
    end

    local function deliveryPage()
        local page = 1
        while running() do
            local orders, owned = onTheRoad()
            local width, height = target.getSize()
            local per = math.max(1, math.floor((height - 6) / 3))
            local list = orders or {}
            local pages = math.max(1, math.ceil(#list / per))
            page = math.max(1, math.min(page, pages))
            ui.clear(target)
            ui.header(target, "Delivery Mode", orders and (#list
                .. " out for delivery") or "Offline", util.formatClock())
            local scene = ui.scene(target)
            for slot = 1, per do
                local index = (page - 1) * per + slot
                local order = list[index]
                if not order then break end
                local delivery = order.delivery or {}
                local pickup = delivery.kind == "pickup"
                scene:button("order:" .. index, 2, 2 + slot * 3, width - 2, 2,
                    ui.truncate(tostring(order.buyer_name) .. "  "
                        .. order.order_id, width - 4) .. "\n"
                        .. ui.truncate(pickup and ("Code "
                            .. tostring(order.delivery_code) .. "  "
                            .. tostring(delivery.point_name))
                            or ("To " .. where(delivery)), width - 4),
                    { background = pickup and colors.purple or ACCENT,
                      foreground = pickup and colors.white or colors.black })
            end
            if #list == 0 then
                ui.wrappedText(target, 2, 5, not orders
                    and "Cannot reach the Bank. Trying again."
                    or owned == 0 and "Start a company first, on the"
                        .. " Companies tab."
                    or "Nothing out for delivery. Orders show here when a"
                        .. " Delivery Terminal moves them to Out for delivery.",
                    width - 2, 5, ui.theme.muted)
            end
            if pages > 1 then
                scene:button("prev", 2, height - 2, 4, 1, "<",
                    { background = ui.theme.panel, disabled = page <= 1 })
                scene:button("next", width - 4, height - 2, 4, 1, ">",
                    { background = ui.theme.panel, disabled = page >= pages })
            end
            ui.tabBar(scene, target, TABS, "delivery", ACCENT)
            local action = scene:wait({ tickRate = 5 })
            if action == "home" or action == "__terminate" then return "home" end
            if action and action:match("^tab:") then return action end
            if action == "prev" then
                page = page - 1
            elseif action == "next" then
                page = page + 1
            else
                local index = tonumber(action and action:match("^order:(%d+)$"))
                if index and list[index] then deliveryScreen(list[index]) end
            end
        end
        return "home"
    end

    -- Starting -----------------------------------------------------------------------

    local tab = type(api.action) == "function" and api.action() == "delivery"
        and "delivery" or "companies"
    while running() do
        local switched
        if tab == "delivery" then
            switched = deliveryPage()
        else
            switched = companiesPage()
        end
        local nextTab = type(switched) == "string"
            and switched:match("^tab:(.+)$")
        if not nextTab then return end
        tab = nextTab
    end
end
