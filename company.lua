-- PUMPE APP: Company
-- PUMPE APP ACTION: companies | My companies | Start and run your companies
-- PUMPE APP ACTION: delivery | Delivery Mode | What is out for delivery
-- PUMPE APP ACTION: sell | Point of Sale | Sell at your till
-- PUMPE APP ACTION: till | Till mode | The till, full screen, never locks
--
-- Running a company from your pocket, new in 11.1.
--
-- Everything to manage a company is here: starting one, its products, its
-- online store, and what its pickup points sell on the spot. FoxyOS 13
-- moved the Service Kiosk in too, as the Sell tab: the till.
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
    -- FoxyOS 14: Till mode has a tab of its own, so it is the first thing
    -- you see rather than something to find.
    local TABS = { { id = "companies", label = "Companies" },
        { id = "till", label = "Till mode", short = "Till" },
        { id = "delivery", label = "Delivery" } }
    -- 12.0 Final: three, all on the bar. Pickup points are part of the
    -- store, so they open from the Store tab.
    -- FoxyOS 13: Sell is the Service Kiosk, moved in, and comes first.
    local COMPANY_TABS = { { id = "sell", label = "Sell" },
        { id = "products", label = "Products", short = "Items" },
        { id = "store", label = "Store" },
        { id = "discounts", label = "Discounts", short = "Deals", hint = "Sales and codes" } }
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
                local where = item.kind == "subscription" and "Daily, at the till"
                    or item.online and "Till and Shop app" or "At the till"
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

    -- 12.0 Final: under the Store tab, beside the switch that lets buyers
    -- choose them at checkout -- everything about pickup in one place.
    local function pointsPage(company)
        while running() do
            local state, err = ask("COMPANY_STATE",
                { company_id = company.company_id })
            local listed, listError = ask("STORE_POINTS",
                { company_id = company.company_id })
            if not state or not listed then
                failed("Cannot open it", err or listError)
                return
            end
            local settings = state.settings
            local points = listed.points or {}
            local width, height = target.getSize()
            local per = math.max(1, math.floor((height - 6) / 3))
            ui.clear(target)
            ui.header(target, "Pickup points", #points .. " of them",
                util.formatClock())
            local scene = ui.scene(target)
            scene:button("pickup", 2, 4, width - 2, 1, settings.pickup
                and "Buyers pick up: on" or "Buyers pick up: off",
                { background = settings.pickup and ACCENT or ui.theme.panel,
                  foreground = settings.pickup and colors.black or colors.white })
            for slot = 1, math.min(per, #points) do
                local point = points[slot]
                scene:button("point:" .. slot, 2, 3 + slot * 3, width - 2, 2,
                    ui.truncate(point.name, width - 4) .. "\n"
                        .. ui.truncate(point.open and ("Selling "
                            .. #point.offers .. " things") or "Parcels only",
                            width - 4),
                    { background = point.open and ACCENT or ui.theme.panel,
                      foreground = point.open and colors.black or colors.white })
            end
            if #points == 0 then
                ui.wrappedText(target, 2, 6, "No pickup points yet. Make one"
                    .. " on a Delivery Terminal of this company: SETUP, on"
                    .. " its board.", width - 2, 5, ui.theme.muted)
            end
            scene:button("back", 1, height, 9, 1, "< Store",
                { background = ui.theme.panel })
            local action = scene:wait()
            if action == "back" or action == "__terminate" then return end
            if action == "pickup" then
                local saved, saveError = ask("COMPANY_SHOP_SETUP", {
                    company_id = company.company_id, pickup = not settings.pickup })
                if not saved then failed("Not changed", saveError) end
            end
            local slot = tonumber(action and action:match("^point:(%d+)$"))
            if slot and points[slot] then
                pointScreen(company, points[slot].point_id)
            end
        end
    end

    -- The online store -------------------------------------------------------------

    -- Shop Websites, FoxyOS 15 -----------------------------------------------------------
    -- The store's address on the web: name.shop. Anybody types it into the
    -- Internet app and the store opens as itself. It replaced Shop Apps,
    -- which cost every Pocket that installed one about 27 KB.
    local function squash(name)
        return (string.lower(tostring(name or "")):gsub("[^%w%-]", "")):sub(1, 20)
    end

    local function shopSitePage(company, state)
        local site = state.shop_site
        while running() do
            local width, height = target.getSize()
            ui.clear(target)
            ui.header(target, "Shop Website", site and "On the web"
                or "Your store on the web", util.formatClock())
            local scene = ui.scene(target)
            ui.card(target, 2, 5, width - 2, 5, colors.lime)
            if site then
                ui.text(target, 4, 5, "YOUR ADDRESS", ui.theme.muted, ui.theme.panel)
                ui.text(target, 4, 6, ui.truncate(site.domain, width - 6), ui.theme.ink,
                    ui.theme.panel)
                ui.wrappedText(target, 4, 8, "Type it into Internet.", width - 6, 2,
                    ui.theme.muted, ui.theme.panel)
                scene:button("visit", 2, 11, width - 2, 2, "Open it",
                    { background = colors.lime, foreground = colors.black })
                scene:button("rename", 2, 14, width - 2, 1, "Change the address",
                    { background = ui.theme.panel })
                scene:button("down", 2, 16, width - 2, 1, "Take it down",
                    { background = ui.theme.danger })
            else
                ui.wrappedText(target, 4, 5, "An address like "
                    .. (squash(company.name) ~= "" and squash(company.name) or "store")
                    .. ".shop. Typed into Internet, it opens your store.",
                    width - 6, 5, ui.theme.ink, ui.theme.panel)
                scene:button("make", 2, 11, width - 2, 3, "Choose an address",
                    { background = colors.lime, foreground = colors.black, shadow = true })
            end
            scene:button("back", 1, height, 8, 1, "< Back", { background = ui.theme.panel })
            local action = scene:wait()
            if action == "back" or action == "__terminate" then return end
            local payload
            if action == "make" or action == "rename" then
                local typed = ui.input(target, "Address", {
                    hint = "Letters, numbers, dashes. Ends .shop",
                    mode = "domain", maxLength = 20, minLength = 3,
                    initial = site and (site.domain:gsub("%.shop$", ""))
                        or squash(company.name) })
                if typed then payload = { site = typed } end
            elseif action == "visit" then
                if type(api.browse) == "function" then
                    api.browse(site.domain)
                else
                    ui.message(target, "info", "Not on this Pocket",
                        "Update the Pocket to open it", 1.6)
                end
            elseif action == "down" and ui.confirm(target, "Take it down?",
                site.domain .. " stops opening your store", "Remove", "Keep") then
                payload = { enabled = false }
            end
            if payload then
                payload.company_id = company.company_id
                local saved, err = ask("COMPANY_SHOP_SITE", payload)
                if not saved then
                    failed("Not changed", err)
                else
                    site = saved.shop_site
                    ui.message(target, "success", site and "On the web" or "Taken down",
                        site and site.domain or company.name, 1.6)
                end
            end
        end
    end

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
                { "points", (settings.pickup and "Pickup points: on"
                    or "Pickup points: off") .. "  >", ui.theme.panel },
                { "cancel", settings.cancel and "Cancelling: on"
                    or "Cancelling: off", ui.theme.panel },
                { "returns", "Returns: " .. tostring(settings.return_days or 5)
                    .. " days", ui.theme.panel },
                -- FoxyOS 15: the store's address on the web.
                { "shopsite", state.shop_site and ("Web: " .. state.shop_site.domain)
                    or "Put it on the web  >", colors.lime },
            }
            -- Two rows apart when there is room for all of them, one when not.
            local gap = (height - 5) >= #entries * 2 and 2 or 1
            for index, entry in ipairs(entries) do
                local y = 3 + (index - 1) * gap + 1
                if y <= height - 2 then
                    scene:button(entry[1], 2, y, width - 2, 1,
                        ui.truncate(entry[2], width - 4), {
                            background = entry[3],
                            foreground = (entry[1] == "open"
                                and settings.open == false or entry[1] == "color"
                                or entry[1] == "shopsite")
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
            elseif action == "points" then
                pointsPage(company)
            elseif action == "shopsite" then
                shopSitePage(company, state)
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

    -- Discounts, 12.0 ---------------------------------------------------------------
    -- A sale takes a percentage off everything; free delivery can start at an
    -- amount; and codes are what a buyer types at checkout. The Bank works
    -- out every price from these, so a phone never says what a thing costs.

    local function describeCode(code)
        local parts = {}
        if (code.percent or 0) > 0 then
            parts[#parts + 1] = code.percent .. "% off"
        elseif (code.amount or 0) > 0 then
            parts[#parts + 1] = money(code.amount) .. " off"
        end
        if code.free_shipping then
            parts[#parts + 1] = #parts > 0 and "+ free delivery" or "Free delivery"
        end
        local used = tostring(code.uses or 0)
        if (code.max_uses or 0) > 0 then used = used .. "/" .. code.max_uses end
        parts[#parts + 1] = "used " .. used
        return table.concat(parts, " ")
    end

    local function newCode(company)
        local typed = ui.input(target, "New code", {
            hint = "3-12 letters and numbers", mode = "text", maxLength = 12,
            minLength = 3 })
        if not typed then return end
        local kind = choose("What does it do?", string.upper(typed), {
            option("A percentage off", "percent"),
            option("An amount off", "amount"),
            option("Free delivery only", "free") }, labelOf)
        if not kind then return end
        local fields = { company_id = company.company_id, code = typed }
        if kind.id == "percent" then
            local percent = ui.input(target, "Percent off", {
                hint = "1 to 100", mode = "integer", maxLength = 3 })
            if not percent then return end
            fields.percent = tonumber(percent)
        elseif kind.id == "amount" then
            local amount = ui.input(target, "Amount off", {
                hint = "Taken off the basket", mode = "number", maxLength = 7 })
            if not amount then return end
            fields.amount = tonumber(amount)
        end
        fields.free_shipping = kind.id == "free" or ui.confirm(target,
            "Free delivery too?", "Home delivery costs nothing with this code.",
            "Yes", "No")
        local uses = ui.input(target, "How many uses?", {
            hint = "0 for no limit", mode = "integer", maxLength = 5,
            initial = "0" })
        if not uses then return end
        fields.max_uses = tonumber(uses) or 0
        local made, err = ask("COMPANY_SHOP_CODE", fields)
        if not made then return failed("Not added", err) end
        ui.message(target, "success", "Code added", string.upper(typed), 1.2)
    end

    local function editCode(company, code)
        local chosen = choose(code.code, describeCode(code), {
            option(code.active and "Switch it off" or "Switch it on", "toggle"),
            option("Remove it", "remove") }, labelOf)
        if not chosen then return end
        if chosen.id == "remove" and not ui.confirm(target, "Remove it?",
            code.code .. " stops working at checkout.", "Remove", "Keep") then
            return
        end
        local done, err = ask("COMPANY_SHOP_CODE", { company_id = company.company_id,
            code = code.code, op = chosen.id })
        if not done then failed("Not changed", err) end
    end

    local function discountsPage(company)
        local page = 1
        while running() do
            local state, err = ask("COMPANY_STATE",
                { company_id = company.company_id })
            if not state then failed("Cannot open it", err) return "home" end
            local settings = state.settings
            local codes = {}
            for _, code in pairs(settings.codes or {}) do codes[#codes + 1] = code end
            table.sort(codes, function(a, b) return a.code < b.code end)
            local width, height = target.getSize()
            local bottom = type(ui.contentBottom) == "function"
                and ui.contentBottom(target) or height - 2
            local per = math.max(1, bottom - 9)
            local pages = math.max(1, math.ceil(#codes / per))
            page = math.max(1, math.min(page, pages))
            ui.clear(target)
            ui.header(target, "Discounts", ui.truncate(((settings.sale or 0) > 0
                and (settings.sale .. "% sale, ") or "") .. #codes
                .. (#codes == 1 and " code" or " codes"), width - 3),
                util.formatClock())
            local scene = ui.scene(target)
            local onSale = (settings.sale or 0) > 0
            scene:button("sale", 2, 4, width - 2, 1, ui.truncate(onSale
                and ("Sale: " .. settings.sale .. "% off all")
                or "Sale: none", width - 4),
                { background = onSale and ACCENT or ui.theme.panel,
                  foreground = onSale and colors.black or colors.white })
            local shipLabel = "Free delivery: off"
            if settings.free_shipping then
                shipLabel = (settings.free_over or 0) > 0 and ("Free delivery over "
                    .. money(settings.free_over)) or "Free delivery: always"
            end
            scene:button("ship", 2, 6, width - 2, 1, ui.truncate(shipLabel, width - 4),
                { background = settings.free_shipping and ACCENT or ui.theme.panel,
                  foreground = settings.free_shipping and colors.black
                    or colors.white })
            scene:button("add", 2, 8, pages > 1 and width - 12 or width - 2, 1,
                "+ New code", { background = ui.theme.accentDark })
            if pages > 1 then
                scene:button("prev", width - 9, 8, 4, 1, "<",
                    { background = ui.theme.panel, disabled = page <= 1 })
                scene:button("next", width - 4, 8, 4, 1, ">",
                    { background = ui.theme.panel, disabled = page >= pages })
            end
            if #codes == 0 then
                ui.wrappedText(target, 2, 10, "No codes yet. A code is typed"
                    .. " at checkout in the Shop app or at your pickup"
                    .. " points: a percentage or an amount off, or free"
                    .. " delivery. The sale counts at both.", width - 2,
                    math.max(1, bottom - 9), ui.theme.muted)
            end
            for slot = 1, per do
                local index = (page - 1) * per + slot
                local code = codes[index]
                if not code then break end
                scene:button("code:" .. index, 2, 9 + slot, width - 2, 1,
                    ui.truncate(code.code .. "  " .. (code.active
                        and describeCode(code) or "off"), width - 4),
                    { background = code.active and ui.theme.panel
                        or ui.theme.background, foreground = code.active
                        and colors.white or ui.theme.muted })
            end
            ui.tabBar(scene, target, COMPANY_TABS, "discounts", ACCENT)
            local action = scene:wait()
            if action == "home" or action == "__terminate" then return "home" end
            if action and action:match("^tab:") then return action end
            local change
            if action == "sale" then
                local typed = ui.input(target, "Sale", {
                    hint = "Percent off everything. 0 ends it", mode = "integer",
                    maxLength = 2, initial = plain(settings.sale) })
                if typed then change = { sale = tonumber(typed) or 0 } end
            elseif action == "ship" then
                local chosen = choose("Free delivery", "On home deliveries", {
                    option("Off", "off"), option("Always", "always"),
                    option("Over an amount", "over") }, labelOf)
                if chosen and chosen.id == "over" then
                    local typed = ui.input(target, "Free over", {
                        hint = "What is paid, after discounts", mode = "number",
                        maxLength = 7, initial = plain(settings.free_over) })
                    if typed then
                        change = { free_shipping = true,
                            free_over = tonumber(typed) or 0 }
                    end
                elseif chosen then
                    change = { free_shipping = chosen.id == "always", free_over = 0 }
                end
            elseif action == "add" then
                newCode(company)
            elseif action == "prev" then
                page = page - 1
            elseif action == "next" then
                page = page + 1
            else
                local index = tonumber(action and action:match("^code:(%d+)$"))
                if index and codes[index] then editCode(company, codes[index]) end
            end
            if change then
                change.company_id = company.company_id
                local saved, saveError = ask("COMPANY_SHOP_SETUP", change)
                if not saved then failed("Not changed", saveError) end
            end
        end
        return "home"
    end

    -- Sell: the till, FoxyOS 13 ---------------------------------------------------------
    -- The Service Kiosk, moved into the Company app. On the Pocket itself it
    -- sells on the spot; on a standing computer running the Pocket it spreads
    -- out into a receipt and a wall of products, and every colour monitor
    -- beside it faces the customer: what they are buying, the code to pay,
    -- and the thank you. The device is one of the company's tills on the Bank,
    -- so every way a kiosk took money works the same here.

    local till = { carts = {} }

    -- The till this device is for the company: kept in the app's own corner
    -- of the phone, and recognised by the Bank when it comes back.
    function till.start(company)
        local kept = type(api.load) == "function" and api.load() or {}
        kept.tills = type(kept.tills) == "table" and kept.tills or {}
        local mine = kept.tills[company.company_id] or {}
        local got, err = ask("COMPANY_TILL", { company_id = company.company_id,
            till_id = mine.id, till_token = mine.token })
        if not got then return nil, err end
        kept.tills[company.company_id] = { id = got.till_id, token = got.till_token }
        kept.last = company.company_id
        if type(api.save) == "function" then api.save(kept) end
        till.carts[company.company_id] = till.carts[company.company_id] or {}
        return {
            id = got.till_id, token = got.till_token, name = got.name,
            company = company, cart = till.carts[company.company_id],
            products = {}, category = "favorites", page = 1,
            screens = type(api.screens) == "function" and api.screens() or {},
            view = { mode = "idle", data = {}, frame = 0 },
        }
    end

    -- A Bank call as this till.
    function till.ask(desk, action, payload)
        payload = payload or {}
        payload.terminal_id, payload.terminal_token = desk.id, desk.token
        return api.request(action, payload, true)
    end

    function till.refresh(desk)
        local state = ask("COMPANY_STATE", { company_id = desk.company.company_id })
        if state then desk.products = state.products or {} end
        -- Favourites first, if there are any.
        if not desk.looked then
            desk.looked = true
            desk.category = "items"
            for _, product in ipairs(desk.products) do
                if product.favorite then desk.category = "favorites" end
            end
        end
        return state ~= nil
    end

    function till.shelf(desk)
        local shown = {}
        for _, product in ipairs(desk.products) do
            local daily = product.kind == "subscription"
            if (desk.category == "favorites" and product.favorite)
                or (desk.category == "items" and not daily)
                or (desk.category == "subs" and daily) then
                shown[#shown + 1] = product
            end
        end
        table.sort(shown, function(a, b) return a.name < b.name end)
        return shown
    end

    -- The basket, sorted, with its total and whether it is daily.
    function till.basket(desk)
        local items, total, kind = {}, 0, nil
        for _, entry in pairs(desk.cart) do
            if (entry.quantity or 0) > 0 then
                items[#items + 1] = { item_id = entry.item_id, name = entry.name,
                    price = entry.price, quantity = entry.quantity,
                    kind = entry.kind }
                total = total + entry.price * entry.quantity
                kind = kind or entry.kind
            end
        end
        table.sort(items, function(a, b) return a.name < b.name end)
        return items, util.roundMoney(total) or 0, kind or "one_time"
    end

    function till.clear(desk)
        for key in pairs(desk.cart) do desk.cart[key] = nil end
    end

    -- One more of something. A basket is either paid once or daily, so
    -- adding the other kind asks before it starts again.
    function till.add(desk, item)
        local items, _, kind = till.basket(desk)
        if #items > 0 and kind ~= item.kind then
            if not ui.confirm(target, "New basket?", item.kind == "subscription"
                and "Daily things are sold on their own" or "This basket is daily",
                "Start over", "Keep") then return end
            till.clear(desk)
        end
        local entry = desk.cart[item.item_id] or { item_id = item.item_id,
            name = item.name, price = item.price, kind = item.kind, quantity = 0 }
        entry.quantity = entry.quantity + 1
        desk.cart[item.item_id] = entry
    end

    -- The customer's screens ---------------------------------------------------------

    function till.paintOne(desk, screen)
        local width, height = screen.getSize()
        local mode, data = desk.view.mode, desk.view.data or {}
        local frame = desk.view.frame or 0
        local compact = width < 24 or height < 11
        local white, dark = colors.white, colors.black
        ui.clear(screen, dark)
        local function title(text, color)
            ui.fill(screen, 1, 1, width, math.min(2, height), color)
            ui.center(screen, 1, ui.truncate(text, math.max(1, width - 2)), dark, color)
        end
        if mode == "idle" then
            title("WELCOME", ACCENT)
            ui.center(screen, compact and 4 or 5, ui.truncate(desk.name,
                math.max(1, width - 2)), white, dark)
            ui.center(screen, compact and 6 or 7, compact and "READY"
                or "READY WHEN YOU ARE", colors.lightGray, dark)
            local pulse = math.max(2, math.min(width - 2, 2 + frame % math.max(2, width - 3)))
            ui.fill(screen, math.floor((width - pulse) / 2) + 1,
                math.min(height, compact and 8 or 9), pulse, 1, ACCENT)
        elseif mode == "cart" then
            title(data.kind == "subscription" and "EVERY DAY" or "YOUR ORDER", ACCENT)
            local items = data.items or {}
            local rows = math.max(1, height - 5)
            local row = 3
            for index = math.max(1, #items - rows + 1), #items do
                local item = items[index]
                local price = money(item.price * item.quantity)
                local priceX = math.max(3, width - #price)
                ui.text(screen, 2, row, ui.truncate(item.quantity .. "x " .. item.name,
                    math.max(1, priceX - 3)), white, dark)
                ui.text(screen, priceX, row, price, white, dark)
                row = row + 1
            end
            local total = money(data.total or 0)
            ui.fill(screen, 1, height - 1, width, 2, colors.gray)
            ui.text(screen, 2, height, "TOTAL", white, colors.gray)
            ui.text(screen, math.max(2, width - #total), height, total,
                colors.lime, colors.gray)
        elseif mode == "nearby" then
            title("FOXY PAY", ACCENT)
            ui.center(screen, 4, money(data.amount or 0), white, dark)
            ui.center(screen, compact and 6 or 7, data.name
                and ui.truncate(data.name, width - 2) or "Looking", ACCENT, dark)
            ui.center(screen, compact and 8 or 9, "CHECK YOUR POCKET"
                .. string.rep(".", frame % 4), colors.lightGray, dark)
        elseif mode == "code" then
            title("PAY WITH YOUR BANK", ACCENT)
            ui.center(screen, 3, money(data.amount or 0)
                .. (data.kind == "subscription" and "/DAY" or ""), white, dark)
            local code = tostring(data.code or "------")
            ui.fill(screen, 2, compact and 4 or 5, width - 2, compact and 2 or 3, white)
            ui.center(screen, compact and 5 or 6, code:sub(1, 3) .. " " .. code:sub(4, 6),
                dark, white)
            ui.center(screen, compact and 7 or 9, data.left or "", colors.lightGray, dark)
        elseif mode == "paid" then
            ui.fill(screen, 1, 1, width, height, colors.lime)
            ui.center(screen, math.max(2, math.floor(height / 2) - 1),
                data.kind == "subscription" and "ACTIVE" or "PAID", dark, colors.lime)
            ui.center(screen, math.max(3, math.floor(height / 2) + 1),
                money(data.amount or 0), dark, colors.lime)
            if height >= 8 then
                ui.center(screen, height - 1, ui.truncate("THANK YOU"
                    .. (data.payer and (", " .. data.payer) or ""), width - 2),
                    dark, colors.lime)
            end
        else
            title("NOT CHARGED", colors.red)
            ui.center(screen, math.max(3, math.floor(height / 2)), "NOTHING PAID",
                white, dark)
        end
    end

    function till.paint(desk)
        for _, screen in ipairs(desk.screens) do pcall(till.paintOne, desk, screen) end
    end

    function till.show(desk, mode, data)
        desk.view = { mode = mode, data = data or {}, frame = 0 }
        till.paint(desk)
    end

    -- What the customer sees between sales: the basket, or the welcome.
    function till.resting(desk)
        local items, total, kind = till.basket(desk)
        if #items > 0 then
            desk.view.mode, desk.view.data = "cart", { items = items, total = total,
                kind = kind }
        elseif desk.view.mode ~= "idle" then
            desk.view.mode, desk.view.data = "idle", {}
        end
    end

    -- Taking the money ------------------------------------------------------------------

    function till.paid(desk, amount, payer, kind)
        till.show(desk, "paid", { amount = amount, payer = payer, kind = kind })
        local width, height = target.getSize()
        for step = 1, 4 do
            ui.clear(target, colors.lime)
            ui.center(target, math.floor(height / 2) - 1, step % 2 == 1 and "PAID"
                or "PAID!", colors.black, colors.lime)
            ui.center(target, math.floor(height / 2) + 1, money(amount),
                colors.black, colors.lime)
            ui.center(target, math.floor(height / 2) + 3, ui.truncate(payer
                or "Customer", width - 2), colors.black, colors.lime)
            sleep(0.15)
        end
        ui.message(target, "success", kind == "subscription" and "Subscription on"
            or "Paid " .. money(amount), payer or "Customer", 1)
        till.clear(desk)
        till.show(desk, "idle")
    end

    function till.gone(desk, title, body)
        till.show(desk, "cancelled")
        ui.message(target, "warning", title, body, 1.4)
        till.show(desk, "idle")
    end

    function till.describe(items)
        local names = {}
        for index, item in ipairs(items) do
            if index <= 3 then names[#names + 1] = item.name end
        end
        return #names > 0 and table.concat(names, ", ") or "Sale"
    end

    -- Waits on a Foxy Pay offer to whoever is nearest, or the one customer
    -- this sale was rung up for. True once paid.
    function till.waitOffer(desk, offer, amount, kind)
        local frame = 0
        while running() do
            local width, height = target.getSize()
            local waiting = offer.status == "offered" or offer.status == "claiming"
                or offer.status == "claimed"
            ui.clear(target)
            ui.header(target, "Foxy Pay", money(amount), util.formatClock())
            ui.center(target, 6, offer.portable and "SENT TO" or "OFFERED TO",
                ui.theme.muted)
            ui.center(target, 8, ui.truncate(offer.target_name
                or (offer.status == "nobody_nearby" and "Nobody nearby" or "Looking"),
                width - 2), offer.target_name and ui.theme.ink or colors.orange)
            if offer.distance then
                ui.center(target, 9, offer.distance .. " blocks away", ui.theme.muted)
            end
            ui.center(target, 12, waiting and ("Waiting for their Pocket"
                .. string.rep(".", frame % 4)) or "Ask them to come closer",
                ui.theme.accent)
            desk.view.frame = frame
            till.show(desk, "nearby", { amount = amount, name = offer.target_name })
            local scene = ui.scene(target)
            scene:button("cancel", 2, height - 2, width - 2, 2, "Cancel",
                { background = ui.theme.danger })
            local action = scene:wait({ tickRate = 0.6, flash = false })
            frame = frame + 1
            if action == "cancel" or action == "__terminate" then
                till.ask(desk, "PROXIMITY_CANCEL", { offer_id = offer.offer_id })
                if desk.customer and desk.customer.offer_id == offer.offer_id then
                    desk.customer = nil
                end
                till.gone(desk, "Cancelled", "Nothing was charged")
                return false
            end
            local polled = till.ask(desk, "PROXIMITY_STATUS", { offer_id = offer.offer_id })
            if polled then offer = polled.offer end
            if offer.status == "paid" then
                if desk.customer and desk.customer.offer_id == offer.offer_id then
                    desk.customer = nil
                end
                till.paid(desk, amount, offer.target_name, kind)
                return true
            end
            if offer.status == "expired" or offer.status == "cancelled" then
                desk.customer = nil
                till.gone(desk, "Sale ended", "They did not confirm")
                return false
            end
        end
        return false
    end

    -- A code for somebody who banks somewhere else: they type it into their
    -- bank's app. True once paid.
    function till.waitCode(desk, created, kind)
        local deadline = util.nowMs() + (tonumber(created.expires_at)
            and math.max(0, created.expires_at - util.nowMs()) or 300000)
        local frame = 0
        while running() do
            local width, height = target.getSize()
            local seconds = math.max(0, math.floor((deadline - util.nowMs()) / 1000))
            local left = string.format("%d:%02d LEFT", math.floor(seconds / 60), seconds % 60)
            ui.clear(target)
            ui.header(target, "Pay code", money(created.amount), util.formatClock())
            ui.fill(target, 3, 6, width - 4, 5, colors.white)
            ui.center(target, 7, "TYPE IN YOUR BANK", colors.gray, colors.white)
            ui.center(target, 9, created.code:sub(1, 3) .. " " .. created.code:sub(4, 6),
                colors.black, colors.white)
            ui.center(target, 12, left, ui.theme.muted)
            ui.center(target, 13, "Waiting" .. string.rep(".", frame % 4), ui.theme.accent)
            desk.view.frame = frame
            till.show(desk, "code", { amount = created.amount, code = created.code,
                kind = kind, left = left })
            local scene = ui.scene(target)
            scene:button("cancel", 2, height - 2, width - 2, 2, "Cancel code",
                { background = ui.theme.danger })
            local action = scene:wait({ tickRate = 0.6, flash = false })
            frame = frame + 1
            if action == "cancel" or action == "__terminate" then
                till.ask(desk, "CANCEL_CODE", { code = created.code })
                till.gone(desk, "Cancelled", "Nothing was charged")
                return false
            end
            local status = till.ask(desk, "CODE_STATUS", { code = created.code })
            if status and status.status == "paid" then
                till.paid(desk, created.amount, status.payer, status.kind or kind)
                return true
            end
            if (status and (status.status == "expired" or status.status == "cancelled"))
                or seconds <= 0 then
                till.gone(desk, "Code expired", "Nothing was charged")
                return false
            end
        end
        return false
    end

    -- Charge: the customer this sale was rung up for, or whoever is nearest
    -- with Foxy, or a code for another bank.
    function till.charge(desk)
        local items, total, kind = till.basket(desk)
        if total <= 0 then
            ui.message(target, "warning", "Nothing to charge", "Add something first", 1.2)
            return
        end
        local payload = { amount = total, items = items, purchase_type = kind,
            description = till.describe(items) }
        if desk.customer then
            payload.offer_id = desk.customer.offer_id
            local sent, err = till.ask(desk, "PROXIMITY_BILL", payload)
            if not sent then return failed("Not sent", err) end
            return till.waitOffer(desk, sent.offer, total, kind)
        end
        local how = choose("Charge " .. money(total), till.describe(items), {
            option("Foxy Pay: nearest Pocket", "nearby"),
            option("Pay code: another bank", "code"),
        }, labelOf)
        if not how then return end
        if how.id == "nearby" then
            local position = type(api.position) == "function" and api.position()
            if not position then
                return failed("No GPS here", "Foxy Pay finds people with GPS anchors")
            end
            payload.position = position
            local created, err = till.ask(desk, "PROXIMITY_OFFER", payload)
            if not created then return failed("Not offered", err) end
            return till.waitOffer(desk, created.offer, total, kind)
        end
        local created, err = till.ask(desk, "CREATE_PAY_CODE", payload)
        if not created then return failed("No code", err) end
        return till.waitCode(desk, created, kind)
    end

    -- Portable: find the customer first, ring them up after. They say yes
    -- on their own Pocket, then again to pay.
    function till.findCustomer(desk)
        local position = type(api.position) == "function" and api.position()
        if not position then
            return failed("No GPS here", "Foxy Pay finds people with GPS anchors")
        end
        local created, err = till.ask(desk, "PROXIMITY_CLAIM", { position = position,
            description = "Sale at " .. desk.name })
        if not created then return failed("Cannot look", err) end
        local offer, frame = created.offer, 0
        while running() do
            local width, height = target.getSize()
            ui.clear(target)
            ui.header(target, "Find customer", desk.name, util.formatClock())
            if offer.status == "claimed" then
                ui.center(target, 7, "READY", ui.theme.success)
            elseif offer.target_name then
                ui.center(target, 7, "ASKING" .. string.rep(".", frame % 4), ui.theme.accent)
            else
                ui.center(target, 7, "NOBODY NEARBY", colors.orange)
            end
            ui.center(target, 9, ui.truncate(offer.target_name or "Ask them to come closer",
                width - 2), ui.theme.ink)
            local scene = ui.scene(target)
            scene:button("cancel", 2, height - 2, width - 2, 2, "Cancel",
                { background = ui.theme.danger })
            local action = scene:wait({ tickRate = 0.6, flash = false })
            frame = frame + 1
            if action == "cancel" or action == "__terminate" then
                till.ask(desk, "PROXIMITY_CANCEL", { offer_id = offer.offer_id })
                return
            end
            local polled = till.ask(desk, "PROXIMITY_STATUS", { offer_id = offer.offer_id })
            if not polled then return end
            offer = polled.offer
            if offer.status == "claimed" then
                desk.customer = offer
                ui.message(target, "success", "Customer ready",
                    tostring(offer.target_name), 1)
                return
            end
        end
    end

    -- Tools: what a kiosk's own tab held that still belongs at a till.
    function till.tools(desk)
        while running() do
            local items = {
                option("Verify a MyID", "myid"),
                option("Customer screens: " .. #desk.screens, "screens"),
                option("Custom amount", "custom"),
            }
            -- FoxyOS 14: from a Sell tab, Till mode is one tap away.
            if not desk.mode then table.insert(items, 1, option("Till mode", "tillmode")) end
            local item = choose("Till", desk.name, items, labelOf)
            if not item then return end
            if item.id == "tillmode" then return "tillmode" end
            if item.id == "myid" then
                if ui.myIdVerifier then
                    ui.myIdVerifier(target, function(code)
                        return api.request("MYID_VERIFY", { code = code }, true)
                    end)
                end
            elseif item.id == "screens" then
                desk.screens = type(api.screens) == "function" and api.screens() or {}
                till.show(desk, "idle")
                ui.message(target, "info", #desk.screens .. " customer screens",
                    #desk.screens > 0 and "Showing the welcome"
                        or "Attach a colour monitor to this computer", 1.6)
            elseif item.id == "custom" then
                till.custom(desk)
                return
            end
        end
    end

    -- An amount typed in, sold once or daily.
    function till.custom(desk)
        local text = ui.input(target, "Custom amount", { hint = "What to charge",
            mode = "number", maxLength = 10 })
        local amount = util.roundMoney(tonumber(text))
        if not amount or amount <= 0 then return end
        local daily = not ui.confirm(target, "Paid how?", "Once, or every day?",
            "Once", "Daily")
        till.custom_count = (till.custom_count or 0) + 1
        till.add(desk, { item_id = "custom:" .. till.custom_count,
            name = daily and "Daily amount" or "Amount", price = amount,
            kind = daily and "subscription" or "one_time" })
    end

    -- The basket on its own, for a narrow screen.
    function till.basketSheet(desk)
        while running() do
            local items, total, kind = till.basket(desk)
            local width, height = target.getSize()
            ui.clear(target)
            ui.header(target, "Basket", #items .. " lines  " .. money(total)
                .. (kind == "subscription" and "/day" or ""), util.formatClock())
            local scene = ui.scene(target)
            local rows = height - 9
            for index, item in ipairs(items) do
                if index > rows then break end
                local y = 3 + index
                ui.text(target, 2, y, ui.truncate(item.quantity .. "x " .. item.name,
                    width - 18), ui.theme.ink)
                ui.text(target, width - 15, y, ui.truncate(money(item.price
                    * item.quantity), 8), ui.theme.muted)
                scene:button("less:" .. index, width - 6, y, 3, 1, "-",
                    { background = ui.theme.panel })
                scene:button("more:" .. index, width - 3, y, 3, 1, "+",
                    { background = ACCENT, foreground = colors.black })
            end
            if #items == 0 then ui.center(target, 6, "Empty", ui.theme.muted) end
            scene:button("clear", 2, height - 3, 9, 1, "Clear",
                { background = ui.theme.danger, disabled = #items == 0 })
            scene:button("back", 2, height - 1, width - 2, 1, "Done",
                { background = ui.theme.panel })
            local action = scene:wait()
            if action == "back" or action == "__terminate" then return end
            if action == "clear" and ui.confirm(target, "Clear basket?",
                "Everything comes out", "Clear", "Keep") then
                till.clear(desk)
            end
            local less = tonumber(action and action:match("^less:(%d+)$"))
            local more = tonumber(action and action:match("^more:(%d+)$"))
            local item = items[less or more or 0]
            if item then
                local entry = desk.cart[item.item_id]
                entry.quantity = entry.quantity + (more and 1 or -1)
                if entry.quantity <= 0 then desk.cart[item.item_id] = nil end
            end
            till.resting(desk)
            till.paint(desk)
        end
    end

    local CATEGORIES = { { "favorites", "Favs" }, { "items", "Items" },
        { "subs", "Daily" } }

    -- The tab itself.
    -- Leaving Till mode is the owner's to do: it asks for the PIN, so a
    -- customer at a standing till cannot walk off with the Pocket behind it.
    function till.leave()
        if type(api.pin) == "function" then return api.pin("Leave till mode") == true end
        return ui.confirm(target, "Leave till mode?", "Back to the Company app",
            "Leave", "Stay")
    end

    -- `tillMode`: FoxyOS 14. The till fills the screen with no tabs, keeps
    -- the Pocket from locking while it is open, and asks for the PIN to
    -- leave. Without it, Sell is a tab like the others and the Pocket locks
    -- as it always does.
    local function sellPage(company, tillMode)
        local desk, err = till.start(company)
        while running() and not desk do
            local width = target.getSize()
            ui.clear(target)
            ui.header(target, ui.truncate(company.name, width - 9),
                tillMode and "Till mode" or "Sell", util.formatClock())
            ui.wrappedText(target, 2, 5, "This Pocket cannot be a till yet: "
                .. tostring(err or "the Bank is not answering")
                .. ". The Bank Server needs FoxyOS 13 or newer.", width - 2, 6,
                ui.theme.muted)
            local scene = ui.scene(target)
            if tillMode then
                local _, height = target.getSize()
                scene:button("back", 1, height, 8, 1, "< Back",
                    { background = ui.theme.panel })
            else
                ui.tabBar(scene, target, COMPANY_TABS, "sell", ACCENT)
            end
            local action = scene:wait()
            if action == "home" or action == "back" or action == "__terminate" then
                return "home"
            end
            if action and action:match("^tab:") then return action end
        end
        till.refresh(desk)
        till.show(desk, "idle")
        desk.mode = tillMode
        local ticks = 0
        while running() do
            -- Till mode keeps the Pocket awake: a till at a counter is used
            -- by customers, not its owner, and locking it would hide it.
            if tillMode and type(ui.noteActivity) == "function" then
                ui.noteActivity()
            end
            local width, height = target.getSize()
            local wide = width >= 40
            local items, total, kind = till.basket(desk)
            local shelf = till.shelf(desk)
            local bottom = tillMode and height or ui.contentBottom(target)
            ui.clear(target)
            ui.header(target, ui.truncate(desk.name, width - 9), desk.customer
                and ("For " .. tostring(desk.customer.target_name))
                or tillMode and "TILL MODE"
                or ("Till  " .. #desk.screens .. " screens"), util.formatClock())
            local scene = ui.scene(target)
            if tillMode then
                scene:button("exit", width - 6, 2, 6, 1, "Exit",
                    { background = ui.theme.panel })
            end

            -- The receipt: a column on a wide screen, a bar on a narrow one.
            local shelfX, shelfWidth = 2, width - 2
            if wide then
                local receiptWidth = math.max(18, math.min(22, math.floor(width * 0.4)))
                shelfX, shelfWidth = receiptWidth + 3, width - receiptWidth - 3
                ui.fill(target, 1, 4, receiptWidth + 1, bottom - 3, ui.theme.panel)
                ui.text(target, 2, 4, desk.customer and ui.truncate(
                    tostring(desk.customer.target_name), receiptWidth - 1)
                    or "RECEIPT", desk.customer and colors.lime or ui.theme.muted,
                    ui.theme.panel)
                local rows = bottom - 11
                local first = math.max(1, #items - rows + 1)
                for index = first, #items do
                    local item = items[index]
                    local y = 6 + index - first
                    local price = money(item.price * item.quantity)
                    scene:button("less:" .. index, 2, y, receiptWidth - #price - 1, 1,
                        ui.truncate(item.quantity .. "x " .. item.name,
                            receiptWidth - #price - 3),
                        { background = ui.theme.panel, flash = false })
                    ui.text(target, receiptWidth - #price + 1, y, price, ui.theme.muted,
                        ui.theme.panel)
                end
                if #items == 0 then
                    ui.text(target, 2, 6, "Tap a product", ui.theme.muted, ui.theme.panel)
                end
                ui.text(target, 2, bottom - 4, kind == "subscription" and "PER DAY"
                    or "TOTAL", ui.theme.muted, ui.theme.panel)
                local totalText = money(total)
                ui.text(target, receiptWidth - #totalText + 1, bottom - 4, totalText,
                    ui.theme.ink, ui.theme.panel)
                local half = math.floor((receiptWidth - 1) / 2)
                scene:button("clear", 2, bottom - 3, half, 1, "Clear",
                    { background = colors.gray, disabled = #items == 0 })
                scene:button("customer", 3 + half, bottom - 3, receiptWidth - half - 1, 1,
                    desk.customer and "Drop" or "Customer",
                    { background = desk.customer and colors.lime or colors.cyan,
                      foreground = colors.black })
                scene:button("charge", 2, bottom - 1, receiptWidth, 2,
                    total > 0 and ("Charge " .. money(total)) or "Charge",
                    { background = colors.lime, foreground = colors.black,
                      disabled = total <= 0 })
            end

            -- Categories, then the products as tiles.
            local chipWidth = math.floor((shelfWidth - 3) / 4)
            local function chip(id, index, label, active)
                local x = shelfX + (index - 1) * (chipWidth + 1)
                local chipW = index == 4 and shelfX + shelfWidth - x or chipWidth
                local background = active and ACCENT or ui.theme.panel
                ui.fill(target, x, 4, chipW, 1, background)
                ui.text(target, x + math.max(0, math.floor((chipW - #label) / 2)), 4,
                    ui.truncate(label, chipW), active and colors.black or ui.theme.ink,
                    background)
                scene:hotspot(id, x, 4, chipW, 1)
            end
            for index, entry in ipairs(CATEGORIES) do
                chip("cat:" .. entry[1], index, entry[2], desk.category == entry[1])
            end
            chip("tools", 4, "More", false)
            local columns = 2
            local tileHeight = wide and 3 or 2
            local shelfBottom = wide and bottom or bottom - 3
            local rows = math.max(1, math.floor((shelfBottom - 5) / (tileHeight + 1)))
            local tileWidth = math.floor((shelfWidth - (columns - 1)) / columns)
            local perPage = rows * columns
            local pages = math.max(1, math.ceil(#shelf / perPage))
            desk.page = math.max(1, math.min(desk.page, pages))
            for slot = 1, perPage do
                local index = (desk.page - 1) * perPage + slot
                local product = shelf[index]
                if not product then break end
                local column = (slot - 1) % columns
                local row = math.floor((slot - 1) / columns)
                local inBasket = desk.cart[product.item_id]
                    and desk.cart[product.item_id].quantity or 0
                local label = ui.truncate(product.name, tileWidth - 2) .. "\n"
                    .. ui.truncate(money(product.price) .. (product.kind == "subscription"
                        and "/d" or "") .. (inBasket > 0 and not wide
                            and ("  x" .. inBasket) or ""), tileWidth - 2)
                if wide then
                    label = label .. "\n" .. (inBasket > 0 and ("x" .. inBasket) or "")
                end
                scene:button("product:" .. index, shelfX + column * (tileWidth + 1),
                    6 + row * (tileHeight + 1), tileWidth, tileHeight, label, {
                        background = inBasket > 0 and ACCENT
                            or product.kind == "subscription" and colors.purple
                            or ui.theme.panel,
                        foreground = inBasket > 0 and colors.black or ui.theme.ink })
            end
            if #shelf == 0 then
                ui.wrappedText(target, shelfX, 7, desk.category == "favorites"
                    and "No favourites yet: star products on the Products tab."
                    or desk.category == "subs" and "Nothing daily: add a subscription"
                        .. " on the Products tab."
                    or "No products yet: add them on the Products tab.",
                    shelfWidth, 4, ui.theme.muted)
            end
            if pages > 1 then
                scene:button("prev", shelfX + shelfWidth - 9, shelfBottom, 4, 1, "<",
                    { background = ui.theme.panel, disabled = desk.page <= 1 })
                scene:button("next", shelfX + shelfWidth - 4, shelfBottom, 4, 1, ">",
                    { background = ui.theme.panel, disabled = desk.page >= pages })
            end

            -- On a narrow screen the basket is a bar above the tabs.
            if not wide then
                local count = 0
                for _, item in ipairs(items) do count = count + item.quantity end
                scene:button("basket", 2, bottom - 1, 9, 2, count == 0 and "Empty"
                    or ("Bag " .. count), { background = ui.theme.panel })
                scene:button("customer", 2, bottom - 2, 9, 1,
                    desk.customer and "Drop" or "Find",
                    { background = desk.customer and colors.lime or colors.cyan,
                      foreground = colors.black })
                scene:button("charge", 12, bottom - 2, width - 12, 3,
                    total > 0 and ("Charge\n" .. money(total)) or "Charge",
                    { background = colors.lime, foreground = colors.black,
                      disabled = total <= 0 })
            end
            if not tillMode then
                ui.tabBar(scene, target, COMPANY_TABS, "sell", ACCENT)
            end
            till.resting(desk)
            desk.view.frame = ticks
            till.paint(desk)

            local action = scene:wait({ tickRate = 0.5, flash = false })
            -- In Till mode the only way out is Exit, and the PIN. Even a
            -- terminate asks: a keyboard at the counter is the customer's too.
            if tillMode and (action == "exit" or action == "__terminate") then
                if till.leave() then action = "home" else action = nil end
            end
            if action == "home" or action == "__terminate"
                or (action and action:match("^tab:")) then
                -- Leaving the till lets go of a customer it found, rather
                -- than leave them waiting on their Pocket until it times out.
                if desk.customer then
                    till.ask(desk, "PROXIMITY_CANCEL", { offer_id = desk.customer.offer_id })
                    desk.customer = nil
                end
                till.show(desk, "idle")
                return action:match("^tab:") and action or "home"
            end
            if action == "__tick" then
                ticks = ticks + 1
                if ticks % 60 == 0 then till.refresh(desk) end
            elseif action == "charge" then
                till.charge(desk)
            elseif action == "customer" then
                if desk.customer then
                    if ui.confirm(target, "Drop customer?", "Let "
                        .. tostring(desk.customer.target_name) .. " go", "Drop", "Keep") then
                        till.ask(desk, "PROXIMITY_CANCEL",
                            { offer_id = desk.customer.offer_id })
                        desk.customer = nil
                    end
                else
                    till.findCustomer(desk)
                end
            elseif action == "basket" then
                till.basketSheet(desk)
            elseif action == "clear" then
                till.clear(desk)
            elseif action == "tools" then
                if till.tools(desk) == "tillmode" then
                    -- Till mode on top of the tab; back here once it is left.
                    sellPage(company, true)
                    till.show(desk, "idle")
                end
            elseif action == "prev" then
                desk.page = desk.page - 1
            elseif action == "next" then
                desk.page = desk.page + 1
            else
                local category = action and action:match("^cat:(.+)$")
                local productIndex = tonumber(action and action:match("^product:(%d+)$"))
                local less = tonumber(action and action:match("^less:(%d+)$"))
                if category then
                    desk.category, desk.page = category, 1
                elseif productIndex and shelf[productIndex] then
                    local product = shelf[productIndex]
                    till.add(desk, { item_id = product.item_id, name = product.name,
                        price = product.price, kind = product.kind == "subscription"
                            and "subscription" or "one_time" })
                elseif less and items[less] then
                    local entry = desk.cart[items[less].item_id]
                    entry.quantity = entry.quantity - 1
                    if entry.quantity <= 0 then desk.cart[items[less].item_id] = nil end
                end
            end
        end
        return "home"
    end

    local function companyScreen(company, first)
        local tab = first or "sell"
        while running() do
            local switched
            if tab == "sell" then
                switched = sellPage(company)
            elseif tab == "store" then
                switched = storePage(company)
            elseif tab == "discounts" then
                switched = discountsPage(company)
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
                    .. " sell at your till, in the Shop app and at"
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

    -- Till mode, FoxyOS 14 --------------------------------------------------------------

    -- The till this device last sold at, or the only company there is.
    local function lastTill(companies)
        local kept = type(api.load) == "function" and api.load() or {}
        local pick = #companies == 1 and companies[1] or nil
        for _, company in ipairs(companies) do
            if company.company_id == kept.last then pick = company end
        end
        return pick
    end

    local function tillPage()
        while running() do
            local listed, err = ask("COMPANY_LIST")
            local companies = listed and listed.companies or {}
            local pick = lastTill(companies)
            local width, height = target.getSize()
            ui.clear(target)
            ui.header(target, "Till mode", pick and ui.truncate(pick.name, width - 3)
                or "Your till, full screen", util.formatClock())
            local scene = ui.scene(target)
            ui.card(target, 2, 5, width - 2, 6, ACCENT)
            ui.wrappedText(target, 4, 5, "The till fills the screen and this"
                .. " Pocket stays awake. Leaving asks for your PIN. On a computer,"
                .. " every colour monitor faces the customer.", width - 6, 6,
                ui.theme.ink, ui.theme.panel)
            if #companies == 0 then
                ui.wrappedText(target, 2, 12, listed and "Start a company first,"
                    .. " on Companies." or tostring(err or "Cannot reach the Bank."),
                    width - 2, 3, ui.theme.muted)
            elseif pick then
                scene:button("start", 2, 12, width - 2, 3, "Start till mode",
                    { background = colors.lime, foreground = colors.black, shadow = true })
                if #companies > 1 then
                    scene:button("other", 2, 16, width - 2, 1, "Another company",
                        { background = ui.theme.panel })
                end
            else
                scene:button("other", 2, 12, width - 2, 3, "Choose a company",
                    { background = colors.lime, foreground = colors.black, shadow = true })
            end
            ui.tabBar(scene, target, TABS, "till", ACCENT)
            local action = scene:wait()
            if action == "home" or action == "__terminate" then return "home" end
            if action and action:match("^tab:") then return action end
            if action == "start" and pick then
                sellPage(pick, true)
            elseif action == "other" then
                local chosen = choose("Till mode", "Which company?", companies,
                    function(company) return company.name end)
                if chosen then sellPage(chosen, true) end
            end
        end
        return "home"
    end

    -- Starting -----------------------------------------------------------------------

    local wanted = type(api.action) == "function" and api.action() or nil
    -- FoxyOS 13: Point of Sale opens the till this device last sold at, or
    -- the only company there is. FoxyOS 14: Till mode does the same, full
    -- screen. A standing computer opens straight onto it.
    if wanted == "sell" or wanted == "till" then
        local listed = ask("COMPANY_LIST")
        local pick = lastTill(listed and listed.companies or {})
        if pick and wanted == "till" then
            sellPage(pick, true)
        elseif pick then
            companyScreen(pick, "sell")
        end
    end
    local tab = wanted == "delivery" and "delivery"
        or (wanted == "till" and "till") or "companies"
    while running() do
        local switched
        if tab == "delivery" then
            switched = deliveryPage()
        elseif tab == "till" then
            switched = tillPage()
        else
            switched = companiesPage()
        end
        local nextTab = type(switched) == "string"
            and switched:match("^tab:(.+)$")
        if not nextTab then return end
        tab = nextTab
    end
end
