local ROOT = fs.getDir(shell.getRunningProgram())
if ROOT == "" then ROOT = "." end
package.path = package.path .. ";" .. fs.combine(ROOT, "?.lua")
    .. ";" .. fs.combine(ROOT, "?/init.lua")

-- Stamped by tools/build_release_manifest.js. A program running beside a
-- config.lua from a different release means a partial install.
local PROGRAM_VERSION = "8.1.1"
local config = require("config")
local util = require("lib.util")
local net = require("lib.net")
local ui = require("lib.ui")

local target = term.current()
local client = net.client(config)
local sessionToken
local betAccessToken
local account
local running = true
local payMenu
local deviceFile = fs.combine(ROOT, "pumpe_device.dat")
local device = util.loadTable(deviceFile, {
    last_name = "",
    onboarding_complete = false,
})
if device.onboarding_complete == nil then device.onboarding_complete = false end

ui.usePhoneStyle(true)

local disableDeviceLock
-- Settings opens the dock picker, which is defined with the Home Screen.
local favouritesPicker

local function request(action, payload, silent)
    payload = payload or {}
    if sessionToken and not payload.session_token then
        payload.session_token = sessionToken
    end
    local result, err, code = client:request(action, payload)
    if not result and not silent then
        if code == "SESSION_EXPIRED" then
            sessionToken, betAccessToken, account = nil, nil, nil
            disableDeviceLock()
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

local function phoneTransition(title, color)
    local width, height = target.getSize()
    color = color or ui.theme.accentDark
    for column = 1, width, 3 do
        ui.fill(target, column, 1, math.min(3, width - column + 1),
            height, column % 2 == 0 and ui.theme.background or color)
        sleep(0.015)
    end
    ui.clear(target)
    ui.center(target, math.floor(height / 2), title or "PUMPE", ui.theme.ink)
    sleep(0.08)
end

local function preparationAnimation(newAccount)
    local width, height = target.getSize()
    local stages = {
        {
            title = "Setting up your",
            detail = "Foxy Account",
            work = function() saveDevice() end,
        },
        {
            title = "Securing your details",
            detail = "Encrypted by your PIN",
            work = function() refreshSummary(true) end,
        },
        {
            title = "Preparing your PUMPE",
            detail = "Installing your apps",
            work = function() client:discover() end,
        },
    }
    if not newAccount then
        stages[1].title = "Opening your"
        stages[1].detail = "Foxy Account"
    end
    for index, stage in ipairs(stages) do
        if stage.work then pcall(stage.work) end
        for frame = 1, 4 do
            ui.clear(target)
            ui.center(target, 5, "PUMPE", ui.theme.ink)
            ui.center(target, 8, stage.title, ui.theme.ink)
            ui.center(target, 9, stage.detail, ui.theme.muted)
            local dots = string.rep(".", (frame - 1) % 4)
            ui.center(target, 11, dots, ui.theme.accent)
            ui.progress(target, 3, height - 4, width - 5,
                (index - 1) * 4 + frame, #stages * 4,
                ui.theme.accent, ui.theme.panel)
            sleep(0.07)
        end
    end
    phoneTransition("Ready.", ui.theme.success)
end

local function unlockAnimation()
    local width, height = target.getSize()
    for row = height, 1, -2 do
        ui.fill(target, 1, row, width, math.min(2, height - row + 1),
            ui.theme.background)
        sleep(0.015)
    end
end

local function lockScreen(forcePin)
    if not sessionToken or not account then return end
    local blink = true
    while running and sessionToken do
        local width, height = target.getSize()
        ui.clear(target, colors.blue)
        for row = 1, height do
            if row % 4 == 0 then
                ui.fill(target, 1, row, width, 1, colors.black, ".")
            end
        end
        ui.text(target, 2, 1, "PUMPE", colors.lightGray, colors.blue)
        ui.text(target, width - 2, 1, "[]", colors.lime, colors.blue)
        ui.center(target, 5, util.formatClock(blink), colors.white, colors.blue)
        ui.center(target, 7, "Day " .. util.ingameDay(), colors.lightGray, colors.blue)
        ui.center(target, 11, account.name, colors.white, colors.blue)
        local pinRequired = forcePin
            or ui.idleForMs() >= (tonumber(config.pumpe_pin_seconds) or 120) * 1000
        ui.center(target, height - 4,
            pinRequired and "PIN required" or "Tap to open",
            pinRequired and colors.orange or colors.white, colors.blue)
        ui.center(target, height - 2, "Foxy Account",
            colors.lightGray, colors.blue)

        local timer = os.startTimer(0.5)
        local event = { os.pullEvent() }
        if event[1] == "timer" then
            blink = not blink
        elseif event[1] == "terminate" then
            running = false
            return
        elseif event[1] == "mouse_click" or event[1] == "monitor_touch"
            or event[1] == "key" or event[1] == "char" then
            local mustUsePin = forcePin
                or ui.idleForMs()
                    >= (tonumber(config.pumpe_pin_seconds) or 120) * 1000
            if mustUsePin then
                local pin = ui.pin(target, "Unlock PUMPE", true)
                if pin then
                    local result, err = client:request("LOGIN", {
                        name = account.name,
                        pin = pin,
                    })
                    if result then
                        sessionToken = result.session_token
                        account = result.account
                        ui.noteActivity()
                        unlockAnimation()
                        return
                    end
                    ui.message(target, "error", "PUMPE Locked",
                        err or "Incorrect PIN", 0.8)
                end
            else
                ui.noteActivity()
                unlockAnimation()
                return
            end
        end
    end
end

local watchForUrgentCalls

-- A PUMPE can be left holding a newer program than lib/ui.lua after a partial
-- install. Urgent Contact then rings from the Home Screen only instead of
-- taking the whole app down at launch.
local canRingAnywhere = type(ui.setBackgroundTask) == "function"

local function enableDeviceLock()
    ui.setIdleLock(tonumber(config.pumpe_lock_seconds) or 60, function()
        lockScreen(false)
    end)
    -- Urgent Contact rings from whatever app is open, so the check lives in
    -- the shared wait loop rather than in any one screen.
    if canRingAnywhere then
        ui.setBackgroundTask(
            tonumber(config.urgent_ring_poll_seconds) or 3,
            function() return watchForUrgentCalls() end)
    end
end

disableDeviceLock = function()
    ui.setIdleLock(nil)
    if canRingAnywhere then ui.setBackgroundTask(nil) end
end

local function pageFooter(scene, page, pages)
    local width, height = scene.width, scene.height
    scene:button("back", 1, height, 8, 1, "< Home",
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
    local name = ui.input(target, "Foxy Account", {
        hint = "Your account name",
        initial = device.last_name,
        maxLength = 20,
        allowSpace = true,
    })
    if not name then return false end
    local pin = ui.pin(target, "Your PIN", true)
    if not pin then return false end
    local result, err = client:request("LOGIN", { name = name, pin = pin })
    if not result then
        ui.message(target, "error", "Could Not Sign In", err, 1.1)
        return false
    end
    sessionToken = result.session_token
    account = result.account
    device.last_name = account.name
    device.onboarding_complete = true
    saveDevice()
    preparationAnimation(false)
    enableDeviceLock()
    return true
end

-- The tour that closes sign-up. Settings re-opens the same screens, so there
-- is only ever one description of how the phone works.
local GUIDE = {
    {
        "Your home screen",
        "Apps sit in the grid. The four in the dock follow you onto"
            .. " every page.",
    },
    {
        "BuckApp",
        "Balance, code payments, sending money and the Bet Wallet all"
            .. " live in BuckApp.",
    },
    {
        "Friends",
        "Add a friend by name, chat, split a bill, or reach one fast"
            .. " with Urgent Contact.",
    },
    {
        "Tickets and Customs",
        "Tickets keeps what you paid for. Customs holds your visas and"
            .. " your territories.",
    },
    {
        "Notifications",
        "The last home page is your alerts. Some of them stay up until"
            .. " you press Continue.",
    },
    {
        "Staying safe",
        "Your PIN locks the PUMPE when it sits idle. This guide lives"
            .. " in Settings too.",
    },
}

local function guideScreen(fromSettings)
    local page = 1
    while running do
        local width, height = target.getSize()
        local entry = GUIDE[page]
        ui.clear(target)
        ui.header(target, "How PUMPE Works",
            "Step " .. page .. " of " .. #GUIDE, util.formatClock())
        ui.card(target, 2, 5, width - 2, 10, ui.theme.accent)
        ui.text(target, 4, 6, entry[1], ui.theme.ink, ui.theme.panel)
        ui.wrappedText(target, 4, 8, entry[2], width - 6, 6,
            ui.theme.muted, ui.theme.panel)
        local scene = ui.scene(target)
        scene:button("next", 3, 15, width - 5, 3,
            page < #GUIDE and "Next" or "Finish",
            { background = ui.theme.accentDark, shadow = true })
        local dots = {}
        for index = 1, #GUIDE do
            dots[index] = index == page and "o" or "."
        end
        ui.center(target, height - 1, table.concat(dots, " "),
            ui.theme.muted, ui.theme.background)
        scene:button("back", 1, height, 8, 1, "< Back",
            { background = ui.theme.panel, disabled = page == 1 })
        scene:button("done", width - 6, height, 7, 1,
            fromSettings and "Done" or "Skip",
            { background = ui.theme.panel })
        local action = scene:wait()
        if action == "next" then
            if page == #GUIDE then return end
            page = page + 1
        elseif action == "back" then
            page = math.max(1, page - 1)
        elseif action == "done" or action == "__terminate" then
            return
        end
    end
end

local function createAccount()
    local name = ui.input(target, "Create Foxy Account", {
        hint = "Choose a username",
        maxLength = 20,
        allowSpace = true,
    })
    if not name then return false end
    local pin = ui.pin(target, "Create a PIN", true)
    if not pin then return false end
    local confirmPin = ui.pin(target, "Repeat Your PIN", true)
    if not confirmPin then return false end
    if pin ~= confirmPin then
        ui.message(target, "error", "PINs Do Not Match", "Please try again", 1)
        return false
    end
    local result, err = client:request("REGISTER", { name = name, pin = pin })
    if not result then
        ui.message(target, "error", "Account Not Created", err, 1.1)
        return false
    end
    sessionToken = result.session_token
    account = result.account
    device.last_name = account.name
    device.onboarding_complete = true
    saveDevice()
    preparationAnimation(true)
    guideScreen(false)
    enableDeviceLock()
    return true
end

-- One screen, one question: is this a new account or an existing one.
local function welcomeScreen()
    local blink = true
    while running and not sessionToken do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "Welcome", "Let us get you started",
            util.formatClock(blink))
        ui.card(target, 2, 5, width - 2, 6, ui.theme.accent)
        ui.text(target, 4, 6, "PUMPE", ui.theme.ink, ui.theme.panel)
        ui.wrappedText(target, 4, 7,
            "Your money, your friends and your tickets, in one pocket.",
            width - 6, 4, ui.theme.muted, ui.theme.panel)
        local scene = ui.scene(target)
        scene:button("create", 3, 12, width - 5, 3, "I need an account",
            { background = ui.theme.accentDark, shadow = true })
        scene:button("login", 3, 16, width - 5, 3, "I already have one",
            { background = ui.theme.panel })
        if device.last_name ~= "" then
            ui.center(target, height - 1,
                ui.truncate("Last used: " .. device.last_name, width),
                ui.theme.muted, ui.theme.background)
        end
        scene:button("exit", 1, height, 6, 1, "Exit",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 0.5 })
        if action == "__tick" or action == "__idle" then
            blink = not blink
        elseif action == "create" or action == "login" then
            return action
        elseif action == "exit" or action == "__terminate" then
            return "exit"
        end
    end
    return "exit"
end

local function welcome()
    while running and not sessionToken do
        disableDeviceLock()
        local action = welcomeScreen()
        if action == "login" then
            login()
        elseif action == "create" then
            createAccount()
        else
            running = false
        end
    end
end

local function reviewTransfer(quote)
    local blink = true
    while true do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "Send Money", "Review transfer",
            util.formatClock(blink))
        ui.card(target, 2, 5, width - 2, 9, ui.theme.accent)
        ui.text(target, 4, 5, "TO", ui.theme.muted, ui.theme.panel)
        ui.text(target, 4, 6, ui.truncate(quote.recipient, width - 6),
            ui.theme.ink, ui.theme.panel)
        ui.text(target, 4, 8, "THEY RECEIVE", ui.theme.muted, ui.theme.panel)
        local receiveText = money(quote.amount)
        ui.text(target, width - #receiveText - 2, 8, receiveText,
            ui.theme.success, ui.theme.panel)
        local rate = math.floor((tonumber(config.send_money_fee_rate) or 0.10)
            * 100 + 0.5)
        ui.text(target, 4, 10, "FEE " .. rate .. "%", ui.theme.muted, ui.theme.panel)
        local feeText = money(quote.fee)
        ui.text(target, width - #feeText - 2, 10, feeText,
            ui.theme.warning, ui.theme.panel)
        ui.text(target, 4, 12, "YOU PAY", ui.theme.ink, ui.theme.panel)
        local totalText = money(quote.total)
        ui.text(target, width - #totalText - 2, 12, totalText,
            ui.theme.ink, ui.theme.panel)
        ui.center(target, 15, "Daily left: " .. money(quote.daily_remaining),
            ui.theme.muted)

        local scene = ui.scene(target)
        local buttonWidth = math.floor((width - 5) / 2)
        scene:button("back", 2, height - 3, buttonWidth, 2, "Back",
            { background = ui.theme.panel })
        scene:button("send", width - buttonWidth, height - 3,
            buttonWidth, 2, "Send",
            { background = ui.theme.accentDark })
        local action = scene:wait({ tickRate = 0.5 })
        if action == "send" then return true end
        if action == "back" or action == "__terminate" then return false end
        blink = not blink
    end
