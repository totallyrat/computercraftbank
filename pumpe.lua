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
local updateGps
local payMenu
local deviceFile = fs.combine(ROOT, "pumpe_device.dat")
local device = util.loadTable(deviceFile, {
    last_name = "",
    onboarding_complete = false,
    proximity_enabled = true,
})
if device.onboarding_complete == nil then device.onboarding_complete = false end
if device.proximity_enabled == nil then device.proximity_enabled = true end

ui.usePhoneStyle(true)

local function request(action, payload, silent)
    payload = payload or {}
    if sessionToken and not payload.session_token then
        payload.session_token = sessionToken
    end
    local result, err, code = client:request(action, payload)
    if not result and not silent then
        if code == "SESSION_EXPIRED" then
            sessionToken, account = nil, nil
            ui.setIdleLock(nil)
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

local function enableDeviceLock()
    ui.setIdleLock(tonumber(config.pumpe_lock_seconds) or 60, function()
        lockScreen(false)
    end)
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
        hint = "Enter your account name",
        initial = device.last_name,
        maxLength = 20,
        allowSpace = true,
    })
    if not name then return false end
    local pin = ui.pin(target, "Foxy Account PIN", true)
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

local function chooseGender()
    local width, height = target.getSize()
    while true do
        ui.clear(target)
        ui.header(target, "Foxy Account", "Choose your pronouns")
        local scene = ui.scene(target)
        local labels = { "She / her", "He / him", "They / them", "Prefer not to say" }
        local startY = 6
        for index, label in ipairs(labels) do
            scene:button("gender:" .. label, 3, startY + (index - 1) * 3,
                width - 5, 2, label, {
                    background = index == 3 and ui.theme.accentDark or ui.theme.panel,
                })
        end
        scene:button("back", 2, height, 7, 1, "<Back",
            { background = ui.theme.panel })
        local action = scene:wait()
        if action == "back" or action == "__terminate" then return nil end
        local gender = action and action:match("^gender:(.+)$")
        if gender then return gender end
    end
end

