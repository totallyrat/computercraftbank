local ROOT = fs.getDir(shell.getRunningProgram())
if ROOT == "" then ROOT = "." end
package.path = package.path .. ";" .. fs.combine(ROOT, "?.lua")
    .. ";" .. fs.combine(ROOT, "?/init.lua")

local config = require("config")
local util = require("lib.util")
local net = require("lib.net")
local ui = require("lib.ui")

local target = term.current()
local client = net.client(config)
local sessionToken
local account
local running = true
local deviceFile = fs.combine(ROOT, "pumpe_device.dat")
local device = util.loadTable(deviceFile, { last_name = "" })

local function request(action, payload, silent)
    payload = payload or {}
    if sessionToken and not payload.session_token then
        payload.session_token = sessionToken
    end
    local result, err, code = client:request(action, payload)
    if not result and not silent then
        if code == "SESSION_EXPIRED" then
            sessionToken, account = nil, nil
        end
        ui.networkError(target, err)
    end
    return result, err, code
end

local function saveDevice()
    util.saveTable(deviceFile, device)
end

local function money(value)
    return util.money(value, config.currency)
end

local function refreshSummary(silent)
    local result = request("ACCOUNT_SUMMARY", {}, silent)
    if result then account = result.account end
    return result
end

local function pageFooter(scene, page, pages)
    local width, height = scene.width, scene.height
    scene:button("back", 1, height, 7, 1, "< BACK",
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

local function login()
    local name = ui.input(target, "SIGN IN", {
        hint = "PUMPE account name",
        initial = device.last_name,
        maxLength = 20,
        allowSpace = true,
    })
    if not name then return false end
    local pin = ui.pin(target, "ACCOUNT PIN", true)
    if not pin then return false end
    local result, err = client:request("LOGIN", { name = name, pin = pin })
    if not result then
        ui.message(target, "error", "SIGN IN FAILED", err, 1.1)
        return false
    end
    sessionToken = result.session_token
    account = result.account
    device.last_name = account.name
    saveDevice()
    ui.message(target, "success", "WELCOME BACK", account.name, 0.65)
    return true
end

local function chooseGender()
    local width, height = target.getSize()
    while true do
        ui.clear(target)
        ui.header(target, "CREATE ACCOUNT", "How should PUMPE address you?")
        local scene = ui.scene(target)
        local labels = { "She / her", "He / him", "They / them", "Prefer not to say" }
        local startY = 6
        for index, label in ipairs(labels) do
            scene:button("gender:" .. label, 3, startY + (index - 1) * 3,
                width - 5, 2, label, {
                    background = index == 3 and ui.theme.accentDark or ui.theme.panel,
                })
        end
        scene:button("back", 2, height, 7, 1, "< BACK",
            { background = ui.theme.panel })
        local action = scene:wait()
        if action == "back" or action == "__terminate" then return nil end
        local gender = action and action:match("^gender:(.+)$")
        if gender then return gender end
    end
end

local function createAccount()
    local name = ui.input(target, "NEW PUMPE", {
        hint = "Choose an account name",
        maxLength = 20,
        allowSpace = true,
    })
    if not name then return false end
    local pin = ui.pin(target, "CREATE A PIN", true)
    if not pin then return false end
    local confirmPin = ui.pin(target, "REPEAT YOUR PIN", true)
    if not confirmPin then return false end
    if pin ~= confirmPin then
        ui.message(target, "error", "PINS DO NOT MATCH", "Please try again", 1)
        return false
    end
    local gender = chooseGender()
    if not gender then return false end
    local result, err = client:request("REGISTER", {
        name = name,
        pin = pin,
        gender = gender,
    })
    if not result then
        ui.message(target, "error", "COULD NOT CREATE", err, 1.1)
        return false
    end
    sessionToken = result.session_token
    account = result.account
    device.last_name = account.name
    saveDevice()
    ui.message(target, "success", "ACCOUNT READY",
        money(account.balance) .. " starting balance", 0.9)
    return true
end

local function welcome()
    local width, height = target.getSize()
    while running and not sessionToken do
        ui.clear(target)
        ui.header(target, "PUMPE", "Banking, tickets, life", util.formatClock())
        ui.center(target, 6, "YOUR MONEY.", ui.theme.ink)
        ui.center(target, 7, "IN YOUR POCKET.", ui.theme.accent)
        local scene = ui.scene(target)
        scene:button("login", 3, 10, width - 5, 3, "SIGN IN",
            { background = ui.theme.accentDark, shadow = true })
        scene:button("create", 3, 14, width - 5, 3, "CREATE ACCOUNT",
            { background = ui.theme.panel, shadow = true })
        scene:button("exit", 1, height, 6, 1, "EXIT",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 0.5 })
        if action == "login" then login()
        elseif action == "create" then createAccount()
        elseif action == "exit" or action == "__terminate" then
            running = false
        end
    end