end

local function sendingAnimation(recipient)
    local width, height = target.getSize()
    local stages = {
        "Securing transfer",
        "Contacting PUMPE Bank",
        "Sending to " .. recipient,
    }
    for index, label in ipairs(stages) do
        for frame = 1, 3 do
            ui.clear(target)
            ui.center(target, 6, "PUMPE Pay", ui.theme.ink)
            ui.wrappedText(target, 2, 9, label, width - 4, 2,
                ui.theme.muted)
            ui.center(target, 12, string.rep(".", frame), ui.theme.accent)
            ui.progress(target, 3, height - 4, width - 5,
                (index - 1) * 3 + frame, #stages * 3,
                ui.theme.accent, ui.theme.panel)
            sleep(0.06)
        end
    end
end

local function sendMoney()
    local recipient = ui.input(target, "Send Money", {
        hint = "Foxy Account username",
        maxLength = 20,
        allowSpace = true,
    })
    if not recipient then return end
    local amountText = ui.input(target, "They Receive", {
        hint = "Up to " .. money(config.send_money_daily_limit) .. " per day",
        mode = "number", maxLength = 12,
    })
    if not amountText then return end
    local amount = tonumber(amountText)
    if not amount or amount <= 0 then
        ui.message(target, "error", "Invalid Amount", "Enter a number above zero")
        return
    end
    local quote, quoteErr = request("SEND_MONEY_QUOTE", {
        recipient = recipient,
        amount = amount,
    }, true)
    if not quote then
        ui.message(target, "error", "Cannot Send Money", quoteErr, 1.1)
        return
    end
    if not reviewTransfer(quote) then return end
    local pin = ui.pin(target, "Confirm with PIN", true)
    if not pin then return end
    sendingAnimation(quote.recipient)
    local result, err = request("SEND_MONEY", {
        recipient = quote.recipient,
        amount = quote.amount,
        pin = pin,
    }, true)
    if result then
        account.balance = result.balance
        account.daily_sent = result.daily_limit - result.daily_remaining
        ui.message(target, "success", "Money Sent",
            result.recipient .. " received " .. money(result.amount), 1.1)
    else
        ui.message(target, "error", "Transfer Failed", err, 1.1)
    end
end