local function createAccount()
    local name = ui.input(target, "Create Foxy Account", {
        hint = "Choose an account name",
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
    local gender = chooseGender()
    if not gender then return false end
    local result, err = client:request("REGISTER", {
        name = name,
        pin = pin,
        gender = gender,
    })
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
    enableDeviceLock()
    return true
end

local function onboardingIntro()
    local width, height = target.getSize()
    local page, blink = 1, true
    while running do
        ui.clear(target)
        ui.header(target, page == 1 and "Hello."
                or page == 2 and "Built for real life"
                or "Your Foxy Account",
            page == 1 and "Welcome to PUMPE"
                or page == 2 and "One pocket. Every app."
                or "One account, every app",
            util.formatClock(blink))
        local scene = ui.scene(target)
        if page == 1 then
            ui.center(target, 6, "Money. Pay. Events.", ui.theme.ink)
            ui.center(target, 8, "Made to feel like", ui.theme.muted)
            ui.center(target, 9, "an actual phone.", ui.theme.accent)
            scene:button("next", 3, 13, width - 5, 3, "Continue",
                { background = ui.theme.accentDark, shadow = true })
        elseif page == 2 then
            local features = {
                { "PUMPE Pay", "Pay by code, nearby or send", colors.blue },
                { "Live Events", "Tickets, countdowns and entry codes", colors.purple },
                { "Private by default", "Protected by your Foxy Account PIN", colors.green },
            }
            for index, feature in ipairs(features) do
                local y = 4 + (index - 1) * 5
                ui.card(target, 2, y, width - 2, 4, feature[3])
                ui.text(target, 4, y, feature[1], ui.theme.ink, ui.theme.panel)
                ui.wrappedText(target, 4, y + 1, feature[2],
                    width - 6, 2, ui.theme.muted, ui.theme.panel)
            end
            scene:button("next", width - 9, height, 9, 1, "Next  >",
                { background = ui.theme.accentDark })
            scene:button("back", 1, height, 8, 1, "< Back",
                { background = ui.theme.panel })
        else
            ui.card(target, 2, 5, width - 2, 6, ui.theme.accent)
            ui.text(target, 4, 6, "Foxy Account", ui.theme.ink, ui.theme.panel)
            ui.wrappedText(target, 4, 8,
                "Balance, identity and purchases stay together.",
                width - 6, 3, ui.theme.muted, ui.theme.panel)
            scene:button("create", 3, 12, width - 5, 3,
                "Set Up New Account",
                { background = ui.theme.accentDark, shadow = true })
            scene:button("login", 3, 16, width - 5, 2,
                "Sign In",
                { background = ui.theme.panel })
            scene:button("back", 1, height, 8, 1, "< Back",
                { background = ui.theme.panel })
        end
        if page == 1 then
            scene:button("exit", 1, height, 6, 1, "Exit",
                { background = ui.theme.panel })
        end
        ui.center(target, height - 1,
            page == 1 and "o . ." or page == 2 and ". o ." or ". . o",
            ui.theme.muted)
        local action = scene:wait({ tickRate = 0.5 })
        if action == "__tick" or action == "__idle" then
            blink = not blink
        elseif action == "next" then
            page = math.min(3, page + 1)
            phoneTransition(page == 2 and "Discover" or "Foxy Account")
        elseif action == "back" then
            page = math.max(1, page - 1)
        elseif action == "login" or action == "create" then
            return action
        elseif action == "exit" or action == "__terminate" then
            return "exit"
        end
    end
end

local function accountLanding()
    local width, height = target.getSize()
    while running and not sessionToken do
        ui.clear(target)
        ui.header(target, "PUMPE", "Your pocket economy",
            util.formatClock())
        ui.center(target, 6, "Welcome back.", ui.theme.ink)
        if device.last_name ~= "" then
            ui.center(target, 8, device.last_name, ui.theme.accent)
        else
            ui.center(target, 8, "Foxy Account", ui.theme.accent)
        end
        local scene = ui.scene(target)
        scene:button("login", 3, 11, width - 5, 3, "Sign In",
            { background = ui.theme.accentDark, shadow = true })
        scene:button("create", 3, 15, width - 5, 2, "Create Foxy Account",
            { background = ui.theme.panel })
        scene:button("exit", 1, height, 6, 1, "Exit",
            { background = ui.theme.panel })
        local action = scene:wait()
        if action == "login" or action == "create" then return action end
        if action == "exit" or action == "__terminate" then return "exit" end
    end
end

local function welcome()
    while running and not sessionToken do
        ui.setIdleLock(nil)
        local action = device.onboarding_complete
            and accountLanding() or onboardingIntro()
        if action == "login" then
            login()
        elseif action == "create" then
            createAccount()
        elseif action == "exit" then
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
        ui.header(target, "Wallet", account.name, util.formatClock(blink))
        ui.card(target, 2, 5, width - 2, 4, ui.theme.success)
        ui.text(target, 4, 6, "AVAILABLE", ui.theme.muted, ui.theme.panel)
        ui.text(target, 4, 7, money(account.balance), ui.theme.ink, ui.theme.panel)
        ui.text(target, 2, 10, "RECENT", ui.theme.muted)
        local pageItems, actualPage, pages = util.page(history, page, 1)
        page = actualPage
        for index, tx in ipairs(pageItems) do
            local y = 11 + (index - 1) * 8
            local color = tx.amount >= 0 and ui.theme.success or ui.theme.ink
            ui.card(target, 2, y, width - 2, 8, color)
            ui.wrappedText(target, 4, y, tx.description,
                width - 6, 5, ui.theme.ink, ui.theme.panel)
            local amountText = (tx.amount >= 0 and "+" or "") .. money(tx.amount)
            ui.text(target, 4, y + 5, "Day " .. tx.day .. " " .. tx.time,
                ui.theme.muted)
            ui.text(target, 4, y + 6, amountText, color)
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

local function notificationsScreen()
    local result = request("NOTIFICATIONS")
    if not result then return end
    request("MARK_NOTIFICATIONS_READ", {}, true)
    local items, page, blink = result.notifications, 1, true
    while true do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "Notifications", #items .. " total", util.formatClock(blink))
        local pageItems, actualPage, pages = util.page(items, page, 1)
        page = actualPage
        if #items == 0 then ui.center(target, 9, "All quiet here", ui.theme.muted) end
        for index, item in ipairs(pageItems) do
            local y = 4 + (index - 1) * 14
            ui.card(target, 2, y, width - 2, 14,
                item.kind == "warning" and ui.theme.warning or ui.theme.accent)
            ui.wrappedText(target, 4, y, item.title,
                width - 6, 2, ui.theme.ink, ui.theme.panel)
            ui.wrappedText(target, 4, y + 3, item.body,
                width - 6, 8, ui.theme.muted, ui.theme.panel)
            ui.text(target, 4, y + 12,
                "Day " .. item.created_day .. " " .. item.created_time,
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

updateGps = function()
    if not device.proximity_enabled then return false, "Paused" end
    if not gps or not gps.locate then return false, "GPS unavailable" end
    local x, y, z = gps.locate(0.25, false)
    if x then
        local result = request("GPS_UPDATE", { x = x, y = y, z = z }, true)
        if result then
            return true, string.format("%.0f, %.0f, %.0f", x, y, z)
        end
    end
    return false, "Finding location"
end

local function proximityScreen()
    local blink, tick = true, 0
    local located, locationText = updateGps()
    while sessionToken do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "Proximity Pay", "PUMPE Pay",
            util.formatClock(blink))
        local active = device.proximity_enabled
        local pulseColor = active and (blink and ui.theme.success or ui.theme.accent)
            or colors.gray
        ui.card(target, 2, 5, width - 2, 9, pulseColor)
        ui.center(target, 6, active and "((  P  ))" or "(  PAUSED  )",
            pulseColor, ui.theme.panel)
        ui.center(target, 8,
            active and (located and "Broadcasting nearby" or locationText)
                or "Location sharing is off",
            ui.theme.ink, ui.theme.panel)
        ui.center(target, 10,
            active and "Nearby kiosks can send" or "Nearby kiosks cannot",
            ui.theme.muted, ui.theme.panel)
        ui.center(target, 11,
            active and "payment requests" or "find your PUMPE",
            ui.theme.muted, ui.theme.panel)
        if active and located then
            ui.center(target, 12, locationText, ui.theme.muted, ui.theme.panel)
        end

        local scene = ui.scene(target)
        scene:button("toggle", 3, 15, width - 5, 2,
            active and "Turn Off Proximity Pay" or "Turn On Proximity Pay", {
                background = active and ui.theme.panel or ui.theme.accentDark,
            })
        scene:button("back", 1, height, 8, 1, "< Pay",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 0.5 })
        if action == "__tick" or action == "__idle" then
            blink = not blink
            tick = tick + 1
            if active and tick % math.max(1,
                math.floor((tonumber(config.proximity_update_seconds) or 2) / 0.5))
                == 0 then
                located, locationText = updateGps()
                local pending = request("PENDING_REQUESTS", {}, true)
                if pending and #pending.requests > 0 then pendingRequestPopup() end
            end
        elseif action == "toggle" then
            device.proximity_enabled = not device.proximity_enabled
            saveDevice()
            located, locationText = updateGps()
        elseif action == "back" or action == "__terminate" then
            return
        end
    end
end

payMenu = function()
    local blink, tick = true, 0
    while sessionToken do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "PUMPE Pay", "Choose how to pay",
            util.formatClock(blink))
        local scene = ui.scene(target)
        scene:button("code", 2, 5, width - 2, 3,
            "Code Pay\nEnter a six-character\nkiosk code", {
                background = colors.blue,
                shadow = true,
            })
        scene:button("proximity", 2, 9, width - 2, 3,
            "Proximity Pay\n"
                .. (device.proximity_enabled and "On and broadcasting\nnearby"
                    or "Off - tap to enable"), {
                background = device.proximity_enabled and colors.green or colors.gray,
                shadow = true,
            })
        scene:button("send", 2, 13, width - 2, 3,
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
            tick = tick + 1
            if device.proximity_enabled and tick % math.max(1,
                math.floor((tonumber(config.proximity_update_seconds) or 2) / 0.5))
                == 0 then
                updateGps()
            end
        elseif action == "code" then
            phoneTransition("Code Pay", colors.blue)
            payCode()
        elseif action == "proximity" then
            phoneTransition("Proximity Pay", colors.green)
            proximityScreen()
        elseif action == "send" then
            phoneTransition("Send Money", colors.purple)
            sendMoney()
        elseif action == "back" or action == "__terminate" then
            return
        end
    end
end

local function settingsScreen()
    local width, height = target.getSize()
    ui.clear(target)
    ui.header(target, "Settings", "Foxy Account", util.formatClock())
    ui.card(target, 2, 5, width - 2, 8, ui.theme.accent)
    ui.text(target, 4, 5, "FOXY ACCOUNT", ui.theme.muted, ui.theme.panel)
    ui.text(target, 4, 6, account.name, ui.theme.ink, ui.theme.panel)
    ui.text(target, 4, 8, "ACCOUNT ID", ui.theme.muted, ui.theme.panel)
    ui.text(target, 4, 9, account.account_id, ui.theme.ink, ui.theme.panel)
    ui.text(target, 4, 11, "PERSONAL NUMBER", ui.theme.muted, ui.theme.panel)
    ui.text(target, 4, 12, account.personal_number, ui.theme.ink, ui.theme.panel)
    local scene = ui.scene(target)
    scene:button("logout", 2, 15, width - 2, 2, "Sign Out",
        { background = ui.theme.danger })
    scene:button("back", 1, height, 8, 1, "< Home",
        { background = ui.theme.panel })
    local action = scene:wait()
    if action == "logout" and ui.confirm(target, "Sign Out",
        "Leave this PUMPE session?", "Sign Out", "Back") then
        sessionToken, account = nil, nil
        ui.setIdleLock(nil)
    end
end

local function mainMenu()
    local blink, tick, page = true, 0, 1
    local summary = refreshSummary() or {}
    enableDeviceLock()
    if device.proximity_enabled then updateGps() end
    local pages = {
        {
            { "pay", "P\nPay", colors.blue },
            { "balance", "$\nWallet", colors.green },
            { "history", "=\nActivity", colors.lightBlue },
            { "events", "*\nEvents", colors.purple },
        },
        {
            { "tickets", "#\nTickets", colors.orange },
            { "notifications", "!\nAlerts", colors.red },
            { "tax", "%\nTax", colors.orange },
            { "subscriptions", "S\nSubs", colors.magenta },
        },
        {
            { "settings", "o\nSettings", colors.gray },
            { "lock", "L\nLock", colors.blue },
            { "exit", "X\nClose", colors.red },
        },
    }
    while running and sessionToken do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "Foxy Account", account.name, util.formatClock(blink))
        ui.card(target, 2, 4, width - 2, 3, ui.theme.success)
        ui.text(target, 4, 4, "AVAILABLE", ui.theme.muted, ui.theme.panel)
        ui.text(target, 4, 5, money(account.balance), ui.theme.ink, ui.theme.panel)
        local alertCount = (summary.unread_notifications or 0)
            + (summary.pending_requests or 0)
        if alertCount > 0 then
            ui.text(target, width - 5, 5, tostring(alertCount), colors.black,
                ui.theme.warning)
        end

        local scene = ui.scene(target)
        local iconWidth = math.max(8, math.floor((width - 4) / 2))
        for index, entry in ipairs(pages[page]) do
            local column = (index - 1) % 2
            local row = math.floor((index - 1) / 2)
            local x = column == 0 and 2 or width - iconWidth
            local y = 8 + row * 4
            local label = entry[2]
            if entry[1] == "notifications" and alertCount > 0 then
                label = "!" .. alertCount .. "\nAlerts"
            end
            scene:button(entry[1], x, y, iconWidth, 3, label, {
                background = entry[3],
                shadow = true,
            })
        end
        ui.center(target, 16,
            page == 1 and "o  .  ."
                or page == 2 and ".  o  ."
                or ".  .  o",
            ui.theme.muted)
        scene:button("prev", 1, 18, 7, 1, "<",
            { background = ui.theme.panel, disabled = page == 1 })
        scene:button("next", width - 6, 18, 7, 1, ">",
            { background = ui.theme.panel, disabled = page == #pages })
        scene:button("home", math.floor(width / 2) - 3, height, 7, 1, "",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 0.5 })
        if action == "__tick" or action == "__idle" then
            blink = not blink
            tick = tick + 1
            net.autoUpdate(config, "pumpe", ROOT)
            local proximityTicks = math.max(1,
                math.floor((tonumber(config.proximity_update_seconds) or 2) / 0.5))
            if device.proximity_enabled and tick % proximityTicks == 0 then
                updateGps()
                local pending = request("PENDING_REQUESTS", {}, true)
                if pending and #pending.requests > 0 then
                    pendingRequestPopup()
                end
            end
            if tick % 10 == 0 then
                summary = refreshSummary(true) or summary
                if not sessionToken then return end
            end
        elseif action == "prev" then
            page = math.max(1, page - 1)
        elseif action == "next" then
            page = math.min(#pages, page + 1)
        elseif action == "home" then
            page = 1
        elseif action == "balance" then
            phoneTransition("Wallet", colors.green); balanceScreen()
        elseif action == "pay" then
            phoneTransition("PUMPE Pay", colors.blue); payMenu()
        elseif action == "history" then
            phoneTransition("Activity", colors.lightBlue); historyScreen()
        elseif action == "events" then
            phoneTransition("Events", colors.purple); eventsScreen()
        elseif action == "tickets" then
            phoneTransition("Tickets", colors.orange); myTicketsScreen()
        elseif action == "notifications" then
            phoneTransition("Alerts", colors.red); notificationsScreen()
        elseif action == "tax" then
            phoneTransition("Tax", colors.orange); taxScreen()
        elseif action == "subscriptions" then
            phoneTransition("Subscriptions", colors.magenta); subscriptionsScreen()
        elseif action == "settings" then
            phoneTransition("Settings", colors.gray); settingsScreen()
        elseif action == "lock" then
            lockScreen(true)
        elseif action == "exit" or action == "__terminate" then
            running = false
        end
        if sessionToken then
            summary = refreshSummary(true) or summary
        end
    end
end

ui.boot(target, "PUMPE", "POCKET ECONOMY v" .. config.version)
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