end

local function balanceScreen()
    local blink = true
    local page = 1
    local history = {}
    local historyResult = request("HISTORY")
    if historyResult then history = historyResult.transactions end
    while sessionToken do
        refreshSummary(true)
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "BALANCE", account.name, util.formatClock(blink))
        ui.card(target, 2, 5, width - 2, 4, ui.theme.success)
        ui.text(target, 4, 6, "AVAILABLE", ui.theme.muted, ui.theme.panel)
        ui.text(target, 4, 7, money(account.balance), ui.theme.ink, ui.theme.panel)
        ui.text(target, 2, 10, "RECENT", ui.theme.muted)
        local pageItems, actualPage, pages = util.page(history, page,
            math.max(1, height - 12))
        page = actualPage
        for index, tx in ipairs(pageItems) do
            local y = 10 + index
            local color = tx.amount >= 0 and ui.theme.success or ui.theme.ink
            ui.text(target, 2, y, ui.truncate(tx.description, width - 11), color)
            local amountText = (tx.amount >= 0 and "+" or "") .. money(tx.amount)
            ui.text(target, width - #amountText, y, amountText, color)
        end
        local scene = ui.scene(target)
        pageFooter(scene, page, pages)
        local action = scene:wait({ tickRate = 0.5 })
        blink = not blink
        if action == "back" or action == "__terminate" then return
        elseif action == "prev" then page = page - 1
        elseif action == "next" then page = page + 1 end
    end
end

local function sendMoney()
    local recipient = ui.input(target, "SEND MONEY", {
        hint = "Recipient account name",
        maxLength = 20,
        allowSpace = true,
    })
    if not recipient then return end
    local amountText = ui.input(target, "AMOUNT", {
        hint = "Available " .. money(account.balance),
        mode = "number", maxLength = 12,
    })
    if not amountText then return end
    local amount = tonumber(amountText)
    if not amount or amount <= 0 then
        ui.message(target, "error", "INVALID AMOUNT", "Enter a number above zero")
        return
    end
    if not ui.confirm(target, "CONFIRM TRANSFER",
        money(amount) .. " to " .. recipient, "SEND", "BACK") then return end
    local pin = ui.pin(target, "CONFIRM WITH PIN", true)
    if not pin then return end
    local result, err = request("SEND_MONEY", {
        recipient = recipient,
        amount = amount,
        pin = pin,
    }, true)
    if result then
        account.balance = result.balance
        ui.message(target, "success", "MONEY SENT",
            money(amount) .. " to " .. result.recipient, 1)
    else
        ui.message(target, "error", "TRANSFER FAILED", err, 1.1)
    end
end

local function payCode()
    local code = ui.input(target, "PAY A CODE", {
        hint = "Six characters from the kiosk",
        mode = "code", maxLength = 6, minLength = 6,
    })
    if not code then return end
    local preview, err = request("PAY_CODE_PREVIEW", { code = code }, true)
    if not preview then
        ui.message(target, "error", "CODE REJECTED", err, 1.1)
        return
    end

    local verb = preview.kind == "withdrawal" and "RECEIVE" or "PAY"
    local body = money(preview.amount) .. "  " .. preview.merchant
    if not ui.confirm(target, verb .. "?", body, verb, "CANCEL") then return end
    local pin
    if preview.pin_required then
        pin = ui.pin(target, "CONFIRM WITH PIN", true)
        if not pin then return end
    end
    local result, payErr = request("PAY_CODE_CONFIRM", {
        code = code,
        pin = pin,
    }, true)
    if result then
        account.balance = result.balance
        local title = result.kind == "withdrawal" and "MONEY RECEIVED" or "PAYMENT ACCEPTED"
        ui.message(target, "success", title,
            money(result.amount) .. " - " .. result.merchant, 1.1)
    else
        ui.message(target, "error", "PAYMENT FAILED", payErr, 1.2)
    end
end

local function historyScreen()
    local result = request("HISTORY")
    if not result then return end
    local items, page, blink = result.transactions, 1, true
    while true do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "HISTORY", #items .. " transactions", util.formatClock(blink))
        local pageItems, actualPage, pages = util.page(items, page,
            math.max(1, math.floor((height - 5) / 3)))
        page = actualPage
        for index, tx in ipairs(pageItems) do
            local y = 4 + (index - 1) * 3
            local color = tx.amount >= 0 and ui.theme.success or ui.theme.danger
            ui.text(target, 2, y, ui.truncate(tx.description, width - 3), ui.theme.ink)
            ui.text(target, 2, y + 1, "Day " .. tx.day .. " " .. tx.time, ui.theme.muted)
            local amountText = (tx.amount >= 0 and "+" or "") .. money(tx.amount)
            ui.text(target, width - #amountText, y + 1, amountText, color)
        end
        local scene = ui.scene(target)
        pageFooter(scene, page, pages)
        local action = scene:wait({ tickRate = 0.5 })
        blink = not blink
        if action == "back" or action == "__terminate" then return
        elseif action == "prev" then page = page - 1
        elseif action == "next" then page = page + 1 end
    end
end

local function ticketTypeScreen(event, ticketTypes)
    local selectedQuantity = {}
    local page, blink = 1, true
    while true do
        local width, height = target.getSize()
        ui.clear(target)
        local countdown = util.eventCountdown(event.event_day, event.event_time)
        ui.header(target, ui.truncate(event.title, width - 9),
            "In " .. countdown, util.formatClock(blink))
        ui.text(target, 2, 4, "Day " .. event.event_day .. "  " .. event.event_time,
            ui.theme.muted)
        ui.text(target, 2, 5, ui.truncate(event.location, width - 3), ui.theme.ink)
        local pageItems, actualPage, pages = util.page(ticketTypes, page, 3)
        page = actualPage
        local scene = ui.scene(target)
        for index, ticketType in ipairs(pageItems) do
            local y = 7 + (index - 1) * 4
            local left = ticketType.total_quantity - ticketType.sold_quantity
            local soldOut = left <= 0
            ui.card(target, 2, y, width - 2, 3,
                soldOut and ui.theme.danger or ui.theme.accent)
            ui.text(target, 4, y, ui.truncate(ticketType.name, width - 12),
                ui.theme.ink, ui.theme.panel)
            ui.text(target, 4, y + 1, money(ticketType.price) .. "  " .. left .. " left",
                soldOut and ui.theme.danger or ui.theme.muted, ui.theme.panel)
            scene:button("buy:" .. ticketType.ticket_type_id,
                width - 8, y, 7, 3, soldOut and "SOLD" or "BUY",
                { background = soldOut and colors.gray or ui.theme.accentDark,
                    disabled = soldOut })
        end
        pageFooter(scene, page, pages)
        local action = scene:wait({ tickRate = 0.5 })
        blink = not blink
        if action == "back" or action == "__terminate" then return
        elseif action == "prev" then page = page - 1
        elseif action == "next" then page = page + 1
        else
            local typeId = action and action:match("^buy:(.+)$")
            if typeId then
                local chosen
                for _, item in ipairs(ticketTypes) do
                    if item.ticket_type_id == typeId then chosen = item break end
                end
                if chosen then
                    local quantityText = ui.input(target, "TICKET QUANTITY", {
                        hint = "Choose 1-" .. config.max_ticket_quantity,
                        mode = "number", maxLength = 1,
                    })
                    local quantity = math.floor(tonumber(quantityText) or 0)
                    if quantity >= 1 and quantity <= config.max_ticket_quantity then
                        local total = chosen.price * quantity
                        if ui.confirm(target, "BUY TICKETS",
                            quantity .. "x " .. chosen.name .. "  " .. money(total),
                            "BUY", "BACK") then
                            local pin = ui.pin(target, "CONFIRM WITH PIN", true)
                            if pin then
                                local result, err = request("BUY_TICKETS", {
                                    event_id = event.event_id,
                                    ticket_type_id = chosen.ticket_type_id,
                                    quantity = quantity,
                                    pin = pin,
                                }, true)
                                if result then
                                    account.balance = result.balance
                                    ui.message(target, "success", "TICKETS SECURED",
                                        quantity .. " for " .. event.title, 1.2)
                                    return
                                else
                                    ui.message(target, "error", "PURCHASE FAILED", err, 1.2)
                                end
                            end
                        end
                    elseif quantityText then
                        ui.message(target, "error", "BAD QUANTITY",
                            "Choose 1-" .. config.max_ticket_quantity)
                    end
                end
            end
        end
    end
end

local function eventsScreen()
    local result = request("LIST_EVENTS")
    if not result then return end
    local events, page, blink = result.events, 1, true
    while true do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "EVENTS", "Live schedule", util.formatClock(blink))
        local pageItems, actualPage, pages = util.page(events, page, 3)
        page = actualPage
        local scene = ui.scene(target)
        if #events == 0 then
            ui.center(target, 9, "No upcoming events", ui.theme.muted)
        end
        for index, event in ipairs(pageItems) do
            local y = 4 + (index - 1) * 5
            local countdown = util.eventCountdown(event.event_day, event.event_time)
            ui.card(target, 2, y, width - 2, 4,
                index == 1 and ui.theme.accent or colors.magenta)
            ui.text(target, 4, y, ui.truncate(event.title, width - 6),
                ui.theme.ink, ui.theme.panel)
            ui.text(target, 4, y + 1, "IN " .. string.upper(countdown),
                ui.theme.accent, ui.theme.panel)
            local price = event.from_price and ("From " .. money(event.from_price)) or "Details"
            ui.text(target, 4, y + 2, ui.truncate(price .. "  " .. event.location, width - 6),
                ui.theme.muted, ui.theme.panel)
            scene:button("event:" .. event.event_id, 2, y, width - 2, 4, "", {
                background = ui.theme.panel,
            })
            -- Redraw content because the invisible hit area paints its background.
            ui.fill(target, 2, y, 1, 4,
                index == 1 and ui.theme.accent or colors.magenta)
            ui.text(target, 4, y, ui.truncate(event.title, width - 6),
                ui.theme.ink, ui.theme.panel)
            ui.text(target, 4, y + 1, "IN " .. string.upper(countdown),
                ui.theme.accent, ui.theme.panel)
            ui.text(target, 4, y + 2, ui.truncate(price .. "  " .. event.location, width - 6),
                ui.theme.muted, ui.theme.panel)
        end
        pageFooter(scene, page, pages)
        local action = scene:wait({ tickRate = 0.5, flash = false })
        blink = not blink
        if action == "back" or action == "__terminate" then return
        elseif action == "prev" then page = page - 1
        elseif action == "next" then page = page + 1
        else
            local eventId = action and action:match("^event:(.+)$")
            if eventId then
                local details = request("EVENT_DETAILS", { event_id = eventId })
                if details then
                    ui.wipe(target, "EVENT DETAILS")
                    ticketTypeScreen(details.event, details.ticket_types)
                    result = request("LIST_EVENTS", {}, true) or result
                    events = result.events
                end
            end
        end
    end
end

local function drawTicket(ticket, blink)
    local width, height = target.getSize()
    ui.clear(target)
    ui.header(target, "MY TICKET", ticket.ticket_type_name, util.formatClock(blink))
    local countdown = util.eventCountdown(ticket.event_day, ticket.event_time)
    ui.center(target, 4, ui.truncate(ticket.event_title, width - 2), ui.theme.ink)
    ui.center(target, 5, "IN " .. string.upper(countdown), ui.theme.accent)
    ui.fill(target, 2, 7, width - 2, 6, colors.white)
    ui.center(target, 8, "ENTRY CODE", colors.gray, colors.white)
    local code = ticket.qr_code
    local spaced = table.concat({ code:sub(1, 4), code:sub(5, 8) }, " ")
    ui.center(target, 10, spaced, colors.black, colors.white)
    ui.center(target, 12, ticket.used and "ALREADY USED" or "READY TO SCAN",
        ticket.used and colors.red or colors.green, colors.white)
    ui.center(target, 15, "Day " .. ticket.event_day .. "  " .. ticket.event_time,
        ui.theme.muted)
    ui.center(target, 16, ui.truncate(ticket.location, width - 3), ui.theme.muted)
end

local function myTicketsScreen()
    local result = request("MY_TICKETS")
    if not result then return end
    local tickets = result.tickets
    if #tickets == 0 then
        ui.message(target, "info", "NO TICKETS YET", "Find one under Events", 1.2)
        return
    end
    local index, blink = 1, true
    while true do
        local ticket = tickets[index]
        drawTicket(ticket, blink)
        local width, height = target.getSize()
        local scene = ui.scene(target)
        scene:button("back", 1, height, 7, 1, "< BACK",
            { background = ui.theme.panel })
        scene:button("prev", width - 12, height, 4, 1, "<",
            { background = ui.theme.panel, disabled = index <= 1 })
        ui.text(target, width - 7, height, index .. "/" .. #tickets, ui.theme.muted)
        scene:button("next", width - 3, height, 3, 1, ">",
            { background = ui.theme.panel, disabled = index >= #tickets })
        local action = scene:wait({ tickRate = 0.5 })
        blink = not blink
        if action == "back" or action == "__terminate" then return
        elseif action == "prev" then index = math.max(1, index - 1)
        elseif action == "next" then index = math.min(#tickets, index + 1) end
    end
end

local function notificationsScreen()
    local result = request("NOTIFICATIONS")
    if not result then return end
    request("MARK_NOTIFICATIONS_READ", {}, true)
    local items, page, blink = result.notifications, 1, true
    while true do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "NOTIFICATIONS", #items .. " total", util.formatClock(blink))
        local pageItems, actualPage, pages = util.page(items, page, 3)
        page = actualPage
        if #items == 0 then ui.center(target, 9, "All quiet here", ui.theme.muted) end
        for index, item in ipairs(pageItems) do
            local y = 4 + (index - 1) * 5
            ui.card(target, 2, y, width - 2, 4,
                item.kind == "warning" and ui.theme.warning or ui.theme.accent)
            ui.text(target, 4, y, ui.truncate(item.title, width - 6),
                ui.theme.ink, ui.theme.panel)
            ui.text(target, 4, y + 1, ui.truncate(item.body, width - 6),
                ui.theme.muted, ui.theme.panel)
            ui.text(target, 4, y + 2, "Day " .. item.created_day .. " " .. item.created_time,
                ui.theme.muted, ui.theme.panel)
        end
        local scene = ui.scene(target)
        pageFooter(scene, page, pages)
        local action = scene:wait({ tickRate = 0.5 })
        blink = not blink
        if action == "back" or action == "__terminate" then return
        elseif action == "prev" then page = page - 1
        elseif action == "next" then page = page + 1 end
    end
end

local function subscriptionsScreen()
    local result = request("LIST_SUBSCRIPTIONS")
    if not result then return end
    local items, page, blink = result.subscriptions, 1, true
    while true do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "SUBSCRIPTIONS", "Daily billing", util.formatClock(blink))
        local pageItems, actualPage, pages = util.page(items, page, 3)
        page = actualPage
        local scene = ui.scene(target)
        if #items == 0 then ui.center(target, 9, "No subscriptions", ui.theme.muted) end
        for index, item in ipairs(pageItems) do
            local y = 4 + (index - 1) * 5
            ui.card(target, 2, y, width - 2, 4,
                item.active and ui.theme.accent or colors.gray)
            ui.text(target, 4, y, ui.truncate(item.description, width - 6),
                ui.theme.ink, ui.theme.panel)
            ui.text(target, 4, y + 1, money(item.amount)
                .. "/day  Next " .. item.next_charge_day,
                ui.theme.muted, ui.theme.panel)
            if item.active then
                scene:button("cancel:" .. item.subscription_id,
                    width - 9, y + 2, 8, 1, "CANCEL",
                    { background = ui.theme.danger })
            else
                ui.text(target, 4, y + 2, "CANCELLED", ui.theme.muted, ui.theme.panel)
            end
        end
        pageFooter(scene, page, pages)
        local action = scene:wait({ tickRate = 0.5 })
        blink = not blink
        if action == "back" or action == "__terminate" then return
        elseif action == "prev" then page = page - 1
        elseif action == "next" then page = page + 1
        else
            local id = action and action:match("^cancel:(.+)$")
            if id and ui.confirm(target, "CANCEL SUBSCRIPTION",
                "Future charges will stop", "CANCEL", "KEEP") then
                local cancelled, err = request("CANCEL_SUBSCRIPTION",
                    { subscription_id = id }, true)
                if cancelled then
                    ui.message(target, "success", "CANCELLED", "No more charges", 0.8)
                    result = request("LIST_SUBSCRIPTIONS", {}, true) or result
                    items = result.subscriptions
                else
                    ui.message(target, "error", "COULD NOT CANCEL", err)
                end
            end
        end
    end
end

local function taxScreen()
    local result = request("DECLARATION_STATUS")
    if not result then return end
    if not result.period then
        ui.message(target, "info", "NO OPEN PERIOD", "Nothing to file right now", 1.1)
        return
    end
    if result.declaration and result.declaration.status == "submitted" then
        if (result.declaration.difference or 0) > 0 then
            local difference = result.declaration.difference
            if ui.confirm(target, "TAX DIFFERENCE DUE",
                "Pay " .. money(difference) .. " now?", "PAY", "BACK") then
                local pin = ui.pin(target, "CONFIRM WITH PIN", true)
                if pin then
                    local settled, err = request("PAY_TAX_DIFFERENCE", {
                        period_id = result.period.period_id,
                        pin = pin,
                    }, true)
                    if settled then
                        account.balance = settled.balance
                        ui.message(target, "success", "TAX SETTLED",
                            "Paid " .. money(settled.paid), 1)
                    else
                        ui.message(target, "error", "PAYMENT FAILED", err, 1.1)
                    end
                end
            end
        else
            ui.message(target, "success", "ALREADY FILED",
                "Paid " .. money(result.declaration.declared_amount), 1.2)
        end
        return
    end
    local width, height = target.getSize()
    ui.clear(target)
    ui.header(target, "TAX DECLARATION", "Period " .. result.period.period_id,
        util.formatClock())
    ui.card(target, 2, 5, width - 2, 5, ui.theme.warning)
    ui.text(target, 4, 6, "DUE BY DAY " .. result.period.end_day,
        ui.theme.warning, ui.theme.panel)
    ui.text(target, 4, 7, "Personal rate " .. result.period.personal_rate .. "%",
        ui.theme.ink, ui.theme.panel)
    ui.text(target, 4, 8, "Smart fee " .. money(config.smart_declare_fee),
        ui.theme.muted, ui.theme.panel)
    local scene = ui.scene(target)
    scene:button("declare", 2, 12, width - 2, 2, "DECLARE AMOUNT",
        { background = ui.theme.panel })
    scene:button("smart", 2, 15, width - 2, 2,
        result.smart_lifetime and "SMART DECLARE - INCLUDED"
            or "SMART DECLARE - " .. money(config.smart_declare_fee),
        { background = ui.theme.accentDark })
    scene:button("back", 1, height, 7, 1, "< BACK",
        { background = ui.theme.panel })
    local action = scene:wait()
    if action == "declare" then
        local amountText = ui.input(target, "DECLARE TAX", {
            hint = "Amount you believe you owe",
            mode = "number", maxLength = 12,
        })
        if not amountText then return end
        local pin = ui.pin(target, "CONFIRM WITH PIN", true)
        if not pin then return end
        local filed, err = request("FILE_DECLARATION", {
            period_id = result.period.period_id,
            amount = tonumber(amountText),
            pin = pin,
        }, true)
        if filed then
            account.balance = filed.balance
            ui.message(target, "success", "DECLARATION FILED",
                "Paid " .. money(filed.declaration.declared_amount), 1.1)
        else ui.message(target, "error", "FILING FAILED", err, 1.1) end
    elseif action == "smart" then
        local buyLifetime = false
        if not result.smart_lifetime then
            buyLifetime = ui.confirm(target, "SMART DECLARE",
                "Lifetime for " .. money(config.lifetime_smart_declare_fee)
                    .. "? No = one-time", "LIFETIME", "ONE-TIME")
        end
        local pin = ui.pin(target, "CONFIRM WITH PIN", true)
        if not pin then return end
        local filed, err = request("SMART_DECLARE", {
            period_id = result.period.period_id,
            buy_lifetime = buyLifetime,
            pin = pin,
        }, true)
        if filed then
            account.balance = filed.balance
            ui.message(target, "success", "SMART FILED",
                "Exact tax " .. money(filed.declaration.declared_amount), 1.1)
        else ui.message(target, "error", "FILING FAILED", err, 1.1) end
    end
end

local function pendingRequestPopup()
    local result = request("PENDING_REQUESTS", {}, true)
    if not result or #result.requests == 0 then return false end
    local item = result.requests[1]
    local approve = ui.confirm(target, "PAYMENT REQUEST",
        item.merchant .. "  " .. money(item.amount), "REVIEW", "DECLINE")
    if not approve then
        request("RESPOND_PAYMENT_REQUEST", {
            request_id = item.request_id,
            approve = false,
        }, true)
        ui.message(target, "info", "REQUEST DECLINED", item.merchant, 0.7)
        return true
    end
    local pin = ui.pin(target, "APPROVE WITH PIN", true)
    if not pin then return true end
    local paid, err = request("RESPOND_PAYMENT_REQUEST", {
        request_id = item.request_id,
        approve = true,
        pin = pin,
    }, true)
    if paid then
        account.balance = paid.balance
        ui.message(target, "success", "PAYMENT ACCEPTED", item.merchant, 0.9)
    else ui.message(target, "error", "PAYMENT FAILED", err, 1) end
    return true
end

local function updateGps()
    if not gps or not gps.locate then return end
    local x, y, z = gps.locate(0.25, false)
    if x then
        request("GPS_UPDATE", { x = x, y = y, z = z }, true)
    end
end

local function settingsScreen()
    local width, height = target.getSize()
    ui.clear(target)
    ui.header(target, "SETTINGS", account.name, util.formatClock())
    ui.card(target, 2, 5, width - 2, 6, ui.theme.accent)
    ui.text(target, 4, 6, "ACCOUNT ID", ui.theme.muted, ui.theme.panel)
    ui.text(target, 4, 7, account.account_id, ui.theme.ink, ui.theme.panel)
    ui.text(target, 4, 9, "PERSONAL NUMBER", ui.theme.muted, ui.theme.panel)
    ui.text(target, 4, 10, account.personal_number, ui.theme.ink, ui.theme.panel)
    local scene = ui.scene(target)
    scene:button("logout", 2, 14, width - 2, 2, "SIGN OUT",
        { background = ui.theme.danger })
    scene:button("back", 1, height, 7, 1, "< BACK",
        { background = ui.theme.panel })
    local action = scene:wait()
    if action == "logout" and ui.confirm(target, "SIGN OUT", "Leave this PUMPE session?",
        "SIGN OUT", "BACK") then
        sessionToken, account = nil, nil
    end
end

local function mainMenu()
    local blink, tick = true, 0
    local summary = refreshSummary() or {}
    updateGps()
    while running and sessionToken do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "PUMPE", account.name, util.formatClock(blink))
        ui.card(target, 2, 5, width - 2, 3, ui.theme.success)
        ui.text(target, 4, 5, "AVAILABLE", ui.theme.muted, ui.theme.panel)
        ui.text(target, 4, 6, money(account.balance), ui.theme.ink, ui.theme.panel)
        local alertCount = (summary.unread_notifications or 0)
            + (summary.pending_requests or 0)
        if alertCount > 0 then
            ui.text(target, width - 5, 6, tostring(alertCount), colors.black,
                ui.theme.warning)
        end

        local scene = ui.scene(target)
        local gap = 1
        local buttonWidth = math.floor((width - 3) / 2)
        local right = 2 + buttonWidth + gap
        local labels = {
            { "balance", "BALANCE" }, { "pay", "PAY" },
            { "send", "SEND" }, { "history", "HISTORY" },
            { "events", "EVENTS" }, { "tickets", "MY TIX" },
            { "notifications", alertCount > 0 and ("NOTIF " .. alertCount) or "NOTIF" },
            { "tax", "TAX" },
            { "subscriptions", "SUBS" }, { "settings", "SETTINGS" },
        }
        for index, entry in ipairs(labels) do
            local column = (index - 1) % 2
            local row = math.floor((index - 1) / 2)
            local x = column == 0 and 2 or right
            local y = 9 + row * 2
            scene:button(entry[1], x, y, buttonWidth, 2, entry[2], {
                background = (entry[1] == "pay" or entry[1] == "events")
                    and ui.theme.accentDark or ui.theme.panel,
            })
        end
        scene:button("exit", 1, height, 6, 1, "EXIT",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 0.5 })
        if action == "__tick" then
            blink = not blink
            tick = tick + 1
            net.autoUpdate(config, "pumpe", ROOT)
            if tick % 10 == 0 then
                summary = refreshSummary(true) or summary
                if not sessionToken then return end
                if (summary.pending_requests or 0) > 0 and pendingRequestPopup() then
                    summary = refreshSummary(true) or summary
                end
            end
            if tick % 60 == 0 then updateGps() end
        elseif action == "balance" then ui.wipe(target); balanceScreen()
        elseif action == "pay" then payCode()
        elseif action == "send" then sendMoney()
        elseif action == "history" then ui.wipe(target); historyScreen()
        elseif action == "events" then ui.wipe(target, "LIVE EVENTS"); eventsScreen()
        elseif action == "tickets" then ui.wipe(target); myTicketsScreen()
        elseif action == "notifications" then ui.wipe(target); notificationsScreen()
        elseif action == "tax" then taxScreen()
        elseif action == "subscriptions" then subscriptionsScreen()
        elseif action == "settings" then settingsScreen()
        elseif action == "exit" or action == "__terminate" then
            running = false
        end
        if sessionToken then
            summary = refreshSummary(true) or summary
        end
    end
end

ui.boot(target, "PUMPE", "POCKET BANKING v" .. config.version)
local online = client:discover()
if not online then
    ui.message(target, "error", "BANK OFFLINE", "Check your wireless modem", 1.5)
end

while running do
    if not sessionToken then welcome() end
    if sessionToken then mainMenu() end
end

ui.clear(target)
print("PUMPE closed.")
