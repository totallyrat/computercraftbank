-- PUMPE BANK APP: BuckApp
--
-- BuckApp used to be the icon on every PUMPE. In 9.0 it left the home screen
-- and became a bank of its own: its own server, its own accounts, its own
-- logins. Nothing here touches your Foxy Account.
--
-- The line at the top of this file is the whole of how a bank app registers
-- itself. A 3rd Party Bank Server reads it, lists BuckApp as something it
-- could host, and hosts it when told to.
--
-- Everything below talks to that server through api.bank, which can only
-- reach the server hosting this app.

return function(api)
    local ui, util, target = api.ui, api.util, api.target
    local colors, money = api.colors, api.money

    local BUCK = colors.green
    local session, me

    local function running() return api.running() end

    local function ask(action, payload)
        local result, err, code = api.bank(action, payload or {})
        return result, err, code
    end

    -- Signing in ---------------------------------------------------------------
    -- Its own name and PIN. A Foxy Account is not a BuckApp account, which is
    -- rather the point of banking somewhere else.

    local function refresh()
        if not session then return nil end
        local summary = ask("TPB_SUMMARY", { session_token = session })
        if summary then me = summary.account end
        return me
    end

    local function signIn(opening)
        local name = ui.input(target, opening and "New account name"
            or "Your BuckApp name", {
            hint = opening and "Not your Foxy name unless you want it"
                or "The name you bank here under",
            maxLength = 20, allowSpace = true, minLength = 2,
        })
        if not name then return false end
        local pin = ui.pin(target, opening and "Choose a BuckApp PIN"
            or "Your BuckApp PIN", true)
        if not pin then return false end
        if opening then
            local again = ui.pin(target, "Repeat it", true)
            if again ~= pin then
                ui.message(target, "error", "PINs do not match", nil, 1.4)
                return false
            end
        end
        local result, err = ask(opening and "TPB_REGISTER" or "TPB_LOGIN",
            { name = name, pin = pin })
        if not result then
            ui.message(target, "error", opening and "Not opened"
                or "Not signed in", err, 2)
            return false
        end
        session, me = result.session_token, result.account
        ui.message(target, "success", opening and "Account opened"
            or "Welcome back", me.name, 1)
        return true
    end

    local function welcome()
        while running() and not session do
            local width, height = target.getSize()
            local info = ask("TPB_INFO")
            ui.clear(target)
            ui.header(target, "BuckApp", info and info.bank_name
                or "Offline", util.formatClock())
            if not info then
                ui.center(target, 8, "No BuckApp bank", ui.theme.ink)
                ui.wrappedText(target, 2, 10, "Nobody is running a BuckApp"
                    .. " Bank Server. Set one up from Easy Deployment:"
                    .. " BANK SERVER, then 3RD PARTY.", width - 2, 5,
                    ui.theme.muted)
            else
                ui.card(target, 2, 5, width - 2, 4, BUCK)
                ui.text(target, 4, 6, "BANK " .. tostring(info.bank_code),
                    ui.theme.muted, ui.theme.panel)
                ui.text(target, 4, 7, info.accounts .. " accounts here",
                    ui.theme.ink, ui.theme.panel)
                ui.wrappedText(target, 2, 10, "A bank of its own, with its"
                    .. " own login. Move money in from Foxy with your"
                    .. " Account ID.", width - 2, 4, ui.theme.muted)
            end
            local scene = ui.scene(target)
            if info then
                scene:button("open", 2, height - 5, width - 2, 2,
                    "Open an account",
                    { background = BUCK, foreground = colors.black })
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

    -- Money ---------------------------------------------------------------------

    local function sendMoney()
        local name = ui.input(target, "Send to", {
            hint = "Their BuckApp name", maxLength = 20, allowSpace = true,
        })
        if not name then return end
        local raw = ui.input(target, "Amount", { mode = "number",
            maxLength = 9 })
        local amount = tonumber(raw)
        if not amount or amount <= 0 then return end
        local pin = ui.pin(target, "Confirm with PIN", true)
        if not pin then return end
        local sent, err = ask("TPB_SEND", { session_token = session,
            recipient = name, amount = amount, pin = pin })
        if not sent then
            ui.message(target, "error", "Not sent", err, 2)
            return
        end
        ui.message(target, "success", "Sent", money(amount)
            .. " to " .. name, 1.2)
        refresh()
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
            "All of it goes to " .. quote.name .. " at " .. quote.bank_name
                .. ".", "Move it", "Keep") then
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

    local function historyScreen()
        local offset = 0
        while running() do
            local width, height = target.getSize()
            local listed = ask("TPB_HISTORY", { session_token = session })
            local items = listed and listed.transactions or {}
            ui.clear(target)
            ui.header(target, "Activity", #items .. " entries",
                util.formatClock())
            local perView = math.max(1, math.floor((height - 6) / 2))
            offset = math.max(0, math.min(offset,
                math.max(0, #items - perView)))
            if #items == 0 then
                ui.center(target, 9, "Nothing yet", ui.theme.muted)
            end
            for slot = 1, perView do
                local item = items[offset + slot]
                if not item then break end
                local y = 4 + (slot - 1) * 2
                ui.text(target, 2, y,
                    ui.truncate(item.counterparty or "-", width - 3),
                    ui.theme.ink)
                ui.text(target, 2, y + 1,
                    ui.truncate(money(item.amount) .. "  " .. (item.time or ""),
                        width - 3),
                    (item.amount or 0) < 0 and ui.theme.muted or BUCK)
            end
            local scene = ui.scene(target)
            if #items > perView then
                scene:button("up", width - 7, height, 3, 1, "^",
                    { background = ui.theme.panel, disabled = offset <= 0 })
                scene:button("down", width - 3, height, 3, 1, "v",
                    { background = ui.theme.panel,
                      disabled = offset + perView >= #items })
            end
            scene:button("back", 1, height, 8, 1, "< Back",
                { background = ui.theme.panel })
            local action = scene:wait({ tickRate = 5 })
            if action == "back" or action == "__terminate" then return end
            if action == "up" then offset = offset - perView
            elseif action == "down" then offset = offset + perView end
        end
    end

    local function accountIdScreen()
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "Account ID", me.bank_name, util.formatClock())
        ui.card(target, 2, 5, width - 2, 5, ui.theme.accent)
        ui.text(target, 4, 5, "YOUR ACCOUNT ID", ui.theme.muted, ui.theme.panel)
        ui.text(target, 4, 7, me.formatted:sub(1, 9), ui.theme.ink,
            ui.theme.panel)
        ui.text(target, 4, 8, me.formatted:sub(11), ui.theme.ink,
            ui.theme.panel)
        ui.wrappedText(target, 2, 11, "Give this to Foxy, or any other bank,"
            .. " to have money sent here.", width - 2, 4, ui.theme.muted)
        local scene = ui.scene(target)
        scene:button("back", 1, height, 8, 1, "< Back",
            { background = ui.theme.panel })
        scene:wait({ tickRate = 5 })
    end

    -- The app ---------------------------------------------------------------------

    if not welcome() then return end

    while running() and session do
        local width, height = target.getSize()
        if not refresh() then
            ui.message(target, "error", "BuckApp offline",
                "Its Bank Server stopped answering", 2)
            return
        end
        ui.clear(target)
        ui.header(target, "BuckApp", me.name, util.formatClock())
        ui.card(target, 2, 5, width - 2, 4, BUCK)
        ui.text(target, 4, 5, "BALANCE", ui.theme.muted, ui.theme.panel)
        ui.text(target, 4, 6, money(me.balance), ui.theme.ink, ui.theme.panel)
        ui.text(target, 4, 7, ui.truncate("ID " .. me.formatted, width - 6),
            ui.theme.muted, ui.theme.panel)
        if (me.balance or 0) == 0 then
            ui.wrappedText(target, 2, 10, "Empty. Move money here from Foxy"
                .. " using the Account ID above.", width - 2, 3,
                ui.theme.muted)
        end
        local scene = ui.scene(target)
        local half = math.floor((width - 3) / 2)
        scene:button("send", 2, 13, half, 2, "Send",
            { background = BUCK, foreground = colors.black })
        scene:button("history", 3 + half, 13, width - 3 - half, 2, "Activity",
            { background = ui.theme.panel })
        scene:button("id", 2, 16, half, 2, "My ID",
            { background = ui.theme.panel })
        scene:button("move", 3 + half, 16, width - 3 - half, 2, "Move out",
            { background = ui.theme.warning, foreground = colors.black })
        scene:button("out", 2, height - 1, 12, 1, "Sign out",
            { background = ui.theme.panel })
        scene:button("back", width - 9, height - 1, 9, 1, "< Home",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 5 })
        if action == "back" or action == "__terminate" then return end
        if action == "send" then sendMoney()
        elseif action == "history" then historyScreen()
        elseif action == "id" then accountIdScreen()
        elseif action == "move" then transferOut()
        elseif action == "out" then session, me = nil, nil return end
    end
end