local function payCode()
    local code = ui.input(target, "PAY A CODE", {
        hint = "6-character kiosk code",
        mode = "code", maxLength = 6, minLength = 6,
    })
    if not code then return end
    local preview, err = request("PAY_CODE_PREVIEW", { code = code }, true)
    if not preview then
        ui.message(target, "error", "CODE REJECTED", err, 1.1)
        return
    end

    local verb = preview.kind == "withdrawal" and "RECEIVE"
        or preview.kind == "subscription" and "SUBSCRIBE" or "PAY"
    local body = money(preview.amount)
        .. (preview.kind == "subscription" and "/day  " or "  ")
        .. preview.merchant
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
        local title = result.kind == "withdrawal" and "MONEY RECEIVED"
            or result.kind == "subscription" and "SUBSCRIPTION ACTIVE"
            or "PAYMENT ACCEPTED"
        ui.message(target, "success", title,
            money(result.amount)
                .. (result.kind == "subscription" and "/day - " or " - ")
                .. result.merchant, 1.1)
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
        ui.header(target, "Event Tickets", "In " .. countdown,
            util.formatClock(blink))
        ui.wrappedText(target, 2, 4, event.title,
            width - 4, 3, ui.theme.ink)
        ui.text(target, 2, 7, "Day " .. event.event_day .. "  " .. event.event_time,
            ui.theme.muted)
        ui.wrappedText(target, 2, 8, event.location,
            width - 4, 3, ui.theme.muted)
        local pageItems, actualPage, pages = util.page(ticketTypes, page, 1)
        page = actualPage
        local scene = ui.scene(target)
        for index, ticketType in ipairs(pageItems) do
            local y = 11 + (index - 1) * 7
            local left = ticketType.total_quantity - ticketType.sold_quantity
            local soldOut = left <= 0
            ui.card(target, 2, y, width - 2, 6,
                soldOut and ui.theme.danger or ui.theme.accent)
            ui.wrappedText(target, 4, y, ticketType.name,
                width - 12, 3, ui.theme.ink, ui.theme.panel)
            ui.text(target, 4, y + 3, money(ticketType.price),
                soldOut and ui.theme.danger or ui.theme.muted,
                ui.theme.panel, width - 12)
            ui.text(target, 4, y + 4, left .. " left",
                soldOut and ui.theme.danger or ui.theme.muted,
                ui.theme.panel, width - 12)
            scene:button("buy:" .. ticketType.ticket_type_id,
                width - 8, y, 7, 6, soldOut and "SOLD" or "BUY",
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
        ui.header(target, "Events", "Live schedule", util.formatClock(blink))
        local pageItems, actualPage, pages = util.page(events, page, 2)
        page = actualPage
        local scene = ui.scene(target)
        if #events == 0 then
            ui.center(target, 9, "No upcoming events", ui.theme.muted)
        end
        for index, event in ipairs(pageItems) do
            local y = 4 + (index - 1) * 7
            local countdown = util.eventCountdown(event.event_day, event.event_time)
            ui.card(target, 2, y, width - 2, 6,
                index == 1 and ui.theme.accent or colors.magenta)
            ui.wrappedText(target, 4, y, event.title,
                width - 6, 2, ui.theme.ink, ui.theme.panel)
            ui.text(target, 4, y + 2, "IN " .. string.upper(countdown),
                ui.theme.accent, ui.theme.panel)
            local price = event.from_price and ("From " .. money(event.from_price)) or "Details"
            ui.text(target, 4, y + 3, ui.truncate(price, width - 6),
                ui.theme.muted, ui.theme.panel)
            ui.wrappedText(target, 4, y + 4, event.location,
                width - 6, 2, ui.theme.muted, ui.theme.panel)
            scene:button("event:" .. event.event_id, 2, y, width - 2, 6, "", {
                background = ui.theme.panel,
            })
            -- Redraw content because the invisible hit area paints its background.
            ui.fill(target, 2, y, 1, 6,
                index == 1 and ui.theme.accent or colors.magenta)
            ui.wrappedText(target, 4, y, event.title,
                width - 6, 2, ui.theme.ink, ui.theme.panel)
            ui.text(target, 4, y + 2, "IN " .. string.upper(countdown),
                ui.theme.accent, ui.theme.panel)
            ui.text(target, 4, y + 3, ui.truncate(price, width - 6),
                ui.theme.muted, ui.theme.panel)
            ui.wrappedText(target, 4, y + 4, event.location,
                width - 6, 2, ui.theme.muted, ui.theme.panel)
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
    ui.header(target, "My Ticket", "Entry pass", util.formatClock(blink))
    local countdown = util.eventCountdown(ticket.event_day, ticket.event_time)
    local titleLines = ui.wrap(ticket.event_title, width - 4)
    for index = 1, math.min(3, #titleLines) do
        ui.center(target, 3 + index,
            ui.truncate(titleLines[index], width - 4), ui.theme.ink)
    end
    ui.center(target, 7, "IN " .. string.upper(countdown), ui.theme.accent)
    ui.wrappedText(target, 2, 8, ticket.ticket_type_name,
        width - 4, 2, ui.theme.muted)
    ui.fill(target, 2, 10, width - 2, 6, colors.white)
    ui.center(target, 11, "ENTRY CODE", colors.gray, colors.white)
    local code = ticket.qr_code
    local spaced = table.concat({ code:sub(1, 4), code:sub(5, 8) }, " ")
    ui.center(target, 13, spaced, colors.black, colors.white)
    ui.center(target, 15, ticket.used and "ALREADY USED" or "READY TO SCAN",
        ticket.used and colors.red or colors.green, colors.white)
    ui.center(target, 16, "Day " .. ticket.event_day .. "  " .. ticket.event_time,
        ui.theme.muted)
    local locationLines = ui.wrap(ticket.location, width - 4)
    for index = 1, math.min(3, #locationLines) do
        ui.center(target, 16 + index,
            ui.truncate(locationLines[index], width - 4), ui.theme.muted)
    end
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
        scene:button("back", 1, height, 7, 1, "<Back",
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

local function subscriptionsScreen()
    local result = request("LIST_SUBSCRIPTIONS")
    if not result then return end
    local items, page, blink = result.subscriptions, 1, true
    while true do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "Subscriptions", "Daily billing", util.formatClock(blink))
        local pageItems, actualPage, pages = util.page(items, page, 1)
        page = actualPage
        local scene = ui.scene(target)
        if #items == 0 then ui.center(target, 9, "No subscriptions", ui.theme.muted) end
        for index, item in ipairs(pageItems) do
            local y = 4 + (index - 1) * 12
            ui.card(target, 2, y, width - 2, 12,
                item.active and ui.theme.accent or colors.gray)
            ui.wrappedText(target, 4, y, item.description,
                width - 6, 6, ui.theme.ink, ui.theme.panel)
            ui.text(target, 4, y + 6, money(item.amount) .. " per day",
                ui.theme.muted, ui.theme.panel)
            ui.text(target, 4, y + 7, "Next: day " .. item.next_charge_day,
                ui.theme.muted, ui.theme.panel)
            if item.active then
                scene:button("cancel:" .. item.subscription_id,
                    4, y + 9, width - 7, 2, "Cancel Subscription",
                    { background = ui.theme.danger })
            else
                ui.text(target, 4, y + 9, "CANCELLED",
                    ui.theme.muted, ui.theme.panel)
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
    ui.header(target, "Tax Declaration", "Period " .. result.period.period_id,
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
    scene:button("back", 1, height, 7, 1, "<Back",
        { background = ui.theme.panel })
    local action = scene:wait()
    if action == "declare" then
        local amountText = ui.input(target, "DECLARE TAX", {
            hint = "Enter the amount due",
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

payMenu = function()
    local blink = true
    while sessionToken do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "PUMPE Pay", "Choose how to pay",
            util.formatClock(blink))
        local scene = ui.scene(target)
        scene:button("code", 2, 5, width - 2, 5,
            "Code Pay\nEnter a six-character\nkiosk code", {
                background = colors.blue,
                shadow = true,
            })
        scene:button("send", 2, 11, width - 2, 5,
            "Send Money\n10% processing fee\n"
                .. money(config.send_money_daily_limit) .. " daily limit", {
                background = colors.purple,
                shadow = true,
            })
        scene:button("back", 1, height, 8, 1, "< Home",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 0.5 })
        if action == "__tick" or action == "__idle" then
            blink = not blink
        elseif action == "code" then
            phoneTransition("Code Pay", colors.blue)
            payCode()
        elseif action == "send" then
            phoneTransition("Send Money", colors.purple)
            sendMoney()
        elseif action == "back" or action == "__terminate" then
            return
        end
    end
end

local function travelDocumentScreen(documents)
    local page = 1
    while sessionToken do
        local width, height = target.getSize()
        local document = documents[page]
        ui.clear(target)
        ui.header(target, "Travel Documents",
            #documents == 0 and "No documents"
                or (page .. " of " .. #documents), util.formatClock())
        local scene = ui.scene(target)
        if not document then
            ui.card(target, 2, 6, width - 2, 7, ui.theme.warning)
            ui.center(target, 8, "NO VISAS YET", ui.theme.ink)
            ui.center(target, 10, "Apply from the Visas app",
                ui.theme.muted)
        else
            local kind = document.kind == "citizenship"
                and "CITIZENSHIP" or "TEMPORARY VISA"
            ui.card(target, 2, 5, width - 2, 11,
                document.permanent and ui.theme.success or colors.purple)
            ui.text(target, 4, 6, kind,
                document.permanent and ui.theme.success or colors.purple,
                ui.theme.panel, width - 6)
            ui.text(target, 4, 8,
                ui.truncate(document.territory_name, width - 6),
                ui.theme.ink, ui.theme.panel)
            ui.text(target, 4, 10, "CODE", ui.theme.muted, ui.theme.panel)
            ui.text(target, 4, 11, document.code,
                ui.theme.ink, ui.theme.panel)
            local stay = document.permanent and "Permanent stay"
                or tostring(document.duration_days) .. " day stay"
            ui.text(target, 4, 13, stay,
                ui.theme.muted, ui.theme.panel, width - 6)
            local visit = document.visits and document.visits[1]
            if visit then
                ui.text(target, 4, 14,
                    visit.permanent and "Visiting - permanent"
                        or ("Leave by day " .. visit.due_day),
                    visit.permanent and ui.theme.success or ui.theme.warning,
                    ui.theme.panel, width - 6)
            elseif document.free_roam and #document.free_roam > 0 then
                ui.text(target, 4, 14,
                    "Free Roam: " .. ui.truncate(
                        document.free_roam[1].territory_name, width - 17),
                    ui.theme.success, ui.theme.panel, width - 6)
            else
                ui.text(target, 4, 14, string.upper(document.status),
                    ui.theme.muted, ui.theme.panel, width - 6)
            end
        end
        scene:button("back", 1, height, 8, 1, "< Visa",
            { background = ui.theme.panel })
        scene:button("prev", width - 12, height, 4, 1, "<", {
            background = ui.theme.panel,
            disabled = page <= 1,
        })
        scene:button("next", width - 3, height, 3, 1, ">", {
            background = ui.theme.panel,
            disabled = page >= #documents,
        })
        local action = scene:wait()
        if action == "prev" then
            page = math.max(1, page - 1)
        elseif action == "next" then
            page = math.min(#documents, page + 1)
        elseif action == "back" or action == "__terminate" then
            return
        end
    end
end

local function visaApplicationsScreen(applications)
    local page = 1
    while sessionToken do
        local width, height = target.getSize()
        local application = applications[page]
        ui.clear(target)
        ui.header(target, "Visa Applications",
            #applications == 0 and "Nothing submitted"
                or (page .. " of " .. #applications), util.formatClock())
        local scene = ui.scene(target)
        if not application then
            ui.card(target, 2, 6, width - 2, 7, ui.theme.accent)
            ui.center(target, 8, "NO APPLICATIONS", ui.theme.ink)
            ui.center(target, 10, "Choose Apply for Visa",
                ui.theme.muted)
        else
            local statusColor = application.status == "approved"
                    and ui.theme.success
                or application.status == "denied" and ui.theme.danger
                or ui.theme.warning
            ui.card(target, 2, 5, width - 2, 10, statusColor)
            ui.text(target, 4, 6,
                ui.truncate(application.territory_name, width - 6),
                ui.theme.ink, ui.theme.panel)
            ui.text(target, 4, 8,
                application.requested_days .. " day stay",
                ui.theme.muted, ui.theme.panel)
            ui.text(target, 4, 10, string.upper(application.status),
                statusColor, ui.theme.panel)
            ui.text(target, 4, 12,
                "Applied day " .. application.created_day,
                ui.theme.muted, ui.theme.panel)
        end
        scene:button("back", 1, height, 8, 1, "< Visa",
            { background = ui.theme.panel })
        scene:button("prev", width - 12, height, 4, 1, "<", {
            background = ui.theme.panel,
            disabled = page <= 1,
        })
        scene:button("next", width - 3, height, 3, 1, ">", {
            background = ui.theme.panel,
            disabled = page >= #applications,
        })
        local action = scene:wait()
        if action == "prev" then
            page = math.max(1, page - 1)
        elseif action == "next" then
            page = math.min(#applications, page + 1)
        elseif action == "back" or action == "__terminate" then
            return
        end
    end
end

local function visaApplyScreen(overview)
    local available = {}
    for _, territory in ipairs(overview.territories or {}) do
        if territory.can_apply then available[#available + 1] = territory end
    end
    local page = 1
    while sessionToken do
        local width, height = target.getSize()
        local visible, current, pages = util.page(available, page, 3)
        page = current
        ui.clear(target)
        ui.header(target, "Apply for Visa",
            #available .. " available", util.formatClock())
        local scene = ui.scene(target)
        if #available == 0 then
            ui.card(target, 2, 6, width - 2, 7, ui.theme.success)
            ui.center(target, 8, "NO VISA NEEDED", ui.theme.ink)
            ui.center(target, 10, "No open destinations",
                ui.theme.muted)
        else
            for index, territory in ipairs(visible) do
                local y = 5 + (index - 1) * 4
                scene:button("apply:" .. territory.territory_id,
                    2, y, width - 2, 3,
                    ui.truncate(territory.name, width - 4)
                        .. "\nRequest a stay", {
                        background = index == 1
                            and colors.purple or ui.theme.panel,
                        shadow = true,
                    })
            end
        end
        scene:button("back", 1, height, 8, 1, "< Visa",
            { background = ui.theme.panel })
        if pages > 1 then
            scene:button("prev", width - 12, height, 4, 1, "<", {
                background = ui.theme.panel,
                disabled = page == 1,
            })
            scene:button("next", width - 3, height, 3, 1, ">", {
                background = ui.theme.panel,
                disabled = page == pages,
            })
        end
        local action = scene:wait()
        local territoryId = action and action:match("^apply:(.+)$")
        if territoryId then
            local territory
            for _, candidate in ipairs(available) do
                if candidate.territory_id == territoryId then
                    territory = candidate
                    break
                end
            end
            if territory then
                local days = ui.input(target, "Length of Stay", {
                    hint = overview.visa_min_days .. "-"
                        .. overview.visa_max_days .. " in-game days",
                    mode = "number",
                    maxLength = 2,
                    minLength = 1,
                })
                if days and ui.confirm(target, "Apply for Visa",
                    territory.name .. " for " .. days .. " day(s)?",
                    "APPLY", "BACK") then
                    local result = request("VISA_APPLY", {
                        territory_id = territory.territory_id,
                        requested_days = days,
                    })
                    if result then
                        phoneTransition("Application Sent", colors.purple)
                        ui.message(target, "success", "APPLICATION SENT",
                            "Customs will review it", 1.1)
                        return
                    end
                end
            end
        elseif action == "prev" then
            page = math.max(1, page - 1)
        elseif action == "next" then
            page = math.min(pages, page + 1)
        elseif action == "back" or action == "__terminate" then
            return
        end
    end
end

local function visasScreen()
    while sessionToken do
        local overview = request("VISA_OVERVIEW")
        if not overview then return end
        local width, height = target.getSize()
        local pending = 0
        for _, application in ipairs(overview.applications or {}) do
            if application.status == "pending" then pending = pending + 1 end
        end
        ui.clear(target)
        ui.header(target, "Visas", "Your travel wallet", util.formatClock())
        ui.card(target, 2, 5, width - 2, 4, colors.purple)
        ui.text(target, 4, 6,
            #overview.documents .. " document(s)",
            ui.theme.ink, ui.theme.panel)
        ui.text(target, 4, 7, pending .. " awaiting review",
            ui.theme.muted, ui.theme.panel)
        local scene = ui.scene(target)
        scene:button("documents", 2, 10, width - 2, 2,
            "My Documents", { background = colors.purple })
        scene:button("apply", 2, 13, width - 2, 2,
            "Apply for Visa", { background = ui.theme.accentDark })
        scene:button("applications", 2, 16, width - 2, 2,
            "Applications", { background = ui.theme.panel })
        scene:button("back", 1, height, 8, 1, "< Home",
            { background = ui.theme.panel })
        local action = scene:wait()
        if action == "documents" then
            travelDocumentScreen(overview.documents)
        elseif action == "apply" then
            visaApplyScreen(overview)
        elseif action == "applications" then
            visaApplicationsScreen(overview.applications)
        elseif action == "back" or action == "__terminate" then
            return
        end
    end
end

local function customsCitizensScreen(territoryId)
    local page = 1
    while sessionToken do
        local detail = request("CUSTOMS_DETAIL", {
            territory_id = territoryId,
        })
        if not detail then return end
        local citizens = detail.citizens or {}
        page = math.max(1, math.min(page, math.max(1, #citizens)))
        local citizen = citizens[page]
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "Citizens",
            #citizens .. " in " .. ui.truncate(detail.territory.name, 12),
            util.formatClock())
        if citizen then
            ui.card(target, 2, 5, width - 2, 8, ui.theme.success)
            ui.text(target, 4, 6, ui.truncate(citizen.name, width - 6),
                ui.theme.ink, ui.theme.panel)
            ui.text(target, 4, 8, "PERMANENT CODE",
                ui.theme.muted, ui.theme.panel)
            ui.text(target, 4, 9, citizen.code,
                ui.theme.ink, ui.theme.panel)
            ui.text(target, 4, 11, "Since day " .. citizen.issued_day,
                ui.theme.muted, ui.theme.panel)
        end
        local scene = ui.scene(target)
        scene:button("issue", 2, 14, width - 2, 3,
            "Grant Citizenship\nPermanent VISA", {
                background = ui.theme.accentDark,
                shadow = true,
            })
        scene:button("back", 1, height, 8, 1, "< Cust",
            { background = ui.theme.panel })
        scene:button("prev", width - 12, height, 4, 1, "<", {
            background = ui.theme.panel,
            disabled = page <= 1,
        })
        scene:button("next", width - 3, height, 3, 1, ">", {
            background = ui.theme.panel,
            disabled = page >= #citizens,
        })
        local action = scene:wait()
        if action == "issue" then
            local username = ui.input(target, "Grant Citizenship", {
                hint = "Foxy Account username",
                maxLength = 20,
                minLength = 2,
                allowSpace = true,
            })
            if username then
                local pin = ui.pin(target, "Confirm with PIN", true)
                if pin then
                    local result = request("CUSTOMS_ISSUE_CITIZENSHIP", {
                        territory_id = territoryId,
                        username = username,
                        pin = pin,
                    })
                    if result then
                        phoneTransition("Citizenship Ready", ui.theme.success)
                        ui.message(target, "success", "CITIZENSHIP GRANTED",
                            result.citizen_name, 1.1)
                    end
                end
            end
        elseif action == "prev" then
            page = math.max(1, page - 1)
        elseif action == "next" then
            page = math.min(#citizens, page + 1)
        elseif action == "back" or action == "__terminate" then
            return
        end
    end
end

local function customsApplicationsScreen(territoryId)
    local page = 1
    while sessionToken do
        local detail = request("CUSTOMS_DETAIL", {
            territory_id = territoryId,
        })
        if not detail then return end
        local pending = {}
        for _, application in ipairs(detail.applications or {}) do
            if application.status == "pending" then
                pending[#pending + 1] = application
            end
        end
        page = math.max(1, math.min(page, math.max(1, #pending)))
        local application = pending[page]
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "Visa Requests",
            #pending .. " pending", util.formatClock())
        local scene = ui.scene(target)
        if not application then
            ui.card(target, 2, 6, width - 2, 7, ui.theme.success)
            ui.center(target, 8, "ALL CAUGHT UP", ui.theme.ink)
            ui.center(target, 10, "No visa requests", ui.theme.muted)
        else
            ui.card(target, 2, 5, width - 2, 7, ui.theme.warning)
            ui.text(target, 4, 6,
                ui.truncate(application.applicant_name, width - 6),
                ui.theme.ink, ui.theme.panel)
            ui.text(target, 4, 8,
                application.requested_days .. " day stay",
                ui.theme.muted, ui.theme.panel)
            ui.text(target, 4, 10,
                "Applied day " .. application.created_day,
                ui.theme.muted, ui.theme.panel)
            scene:button("approve", 2, 13, width - 2, 2,
                "Approve VISA", { background = ui.theme.success,
                    foreground = colors.black })
            scene:button("deny", 2, 16, width - 2, 2,
                "Decline", { background = ui.theme.danger })
        end
        scene:button("back", 1, height, 8, 1, "< Cust",
            { background = ui.theme.panel })
        local action = scene:wait()
        if action == "approve" or action == "deny" then
            local pin = ui.pin(target, "Review with PIN", true)
            if pin then
                local result = request("CUSTOMS_REVIEW_APPLICATION", {
                    application_id = application.application_id,
                    approved = action == "approve",
                    pin = pin,
                })
                if result then
                    ui.message(target,
                        action == "approve" and "success" or "warning",
                        action == "approve" and "VISA APPROVED"
                            or "VISA DECLINED",
                        application.applicant_name, 1.1)
                end
            end
        elseif action == "back" or action == "__terminate" then
            return
        end
    end
end

local function customsFreeRoamScreen(territoryId)
    local page = 1
    while sessionToken do
        local detail = request("CUSTOMS_DETAIL", {
            territory_id = territoryId,
        })
        if not detail then return end
        local territories = detail.other_territories or {}
        page = math.max(1, math.min(page, math.max(1, #territories)))
        local partner = territories[page]
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "Free Roam",
            #territories == 0 and "No partner territories"
                or (page .. " of " .. #territories), util.formatClock())
        local scene = ui.scene(target)
        if not partner then
            ui.card(target, 2, 6, width - 2, 7, ui.theme.accent)
            ui.center(target, 8, "NO OTHER TERRITORIES", ui.theme.ink)
            ui.center(target, 10, "A partner must register",
                ui.theme.muted)
        else
            ui.card(target, 2, 5, width - 2, 8,
                partner.free_roam and ui.theme.success or ui.theme.warning)
            ui.text(target, 4, 6,
                ui.truncate(partner.name, width - 6),
                ui.theme.ink, ui.theme.panel)
            ui.text(target, 4, 9,
                partner.free_roam and "PERMANENT ENTRY ON"
                    or "ENTRY NOT ALLOWED",
                partner.free_roam and ui.theme.success or ui.theme.warning,
                ui.theme.panel, width - 6)
            scene:button("toggle", 2, 14, width - 2, 3,
                partner.free_roam and "Remove Free Roam"
                    or "Allow Permanent Entry", {
                    background = partner.free_roam
                        and ui.theme.danger or ui.theme.success,
                    foreground = partner.free_roam
                        and colors.white or colors.black,
                    shadow = true,
                })
        end
        scene:button("back", 1, height, 8, 1, "< Cust",
            { background = ui.theme.panel })
        scene:button("prev", width - 12, height, 4, 1, "<", {
            background = ui.theme.panel,
            disabled = page <= 1,
        })
        scene:button("next", width - 3, height, 3, 1, ">", {
            background = ui.theme.panel,
            disabled = page >= #territories,
        })
        local action = scene:wait()
        if action == "toggle" then
            local pin = ui.pin(target, "Confirm with PIN", true)
            if pin then
                local result = request("CUSTOMS_SET_FREE_ROAM", {
                    territory_id = territoryId,
                    source_territory_id = partner.territory_id,
                    enabled = not partner.free_roam,
                    pin = pin,
                })
                if result then
                    ui.message(target, "success", "FREE ROAM UPDATED",
                        partner.name, 1.0)
                end
            end
        elseif action == "prev" then
            page = math.max(1, page - 1)
        elseif action == "next" then
            page = math.min(#territories, page + 1)
        elseif action == "back" or action == "__terminate" then
            return
        end
    end
end

local function customsTerritoryScreen(territoryId)
    while sessionToken do
        local detail = request("CUSTOMS_DETAIL", {
            territory_id = territoryId,
        })
        if not detail then return end
        local territory = detail.territory
        local pending = 0
        for _, application in ipairs(detail.applications or {}) do
            if application.status == "pending" then pending = pending + 1 end
        end
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, ui.truncate(territory.name, width - 3),
            territory.citizen_count .. " citizens  " .. pending .. " requests",
            util.formatClock())
        local scene = ui.scene(target)
        scene:button("citizens", 2, 5, width - 2, 3,
            "Citizenships\nPermanent VISAs", {
                background = ui.theme.success,
                foreground = colors.black,
                shadow = true,
            })
        scene:button("applications", 2, 9, width - 2, 3,
            "Visa Requests\n" .. pending .. " awaiting review", {
                background = colors.purple,
                shadow = true,
            })
        scene:button("roam", 2, 13, width - 2, 3,
            "Free Roam\n" .. territory.free_roam_count .. " partners", {
                background = ui.theme.accentDark,
                shadow = true,
            })
        scene:button("back", 1, height, 8, 1, "< Cust",
            { background = ui.theme.panel })
        local action = scene:wait()
        if action == "citizens" then
            customsCitizensScreen(territoryId)
        elseif action == "applications" then
            customsApplicationsScreen(territoryId)
        elseif action == "roam" then
            customsFreeRoamScreen(territoryId)
        elseif action == "back" or action == "__terminate" then
            return
        end
    end
end

local function createTerritory()
    local name = ui.input(target, "Create Territory", {
        hint = "3-24 letters or numbers",
        maxLength = 24,
        minLength = 3,
        allowSpace = true,
    })
    if not name then return end
    local pin = ui.pin(target, "Confirm with PIN", true)
    if not pin then return end
    local result = request("CUSTOMS_CREATE_TERRITORY", {
        name = name,
        pin = pin,
    })
    if result then
        phoneTransition("Territory Ready", colors.lightBlue)
        ui.message(target, "success", "TERRITORY CREATED",
            result.territory.name, 1.2)
    end
end

local function customsScreen()
    while sessionToken do
        local overview = request("CUSTOMS_OVERVIEW")
        if not overview then return end
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "Customs", "Territory control", util.formatClock())
        local scene = ui.scene(target)
        if #overview.territories == 0 then
            ui.card(target, 2, 5, width - 2, 7, colors.lightBlue)
            ui.center(target, 7, "CREATE A TERRITORY", ui.theme.ink)
            ui.center(target, 9, "Manage borders and VISAs",
                ui.theme.muted)
            scene:button("create", 2, 14, width - 2, 3,
                "Create Territory", {
                    background = ui.theme.accentDark,
                    shadow = true,
                })
        else
            for index, territory in ipairs(overview.territories) do
                local y = 5 + (index - 1) * 4
                scene:button("territory:" .. territory.territory_id,
                    2, y, width - 2, 3,
                    ui.truncate(territory.name, width - 4)
                        .. "\n" .. territory.citizen_count
                        .. " citizens  " .. territory.pending_count
                        .. " requests", {
                        background = index == 1
                            and colors.lightBlue or ui.theme.panel,
                        shadow = true,
                    })
            end
            if #overview.territories < overview.maximum_territories then
                scene:button("create", 2, 17, width - 2, 2,
                    "+ New Territory", { background = ui.theme.panel })
            end
        end
        scene:button("back", 1, height, 8, 1, "< Home",
            { background = ui.theme.panel })
        local action = scene:wait()
        local territoryId = action
            and action:match("^territory:(.+)$")
        if territoryId then
            customsTerritoryScreen(territoryId)
        elseif action == "create" then
            createTerritory()
        elseif action == "back" or action == "__terminate" then
            return
        end
    end
end

-- ComputerCraftGaming apps --------------------------------------------------

local betColors = {
    red = colors.red,
    orange = colors.orange,
    yellow = colors.yellow,
    green = colors.lime,
    blue = colors.lightBlue,
    purple = colors.purple,
}

local function betRequest(action, payload, silent)
    payload = payload or {}
    payload.bet_token = betAccessToken
    return request(action, payload, silent)
end

local function heldReleaseText(hold)
    if hold.status ~= "holding" then return "Released" end
    return "Day " .. tostring(hold.release_day or "?")
        .. " " .. tostring(hold.release_time or "")
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
        account.balance = result.account_balance
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
    while sessionToken do
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
            wallet = betWalletMove("BET_WALLET_DEPOSIT", account.balance)
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

local function chooseBetSelection(lobby)
    local width, height = target.getSize()
    if lobby.game == "survivor" then
        ui.clear(target)
        ui.header(target, "Survivor", "Interactive // 3X", util.formatClock())
        ui.card(target, 2, 5, width - 2, 8, colors.purple)
        ui.center(target, 7, "LAST ONE STANDING", ui.theme.ink)
        ui.wrappedText(target, 4, 9,
            "Use the touch joystick. Get close and PUSH opponents off the ring.",
            width - 6, 3, ui.theme.muted)
        local scene = ui.scene(target)
        scene:button("continue", 2, 15, width - 2, 3,
            "SET WAGER", { background = colors.purple })
        scene:button("back", 1, height, 8, 1, "< Back",
            { background = ui.theme.panel })
        return scene:wait() == "continue" and "survivor" or nil
    end
    while true do
        ui.clear(target)
        ui.header(target, lobby.game_name,
            "Choose your pick // " .. lobby.multiplier .. "X",
            util.formatClock())
        local scene = ui.scene(target)
        if lobby.game == "heads_tails" then
            scene:button("pick:heads", 2, 6, width - 2, 5,
                "H\nHEADS", { background = colors.orange,
                    foreground = colors.black })
            scene:button("pick:tails", 2, 12, width - 2, 5,
                "T\nTAILS", { background = colors.blue })
        else
            local choices = {
                "red", "orange", "yellow", "green", "blue", "purple",
            }
            local buttonWidth = math.floor((width - 5) / 2)
            for index, name in ipairs(choices) do
                local column = (index - 1) % 2
                local row = math.floor((index - 1) / 2)
                local x = column == 0 and 2 or width - buttonWidth
                local y = 5 + row * 4
                scene:button("pick:" .. name, x, y, buttonWidth, 3,
                    string.upper(name), {
                        background = betColors[name],
                        foreground = (name == "yellow" or name == "orange"
                            or name == "green") and colors.black or colors.white,
                    })
            end
        end
        scene:button("back", 1, height, 8, 1, "< Back",
            { background = ui.theme.panel })
        local action = scene:wait()
        local selection = action and action:match("^pick:(.+)$")
        if selection then return selection end
        if action == "back" or action == "__terminate" then return nil end
    end
end

local function betResultScreen(result)
    local lobby, player, wallet = result.lobby, result.player, result.wallet
    local width, height = target.getSize()
    ui.clear(target)
    ui.header(target, player.won and "YOU WON" or "ROUND COMPLETE",
        lobby.game_name, util.formatClock())
    ui.card(target, 2, 5, width - 2, 8,
        player.won and ui.theme.success or ui.theme.warning)
    if player.won then
        ui.center(target, 7, money(player.payout), ui.theme.ink)
        ui.center(target, 9, "NOW HOLDING", ui.theme.warning)
        local release = "One full in-game day"
        for _, hold in ipairs(wallet.holds or {}) do
            if hold.hold_id == player.hold_id then
                release = "Day " .. hold.release_day .. " " .. hold.release_time
                break
            end
        end
        ui.center(target, 11, release, ui.theme.muted)
    else
        ui.center(target, 7, "NOT THIS ROUND", ui.theme.ink)
        ui.center(target, 9,
            lobby.game == "survivor" and (lobby.winner_name .. " survived")
                or "Result: " .. string.upper(lobby.outcome or "?"),
            ui.theme.muted)
        ui.center(target, 11, "BET WALLET " .. money(wallet.available),
            ui.theme.muted)
    end
    local scene = ui.scene(target)
    scene:button("done", 2, height - 3, width - 2, 2, "DONE",
        { background = ui.theme.accentDark })
    scene:wait()
end

local function survivorController(code, initial)
    local status, pulse = initial, false
    while status and status.lobby.status == "running" do
        local lobby, player = status.lobby, status.player
        local width, height = target.getSize()
        ui.clear(target, colors.black)
        ui.header(target, "Survivor", player.alive and "YOU ARE IN" or "SPECTATING",
            util.formatClock())
        ui.center(target, 5,
            player.alive and "MOVE + PUSH" or "YOU WERE PUSHED OUT",
            player.alive and colors.lime or colors.red)
        local scene = ui.scene(target)
        if player.alive then
            scene:button("move:0:-1", 10, 7, 7, 2, "UP",
                { background = colors.gray })
            scene:button("move:-1:0", 2, 10, 7, 3, "LEFT",
                { background = colors.gray })
            scene:button("move:0:1", 10, 10, 7, 3, "DOWN",
                { background = colors.gray })
            scene:button("move:1:0", 18, 10, width - 18, 3, "RIGHT",
                { background = colors.gray })
            scene:button("push", 4, 15, width - 7, 3,
                pulse and "PUSH // LOCKED" or "PUSH!", {
                    background = pulse and colors.gray or colors.magenta,
                })
        else
            ui.center(target, 10, "Waiting for a winner...", ui.theme.muted)
        end
        local action = scene:wait({ tickRate = 0.25, flash = false })
        local dx, dy = action and action:match("^move:([%-0-9]+):([%-0-9]+)$")
        if dx then
            betRequest("BET_CONTROL", {
                code = code, dx = tonumber(dx), dy = tonumber(dy),
            }, true)
        elseif action == "push" then
            local pushed = betRequest("BET_CONTROL", {
                code = code, dx = 0, dy = 0, push = true,
            }, true)
            pulse = pushed and pushed.pushed == true
        elseif action == "__terminate" then
            running = false
            return nil
        end
        status = betRequest("BET_LOBBY_STATUS", { code = code }, true)
        if not status then return nil end
        if pulse and action == "__tick" then pulse = false end
    end
    return status
end

local function waitForBetResult(code, initial)
    local status, frame = initial, 0
    while status and status.lobby.status == "lobby" do
        local lobby, player = status.lobby, status.player
        local width, height = target.getSize()
        ui.clear(target, colors.black)
        ui.header(target, "CCG Lobby", lobby.game_name, util.formatClock())
        ui.center(target, 6, ui.truncate(lobby.code, width - 4),
            colors.cyan, colors.black)
        ui.center(target, 8, player.display_name, colors.white, colors.black)
        ui.center(target, 10,
            string.upper(player.selection) .. " // " .. money(player.wager),
            betColors[player.selection] or colors.magenta, colors.black)
        ui.center(target, 13,
            "WAITING FOR START" .. string.rep(".", frame % 4),
            colors.lightGray, colors.black)
        local scene = ui.scene(target)
        scene:button("leave", 2, height - 3, width - 2, 2,
            "LEAVE + REFUND", { background = colors.red })
        local action = scene:wait({ tickRate = 0.5 })
        if action == "leave" then
            if ui.confirm(target, "Leave Lobby?",
                "Your wager returns to Bet Wallet", "LEAVE", "STAY") then
                betRequest("BET_LEAVE", { code = code }, true)
                return nil
            end
        elseif action == "__terminate" then
            betRequest("BET_LEAVE", { code = code }, true)
            running = false
            return nil
        end
        frame = frame + 1
        status = betRequest("BET_LOBBY_STATUS", { code = code }, true)
        if not status then return nil end
    end
    if status and status.lobby.status == "running"
        and status.lobby.game == "survivor" then
        return survivorController(code, status)
    end
    while status and status.lobby.status == "running" do
        local width, height = target.getSize()
        ui.clear(target, colors.black)
        ui.header(target, status.lobby.game_name, "BET LOCKED",
            util.formatClock())
        local symbols = status.lobby.game == "race"
            and { ">--", "->-", "-->", ">>-" }
            or { "H", "T", "H", "T" }
        ui.center(target, 8, symbols[frame % #symbols + 1], colors.magenta,
            colors.black)
        ui.center(target, 11, "GAME IN PROGRESS" .. string.rep(".", frame % 4),
            colors.lightGray, colors.black)
        ui.progress(target, 3, 15, width - 5, frame % 12, 12,
            colors.cyan, colors.gray)
        sleep(0.35)
        frame = frame + 1
        status = betRequest("BET_LOBBY_STATUS", { code = code }, true)
    end
    return status
end

local function betApp()
    local pin = ui.pin(target, "Unlock Bet", true)
    if not pin then return end
    local unlocked, unlockError = request("BET_UNLOCK", { pin = pin }, true)
    if not unlocked then
        ui.message(target, "error", "BET LOCKED", unlockError, 1.1)
        return
    end
    betAccessToken = unlocked.bet_token
    if (unlocked.wallet.available or 0) <= 0 then
        ui.message(target, "warning", "BET WALLET EMPTY",
            "Add money in the Bet Wallet app", 1.2)
    end
    local code = ui.input(target, "Join CCG", {
        hint = "Letters + numbers",
        mode = "code",
        maxLength = math.huge,
        scrollToEnd = true,
    })
    if not code then return end
    code = string.upper(util.trim(code))
    if not code:match("^[A-Z0-9]+$") then
        ui.message(target, "error", "INVALID CODE",
            "Use letters and numbers only", 1.1)
        return
    end
    local name = ui.input(target, "Player Name", {
        hint = "Shown on the big screen",
        maxLength = 14,
        minLength = 2,
        allowSpace = true,
        initial = account.name,
    })
    if not name then return end
    local joined, joinError = betRequest("BET_JOIN", {
        code = code,
        display_name = name,
    }, true)
    if not joined then
        ui.message(target, "error", "CANNOT JOIN", joinError, 1.1)
        return
    end
    local selection = chooseBetSelection(joined.lobby)
    if not selection then
        betRequest("BET_LEAVE", { code = code }, true)
        return
    end
    local amountText = ui.input(target, "Set Wager", {
        hint = joined.lobby.multiplier .. "X if you win // Wallet "
            .. money(unlocked.wallet.available),
        mode = "number",
        maxLength = 12,
    })
    if not amountText then
        betRequest("BET_LEAVE", { code = code }, true)
        return
    end
    local placed, placeError = betRequest("BET_PLACE_WAGER", {
        code = code,
        selection = selection,
        amount = tonumber(amountText),
    }, true)
    if not placed then
        ui.message(target, "error", "WAGER REJECTED", placeError, 1.2)
        betRequest("BET_LEAVE", { code = code }, true)
        return
    end
    local final = waitForBetResult(code, placed)
    if final and final.lobby.status == "finished" then
        betResultScreen(final)
    elseif final and final.lobby.status == "cancelled" then
        ui.message(target, "warning", "LOBBY CANCELLED",
            "Your wager returned to Bet Wallet", 1.1)
    end
end

-- Friends, Messages, and Urgent Contact --------------------------------------

local conversationScreen

local urgentCallScreen
local inCall = false
local lastBannerId

-- A banner drops over the top of whatever app is open, then the screen
-- repaints on its next tick, exactly like a phone.
local function showBanner(item)
    local width = target.getSize()
    local color = item.kind == "warning" and ui.theme.warning
        or item.kind == "urgent" and ui.theme.danger
        or item.kind == "money" and ui.theme.success
        or ui.theme.accent
    ui.fill(target, 1, 1, width, 3, color)
    ui.text(target, 2, 1, ui.truncate(item.title, width - 2), colors.black, color)
    ui.wrappedText(target, 2, 2, item.body, width - 2, 2, colors.black, color)
    sleep(1.6)
end

local function socialAmount(title)
    local raw = ui.input(target, title, {
        hint = "Amount in " .. config.currency,
        mode = "number",
        maxLength = 9,
    })
    if not raw then return nil end
    local amount = tonumber(raw)
    if not amount or amount <= 0 then
        ui.message(target, "warning", "Enter an amount", nil, 1)
        return nil
    end
    return amount
end

local function pickFriend(title, friends, hint)
    if #friends == 0 then
        ui.message(target, "info", "No friends yet",
            "Add someone in the Friends app first", 1.4)
        return nil
    end
    local page = 1
    while true do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, title, hint or (#friends .. " friends"),
            util.formatClock())
        local scene = ui.scene(target)
        local pageItems, actualPage, pages = util.page(friends, page, 4)
        page = actualPage
        for index, friend in ipairs(pageItems) do
            scene:button("friend:" .. friend.account_id, 2, 4 + (index - 1) * 4,
                width - 2, 3, friend.name, { background = ui.theme.accentDark })
        end
        pageFooter(scene, page, pages)
        local action = scene:wait({ tickRate = 0.5 })
        if action == "back" or action == "__terminate" then return nil
        elseif action == "prev" then page = page - 1
        elseif action == "next" then page = page + 1
        else
            local id = action and action:match("^friend:(.+)$")
            if id then
                for _, friend in ipairs(friends) do
                    if friend.account_id == id then return friend end
                end
            end
        end
    end
end

local function friendSearchScreen()
    local query = ui.input(target, "Find a Foxy Account", {
        hint = "Type part of their name",
        maxLength = 20,
        minLength = 2,
        allowSpace = true,
    })
    if not query then return end
    local result = request("FRIEND_SEARCH", { query = query })
    if not result then return end
    local results, page = result.results, 1
    while true do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "Search", #results .. " found", util.formatClock())
        if #results == 0 then
            ui.center(target, 9, "Nobody matched", ui.theme.muted)
        end
        local scene = ui.scene(target)
        local pageItems, actualPage, pages = util.page(results, page, 4)
        page = actualPage
        for index, item in ipairs(pageItems) do
            local state = item.friend and "Friend"
                or item.requested and "Asked"
                or item.incoming and "Wants you"
                or "Tap to add"
            scene:button("add:" .. item.account_id, 2, 4 + (index - 1) * 4,
                width - 2, 3, item.name .. "\n" .. state, {
                    background = item.friend and ui.theme.success
                        or ui.theme.accentDark,
                    foreground = item.friend and colors.black or colors.white,
                    disabled = item.friend,
                })
        end
        pageFooter(scene, page, pages)
        local action = scene:wait({ tickRate = 0.5 })
        if action == "back" or action == "__terminate" then return
        elseif action == "prev" then page = page - 1
        elseif action == "next" then page = page + 1
        else
            local id = action and action:match("^add:(.+)$")
            if id then
                local sent = request("FRIEND_REQUEST", { account_id = id })
                if sent then
                    ui.message(target, "success",
                        sent.status == "friends" and "Now friends"
                            or "Request sent", sent.name, 1.2)
                    result = request("FRIEND_SEARCH", { query = query }, true)
                    results = result and result.results or results
                end
            end
        end
    end
end

local function friendRequestsScreen(incoming)
    local page = 1
    while #incoming > 0 do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "Requests", #incoming .. " waiting", util.formatClock())
        local scene = ui.scene(target)
        local pageItems, actualPage, pages = util.page(incoming, page, 2)
        page = actualPage
        for index, item in ipairs(pageItems) do
            local y = 4 + (index - 1) * 7
            ui.card(target, 2, y, width - 2, 3, ui.theme.accent)
            ui.wrappedText(target, 4, y + 1, item.name, width - 6, 2,
                ui.theme.ink, ui.theme.panel)
            scene:button("yes:" .. item.account_id, 2, y + 4,
                math.floor((width - 3) / 2), 2, "Accept",
                { background = ui.theme.success, foreground = colors.black })
            scene:button("no:" .. item.account_id,
                2 + math.floor((width - 3) / 2) + 1, y + 4,
                width - 3 - math.floor((width - 3) / 2), 2, "Decline",
                { background = ui.theme.danger })
        end
        pageFooter(scene, page, pages)
        local action = scene:wait({ tickRate = 0.5 })
        if action == "back" or action == "__terminate" then return
        elseif action == "prev" then page = page - 1
        elseif action == "next" then page = page + 1
        else
            local yesId = action and action:match("^yes:(.+)$")
            local noId = action and action:match("^no:(.+)$")
            local id = yesId or noId
            if id then
                local answered = request("FRIEND_RESPOND", {
                    account_id = id,
                    accept = yesId ~= nil,
                })
                if answered then
                    ui.message(target, yesId and "success" or "info",
                        yesId and "Now friends" or "Declined",
                        answered.name, 1)
                    local refreshed = request("FRIEND_OVERVIEW", {}, true)
                    incoming = refreshed and refreshed.incoming or {}
                end
            end
        end
    end
end

local function friendsScreen()
    local page = 1
    while true do
        local overview = request("FRIEND_OVERVIEW")
        if not overview then return end
        local friends, incoming = overview.friends, overview.incoming
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "Friends", #friends .. " friends", util.formatClock())
        local scene = ui.scene(target)
        scene:button("add", 2, 4, math.floor((width - 3) / 2), 2, "Add",
            { background = ui.theme.accentDark })
        scene:button("requests", 2 + math.floor((width - 3) / 2) + 1, 4,
            width - 3 - math.floor((width - 3) / 2), 2,
            #incoming > 0 and ("Requests " .. #incoming) or "Requests", {
                background = #incoming > 0 and ui.theme.warning
                    or ui.theme.panel,
                foreground = #incoming > 0 and colors.black or colors.white,
            })
        if #friends == 0 then
            ui.center(target, 10, "No friends yet", ui.theme.muted)
            ui.center(target, 12, "Tap Add to search", ui.theme.muted)
        end
        local pageItems, actualPage, pages = util.page(friends, page, 3)
        page = actualPage
        for index, friend in ipairs(pageItems) do
            local y = 7 + (index - 1) * 4
            scene:button("open:" .. friend.account_id, 2, y,
                width - 9, 3, friend.name, { background = ui.theme.panel })
            scene:button("drop:" .. friend.account_id, width - 6, y, 6, 3,
                "X", { background = ui.theme.danger })
        end
        pageFooter(scene, page, pages)
        local action = scene:wait({ tickRate = 0.5 })
        if action == "back" or action == "__terminate" then return
        elseif action == "prev" then page = page - 1
        elseif action == "next" then page = page + 1
        elseif action == "add" then friendSearchScreen()
        elseif action == "requests" then friendRequestsScreen(incoming)
        else
            local dropId = action and action:match("^drop:(.+)$")
            local openId = action and action:match("^open:(.+)$")
            if dropId then
                local name = "this friend"
                for _, friend in ipairs(friends) do
                    if friend.account_id == dropId then name = friend.name end
                end
                if ui.confirm(target, "Remove friend",
                    "Remove " .. name .. " from your friends?",
                    "Remove", "Keep") then
                    request("FRIEND_REMOVE", { account_id = dropId })
                end
            elseif openId then
                local started = request("CHAT_START", { account_ids = { openId } })
                if started then
                    conversationScreen(started.conversation)
                end
            end
        end
    end
end

-- Messages -------------------------------------------------------------------

local function messageLines(item, width)
    local prefix = item.kind == "system" and "* " or (item.sender_name .. ": ")
    local body = item.body
    if item.kind == "money_request" then
        body = "asks " .. money(item.amount)
            .. (item.status == "paid" and " (paid)"
                or item.status == "declined" and " (declined)" or "")
        if item.body ~= "" then body = body .. " - " .. item.body end
    elseif item.kind == "money_sent" then
        body = item.body
    end
    return ui.wrap(prefix .. body, width)
end

local function drawTranscript(items, top, bottom, width)
    local lines = {}
    for _, item in ipairs(items) do
        for _, line in ipairs(messageLines(item, width - 3)) do
            lines[#lines + 1] = { text = line, item = item }
        end
    end
    local visible = bottom - top + 1
    local first = math.max(1, #lines - visible + 1)
    local row = top
    for index = first, #lines do
        local entry = lines[index]
        local color = ui.theme.ink
        if entry.item.kind == "system" then color = ui.theme.muted
        elseif entry.item.kind == "money_request" then color = ui.theme.warning
        elseif entry.item.kind == "money_sent" then color = ui.theme.success end
        ui.text(target, 2, row, entry.text, color)
        row = row + 1
    end
    if #lines == 0 then
        ui.center(target, math.floor((top + bottom) / 2), "No messages yet",
            ui.theme.muted)
    end
end

local function pendingRequestFor(items, accountId)
    for index = #items, 1, -1 do
        local item = items[index]
        if item.kind == "money_request" and item.status == "pending"
            and item.sender_id ~= accountId then
            return item
        end
    end
    return nil
end

local function chatMoneyMenu(conversation, items)
    local pending = pendingRequestFor(items, account.account_id)
    local width, height = target.getSize()
    ui.clear(target)
    ui.header(target, "Money", conversation.title, util.formatClock())
    local scene = ui.scene(target)
    scene:button("send", 2, 5, width - 2, 3, "Send money",
        { background = ui.theme.success, foreground = colors.black })
    scene:button("ask", 2, 9, width - 2, 3, "Ask for money",
        { background = ui.theme.warning, foreground = colors.black })
    if pending then
        scene:button("pay", 2, 13, width - 2, 3,
            "Pay " .. money(pending.amount) .. " to " .. pending.sender_name,
            { background = ui.theme.accentDark })
    end
    scene:button("back", 1, height, 8, 1, "< Back",
        { background = ui.theme.panel })
    local action = scene:wait()
    if action == "send" then
        local recipientId
        if conversation.kind == "group" then
            local overview = request("FRIEND_OVERVIEW", {}, true)
            local members = {}
            for _, friend in ipairs(overview and overview.friends or {}) do
                for _, name in ipairs(conversation.member_names or {}) do
                    if name == friend.name then members[#members + 1] = friend end
                end
            end
            local chosen = pickFriend("Pay who?", members)
            if not chosen then return end
            recipientId = chosen.account_id
        end
        local amount = socialAmount("Send how much?")
        if not amount then return end
        local pin = ui.pin(target, "Confirm with PIN", true)
        if not pin then return end
        local sent = request("CHAT_SEND_MONEY", {
            conversation_id = conversation.conversation_id,
            to_account_id = recipientId,
            amount = amount,
            pin = pin,
        })
        if sent then
            ui.message(target, "success", "Sent " .. money(sent.quote.amount),
                "Fee " .. money(sent.quote.fee), 1.2)
        end
    elseif action == "ask" then
        local amount = socialAmount("Ask for how much?")
        if not amount then return end
        if request("CHAT_REQUEST_MONEY", {
            conversation_id = conversation.conversation_id,
            amount = amount,
        }) then
            ui.message(target, "success", "Request sent", nil, 1)
        end
    elseif action == "pay" and pending then
        local pin = ui.pin(target, "Pay " .. money(pending.amount), true)
        if not pin then return end
        local paid = request("CHAT_PAY_REQUEST", {
            conversation_id = conversation.conversation_id,
            seq = pending.seq,
            pin = pin,
        })
        if paid then
            ui.message(target, "success", "Paid " .. money(paid.quote.amount),
                "Fee " .. money(paid.quote.fee), 1.2)
        end
    end
end

conversationScreen = function(summary)
    local opened = request("CHAT_OPEN", {
        conversation_id = summary.conversation_id,
    })
    if not opened then return end
    local items = opened.messages
    local conversation = opened.conversation
    local nextSeq = opened.next_seq
    local blink = true
    while true do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, conversation.title,
            conversation.kind == "group"
                and (conversation.member_count .. " people") or "Direct",
            util.formatClock(blink))
        drawTranscript(items, 4, height - 4, width)
        local scene = ui.scene(target)
        local half = math.floor((width - 3) / 2)
        scene:button("type", 2, height - 3, half, 2, "Message",
            { background = ui.theme.accentDark })
        scene:button("money", 2 + half + 1, height - 3, width - 3 - half, 2,
            "Money", { background = ui.theme.success,
                foreground = colors.black })
        scene:button("back", 1, height, 8, 1, "< Back",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 1 })
        blink = not blink
        if action == "back" or action == "__terminate" then return end
        if action == "type" then
            local body = ui.input(target, "Message", {
                hint = conversation.title,
                maxLength = 120,
                allowSpace = true,
            })
            if body then
                request("CHAT_SEND", {
                    conversation_id = conversation.conversation_id,
                    body = body,
                })
            end
        elseif action == "money" then
            chatMoneyMenu(conversation, items)
        end
        -- Pull only what is new, so an open chat stays cheap and current.
        local update = request("CHAT_OPEN", {
            conversation_id = conversation.conversation_id,
            after_seq = nextSeq - 1,
        }, true)
        if update then
            for _, item in ipairs(update.messages) do
                items[#items + 1] = item
            end
            while #items > 60 do table.remove(items, 1) end
            nextSeq = update.next_seq
            conversation = update.conversation
        end
    end
end

local function newGroupScreen(friends)
    if #friends < 2 then
        ui.message(target, "info", "Need two friends",
            "A group needs at least two other people", 1.4)
        return
    end
    local chosen, chosenIds, page = {}, {}, 1
    while true do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "New group", #chosen .. " chosen", util.formatClock())
        local scene = ui.scene(target)
        local pageItems, actualPage, pages = util.page(friends, page, 3)
        page = actualPage
        for index, friend in ipairs(pageItems) do
            scene:button("pick:" .. friend.account_id, 2, 4 + (index - 1) * 4,
                width - 2, 3, (chosenIds[friend.account_id] and "* " or "")
                    .. friend.name, {
                    background = chosenIds[friend.account_id]
                        and ui.theme.success or ui.theme.panel,
                    foreground = chosenIds[friend.account_id]
                        and colors.black or colors.white,
                })
        end
        scene:button("create", 2, height - 3, width - 2, 2, "Create group",
            { background = ui.theme.accentDark, disabled = #chosen < 2 })
        pageFooter(scene, page, pages)
        local action = scene:wait({ tickRate = 0.5 })
        if action == "back" or action == "__terminate" then return end
        if action == "prev" then page = page - 1 end
        if action == "next" then page = page + 1 end
        if action == "create" and #chosen >= 2 then
            local title = ui.input(target, "Group name", {
                hint = "Shown to everyone",
                maxLength = 20,
                allowSpace = true,
            })
            if title then
                local created = request("CHAT_START", {
                    account_ids = chosen,
                    title = title,
                })
                if created then
                    conversationScreen(created.conversation)
                    return
                end
            end
        else
            local id = action and action:match("^pick:(.+)$")
            if id then
                if chosenIds[id] then
                    chosenIds[id] = nil
                    for index = #chosen, 1, -1 do
                        if chosen[index] == id then table.remove(chosen, index) end
                    end
                elseif #chosen < 7 then
                    chosenIds[id] = true
                    chosen[#chosen + 1] = id
                end
            end
        end
    end
end

local function messagesScreen()
    local page = 1
    while true do
        local list = request("CHAT_LIST")
        if not list then return end
        local conversations = list.conversations
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "Messages", #conversations .. " chats",
            util.formatClock())
        local scene = ui.scene(target)
        local half = math.floor((width - 3) / 2)
        scene:button("new", 2, 4, half, 2, "New chat",
            { background = ui.theme.accentDark })
        scene:button("group", 2 + half + 1, 4, width - 3 - half, 2, "New group",
            { background = ui.theme.panel })
        if #conversations == 0 then
            ui.center(target, 11, "No chats yet", ui.theme.muted)
        end
        local pageItems, actualPage, pages = util.page(conversations, page, 3)
        page = actualPage
        for index, item in ipairs(pageItems) do
            local y = 7 + (index - 1) * 4
            local label = item.title
            if item.unread > 0 then label = "(" .. item.unread .. ") " .. label end
            scene:button("open:" .. item.conversation_id, 2, y, width - 2, 3,
                label .. "\n" .. ui.truncate(item.last_preview, width - 6), {
                    background = item.unread > 0 and ui.theme.accentDark
                        or ui.theme.panel,
                })
        end
        pageFooter(scene, page, pages)
        local action = scene:wait({ tickRate = 0.5 })
        if action == "back" or action == "__terminate" then return
        elseif action == "prev" then page = page - 1
        elseif action == "next" then page = page + 1
        elseif action == "new" or action == "group" then
            local overview = request("FRIEND_OVERVIEW")
            if overview then
                if action == "new" then
                    local friend = pickFriend("Chat with", overview.friends)
                    if friend then
                        local started = request("CHAT_START", {
                            account_ids = { friend.account_id },
                        })
                        if started then conversationScreen(started.conversation) end
                    end
                else
                    newGroupScreen(overview.friends)
                end
            end
        else
            local id = action and action:match("^open:(.+)$")
            if id then
                for _, item in ipairs(conversations) do
                    if item.conversation_id == id then conversationScreen(item) end
                end
            end
        end
    end
end

-- Urgent Contact --------------------------------------------------------------

local function urgentMoneyMenu(call, items)
    local pending = pendingRequestFor(items, account.account_id)
    local width, height = target.getSize()
    ui.clear(target)
    ui.header(target, "Urgent money", call.other_name, util.formatClock())
    local scene = ui.scene(target)
    scene:button("send", 2, 5, width - 2, 3, "Send money",
        { background = ui.theme.success, foreground = colors.black })
    scene:button("ask", 2, 9, width - 2, 3, "Ask for money",
        { background = ui.theme.warning, foreground = colors.black })
    if pending then
        scene:button("pay", 2, 13, width - 2, 3,
            "Pay " .. money(pending.amount),
            { background = ui.theme.accentDark })
    end
    scene:button("back", 1, height, 8, 1, "< Back",
        { background = ui.theme.panel })
    local action = scene:wait()
    if action == "send" then
        local amount = socialAmount("Send how much?")
        if not amount then return end
        local pin = ui.pin(target, "Confirm with PIN", true)
        if not pin then return end
        local sent = request("URGENT_SEND_MONEY", {
            call_id = call.call_id, amount = amount, pin = pin,
        })
        if sent then
            ui.message(target, "success", "Sent " .. money(sent.quote.amount),
                "Fee " .. money(sent.quote.fee), 1.1)
        end
    elseif action == "ask" then
        local amount = socialAmount("Ask for how much?")
        if not amount then return end
        request("URGENT_REQUEST_MONEY", {
            call_id = call.call_id, amount = amount,
        })
    elseif action == "pay" and pending then
        local pin = ui.pin(target, "Pay " .. money(pending.amount), true)
        if not pin then return end
        local paid = request("URGENT_PAY_REQUEST", {
            call_id = call.call_id, seq = pending.seq, pin = pin,
        })
        if paid then
            ui.message(target, "success", "Paid " .. money(paid.quote.amount),
                nil, 1.1)
        end
    end
end

urgentCallScreen = function(call)
    inCall = true
    local items, nextSeq, blink = {}, 0, true
    while running do
        local width, height = target.getSize()
        ui.clear(target)
        local saveLabel = call.i_saved and ("Saved " .. call.save_votes .. "/2")
            or "Save"
        ui.header(target, call.other_name,
            call.status == "active" and "Urgent Contact" or call.status,
            util.formatClock(blink))
        local scene = ui.scene(target)
        scene:button("save", width - 10, 2, 10, 1, saveLabel, {
            background = call.save_votes and call.save_votes > 0
                and ui.theme.success or ui.theme.panel,
            foreground = call.save_votes and call.save_votes > 0
                and colors.black or colors.white,
        })
        drawTranscript(items, 5, height - 4, width)
        local half = math.floor((width - 3) / 2)
        scene:button("type", 2, height - 3, half, 2, "Type",
            { background = ui.theme.accentDark })
        scene:button("money", 2 + half + 1, height - 3, width - 3 - half, 2,
            "Money", { background = ui.theme.success,
                foreground = colors.black })
        scene:button("hang", 2, height, width - 2, 1, "Hang up",
            { background = ui.theme.danger })
        local action = scene:wait({ tickRate = 0.4 })
        blink = not blink
        if action == "hang" or action == "__terminate" then
            request("URGENT_END", { call_id = call.call_id }, true)
            inCall = false
            return
        elseif action == "type" then
            local body = ui.input(target, "Say something", {
                hint = call.other_name .. " sees it at once",
                maxLength = 120,
                allowSpace = true,
            })
            if body then
                request("URGENT_SEND", { call_id = call.call_id, body = body })
            end
        elseif action == "money" then
            urgentMoneyMenu(call, items)
        elseif action == "save" then
            local voted = request("URGENT_SAVE", { call_id = call.call_id })
            if voted then call = voted.call end
        end
        local update = request("URGENT_STATE", {
            call_id = call.call_id,
            after_seq = nextSeq,
        }, true)
        if not update then
            ui.message(target, "warning", "Urgent Contact ended", nil, 1.2)
            inCall = false
            return
        end
        call = update.call
        for _, item in ipairs(update.messages) do
            items[#items + 1] = item
            nextSeq = math.max(nextSeq, item.seq)
        end
        while #items > 60 do table.remove(items, 1) end
        if call.status ~= "active" then
            ui.message(target, call.saved and "success" or "info",
                call.saved and "Saved to Messages" or "Urgent Contact ended",
                call.other_name, 1.4)
            inCall = false
            return
        end
    end
    inCall = false
end

-- A full-screen ring that takes over whatever app was open.
local function incomingCallScreen(call)
    inCall = true
    local frame = 0
    while running do
        local width, height = target.getSize()
        ui.fill(target, 1, 1, width, height, ui.theme.danger)
        ui.center(target, 4, "URGENT CONTACT", colors.white, ui.theme.danger)
        ui.center(target, 6, frame % 2 == 0 and "* * *" or "  *  ",
            colors.white, ui.theme.danger)
        ui.wrappedText(target, 2, 9, call.other_name, width - 2, 3,
            colors.white, ui.theme.danger)
        ui.center(target, 13, "wants to reach you", colors.white, ui.theme.danger)
        local scene = ui.scene(target)
        scene:button("accept", 2, height - 5, width - 2, 2, "Accept",
            { background = ui.theme.success, foreground = colors.black })
        scene:button("decline", 2, height - 2, width - 2, 2, "Decline",
            { background = colors.gray })
        local action = scene:wait({ tickRate = 0.5 })
        frame = frame + 1
        if action == "accept" then
            local answered = request("URGENT_ANSWER", {
                call_id = call.call_id, accept = true,
            })
            inCall = false
            if answered then urgentCallScreen(answered.call) end
            return
        elseif action == "decline" or action == "__terminate" then
            request("URGENT_ANSWER", { call_id = call.call_id, accept = false },
                true)
            inCall = false
            return
        elseif action == "__tick" then
            local still = request("URGENT_RING", {}, true)
            if not still or not still.call
                or still.call.call_id ~= call.call_id then
                inCall = false
                return
            end
        end
    end
    inCall = false
end

local function urgentScreen()
    local overview = request("FRIEND_OVERVIEW")
    if not overview then return end
    local friend = pickFriend("Urgent Contact", overview.friends,
        "Reach a friend now")
    if not friend then return end
    local started = request("URGENT_CALL", { account_id = friend.account_id })
    if not started then return end
    local call = started.call
    inCall = true
    local frame = 0
    while running do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "Reaching", friend.name, util.formatClock())
        ui.center(target, 8, friend.name, ui.theme.ink)
        ui.center(target, 10, string.rep(".", frame % 4 + 1), ui.theme.accent)
        ui.center(target, 12, "Waiting for an answer", ui.theme.muted)
        local scene = ui.scene(target)
        scene:button("cancel", 2, height - 2, width - 2, 2, "Cancel",
            { background = ui.theme.danger })
        local action = scene:wait({ tickRate = 0.5 })
        frame = frame + 1
        if action == "cancel" or action == "__terminate" then
            request("URGENT_END", { call_id = call.call_id }, true)
            inCall = false
            return
        end
        local update = request("URGENT_STATE", { call_id = call.call_id }, true)
        if not update then
            ui.message(target, "warning", "No answer", friend.name, 1.2)
            inCall = false
            return
        end
        call = update.call
        if call.status == "active" then
            inCall = false
            urgentCallScreen(call)
            return
        elseif call.status ~= "ringing" then
            ui.message(target, "info",
                call.status == "declined" and "Declined" or "No answer",
                friend.name, 1.3)
            inCall = false
            return
        end
    end
    inCall = false
end

-- Polled from every screen so a call reaches the user wherever they are.
-- A payment offered by a nearby kiosk takes over the screen. It is never
-- charged without a tap, so an offer meant for someone else is just declined.
local function proximityOfferScreen(offer)
    inCall = true
    local frame = 0
    while running and sessionToken do
        local width, height = target.getSize()
        ui.fill(target, 1, 1, width, height, ui.theme.accentDark)
        ui.center(target, 3, "PAYMENT NEARBY", colors.white, ui.theme.accentDark)
        ui.center(target, 5, frame % 2 == 0 and "( ( ( ) ) )" or "  ( ( ) )  ",
            colors.white, ui.theme.accentDark)
        ui.wrappedText(target, 2, 7, offer.merchant, width - 2, 2,
            colors.white, ui.theme.accentDark)
        ui.center(target, 10, money(offer.amount), colors.white,
            ui.theme.accentDark)
        ui.wrappedText(target, 2, 12, offer.description or "", width - 2, 2,
            colors.lightGray, ui.theme.accentDark)
        if offer.distance then
            ui.center(target, 15, offer.distance .. " blocks away",
                colors.lightGray, ui.theme.accentDark)
        end
        local scene = ui.scene(target)
        scene:button("pay", 2, height - 5, width - 2, 2, "Pay " .. money(offer.amount),
            { background = ui.theme.success, foreground = colors.black })
        scene:button("no", 2, height - 2, width - 2, 2, "Not mine",
            { background = colors.gray })
        local action = scene:wait({ tickRate = 0.5 })
        frame = frame + 1
        if action == "pay" then
            inCall = false
            local preview = request("PAY_CODE_PREVIEW", { code = offer.code })
            if preview then
                local pin
                if preview.pin_required then
                    pin = ui.pin(target, "Confirm payment", true)
                    if not pin then return end
                end
                local paid = request("PAY_CODE_CONFIRM",
                    { code = offer.code, pin = pin })
                if paid then
                    ui.message(target, "success", "Paid " .. money(offer.amount),
                        offer.merchant, 1.4)
                end
            end
            return
        elseif action == "no" or action == "__terminate" then
            request("PROXIMITY_DECLINE", { offer_id = offer.offer_id }, true)
            inCall = false
            return
        elseif action == "__tick" then
            -- Someone else may have taken it, or it may have moved on.
            local poll = request("PUMPE_POLL", {}, true)
            if not poll or not poll.offer
                or poll.offer.offer_id ~= offer.offer_id then
                inCall = false
                return
            end
        end
    end
    inCall = false
end

-- A government announcement. Banner mode drops in and goes away; full screen
-- mode stays put until it is acknowledged, so it cannot be missed.
local function announcementScreen(item)
    inCall = true
    while running and sessionToken do
        local width, height = target.getSize()
        ui.fill(target, 1, 1, width, height, ui.theme.danger)
        ui.center(target, 3, "ANNOUNCEMENT", colors.white, ui.theme.danger)
        ui.fill(target, 2, 5, width - 2, 1, colors.white)
        ui.wrappedText(target, 2, 7, item.title, width - 2, 3,
            colors.white, ui.theme.danger)
        ui.wrappedText(target, 2, 11, item.body or "", width - 2, 6,
            colors.lightGray, ui.theme.danger)
        local scene = ui.scene(target)
        scene:button("ok", 2, height - 2, width - 2, 2, "Continue",
            { background = colors.white, foreground = colors.black })
        local action = scene:wait({ tickRate = 2 })
        if action == "ok" or action == "__terminate" then
            request("ANNOUNCEMENT_ACK",
                { announcement_id = item.announcement_id }, true)
            inCall = false
            return
        end
    end
    inCall = false
end

-- A government tax demand has to be settled from the account holder's own
-- PUMPE, with their PIN. Nothing is ever taken without them paying it.
local function taxDemandScreen(demand)
    while running and sessionToken do
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
                    account.balance = paid.balance
                    ui.message(target, "success", "Tax settled",
                        money(demand.amount), 1.4)
                    return
                end
            end
        end
    end
end

-- The one OS poll: it rings an Urgent Contact and banners a new alert.
watchForUrgentCalls = function()
    if not sessionToken or inCall then return false end
    local poll = request("PUMPE_POLL", { position = net.locate(1) }, true)
    if not poll then return false end
    local latest = poll.latest
    local announcement = poll.announcement
    if announcement and announcement.mode == "modal" then
        if latest then lastBannerId = latest.notification_id end
        announcementScreen(announcement)
        return true
    end
    if poll.offer then
        if latest then lastBannerId = latest.notification_id end
        proximityOfferScreen(poll.offer)
        return true
    end
    if poll.call then
        if latest then lastBannerId = latest.notification_id end
        incomingCallScreen(poll.call)
        return true
    end
    if latest and latest.notification_id ~= lastBannerId then
        lastBannerId = latest.notification_id
        showBanner(latest)
    end
    return false
end

local function settingsScreen()
    while running and sessionToken do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "Settings", account.name, util.formatClock())
        ui.card(target, 2, 5, width - 2, 6, ui.theme.accent)
        ui.text(target, 4, 5, "FOXY ACCOUNT", ui.theme.muted, ui.theme.panel)
        ui.text(target, 4, 6, ui.truncate(account.name, width - 6),
            ui.theme.ink, ui.theme.panel)
        ui.text(target, 4, 8, "ID  " .. tostring(account.account_id),
            ui.theme.muted, ui.theme.panel)
        ui.text(target, 4, 9, "NO  " .. tostring(account.personal_number),
            ui.theme.muted, ui.theme.panel)
        local scene = ui.scene(target)
        scene:button("guide", 2, 11, width - 2, 2, "How PUMPE Works",
            { background = ui.theme.accentDark })
        scene:button("dock", 2, 13, width - 2, 2, "Edit Your Dock",
            { background = ui.theme.panel })
        scene:button("logout", 2, 15, width - 2, 2, "Sign Out",
            { background = ui.theme.danger })
        scene:button("close", 2, 17, width - 2, 2, "Close PUMPE",
            { background = ui.theme.panel })
        scene:button("back", 1, height, 8, 1, "< Home",
            { background = ui.theme.panel })
        local action = scene:wait()
        if action == "guide" then
            guideScreen(true)
        elseif action == "dock" then
            favouritesPicker()
        elseif action == "logout" then
            if ui.confirm(target, "Sign Out", "Leave this PUMPE session?",
                "Sign Out", "Back") then
                sessionToken, betAccessToken, account = nil, nil, nil
                disableDeviceLock()
                return
            end
        elseif action == "close" then
            if ui.confirm(target, "Close PUMPE", "Shut down the PUMPE app?",
                "CLOSE", "BACK") then
                running = false
                return
            end
        else
            return
        end
    end
end

-- The PUMPE OS: consolidated apps, alerts, banners, and favourites ----------

-- BuckApp gathers everything to do with money: the balance you see first,
-- payments behind Continue, the Bet Wallet, and your activity.
local function buckApp()
    local blink = true
    while running and sessionToken do
        local width, height = target.getSize()
        local summary = refreshSummary(true)
        ui.clear(target)
        ui.header(target, "BuckApp", "Foxy Account", util.formatClock(blink))
        ui.card(target, 2, 4, width - 2, 4, ui.theme.success)
        ui.text(target, 4, 4, "AVAILABLE", ui.theme.muted, ui.theme.panel)
        ui.text(target, 4, 5, money(account.balance), ui.theme.ink, ui.theme.panel)
        ui.text(target, 4, 6, "Daily sent " .. money(account.daily_sent or 0),
            ui.theme.muted, ui.theme.panel)

        local demand = request("TAX_DEMAND_STATUS", {}, true)
        demand = demand and demand.demand or nil
        local scene = ui.scene(target)
        if demand then
            scene:button("demand", 2, 9, width - 2, 3,
                "Tax demand " .. money(demand.amount),
                { background = ui.theme.warning, foreground = colors.black })
        else
            scene:button("pay", 2, 9, width - 2, 3, "Continue",
                { background = ui.theme.accentDark, shadow = true })
        end
        local half = math.floor((width - 3) / 2)
        scene:button("wallet", 2, 13, half, 3, "Bet\nWallet",
            { background = colors.purple })
        scene:button("activity", 2 + half + 1, 13, width - 3 - half, 3,
            "Activity", { background = ui.theme.panel })
        scene:button("back", 1, height, 8, 1, "< Home",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 0.5 })
        blink = not blink
        if action == "back" or action == "__terminate" then return
        elseif action == "pay" then payMenu()
        elseif action == "demand" then taxDemandScreen(demand)
        elseif action == "wallet" then betWalletScreen()
        elseif action == "activity" then historyScreen() end
        if summary == nil and not sessionToken then return end
    end
end

-- One entry point for everything social.
local function friendsApp()
    while running and sessionToken do
        local width, height = target.getSize()
        local poll = request("PUMPE_POLL", {}, true) or {}
        ui.clear(target)
        ui.header(target, "Friends", "People and messages", util.formatClock())
        local scene = ui.scene(target)
        local unread = poll.unread_messages or 0
        local requests = poll.friend_requests or 0
        scene:button("messages", 2, 5, width - 2, 4,
            unread > 0 and ("Messages (" .. unread .. ")") or "Messages", {
                background = unread > 0 and ui.theme.accentDark or colors.cyan,
                shadow = true,
            })
        scene:button("people", 2, 10, width - 2, 4,
            requests > 0 and ("Friends (+" .. requests .. ")") or "Friends", {
                background = requests > 0 and ui.theme.warning or colors.lime,
                foreground = colors.black,
                shadow = true,
            })
        scene:button("urgent", 2, 15, width - 2, 3, "Urgent Contact",
            { background = ui.theme.danger, shadow = true })
        scene:button("back", 1, height, 8, 1, "< Home",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 1 })
        if action == "back" or action == "__terminate" then return
        elseif action == "messages" then messagesScreen()
        elseif action == "people" then friendsScreen()
        elseif action == "urgent" then urgentScreen() end
    end
end

local function ticketsApp()
    while running and sessionToken do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "Tickets", "Events and your tickets",
            util.formatClock())
        local scene = ui.scene(target)
        scene:button("browse", 2, 6, width - 2, 5, "Browse Events",
            { background = colors.purple, shadow = true })
        scene:button("mine", 2, 12, width - 2, 5, "My Tickets",
            { background = colors.orange, foreground = colors.black,
                shadow = true })
        scene:button("back", 1, height, 8, 1, "< Home",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 1 })
        if action == "back" or action == "__terminate" then return
        elseif action == "browse" then eventsScreen()
        elseif action == "mine" then myTicketsScreen() end
    end
end

local function customsApp()
    while running and sessionToken do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "Customs", "Territories and travel",
            util.formatClock())
        local scene = ui.scene(target)
        scene:button("visas", 2, 6, width - 2, 5, "My Visas",
            { background = colors.purple, shadow = true })
        scene:button("territories", 2, 12, width - 2, 5, "Territories",
            { background = colors.lightBlue, shadow = true })
        scene:button("back", 1, height, 8, 1, "< Home",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 1 })
        if action == "back" or action == "__terminate" then return
        elseif action == "visas" then visasScreen()
        elseif action == "territories" then customsScreen() end
    end
end

-- The app catalogue the Home Screen, the dock and the picker share.
local APPS = {
    buck = { name = "BuckApp", glyph = "$", color = colors.green,
        open = buckApp },
    friends = { name = "Friends", glyph = "@", color = colors.cyan,
        open = friendsApp },
    tickets = { name = "Tickets", glyph = "#", color = colors.orange,
        open = ticketsApp },
    customs = { name = "Customs", glyph = "=", color = colors.lightBlue,
        open = customsApp },
    bet = { name = "Bet", glyph = "?", color = colors.magenta },
    tax = { name = "Tax", glyph = "%", color = colors.orange },
    subs = { name = "Subs", glyph = "~", color = colors.magenta },
    settings = { name = "Settings", glyph = "*", color = colors.gray },
}
local APP_ORDER = {
    "buck", "friends", "tickets", "customs", "bet", "tax", "subs", "settings",
}
local DOCK_SLOTS = 4

local function appBadge(id, poll)
    if id == "friends" then
        local total = (poll.unread_messages or 0) + (poll.friend_requests or 0)
        if total > 0 then return total end
    end
    return nil
end

local function badgeText(count)
    return count > 9 and "9+" or (" " .. count)
end

local function favouriteIds()
    local chosen = {}
    for _, id in ipairs(device.favorites or {}) do
        if APPS[id] and #chosen < DOCK_SLOTS then chosen[#chosen + 1] = id end
    end
    return chosen
end

favouritesPicker = function()
    while running do
        local width, height = target.getSize()
        local chosen, lookup = favouriteIds(), {}
        for _, id in ipairs(chosen) do lookup[id] = true end
        ui.clear(target)
        ui.header(target, "Your Dock",
            #chosen .. " of " .. DOCK_SLOTS .. " chosen", util.formatClock())
        local scene = ui.scene(target)
        local tileWidth = math.floor((width - 3) / 2)
        for index, id in ipairs(APP_ORDER) do
            local column = (index - 1) % 2
            local row = math.floor((index - 1) / 2)
            scene:button("pick:" .. id, 2 + column * (tileWidth + 1),
                4 + row * 3, tileWidth, 2,
                (lookup[id] and "*" or "") .. APPS[id].name, {
                    background = lookup[id] and ui.theme.success
                        or APPS[id].color,
                    foreground = lookup[id] and colors.black or colors.white,
                })
        end
        scene:button("back", 1, height, 10, 1, "< Done",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 1 })
        if action == "back" or action == "__terminate" then return end
        local id = action and action:match("^pick:(.+)$")
        if id and APPS[id] then
            device.favorites = device.favorites or {}
            if lookup[id] then
                for index = #device.favorites, 1, -1 do
                    if device.favorites[index] == id then
                        table.remove(device.favorites, index)
                    end
                end
            elseif #chosen < DOCK_SLOTS then
                device.favorites[#device.favorites + 1] = id
            end
            saveDevice()
        end
    end
end

-- Home Screen geometry. Small icons in a grid with the name underneath and a
-- dock pinned above the page dots, all measured off the screen so a 26x20
-- pocket and a wide desktop both land on whole rows.
local function homeLayout(width, height)
    local columns = width >= 40 and 5 or 3
    local cell = math.max(4, math.floor((width - 1) / columns))
    local dockY = height - 3
    local top = 5
    local rows = math.max(1, math.floor((dockY - top) / 4))
    return {
        columns = columns,
        rows = rows,
        perPage = columns * rows,
        cell = cell,
        iconWidth = math.max(3, cell - 2),
        left = math.max(1, math.floor((width - cell * columns) / 2) + 1),
        top = top,
        dividerY = dockY - 1,
        dockY = dockY,
        listBottom = dockY - 2,
        dotsY = height - 1,
        navY = height,
    }
end

-- One icon: a small coloured square, the app name under it, and an unread
-- badge in the corner. The caption shares the icon's tap target.
local function drawIcon(scene, action, app, x, y, layout, badge)
    scene:button(action, x, y, layout.iconWidth, 2, app.glyph,
        { background = app.color, foreground = colors.white })
    if badge then
        ui.text(target, x + layout.iconWidth - 2, y, badgeText(badge),
            colors.white, ui.theme.danger)
    end
    local name = ui.truncate(app.name, layout.cell)
    local nameX = math.max(1, math.min(scene.width - #name + 1,
        x + math.floor((layout.iconWidth - #name) / 2)))
    -- The caption is painted on the wallpaper, not on the icon: without an
    -- explicit background it inherits whatever colour was last set, which
    -- put a red badge's colour behind the app's name.
    ui.text(target, nameX, y + 2, name, ui.theme.ink, ui.theme.background)
    scene:hotspot(action, nameX, y + 2, #name, 1)
end

-- The dock follows every app page. An empty slot is the way into the picker.
local function drawDock(scene, layout, poll, width)
    local slotWidth = math.max(3, math.floor((width - 2) / DOCK_SLOTS) - 1)
    local span = DOCK_SLOTS * (slotWidth + 1) - 1
    local left = math.max(1, math.floor((width - span) / 2) + 1)
    ui.fill(target, 2, layout.dividerY, width - 2, 1, ui.theme.panel)
    local chosen = favouriteIds()
    for slot = 1, DOCK_SLOTS do
        local x = left + (slot - 1) * (slotWidth + 1)
        local id = chosen[slot]
        if id then
            scene:button("open:" .. id, x, layout.dockY, slotWidth, 2,
                APPS[id].glyph, { background = APPS[id].color })
            local badge = appBadge(id, poll)
            if badge then
                ui.text(target, x + slotWidth - 2, layout.dockY,
                    badgeText(badge), colors.white, ui.theme.danger)
            end
        else
            scene:button("edit", x, layout.dockY, slotWidth, 2, "+",
                { background = ui.theme.panel })
        end
    end
end

local function alertColor(item)
    return item.kind == "warning" and ui.theme.warning
        or item.kind == "urgent" and ui.theme.danger
        or item.kind == "money" and ui.theme.success
        or ui.theme.accent
end

-- Alerts are part of the OS, so the notification centre is the last home
-- page rather than an app. Unread entries keep their colour and a marker;
-- read ones fade. Tapping one opens the whole message.
local function notificationDetail(item)
    local width, height = target.getSize()
    ui.clear(target)
    ui.header(target, "Notification",
        "Day " .. tostring(item.created_day or "?") .. "  "
            .. tostring(item.created_time or ""), util.formatClock())
    local cardHeight = math.max(4, height - 8)
    ui.card(target, 2, 5, width - 2, cardHeight, alertColor(item))
    ui.wrappedText(target, 4, 6, item.title, width - 6, 2,
        ui.theme.ink, ui.theme.panel)
    ui.wrappedText(target, 4, 9, item.body, width - 6,
        math.max(1, cardHeight - 5), ui.theme.muted, ui.theme.panel)
    local scene = ui.scene(target)
    scene:button("back", 1, height, 10, 1, "< Alerts",
        { background = ui.theme.panel })
    scene:wait()
end

local function drawAlertsPage(scene, items, offset, width, layout)
    -- Three rows per entry, from row four down to the row above the
    -- controls. The last entry needs no trailing gap, hence the +1.
    local perView = math.max(1, math.floor((layout.dividerY - 4) / 3))
    ui.fill(target, 2, layout.dividerY - 1, width - 2, 1, ui.theme.panel)
    scene:button("markread", 2, layout.dividerY, width - 9, 2,
        "Mark all read", { background = ui.theme.panel,
            disabled = #items == 0 })
    scene:button("scrollup", width - 6, layout.dividerY, 5, 1, "^",
        { background = ui.theme.panel, disabled = offset <= 0 })
    scene:button("scrolldown", width - 6, layout.dividerY + 1, 5, 1, "v",
        { background = ui.theme.panel,
            disabled = offset + perView >= #items })
    if #items == 0 then
        local middle = math.max(5, math.floor((layout.dividerY + 2) / 2))
        ui.center(target, middle - 1, "Nothing new", ui.theme.ink,
            ui.theme.background)
        ui.center(target, middle + 1, "Alerts land here", ui.theme.muted,
            ui.theme.background)
        return perView
    end
    for slot = 1, perView do
        local item = items[offset + slot]
        if not item then break end
        local row = 4 + (slot - 1) * 3
        local color = alertColor(item)
        -- The bar carries the colour; the words stay on the wallpaper. Every
        -- draw names its background, because ui.text otherwise inherits
        -- whatever the bar just set and paints the title on top of it.
        ui.fill(target, 2, row, 1, 2, item.read and ui.theme.panel or color)
        ui.text(target, 4, row, ui.truncate(item.title, width - 10),
            item.read and ui.theme.muted or ui.theme.ink, ui.theme.background)
        ui.text(target, width - 5, row,
            ui.truncate(tostring(item.created_time or ""), 5),
            ui.theme.muted, ui.theme.background)
        ui.text(target, 4, row + 1,
            ui.truncate(ui.wrap(item.body, width - 5)[1] or "", width - 5),
            ui.theme.muted, ui.theme.background)
        scene:hotspot("note:" .. (offset + slot), 2, row, width - 2, 2)
    end
    return perView
end

local function mainMenu()
    -- The apps that are not hubs are wired here, where their screens exist.
    APPS.bet.open = betApp
    APPS.tax.open = taxScreen
    APPS.subs.open = subscriptionsScreen
    APPS.settings.open = settingsScreen

    local blink, tick, page, alertOffset = true, 0, 1, 0
    local poll = request("PUMPE_POLL", {}, true) or {}
    lastBannerId = poll.latest and poll.latest.notification_id or lastBannerId
    local alerts, alertsLoaded, perView = {}, false, 1
    refreshSummary()
    enableDeviceLock()

    while running and sessionToken do
        local width, height = target.getSize()
        local layout = homeLayout(width, height)
        -- The app pages come first, the notification centre is always last.
        local pages = math.max(1, math.ceil(#APP_ORDER / layout.perPage)) + 1
        page = math.max(1, math.min(page, pages))
        local onAlerts = page == pages
        local unread = poll.unread_notifications or 0
        -- Load before drawing, so opening the centre never flashes "nothing
        -- new" at alerts that are already on their way.
        if not onAlerts then
            alertsLoaded = false
        elseif not alertsLoaded then
            local loaded = request("NOTIFICATIONS", {}, true)
            alerts = loaded and loaded.notifications or {}
            alertsLoaded = true
        end

        ui.clear(target)
        if onAlerts then
            ui.header(target, "Notifications",
                unread > 0 and (unread .. " unread") or "All caught up",
                util.formatClock(blink))
        else
            ui.header(target, account.name, money(account.balance),
                util.formatClock(blink))
        end

        local scene = ui.scene(target)
        if onAlerts then
            perView = drawAlertsPage(scene, alerts, alertOffset, width, layout)
        else
            local first = (page - 1) * layout.perPage
            for slot = 1, layout.perPage do
                local id = APP_ORDER[first + slot]
                if id then
                    local column = (slot - 1) % layout.columns
                    local row = math.floor((slot - 1) / layout.columns)
                    drawIcon(scene, "open:" .. id, APPS[id],
                        layout.left + column * layout.cell
                            + math.floor((layout.cell - layout.iconWidth) / 2),
                        layout.top + row * 4, layout, appBadge(id, poll))
                end
            end
            drawDock(scene, layout, poll, width)
        end

        local dots = {}
        for dot = 1, pages do
            dots[dot] = dot == page and "o"
                or (dot == pages and unread > 0 and "!" or ".")
        end
        ui.center(target, layout.dotsY, table.concat(dots, " "),
            ui.theme.muted, ui.theme.background)
        scene:button("prev", 1, layout.navY, 7, 1, "<",
            { background = ui.theme.panel, disabled = page == 1 })
        scene:button("next", width - 6, layout.navY, 7, 1, ">",
            { background = ui.theme.panel, disabled = page == pages })
        scene:button("lock", math.floor(width / 2) - 3, layout.navY, 7, 1,
            "()", { background = ui.theme.panel })

        local action = scene:wait({ tickRate = 0.5 })
        blink = not blink
        if action == "prev" then
            page, alertOffset = math.max(1, page - 1), 0
        elseif action == "next" then
            page, alertOffset = math.min(pages, page + 1), 0
        elseif action == "lock" then lockScreen(true)
        elseif action == "edit" then favouritesPicker()
        elseif action == "scrollup" then
            alertOffset = math.max(0, alertOffset - perView)
        elseif action == "scrolldown" then
            alertOffset = alertOffset + perView
        elseif action == "markread" then
            request("MARK_NOTIFICATIONS_READ", {}, true)
            for _, item in ipairs(alerts) do item.read = true end
            poll.unread_notifications = 0
        elseif action == "__terminate" then
            running = false
        else
            local note = tonumber(action and action:match("^note:(%d+)$"))
            local id = action and action:match("^open:(.+)$")
            if note and alerts[note] then
                notificationDetail(alerts[note])
            elseif id and APPS[id] and APPS[id].open then
                phoneTransition(APPS[id].name, APPS[id].color)
                APPS[id].open()
                refreshSummary(true)
            end
        end

        if action == "__tick" or action == "__idle" or action == "__wake" then
            tick = tick + 1
            net.autoUpdate(config, "pumpe", ROOT, client)
        end
        -- The OS poll drives the badges, the balance and the alert dot.
        if tick % 6 == 0 or (action ~= "__tick" and action ~= "__idle") then
            poll = request("PUMPE_POLL", {}, true) or poll
            if poll.balance and account then account.balance = poll.balance end
            if not sessionToken then return end
        end
    end
end

-- The start-up: the letters land one at a time, the wordmark blinks, then
-- the tagline holds. A device still carrying an older shared library has no
-- ui.splash, so it keeps the old progress-bar boot instead of crashing.
if type(ui.splash) == "function" then
    ui.splash(target, "PUMPE", "Small yet Mighty",
        { footnote = "v" .. config.version })
else
    ui.boot(target, "PUMPE", "POCKET ECONOMY v" .. config.version)
end
-- Check for a new release at every restart, straight from the public
-- manifest. The Bank Server no longer has to hold a copy for us.
net.autoUpdate(config, "pumpe", ROOT, client,
    { force = true, programVersion = PROGRAM_VERSION })
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
