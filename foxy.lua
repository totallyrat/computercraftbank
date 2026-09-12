-- PUMPE APP: Foxy
-- The Foxy Account and the bank behind it, in one place. Downloaded from the
-- App Server rather than shipped with the PUMPE, so it can move faster than
-- the phone underneath it.
--
-- An app is one file returning one function. Everything it is allowed to do
-- arrives in `api`; it never sees the session token.

return function(api)
    local ui, util, target = api.ui, api.util, api.target
    local money, request = api.money, api.request
    local colors = api.colors

    local FOX = colors.orange
    local INK = colors.white

    local function running()
        return api.running()
    end

    -- Animations ------------------------------------------------------------

    -- The wordmark sweeps in from the left, one column at a time.
    local function sweepIn(word, row, color)
        local width = target.getSize()
        local left = math.max(1, math.floor((width - #word) / 2) + 1)
        for count = 1, #word do
            ui.text(target, left, row, word:sub(1, count), color,
                ui.theme.background)
            sleep(0.05)
        end
    end

    -- A band of light travelling across the card, the way a real one catches
    -- the light when you tilt it.
    local function shimmer(x, y, width, height)
        for column = 0, width + 3 do
            for row = 0, height - 1 do
                local at = x + column - 2
                if at >= x and at < x + width then
                    ui.fill(target, at, y + row, 1, 1, FOX)
                end
                local trail = x + column - 3
                if trail >= x and trail < x + width then
                    ui.fill(target, trail, y + row, 1, 1, colors.brown)
                end
            end
            sleep(0.012)
        end
        ui.fill(target, x, y, width, height, colors.brown)
    end

    local function progressPulse(row, label)
        local width = target.getSize()
        local barWidth = width - 6
        for step = 1, barWidth do
            ui.fill(target, 4, row, barWidth, 1, ui.theme.panel)
            ui.fill(target, 4, row, step, 1, FOX)
            ui.center(target, row - 2, label, INK, ui.theme.background)
            sleep(0.012)
        end
    end

    -- The card ----------------------------------------------------------------

    -- Twelve digits that read like a card rather than an account id: a
    -- Foxy prefix, your personal number, then the tail of your account.
    local function cardNumber(overview)
        local personal = tostring(overview.personal_number or ""):gsub("%D", "")
        local account = tostring(overview.card_id or ""):gsub("%D", "")
        local raw = "40" .. personal .. account:sub(-5)
        while #raw < 12 do raw = raw .. "0" end
        raw = raw:sub(1, 12)
        return table.concat({
            raw:sub(1, 4), raw:sub(5, 8), raw:sub(9, 12),
        }, " ")
    end

    local function drawCard(overview, y)
        local width = target.getSize()
        local cardWidth = width - 2
        ui.fill(target, 2, y, cardWidth, 6, colors.brown)
        ui.text(target, 3, y, "FOXY", FOX, colors.brown)
        ui.text(target, cardWidth - 2, y, "[]", colors.yellow, colors.brown)
        ui.text(target, 3, y + 2, cardNumber(overview), INK, colors.brown)
        ui.text(target, 3, y + 4,
            ui.truncate(string.upper(overview.name or ""), cardWidth - 8),
            INK, colors.brown)
        ui.text(target, cardWidth - 4, y + 4,
            ui.truncate(tostring(overview.personal_number or ""), 5),
            ui.theme.muted, colors.brown)
    end

    -- Moving money between your own accounts -----------------------------------

    local function amountPrompt(title, hint)
        local raw = ui.input(target, title, {
            hint = hint, mode = "number", maxLength = 12,
        })
        if not raw then return nil end
        local amount = tonumber(raw)
        if not amount or amount <= 0 then
            ui.message(target, "error", "Not an amount", "Try again", 1)
            return nil
        end
        return amount
    end

    local function pickAccount(title, options)
        local width, height = target.getSize()
        local page = 1
        while running() do
            local shown, actualPage, pages = util.page(options, page, 4)
            page = actualPage
            ui.clear(target)
            ui.header(target, title, "Where to?", util.formatClock())
            local scene = ui.scene(target)
            for index, option in ipairs(shown) do
                scene:button("pick:" .. option.id, 2, 4 + (index - 1) * 3,
                    width - 2, 2,
                    option.name .. "\n" .. money(option.balance),
                    { background = option.id == "main" and FOX
                        or ui.theme.panel,
                      foreground = option.id == "main" and colors.black
                        or INK })
            end
            scene:button("back", 1, height, 8, 1, "< Back",
                { background = ui.theme.panel })
            if pages > 1 then
                scene:button("prev", width - 11, height, 4, 1, "<",
                    { background = ui.theme.panel, disabled = page <= 1 })
                ui.text(target, width - 6, height, page .. "/" .. pages,
                    ui.theme.muted)
                scene:button("next", width - 2, height, 2, 1, ">",
                    { background = ui.theme.panel, disabled = page >= pages })
            end
            local action = scene:wait({ tickRate = 5 })
            if action == "back" or action == "__terminate" then return nil
            elseif action == "prev" then page = page - 1
            elseif action == "next" then page = page + 1
            else
                local id = action and action:match("^pick:(.+)$")
                if id then return id end
            end
        end
    end

    local function moveMoney(overview, fromId, fromName, available)
        local options = {}
        if fromId ~= "main" then
            options[#options + 1] = { id = "main", name = "Main account",
                balance = overview.balance }
        end
        for _, pot in ipairs(overview.pots) do
            if pot.pot_id ~= fromId then
                options[#options + 1] = { id = pot.pot_id, name = pot.name,
                    balance = pot.balance }
            end
        end
        if #options == 0 then
            ui.message(target, "info", "Nowhere to move it",
                "Make another account first", 1.4)
            return false
        end
        local toId = pickAccount("Move from " .. fromName, options)
        if not toId then return false end
        local amount = amountPrompt("How much?",
            money(available) .. " available")
        if not amount then return false end
        local moved, err = request("FOXY_POT_MOVE", {
            from_pot = fromId, to_pot = toId, amount = amount,
        }, true)
        if not moved then
            ui.message(target, "error", "Could not move it", err, 1.6)
            return false
        end
        ui.clear(target)
        ui.header(target, "Moving", fromName, util.formatClock())
        progressPulse(11, money(amount))
        ui.message(target, "success", "Moved " .. money(amount),
            fromName .. " to your other account", 1.2)
        return true
    end

    local function potScreen(overview, pot)
        while running() do
            local width, height = target.getSize()
            ui.clear(target)
            ui.header(target, pot.name, "Foxy account", util.formatClock())
            ui.card(target, 2, 5, width - 2, 5, FOX)
            ui.text(target, 4, 6, "BALANCE", ui.theme.muted, ui.theme.panel)
            ui.text(target, 4, 8, money(pot.balance), INK, ui.theme.panel,
                width - 6)
            local scene = ui.scene(target)
            scene:button("move", 2, 11, width - 2, 3, "Move money",
                { background = FOX, foreground = colors.black, shadow = true })
            scene:button("close", 2, 15, width - 2, 2, "Close this account",
                { background = ui.theme.panel })
            scene:button("back", 1, height, 8, 1, "< Bank",
                { background = ui.theme.panel })
            local action = scene:wait({ tickRate = 5 })
            if action == "back" or action == "__terminate" then return end
            if action == "move" then
                if moveMoney(overview, pot.pot_id, pot.name, pot.balance) then
                    return
                end
            elseif action == "close" then
                if ui.confirm(target, "Close account",
                    money(pot.balance) .. " goes back to Main.",
                    "Close", "Keep") then
                    request("FOXY_POT_CLOSE", { pot_id = pot.pot_id }, true)
                    return
                end
            end
        end
    end

    -- Foxy Cash ---------------------------------------------------------------

    local function foxyCash(overview)
        local friends = request("FRIEND_OVERVIEW", {}, true)
        local list = friends and friends.friends or {}
        if #list == 0 then
            ui.clear(target)
            ui.header(target, "Foxy Cash", "Friends only", util.formatClock())
            local width, height = target.getSize()
            ui.card(target, 2, 5, width - 2, 8, FOX)
            ui.wrappedText(target, 4, 6,
                "Foxy Cash only reaches your friends. Add someone in Friends"
                    .. " first, then send instantly.",
                width - 6, 5, ui.theme.muted, ui.theme.panel)
            local scene = ui.scene(target)
            scene:button("back", 1, height, 10, 1, "< Bank",
                { background = ui.theme.panel })
            scene:wait()
            return
        end
        local options = {}
        for _, friend in ipairs(list) do
            options[#options + 1] = { id = friend.account_id,
                name = friend.name, balance = 0 }
        end
        local width, height = target.getSize()
        local page = 1
        local chosen
        while running() and not chosen do
            local shown, actualPage, pages = util.page(options, page, 4)
            page = actualPage
            ui.clear(target)
            ui.header(target, "Foxy Cash", "Send to a friend",
                util.formatClock())
            local scene = ui.scene(target)
            for index, option in ipairs(shown) do
                scene:button("pick:" .. option.id, 2, 4 + (index - 1) * 3,
                    width - 2, 2, option.name,
                    { background = ui.theme.panel })
            end
            scene:button("back", 1, height, 8, 1, "< Bank",
                { background = ui.theme.panel })
            if pages > 1 then
                scene:button("prev", width - 11, height, 4, 1, "<",
                    { background = ui.theme.panel, disabled = page <= 1 })
                ui.text(target, width - 6, height, page .. "/" .. pages,
                    ui.theme.muted)
                scene:button("next", width - 2, height, 2, 1, ">",
                    { background = ui.theme.panel, disabled = page >= pages })
            end
            local action = scene:wait({ tickRate = 5 })
            if action == "back" or action == "__terminate" then return
            elseif action == "prev" then page = page - 1
            elseif action == "next" then page = page + 1
            else chosen = action and action:match("^pick:(.+)$") end
        end
        if not chosen then return end
        local amount = amountPrompt("Send how much?", "No daily limit")
        if not amount then return end
        local quote, quoteError = request("FOXY_CASH_QUOTE",
            { account_id = chosen, amount = amount }, true)
        if not quote then
            ui.message(target, "error", "Cannot send that", quoteError, 1.8)
            return
        end
        ui.clear(target)
        ui.header(target, "Foxy Cash", quote.recipient, util.formatClock())
        ui.card(target, 2, 5, width - 2, 8, FOX)
        ui.text(target, 4, 6, "THEY GET", ui.theme.muted, ui.theme.panel)
        ui.text(target, 4, 7, money(quote.amount), INK, ui.theme.panel,
            width - 6)
        ui.text(target, 4, 9, "FEE  " .. money(quote.fee) .. "  ("
            .. math.floor(quote.fee_rate * 100) .. "%)",
            ui.theme.muted, ui.theme.panel, width - 6)
        ui.text(target, 4, 11, "YOU PAY  " .. money(quote.total),
            INK, ui.theme.panel, width - 6)
        local scene = ui.scene(target)
        scene:button("send", 2, 14, width - 2, 3, "Send instantly",
            { background = FOX, foreground = colors.black, shadow = true })
        scene:button("back", 1, height, 8, 1, "< Back",
            { background = ui.theme.panel })
        if scene:wait() ~= "send" then return end
        local pin = ui.pin(target, "Confirm Foxy Cash", true)
        if not pin then return end
        local sent, sendError = request("FOXY_CASH_SEND",
            { account_id = chosen, amount = amount, pin = pin }, true)
        if not sent then
            ui.message(target, "error", "Not sent", sendError, 1.8)
            return
        end
        -- The money "flies" across before the receipt lands.
        ui.clear(target)
        ui.header(target, "Foxy Cash", quote.recipient, util.formatClock())
        for step = 1, width - 4 do
            ui.fill(target, 2, 10, width - 2, 1, ui.theme.background)
            ui.text(target, 1 + step, 10, "$", FOX, ui.theme.background)
            sleep(0.015)
        end
        ui.message(target, "success", "Sent " .. money(sent.amount),
            quote.recipient .. " has it now", 1.4)
    end

    -- The bank ----------------------------------------------------------------

    -- The bank itself -------------------------------------------------------
    -- Until 9.4 all of this was a Bank tab built into the PUMPE, beside Foxy
    -- rather than inside it, so your money lived in two places on the same
    -- phone. It lives here now: one account, one app.

    -- Screens inside the bank go back to the bank, not to the Home Screen.
    local function bankFooter(scene, page, pages)
        local width, height = scene.width, scene.height
        scene:button("back", 1, height, 8, 1, "< Bank",
            { background = ui.theme.panel })
        if pages and pages > 1 then
            scene:button("prev", width - 15, height, 4, 1, "<",
                { background = ui.theme.panel, disabled = page <= 1 })
            ui.text(scene.target, width - 10, height,
                page .. "/" .. pages, ui.theme.muted)
            scene:button("next", width - 4, height, 4, 1, ">",
                { background = ui.theme.panel, disabled = page >= pages })
        end
    end

    local function heldReleaseText(hold)
        if hold.status ~= "holding" then return "Released" end
        return "Day " .. tostring(hold.release_day or "?")
            .. " " .. tostring(hold.release_time or "")
    end

    local accountIdScreen

    -- Cashing out at a kiosk ----------------------------------------------
    -- The one code a Foxy account still uses. A withdrawal is a kiosk
    -- handing you money, which is the opposite of paying, so it survived
    -- 9.4 where Code Pay did not. Paying a kiosk is Foxy Pay: stand in
    -- front of it and it finds you.
    local function withdrawScreen()
        while running() do
            local code = ui.input(target, "Cash out", {
                hint = "Withdrawal code from the kiosk",
                mode = "code", maxLength = 8,
            })
            if not code then return end
            local preview, previewError =
                request("PAY_CODE_PREVIEW", { code = code })
            if not preview then
                ui.message(target, "error", "Bad code", previewError, 2.2)
            elseif preview.kind ~= "withdrawal" then
                ui.message(target, "warning", "That is a payment",
                    "Stand at the kiosk and pay with Foxy Pay instead", 2.6)
            else
                local width, height = target.getSize()
                ui.clear(target)
                ui.header(target, "Cash out", preview.merchant,
                    util.formatClock())
                ui.card(target, 2, 5, width - 2, 6, FOX)
                ui.text(target, 4, 6, "YOU RECEIVE", ui.theme.muted,
                    ui.theme.panel)
                ui.text(target, 4, 7, money(preview.amount), INK,
                    ui.theme.panel)
                ui.wrappedText(target, 4, 9,
                    preview.description or "Kiosk withdrawal", width - 6, 2,
                    ui.theme.muted, ui.theme.panel)
                local scene = ui.scene(target)
                scene:button("take", 2, height - 5, width - 2, 2,
                    "Take " .. money(preview.amount),
                    { background = ui.theme.success,
                      foreground = colors.black })
                scene:button("back", 1, height, 8, 1, "< Bank",
                    { background = ui.theme.panel })
                local action = scene:wait({ tickRate = 5 })
                if action == "back" or action == "__terminate" then return end
                if action == "take" then
                    local pin
                    if preview.pin_required then
                        pin = ui.pin(target, "Confirm", true)
                        if not pin then return end
                    end
                    local took, takeError = request("PAY_CODE_CONFIRM",
                        { code = code, pin = pin })
                    if took then
                        api.refresh()
                        ui.message(target, "success", "Received",
                            money(preview.amount) .. " from "
                                .. preview.merchant, 1.8)
                        return
                    end
                    ui.message(target, "error", "Not taken", takeError, 2.4)
                end
            end
        end
    end

    local function historyScreen()
        local result = request("HISTORY")
        if not result then return end
        local items, page, blink = result.transactions, 1, true
        while true do
            local width, height = target.getSize()
            ui.clear(target)
            ui.header(target, "Activity", #items .. " transactions", util.formatClock(blink))
            local pageItems, actualPage, pages = util.page(items, page, 1)
            page = actualPage
            for index, tx in ipairs(pageItems) do
                local y = 4 + (index - 1) * 14
                local color = tx.amount >= 0 and ui.theme.success or ui.theme.danger
                ui.card(target, 2, y, width - 2, 14, color)
                ui.wrappedText(target, 4, y, tx.description,
                    width - 6, 11, ui.theme.ink, ui.theme.panel)
                ui.text(target, 4, y + 11, "Day " .. tx.day .. " " .. tx.time,
                    ui.theme.muted, ui.theme.panel)
                local amountText = (tx.amount >= 0 and "+" or "") .. money(tx.amount)
                ui.text(target, 4, y + 12, amountText, color, ui.theme.panel)
            end
            local scene = ui.scene(target)
            bankFooter(scene, page, pages)
            local action = scene:wait({ tickRate = 0.5 })
            blink = not blink
            if action == "back" or action == "__terminate" then return
            elseif action == "prev" then page = page - 1
            elseif action == "next" then page = page + 1 end
        end
    end

    local function betHoldingScreen(holds)
        local pending = {}
        for _, hold in ipairs(holds or {}) do
            if hold.status == "holding" then pending[#pending + 1] = hold end
        end
        local page = 1
        while true do
            local width, height = target.getSize()
            local visible, current, pages = util.page(pending, page, 2)
            page = current
            ui.clear(target)
            ui.header(target, "Holding", #pending .. " CCG payouts",
                util.formatClock())
            if #visible == 0 then
                ui.center(target, 8, "Nothing is holding", ui.theme.ink)
                ui.center(target, 10, "Wins appear here for one day",
                    ui.theme.muted)
            end
            for index, hold in ipairs(visible) do
                local y = 5 + (index - 1) * 6
                ui.card(target, 2, y, width - 2, 5, colors.purple)
                ui.text(target, 4, y, ui.truncate(
                    hold.game_name or "CCG WIN", width - 6),
                    ui.theme.muted, ui.theme.panel)
                ui.text(target, 4, y + 1, money(hold.amount),
                    ui.theme.ink, ui.theme.panel)
                ui.text(target, 4, y + 3, "UNLOCKS " .. heldReleaseText(hold),
                    ui.theme.warning, ui.theme.panel)
            end
            local scene = ui.scene(target)
            scene:button("prev", 2, height - 2, 6, 1, "<",
                { background = ui.theme.panel, disabled = page <= 1 })
            scene:button("next", width - 7, height - 2, 6, 1, ">",
                { background = ui.theme.panel, disabled = page >= pages })
            scene:button("back", 1, height, 10, 1, "< Wallet",
                { background = ui.theme.panel })
            local action = scene:wait()
            if action == "prev" then page = math.max(1, page - 1)
            elseif action == "next" then page = math.min(pages, page + 1)
            elseif action == "back" or action == "__terminate" then return end
        end
    end

    local function betActivityScreen(items)
        local page = 1
        while true do
            local width, height = target.getSize()
            local visible, current, pages = util.page(items or {}, page, 3)
            page = current
            ui.clear(target)
            ui.header(target, "Bet Activity", #items .. " entries",
                util.formatClock())
            if #visible == 0 then
                ui.center(target, 9, "No Bet Wallet activity", ui.theme.muted)
            end
            for index, item in ipairs(visible) do
                local y = 5 + (index - 1) * 4
                ui.text(target, 3, y, ui.truncate(item.description, width - 5),
                    ui.theme.ink)
                local amountText = money(math.abs(item.amount or 0))
                if (item.amount or 0) < 0 then amountText = "-" .. amountText end
                ui.text(target, 3, y + 1, amountText,
                    (item.amount or 0) >= 0 and ui.theme.success
                        or ui.theme.warning)
                ui.text(target, width - 8, y + 1,
                    "D" .. tostring(item.day or "?"), ui.theme.muted)
            end
            local scene = ui.scene(target)
            scene:button("prev", 2, height - 2, 6, 1, "<",
                { background = ui.theme.panel, disabled = page <= 1 })
            scene:button("next", width - 7, height - 2, 6, 1, ">",
                { background = ui.theme.panel, disabled = page >= pages })
            scene:button("back", 1, height, 10, 1, "< Wallet",
                { background = ui.theme.panel })
            local action = scene:wait()
            if action == "prev" then page = math.max(1, page - 1)
            elseif action == "next" then page = math.min(pages, page + 1)
            elseif action == "back" or action == "__terminate" then return end
        end
    end

    local function betWalletMove(action, available)
        local adding = action == "BET_WALLET_DEPOSIT"
        local amountText = ui.input(target,
            adding and "Add to Bet Wallet" or "Send to Foxy Account", {
                hint = "Available " .. money(available),
                mode = "number",
                maxLength = 12,
            })
        if not amountText then return nil end
        local amount = tonumber(amountText)
        if not amount or amount <= 0 then
            ui.message(target, "error", "Invalid Amount", "Enter a number above zero")
            return nil
        end
        local pin = ui.pin(target, "Confirm with PIN", true)
        if not pin then return nil end
        local result, err = request(action, { amount = amount, pin = pin }, true)
        if result then
            api.refresh()
            ui.message(target, "success",
                adding and "MONEY ADDED" or "MONEY TRANSFERRED",
                money(amount), 0.9)
            return result.wallet
        end
        ui.message(target, "error", "TRANSFER FAILED", err, 1.1)
        return nil
    end

    local function betWalletScreen()
        local result = request("BET_WALLET_SUMMARY")
        if not result then return end
        local wallet = result.wallet
        while running() do
            local width, height = target.getSize()
            ui.clear(target)
            ui.header(target, "Bet Wallet", "CCG game balance", util.formatClock())
            ui.card(target, 2, 4, width - 2, 4, colors.magenta)
            ui.text(target, 4, 4, "AVAILABLE", ui.theme.muted, ui.theme.panel)
            ui.text(target, 4, 6, money(wallet.available),
                ui.theme.ink, ui.theme.panel)
            ui.card(target, 2, 9, width - 2, 3, colors.purple)
            ui.text(target, 4, 9, "HOLDING FOR 1 DAY", ui.theme.muted,
                ui.theme.panel)
            ui.text(target, 4, 10, money(wallet.held),
                ui.theme.warning, ui.theme.panel)
            local scene = ui.scene(target)
            scene:button("add", 2, 13, 11, 2, "+ ADD",
                { background = ui.theme.success, foreground = colors.black })
            scene:button("withdraw", width - 12, 13, 11, 2, "CASH OUT",
                { background = ui.theme.accentDark })
            scene:button("holding", 2, 16, 11, 2,
                "HOLDING " .. tostring(wallet.hold_count or 0),
                { background = colors.purple })
            scene:button("activity", width - 12, 16, 11, 2, "ACTIVITY",
                { background = ui.theme.panel })
            scene:button("back", 1, height, 8, 1, "< Home",
                { background = ui.theme.panel })
            local action = scene:wait({ tickRate = 1 })
            if action == "add" then
                wallet = betWalletMove("BET_WALLET_DEPOSIT",
                    api.account().balance)
                    or wallet
            elseif action == "withdraw" then
                wallet = betWalletMove("BET_WALLET_WITHDRAW", wallet.available)
                    or wallet
            elseif action == "holding" then
                betHoldingScreen(wallet.holds)
            elseif action == "activity" then
                betActivityScreen(wallet.activity)
            elseif action == "__tick" then
                local refreshed = request("BET_WALLET_SUMMARY", {}, true)
                if refreshed then wallet = refreshed.wallet end
            elseif action == "back" or action == "__terminate" then
                return
            end
        end
    end

    local function taxDemandScreen(demand)
        while running() do
            local width, height = target.getSize()
            ui.clear(target)
            ui.header(target, "Tax demand", money(demand.amount),
                util.formatClock())
            ui.card(target, 2, 5, width - 2, 4, ui.theme.warning)
            ui.text(target, 4, 6, "OWED", ui.theme.muted, ui.theme.panel)
            ui.text(target, 4, 7, money(demand.amount), ui.theme.ink, ui.theme.panel)
            ui.wrappedText(target, 2, 10, demand.reason or "", width - 2, 4,
                ui.theme.muted)
            local scene = ui.scene(target)
            scene:button("pay", 2, height - 5, width - 2, 2,
                "Pay " .. money(demand.amount),
                { background = ui.theme.success, foreground = colors.black })
            scene:button("back", 2, height - 2, width - 2, 2, "Later",
                { background = ui.theme.panel })
            local action = scene:wait({ tickRate = 1 })
            if action == "back" or action == "__terminate" then return end
            if action == "pay" then
                local pin = ui.pin(target, "Confirm tax payment", true)
                if pin then
                    local paid = request("PAY_TAX_DEMAND", { pin = pin })
                    if paid then
                        api.refresh()
                        ui.message(target, "success", "Tax settled",
                            money(demand.amount), 1.4)
                        return
                    end
                end
            end
        end
    end

    local function bankTransferScreen(identity)
        local typed = ui.input(target, "Their Account ID", {
            hint = "16 digits from the other bank",
            mode = "number", maxLength = 19, allowSpace = true,
        })
        if not typed then return false end
        local quote, err = request("BANK_TRANSFER_QUOTE",
            { bank_account_id = typed }, true)
        if not quote then
            ui.message(target, "error", "Cannot send there", err, 2)
            return false
        end

        -- Everything moves, and this account closes behind it. Said plainly,
        -- before the PIN rather than after.
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "Move your money", quote.bank_name, util.formatClock())
        ui.card(target, 2, 5, width - 2, 7, ui.theme.warning)
        ui.text(target, 4, 5, "TO", ui.theme.muted, ui.theme.panel)
        ui.text(target, 4, 6, ui.truncate(quote.name, width - 6),
            ui.theme.ink, ui.theme.panel)
        ui.text(target, 4, 7, ui.truncate(quote.bank_name, width - 6),
            ui.theme.muted, ui.theme.panel)
        ui.text(target, 4, 9, "AMOUNT", ui.theme.muted, ui.theme.panel)
        ui.text(target, 4, 10, money(quote.amount), ui.theme.ink, ui.theme.panel)
        ui.wrappedText(target, 2, 13, "All of it goes, and your Bank here closes"
            .. " until you transfer money back.", width - 2, 3, ui.theme.muted)
        local scene = ui.scene(target)
        scene:button("go", 2, height - 5, width - 2, 2, "Move it all",
            { background = ui.theme.danger })
        scene:button("no", 2, height - 2, width - 2, 2, "Keep it here",
            { background = ui.theme.panel })
        if scene:wait({ tickRate = 5 }) ~= "go" then return false end

        local pin = ui.pin(target, "Confirm with PIN", true)
        if not pin then return false end
        local moved, moveError, code = request("BANK_TRANSFER_CONFIRM", {
            bank_account_id = quote.bank_account_id, pin = pin,
        }, true)
        if not moved then
            ui.message(target, code == "TRANSFER_PENDING" and "warning" or "error",
                code == "TRANSFER_PENDING" and "Held safely" or "Not moved",
                moveError, 2.4)
            return false
        end
        ui.message(target, "success", "Moved to " .. moved.bank_name,
            money(moved.moved) .. " transferred", 2)
        api.refresh()
        return true
    end

    accountIdScreen = function()
        while running() do
            local width, height = target.getSize()
            local identity = request("BANK_IDENTITY", {}, true)
            if not identity then return end
            ui.clear(target)
            ui.header(target, "Account ID", identity.bank_name,
                util.formatClock())
            ui.card(target, 2, 5, width - 2, 5, ui.theme.accent)
            ui.text(target, 4, 5, "YOUR ACCOUNT ID", ui.theme.muted,
                ui.theme.panel)
            -- Two halves on a narrow screen, so all sixteen digits are readable
            -- rather than trailing off into an ellipsis.
            ui.text(target, 4, 7, identity.formatted:sub(1, 9),
                ui.theme.ink, ui.theme.panel)
            ui.text(target, 4, 8, identity.formatted:sub(11),
                ui.theme.ink, ui.theme.panel)
            ui.wrappedText(target, 2, 11, "Give this to another bank to have"
                .. " money sent here. It works at every bank on the network.",
                width - 2, 4, ui.theme.muted)
            local scene = ui.scene(target)
            if identity.bank_closed then
                ui.wrappedText(target, 2, 15, "Your money is at "
                    .. tostring(identity.moved_to_name or "another bank")
                    .. ". Transfer it back from there.", width - 2, 3,
                    ui.theme.warning)
            else
                scene:button("move", 2, height - 5, width - 2, 2,
                    "Move my money to another bank",
                    { background = ui.theme.warning, foreground = colors.black })
            end
            scene:button("back", 1, height, 8, 1, "< Back",
                { background = ui.theme.panel })
            local action = scene:wait({ tickRate = 5 })
            if action == "back" or action == "__terminate" then return end
            if action == "move" then
                if bankTransferScreen(identity) then return end
            end
        end
    end

    local function bankScreen()
        local offset, shimmered = 0, false
        while running() do
            -- An account whose money has moved to another bank keeps its
            -- Foxy identity and its friends, but there is nothing here to
            -- show. Say where it went, and offer the way back.
            local here = api.account()
            if here.bank_closed then
                local width, height = target.getSize()
                ui.clear(target)
                ui.header(target, "Foxy Bank", "Closed", util.formatClock())
                ui.card(target, 2, 5, width - 2, 6, ui.theme.warning)
                ui.wrappedText(target, 4, 6, "Your money is at "
                    .. tostring(here.moved_to_name or "another bank") .. ".",
                    width - 6, 3, ui.theme.ink, ui.theme.panel)
                ui.wrappedText(target, 4, 9, "Transfer it back from there to"
                    .. " use this account again.", width - 6, 2,
                    ui.theme.muted, ui.theme.panel)
                local closed = ui.scene(target)
                closed:button("id", 2, height - 5, width - 2, 2,
                    "Show my Account ID", { background = ui.theme.panel })
                closed:button("back", 1, height, 8, 1, "< Foxy",
                    { background = ui.theme.panel })
                local closedAction = closed:wait({ tickRate = 5 })
                if closedAction == "id" then accountIdScreen() else return end
            else
            local overview = request("FOXY_OVERVIEW", {}, true)
            if not overview then return end
            local width, height = target.getSize()
            ui.clear(target)
            ui.header(target, "Foxy Bank", overview.name, util.formatClock())
            drawCard(overview, 4)
            if not shimmered then
                shimmer(2, 4, width - 2, 6)
                drawCard(overview, 4)
                shimmered = true
            end
            ui.text(target, 2, 11, "BALANCE", ui.theme.muted)
            ui.text(target, 2, 12, money(overview.balance), INK)
            if overview.saved > 0 then
                local saved = "SAVED " .. money(overview.saved)
                ui.text(target, math.max(2, width - #saved), 12, saved,
                    ui.theme.muted)
            end

            -- One scrolling column: your accounts, then a way to make
            -- another, then Foxy Cash at the bottom.
            local rows = { { kind = "main", name = "Main account",
                balance = overview.balance } }
            for _, pot in ipairs(overview.pots) do
                rows[#rows + 1] = { kind = "pot", pot = pot,
                    name = pot.name, balance = pot.balance }
            end
            rows[#rows + 1] = { kind = "new" }
            rows[#rows + 1] = { kind = "cash" }
            rows[#rows + 1] = { kind = "wallet" }
            rows[#rows + 1] = { kind = "activity" }
            rows[#rows + 1] = { kind = "cashout" }
            rows[#rows + 1] = { kind = "id" }
            -- A tax demand is not a menu item you can ignore: it comes
            -- first, and while one is open the account cannot spend.
            local demand = request("TAX_DEMAND_STATUS", {}, true)
            demand = demand and demand.demand or nil
            if demand then
                table.insert(rows, 1, { kind = "demand", demand = demand })
            end
            local perView = 3
            offset = math.max(0, math.min(offset, #rows - perView))
            local scene = ui.scene(target)
            for slot = 1, perView do
                local row = rows[offset + slot]
                if row then
                    local y = 14 + (slot - 1) * 2
                    if row.kind == "new" then
                        scene:button("new", 2, y, width - 2, 2,
                            "+  New account",
                            { background = ui.theme.panel })
                    elseif row.kind == "cash" then
                        scene:button("cash", 2, y, width - 2, 2,
                            "Foxy Cash  "
                                .. math.floor(overview.fee_rate * 100)
                                .. "%  friends",
                            { background = FOX, foreground = colors.black })
                    elseif row.kind == "demand" then
                        scene:button("demand", 2, y, width - 2, 2,
                            "Tax demand  " .. money(row.demand.amount),
                            { background = ui.theme.warning,
                              foreground = colors.black })
                    elseif row.kind == "wallet" then
                        scene:button("wallet", 2, y, width - 2, 2,
                            "Bet Wallet", { background = colors.purple })
                    elseif row.kind == "activity" then
                        scene:button("activity", 2, y, width - 2, 2,
                            "Activity", { background = ui.theme.panel })
                    elseif row.kind == "cashout" then
                        scene:button("cashout", 2, y, width - 2, 2,
                            "Cash out with a code",
                            { background = ui.theme.panel })
                    elseif row.kind == "id" then
                        scene:button("id", 2, y, width - 2, 2,
                            "Account ID + Transfer",
                            { background = ui.theme.accentDark })
                    else
                        scene:button(row.kind == "main" and "main"
                            or ("pot:" .. row.pot.pot_id), 2, y,
                            width - 2, 2,
                            ui.truncate(row.name, width - 11)
                                .. "\n" .. money(row.balance),
                            { background = ui.theme.panel })
                    end
                end
            end
            scene:button("up", width - 8, height, 3, 1, "^",
                { background = ui.theme.panel, disabled = offset <= 0 })
            scene:button("down", width - 4, height, 3, 1, "v",
                { background = ui.theme.panel,
                  disabled = offset + perView >= #rows })
            scene:button("back", 1, height, 8, 1, "< Foxy",
                { background = ui.theme.panel })
            local action = scene:wait({ tickRate = 5 })
            if action == "back" or action == "__terminate" then return
            elseif action == "up" then offset = offset - 1
            elseif action == "down" then offset = offset + 1
            elseif action == "cash" then foxyCash(overview)
            elseif action == "demand" then taxDemandScreen(demand)
            elseif action == "wallet" then betWalletScreen()
            elseif action == "activity" then historyScreen()
            elseif action == "cashout" then withdrawScreen()
            elseif action == "id" then accountIdScreen()
            elseif action == "main" then
                moveMoney(overview, "main", "Main account", overview.balance)
            elseif action == "new" then
                local name = ui.input(target, "New account", {
                    hint = "Savings, Rent, Holiday...",
                    maxLength = 18, allowSpace = true, minLength = 2,
                })
                if name then
                    local made, err = request("FOXY_POT_CREATE",
                        { name = name }, true)
                    if made then
                        ui.message(target, "success", "Account opened",
                            name, 1.1)
                    else
                        ui.message(target, "error", "Not opened", err, 1.6)
                    end
                end
            else
                local potId = action and action:match("^pot:(.+)$")
                for _, pot in ipairs(overview.pots) do
                    if pot.pot_id == potId then
                        potScreen(overview, pot)
                        break
                    end
                end
            end
            end
        end
    end

    -- Your account ------------------------------------------------------------

    local function accountScreen()
        while running() do
            local account = api.account()
            local width, height = target.getSize()
            ui.clear(target)
            ui.header(target, "Your Account", account.name, util.formatClock())
            ui.card(target, 2, 5, width - 2, 6, FOX)
            ui.text(target, 4, 5, "FOXY ACCOUNT", ui.theme.muted, ui.theme.panel)
            ui.text(target, 4, 6, ui.truncate(account.name, width - 6),
                INK, ui.theme.panel)
            ui.text(target, 4, 8, "ID  " .. tostring(account.account_id),
                ui.theme.muted, ui.theme.panel)
            ui.text(target, 4, 9, "NO  " .. tostring(account.personal_number),
                ui.theme.muted, ui.theme.panel)
            local scene = ui.scene(target)
            scene:button("name", 2, 12, width - 2, 2, "Change your name",
                { background = ui.theme.panel })
            scene:button("pin", 2, 14, width - 2, 2, "Change your PIN",
                { background = ui.theme.panel })
            ui.wrappedText(target, 2, 17, "More coming to your account soon.",
                width - 2, 2, ui.theme.muted)
            scene:button("back", 1, height, 8, 1, "< Foxy",
                { background = ui.theme.panel })
            local action = scene:wait({ tickRate = 5 })
            if action == "back" or action == "__terminate" then return end
            if action == "name" then
                local name = ui.input(target, "Change your name", {
                    hint = "2-20 characters", initial = account.name,
                    maxLength = 20, allowSpace = true, minLength = 2,
                })
                if name then
                    local pin = ui.pin(target, "Confirm with PIN", true)
                    if pin then
                        local ok, err = request("FOXY_SET_ACCOUNT",
                            { name = name, pin = pin }, true)
                        if ok then
                            api.refresh()
                            ui.message(target, "success", "Name changed",
                                name, 1.2)
                        else
                            ui.message(target, "error", "Not changed",
                                err, 1.6)
                        end
                    end
                end
            elseif action == "pin" then
                local current = ui.pin(target, "Your current PIN", true)
                if current then
                    local fresh = ui.pin(target, "Your new PIN", true)
                    if fresh then
                        local again = ui.pin(target, "Repeat new PIN", true)
                        if again ~= fresh then
                            ui.message(target, "error", "PINs do not match",
                                "Nothing changed", 1.4)
                        else
                            local ok, err = request("FOXY_SET_ACCOUNT",
                                { pin = current, new_pin = fresh }, true)
                            ui.message(target, ok and "success" or "error",
                                ok and "PIN changed" or "Not changed",
                                ok and "Use it from now on" or err, 1.4)
                        end
                    end
                end
            end
        end
    end

    -- Home --------------------------------------------------------------------

    ui.clear(target)
    sweepIn("FOXY", 8, FOX)
    sweepIn("small bank, big vault", 10, ui.theme.muted)
    sleep(0.5)

    while running() do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "Foxy", api.account().name, util.formatClock())
        ui.center(target, 5, "FOXY", FOX, ui.theme.background)
        local scene = ui.scene(target)
        scene:button("bank", 2, 8, width - 2, 4, "Bank\nBalance, accounts, cash",
            { background = FOX, foreground = colors.black, shadow = true })
        scene:button("account", 2, 13, width - 2, 4,
            "Account\nYour details", { background = ui.theme.panel,
                shadow = true })
        scene:button("back", 1, height, 8, 1, "< Home",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 5 })
        if action == "back" or action == "__terminate" then return end
        if action == "bank" then bankScreen()
        elseif action == "account" then accountScreen() end
    end
end
