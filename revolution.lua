-- PUMPE BANK APP: Revolution
-- PUMPE BANK CLEARING: 1
-- PUMPE BANK FEE: 0
--
-- A bank for people who take money on their phone.
--
-- The three lines above are the whole of how a bank registers itself and its
-- terms. A 3rd Party Bank Server reads them and enforces them: no fee on
-- anything, and one in-game hour before money is spendable. Revolution is
-- slower than Foxy on purpose and free where Foxy charges ten per cent --
-- which is the trade it offers somebody taking payments all day.
--
-- Take is the reason the app exists. Open a charge, hold the phone out, and
-- whoever is standing in front of you pays it from theirs.

return function(api)
    local ui, util, target = api.ui, api.util, api.target
    local colors, money = api.colors, api.money

    local REVO = colors.purple
    local session, me

    local function running() return api.running() end
    local function ask(action, payload) return api.bank(action, payload or {}) end

    local function refresh()
        if not session then return nil end
        local summary = ask("TPB_SUMMARY", { session_token = session })
        if summary then me = summary.account end
        return me
    end

    -- Signing in ---------------------------------------------------------------

    local function signIn(opening)
        local name = ui.input(target, opening and "New account name"
            or "Your Revolution name", {
            hint = opening and "The name people will pay"
                or "The name you bank under",
            maxLength = 20, allowSpace = true, minLength = 2,
        })
        if not name then return false end
        local pin = ui.pin(target, opening and "Choose a PIN" or "Your PIN",
            true)
        if not pin then return false end
        if opening and ui.pin(target, "Repeat it", true) ~= pin then
            ui.message(target, "error", "PINs do not match", nil, 1.4)
            return false
        end
        local result, err = ask(opening and "TPB_REGISTER" or "TPB_LOGIN",
            { name = name, pin = pin })
        if not result then
            ui.message(target, "error", opening and "Not opened"
                or "Not signed in", err, 2)
            return false
        end
        session, me = result.session_token, result.account
        return true
    end

    local function welcome()
        while running() and not session do
            local width, height = target.getSize()
            local info = ask("TPB_INFO")
            ui.clear(target)
            ui.header(target, "Revolution", info and "Take payments free"
                or "Offline", util.formatClock())
            if not info then
                ui.center(target, 8, "No Revolution bank", ui.theme.ink)
                ui.wrappedText(target, 2, 10, "Nobody is running a Revolution"
                    .. " Bank Server. Set one up from Easy Deployment: BANK"
                    .. " SERVER, then 3RD PARTY.", width - 2, 5,
                    ui.theme.muted)
            else
                ui.card(target, 2, 5, width - 2, 5, REVO)
                ui.text(target, 4, 6, "0% FEES", ui.theme.ink, ui.theme.panel)
                ui.wrappedText(target, 4, 7, "Take payments in person for"
                    .. " nothing. Money clears in one hour.", width - 6, 3,
                    ui.theme.muted, ui.theme.panel)
                ui.wrappedText(target, 2, 11, "Move money in from Foxy with"
                    .. " your Account ID.", width - 2, 3, ui.theme.muted)
            end
            local scene = ui.scene(target)
            if info then
                scene:button("open", 2, height - 5, width - 2, 2,
                    "Open an account",
                    { background = REVO, foreground = colors.white })
                scene:button("in", 2, height - 2, width - 2, 2, "Sign in",
                    { background = ui.theme.panel })
            end
            scene:button("back", 1, height, 8, 1, "< Home",
                { background = ui.theme.panel })
            local action = scene:wait({ tickRate = 5 })
            if action == "back" or action == "__terminate" then return false end
            if action == "open" then signIn(true)
            elseif action == "in" then signIn(false) end
        end
        return session ~= nil
    end

    -- Taking a payment ------------------------------------------------------------
    -- The reason for the app. Open a charge and wait; the Bank Server tells
    -- whoever is standing nearby that it is there.

    local function takeScreen()
        local raw = ui.input(target, "Amount to take", {
            hint = "They pay this, you keep all of it",
            mode = "number", maxLength = 9,
        })
        local amount = tonumber(raw)
        if not amount or amount <= 0 then return end
        local note = ui.input(target, "What for", {
            hint = "Optional", maxLength = 30, allowSpace = true,
        })
        local position = api.position()
        if not position then
            ui.message(target, "error", "No position",
                "This needs GPS anchors on the network", 2.2)
            return
        end
        local opened, err = ask("TPB_CHARGE_OPEN", {
            session_token = session, amount = amount, note = note or "",
            position = position,
        })
        if not opened then
            ui.message(target, "error", "Not opened", err, 2)
            return
        end

        local chargeId = opened.charge.charge_id
        local frame = 0
        while running() do
            local width, height = target.getSize()
            local status = ask("TPB_CHARGE_STATUS", {
                session_token = session, charge_id = chargeId })
            if not status then
                ui.message(target, "warning", "Charge ended",
                    "It was not paid", 1.6)
                return
            end
            local charge = status.charge
            if charge.status == "paid" then
                ui.message(target, "success", "Paid by " .. charge.paid_by,
                    charge.clears and ("Clears day " .. charge.clears.day
                        .. " " .. charge.clears.time)
                        or money(charge.amount), 2.4)
                refresh()
                return
            end
            ui.clear(target)
            ui.header(target, "Waiting", money(amount), util.formatClock())
            ui.card(target, 2, 5, width - 2, 5, REVO)
            ui.center(target, 6, money(amount), ui.theme.ink, ui.theme.panel)
            ui.center(target, 8, ("."):rep(frame % 4 + 1), ui.theme.muted,
                ui.theme.panel)
            ui.wrappedText(target, 2, 11, "Hold your PUMPE out. Whoever is"
                .. " standing next to you can pay it from Revolution.",
                width - 2, 4, ui.theme.muted)
            ui.text(target, 2, 16, "0% fee", REVO)
            local scene = ui.scene(target)
            scene:button("cancel", 2, height - 2, width - 2, 2, "Cancel",
                { background = ui.theme.danger })
            local action = scene:wait({ tickRate = 1 })
            frame = frame + 1
            if action == "cancel" or action == "__terminate" then
                ask("TPB_CHARGE_CANCEL", { session_token = session,
                    charge_id = chargeId })
                return
            end
        end
    end

    -- Paying somebody --------------------------------------------------------------

    local function payScreen()
        local position = api.position()
        if not position then
            ui.message(target, "error", "No position",
                "This needs GPS anchors on the network", 2.2)
            return
        end
        while running() do
            local width, height = target.getSize()
            local found = ask("TPB_CHARGE_NEARBY", {
                session_token = session, position = position })
            local charge = found and found.charge
            ui.clear(target)
            ui.header(target, "Pay", charge and "Someone nearby"
                or "Nobody nearby", util.formatClock())
            local scene = ui.scene(target)
            if charge then
                ui.card(target, 2, 5, width - 2, 6, REVO)
                ui.text(target, 4, 6, ui.truncate(charge.to_name, width - 6),
                    ui.theme.ink, ui.theme.panel)
                ui.text(target, 4, 8, money(charge.amount), ui.theme.ink,
                    ui.theme.panel)
                ui.text(target, 4, 9, ui.truncate(charge.note ~= ""
                    and charge.note or "No note", width - 6),
                    ui.theme.muted, ui.theme.panel)
                ui.text(target, 4, 10, charge.distance
                    .. " blocks away", ui.theme.muted, ui.theme.panel)
                scene:button("pay", 2, height - 5, width - 2, 2,
                    "Pay " .. money(charge.amount),
                    { background = ui.theme.success,
                      foreground = colors.black })
            else
                ui.center(target, 9, "Nothing to pay", ui.theme.ink)
                ui.wrappedText(target, 2, 11, "Stand next to somebody taking"
                    .. " a payment on Revolution.", width - 2, 4,
                    ui.theme.muted)
            end
            scene:button("again", 2, height - 2, width - 2, 2, "Look again",
                { background = ui.theme.panel })
            scene:button("back", 1, height, 8, 1, "< Back",
                { background = ui.theme.panel })
            local action = scene:wait({ tickRate = 2 })
            if action == "back" or action == "__terminate" then return end
            if action == "pay" and charge then
                local pin = ui.pin(target, "Pay " .. money(charge.amount),
                    true)
                if pin then
                    local paid, err = ask("TPB_CHARGE_PAY", {
                        session_token = session,
                        charge_id = charge.charge_id, pin = pin })
                    if paid then
                        ui.message(target, "success", "Paid",
                            money(paid.paid) .. " to " .. charge.to_name, 1.6)
                        refresh()
                        return
                    end
                    ui.message(target, "error", "Not paid", err, 2)
                end
            end
        end
    end

    -- Everything else ----------------------------------------------------------------

    local function pendingScreen()
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "Clearing", money(me.pending), util.formatClock())
        ui.wrappedText(target, 2, 5, "Money at Revolution takes one in-game"
            .. " hour to become spendable.", width - 2, 3, ui.theme.muted)
        local row = 9
        for _, item in ipairs(me.pending_items or {}) do
            if row > height - 3 then break end
            ui.text(target, 2, row, ui.truncate(money(item.amount) .. "  "
                .. (item.description or ""), width - 3), ui.theme.ink)
            ui.text(target, 2, row + 1, "Clears day " .. tostring(item.clears_day)
                .. " " .. tostring(item.clears_time), ui.theme.muted)
            row = row + 3
        end
        if (me.pending_count or 0) == 0 then
            ui.center(target, 10, "Nothing waiting", ui.theme.muted)
        end
        local scene = ui.scene(target)
        scene:button("back", 1, height, 8, 1, "< Back",
            { background = ui.theme.panel })
        scene:wait({ tickRate = 5 })
    end

    local function transferOut()
        local typed = ui.input(target, "Their Account ID", {
            hint = "16 digits, any bank", mode = "number", maxLength = 19,
            allowSpace = true,
        })
        if not typed then return end
        local quote, err = ask("TPB_TRANSFER_QUOTE", {
            session_token = session, bank_account_id = typed })
        if not quote then
            ui.message(target, "error", "Cannot send there", err, 2)
            return
        end
        if not ui.confirm(target, "Move " .. money(quote.amount),
            "All cleared money goes to " .. quote.name .. " at "
                .. quote.bank_name .. ".", "Move it", "Keep") then
            return
        end
        local pin = ui.pin(target, "Confirm with PIN", true)
        if not pin then return end
        local moved, moveError, code = ask("TPB_TRANSFER_CONFIRM", {
            session_token = session, bank_account_id = quote.bank_account_id,
            pin = pin })
        if not moved then
            ui.message(target,
                code == "TRANSFER_PENDING" and "warning" or "error",
                code == "TRANSFER_PENDING" and "Held safely" or "Not moved",
                moveError, 2.4)
            return
        end
        ui.message(target, "success", "Moved to " .. moved.bank_name,
            money(moved.moved) .. " transferred", 2)
        refresh()
    end

    local function accountIdScreen()
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "Account ID", "Revolution", util.formatClock())
        ui.card(target, 2, 5, width - 2, 5, ui.theme.accent)
        ui.text(target, 4, 5, "YOUR ACCOUNT ID", ui.theme.muted, ui.theme.panel)
        ui.text(target, 4, 7, me.formatted:sub(1, 9), ui.theme.ink,
            ui.theme.panel)
        ui.text(target, 4, 8, me.formatted:sub(11), ui.theme.ink,
            ui.theme.panel)
        ui.wrappedText(target, 2, 11, "Give this to Foxy, or any other bank,"
            .. " to move money here.", width - 2, 4, ui.theme.muted)
        local scene = ui.scene(target)
        scene:button("back", 1, height, 8, 1, "< Back",
            { background = ui.theme.panel })
        scene:wait({ tickRate = 5 })
    end

    -- The app ------------------------------------------------------------------------

    if not welcome() then return end

    while running() and session do
        local width, height = target.getSize()
        if not refresh() then
            ui.message(target, "error", "Revolution offline",
                "Its Bank Server stopped answering", 2)
            return
        end
        ui.clear(target)
        ui.header(target, "Revolution", me.name, util.formatClock())
        ui.card(target, 2, 5, width - 2, 4, REVO)
        ui.text(target, 4, 5, "AVAILABLE", ui.theme.muted, ui.theme.panel)
        ui.text(target, 4, 6, money(me.balance), ui.theme.ink, ui.theme.panel)
        ui.text(target, 4, 7, ui.truncate((me.pending or 0) > 0
            and (money(me.pending) .. " clearing") or "Nothing clearing",
            width - 6), ui.theme.muted, ui.theme.panel)
        local scene = ui.scene(target)
        scene:button("take", 2, 10, width - 2, 3, "Take a payment\n0% fee",
            { background = REVO, foreground = colors.white })
        local half = math.floor((width - 3) / 2)
        scene:button("pay", 2, 14, half, 2, "Pay",
            { background = ui.theme.success, foreground = colors.black })
        scene:button("clearing", 3 + half, 14, width - 3 - half, 2,
            "Clearing", { background = ui.theme.panel })
        scene:button("id", 2, 17, half, 2, "My ID",
            { background = ui.theme.panel })
        scene:button("move", 3 + half, 17, width - 3 - half, 2, "Move out",
            { background = ui.theme.warning, foreground = colors.black })
        scene:button("back", 1, height, 8, 1, "< Home",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 5 })
        if action == "back" or action == "__terminate" then return end
        if action == "take" then takeScreen()
        elseif action == "pay" then payScreen()
        elseif action == "clearing" then pendingScreen()
        elseif action == "id" then accountIdScreen()
        elseif action == "move" then transferOut() end
    end
end
