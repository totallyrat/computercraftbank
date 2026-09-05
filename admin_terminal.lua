local ROOT = fs.getDir(shell.getRunningProgram())
if ROOT == "" then ROOT = "." end
package.path = package.path .. ";" .. fs.combine(ROOT, "?.lua")
    .. ";" .. fs.combine(ROOT, "?/init.lua")

-- Stamped by tools/build_release_manifest.js. A program running beside a
-- config.lua from a different release means a partial install.
local PROGRAM_VERSION = "8.2.0"
local config = require("config")
local util = require("lib.util")
local net = require("lib.net")
local ui = require("lib.ui")

local target = term.current()
local client = net.client(config)
local governmentToken
local running = true

local function money(value)
    return util.money(value, config.currency)
end

local function request(action, payload, silent)
    payload = payload or {}
    if governmentToken and not payload.government_token then
        payload.government_token = governmentToken
    end
    local result, err, code = client:request(action, payload)
    if not result and not silent then ui.networkError(target, err) end
    if code == "GOVERNMENT_AUTH" then governmentToken = nil end
    return result, err, code
end

local function login()
    local key = ui.input(target, "GOVERNMENT ACCESS", {
        hint = "Enter the controller security key",
        maxLength = 64,
        mask = "*",
    })
    if not key then return false end
    local result, err = client:request("GOVERNMENT_LOGIN", { key = key })
    if not result then
        ui.message(target, "error", "ACCESS DENIED", err, 1.3)
        return false
    end
    governmentToken = result.government_token
    ui.message(target, "success", "ACCESS GRANTED", "Controller unlocked", 0.8)
    return true
end

local function loginScreen()
    local width, height = target.getSize()
    while running and not governmentToken do
        ui.clear(target)
        ui.header(target, "TAX CONTROLLER", "Government administration",
            util.formatClock())
        ui.center(target, 6, "RESTRICTED SYSTEM", ui.theme.warning)
        ui.center(target, 8, "Every action is logged by the bank", ui.theme.muted)
        local scene = ui.scene(target)
        scene:button("login", 4, 11, width - 7, 3, "UNLOCK CONTROLLER",
            { background = ui.theme.warning, foreground = colors.black, shadow = true })
        scene:button("exit", 1, height, 6, 1, "EXIT",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 0.5 })
        if action == "login" then login()
        elseif action == "exit" or action == "__terminate" then running = false end
    end
end

local function openPeriod()
    local endDay = ui.input(target, "OPEN TAX PERIOD", {
        hint = "End day (today " .. util.ingameDay() .. ")",
        mode = "number",
        initial = tostring(util.ingameDay() + 7),
        maxLength = 8,
    })
    if not endDay then return end
    local personal = ui.input(target, "PERSONAL RATE", {
        hint = "Percentage, 0-100",
        mode = "number", initial = "10", maxLength = 6,
    })
    if not personal then return end
    local commercial = ui.input(target, "COMMERCIAL RATE", {
        hint = "Percentage, 0-100",
        mode = "number", initial = "15", maxLength = 6,
    })
    if not commercial then return end
    local threshold = ui.input(target, "INCOME THRESHOLD", {
        hint = "Only qualifying accounts are notified",
        mode = "number", initial = "1500", maxLength = 12,
    })
    if not threshold then return end
    if not ui.confirm(target, "OPEN PERIOD",
        "Until day " .. endDay .. " at " .. personal .. "%", "OPEN", "BACK") then
        return
    end
    local result, err = request("OPEN_TAX_PERIOD", {
        end_day = tonumber(endDay),
        personal_rate = tonumber(personal),
        commercial_rate = tonumber(commercial),
        threshold = tonumber(threshold),
    }, true)
    if result then
        ui.message(target, "success", "PERIOD OPEN",
            result.period.period_id .. " until day " .. result.period.end_day, 1.1)
    else ui.message(target, "error", "COULD NOT OPEN", err, 1.1) end
end

local function setRates()
    local personal = ui.input(target, "NEW PERSONAL RATE", {
        hint = "Percentage, 0-100",
        mode = "number", maxLength = 6,
    })
    if not personal then return end
    local commercial = ui.input(target, "NEW COMMERCIAL RATE", {
        hint = "Percentage, 0-100",
        mode = "number", maxLength = 6,
    })
    if not commercial then return end
    if not ui.confirm(target, "CHANGE RATES",
        personal .. "% personal / " .. commercial .. "% company",
        "APPLY", "BACK") then return end
    local result, err = request("SET_TAX_RATES", {
        personal_rate = tonumber(personal),
        commercial_rate = tonumber(commercial),
    }, true)
    if result then
        ui.message(target, "success", "RATES UPDATED",
            result.period.period_id, 0.9)
    else ui.message(target, "error", "UPDATE FAILED", err, 1.1) end
end

local function revenueScreen()
    local result = request("TAX_OVERVIEW")
    if not result then return end
    local periods, page, blink = result.periods, 1, true
    while true do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "TAX REVENUE", "All declaration periods",
            util.formatClock(blink))
        ui.card(target, 2, 5, width - 2, 3, ui.theme.success)
        ui.text(target, 4, 5, "TOTAL COLLECTED", ui.theme.muted, ui.theme.panel)
        ui.text(target, 4, 6, money(result.total_revenue),
            ui.theme.success, ui.theme.panel)
        local pageItems, actualPage, pages = util.page(periods, page, 3)
        page = actualPage
        for index, period in ipairs(pageItems) do
            local y = 9 + (index - 1) * 3
            ui.card(target, 2, y, width - 2, 2,
                period.status == "open" and ui.theme.warning or colors.gray)
            ui.text(target, 4, y, period.period_id .. "  " .. string.upper(period.status),
                ui.theme.ink, ui.theme.panel)
            local detail = period.submitted .. "/" .. period.requested
                .. " filed  " .. money(period.collected)
            ui.text(target, 4, y + 1, detail, ui.theme.muted, ui.theme.panel)
        end
        local scene = ui.scene(target)
        scene:button("back", 1, height, 7, 1, "< BACK",
            { background = ui.theme.panel })
        if pages > 1 then
            scene:button("prev", width - 9, height, 4, 1, "<",
                { background = ui.theme.panel, disabled = page <= 1 })
            scene:button("next", width - 4, height, 4, 1, ">",
                { background = ui.theme.panel, disabled = page >= pages })
        end
        local action = scene:wait({ tickRate = 0.5 })
        blink = not blink
        if action == "back" or action == "__terminate" then return
        elseif action == "prev" then page = page - 1
        elseif action == "next" then page = page + 1 end
    end
end

local function stateDeposit()
    local recipient = ui.input(target, "STATE DEPOSIT", {
        hint = "Recipient PUMPE account",
        maxLength = 20,
        allowSpace = true,
    })
    if not recipient then return end
    local amount = ui.input(target, "DEPOSIT AMOUNT", {
        hint = recipient,
        mode = "number", maxLength = 14,
    })
    if not amount then return end
    local reason = ui.input(target, "DEPOSIT REASON", {
        hint = "Shown in the citizen's history",
        maxLength = 60,
        allowSpace = true,
    })
    if not reason then return end
    if not ui.confirm(target, "AUTHORIZE DEPOSIT",
        money(amount) .. " to " .. recipient, "DEPOSIT", "BACK") then return end
    local result, err = request("STATE_DEPOSIT", {
        recipient = recipient,
        amount = tonumber(amount),
        reason = reason,
    }, true)
    if result then
        ui.message(target, "success", "DEPOSIT COMPLETE",
            money(result.amount) .. " to " .. result.account.name, 1)
    else ui.message(target, "error", "DEPOSIT FAILED", err, 1.1) end
end

local function auditCompany()
    local query = ui.input(target, "AUDIT COMPANY", {
        hint = "Exact company name or tax ID",
        maxLength = 30,
        allowSpace = true,
    })
    if not query then return end
    local result, err = request("AUDIT_COMPANY", { query = query }, true)
    if not result then
        ui.message(target, "error", "NOT FOUND", err, 1)
        return
    end
    local company = result.company
    local width, height = target.getSize()
    ui.clear(target)
    ui.header(target, "COMPANY AUDIT", company.tax_id, util.formatClock())
    ui.card(target, 3, 5, width - 5, 10,
        company.status == "active" and ui.theme.success or ui.theme.danger)
    ui.text(target, 5, 6, company.name, ui.theme.ink, ui.theme.panel)
    ui.text(target, 5, 8, "OWNER  " .. tostring(result.owner_name),
        ui.theme.muted, ui.theme.panel)
    ui.text(target, 5, 10, "TERMINALS  " .. #company.linked_terminal_ids,
        ui.theme.muted, ui.theme.panel)
    ui.text(target, 5, 12, "QUICK ITEMS  " .. #company.quick_items,
        ui.theme.muted, ui.theme.panel)
    ui.text(target, 5, 14, "STATUS  " .. string.upper(company.status),
        company.status == "active" and ui.theme.success or ui.theme.danger,
        ui.theme.panel)
    local scene = ui.scene(target)
    scene:button("back", 1, height, 7, 1, "< BACK",
        { background = ui.theme.panel })
    scene:wait()
end

local function statsScreen()
    local result = request("GOVERNMENT_STATS")
    if not result then return end
    local width, height = target.getSize()
    ui.clear(target)
    ui.header(target, "BANK STATISTICS", "Server v" .. result.version,
        util.formatClock())
    local values = {
        { "ACCOUNTS", result.accounts, ui.theme.accent },
        { "COMPANIES", result.companies, colors.magenta },
        { "TRANSACTIONS", result.transactions, ui.theme.success },
        { "DECLARATIONS", result.declarations, ui.theme.warning },
        { "TAX REVENUE", money(result.tax_revenue), ui.theme.success },
        { "UPTIME", result.uptime .. "s", ui.theme.accent },
    }
    local cardWidth = math.floor((width - 5) / 2)
    for index, item in ipairs(values) do
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        local x = 2 + column * (cardWidth + 1)
        local y = 5 + row * 4
        ui.card(target, x, y, cardWidth, 3, item[3])
        ui.text(target, x + 2, y, item[1], ui.theme.muted, ui.theme.panel)
        ui.text(target, x + 2, y + 1, tostring(item[2]),
            ui.theme.ink, ui.theme.panel, cardWidth - 3)
    end
    local scene = ui.scene(target)
    scene:button("back", 1, height, 7, 1, "< BACK",
        { background = ui.theme.panel })
    scene:wait()
end

local function closePeriod()
    local overview = request("TAX_OVERVIEW")
    if not overview then return end
    local open
    for _, period in ipairs(overview.periods) do
        if period.status == "open" then open = period break end
    end
    if not open then
        ui.message(target, "info", "NO OPEN PERIOD", "Nothing to close", 1)
        return
    end
    if not ui.confirm(target, "CLOSE " .. open.period_id,
        open.submitted .. "/" .. open.requested .. " declarations filed",
        "CLOSE", "BACK") then return end
    local result, err = request("CLOSE_TAX_PERIOD", {
        period_id = open.period_id,
    }, true)
    if result then
        ui.message(target, "success", "PERIOD CLOSED", open.period_id, 1)
    else ui.message(target, "error", "CLOSE FAILED", err, 1.1) end
end

local function systemScreen()
    local width, height = target.getSize()
    ui.clear(target)
    ui.header(target, "SYSTEM CONTROL", "Tax Controller v" .. config.version,
        util.formatClock())
    ui.card(target, 3, 6, width - 5, 7, ui.theme.accent)
    ui.text(target, 5, 7, "SECURE SESSION ACTIVE", ui.theme.success, ui.theme.panel)
    ui.text(target, 5, 9, "Protocol " .. config.protocol, ui.theme.muted, ui.theme.panel)
    ui.text(target, 5, 11, "Computer #" .. os.getComputerID(),
        ui.theme.muted, ui.theme.panel)
    local scene = ui.scene(target)
    scene:button("back", 1, height, 7, 1, "< BACK",
        { background = ui.theme.panel })
    scene:wait()
end

-- Admin controls -------------------------------------------------------------

local function adminRequest(action, payload, silent)
    payload = payload or {}
    payload.government_token = governmentToken
    local result, err = client:request(action, payload)
    if not result and not silent then ui.networkError(target, err) end
    return result, err
end

local function amountPrompt(title, hint)
    local raw = ui.input(target, title, {
        hint = hint, mode = "number", maxLength = 12,
    })
    if not raw then return nil end
    local amount = tonumber(raw)
    if not amount or amount <= 0 then
        ui.message(target, "warning", "ENTER AN AMOUNT", nil, 1.2)
        return nil
    end
    return amount
end

local function reasonPrompt(title)
    return ui.input(target, title, {
        hint = "Shown to the account holder",
        maxLength = 50, allowSpace = true, minLength = 2,
    })
end

-- Everything that can be done to one account, in one place.
-- A thread between the state and one account. Only the government moves
-- money in it, but the holder can answer and can settle what is asked, which
-- is what makes it usable for a speeding ticket rather than a broadcast.
local function messageThread(card)
    local afterSeq, messages, blink = 0, {}, true
    while running and governmentToken do
        local width, height = target.getSize()
        local loaded = adminRequest("ADMIN_MESSAGE_HISTORY", {
            account_id = card.account_id,
            after_seq = afterSeq,
        }, true)
        if loaded then
            for _, item in ipairs(loaded.messages) do
                messages[#messages + 1] = item
                afterSeq = math.max(afterSeq, item.seq or 0)
            end
            while #messages > 40 do table.remove(messages, 1) end
        end
        ui.clear(target)
        ui.header(target, "GOVERNMENT MESSAGE", card.name,
            util.formatClock(blink))
        local row, bottom = 5, height - 6
        local first = math.max(1, #messages - (bottom - row))
        for index = first, #messages do
            local item = messages[index]
            if row > bottom then break end
            local mine = item.sender_id == "GOVERNMENT"
            local label
            if item.kind == "money_request" then
                label = "ASKED " .. money(item.amount)
                    .. (item.status == "paid" and " - PAID" or "")
            elseif item.kind == "money_sent" then
                label = item.body or "money"
            else
                label = item.body or ""
            end
            ui.text(target, 2, row,
                ui.truncate((mine and "GOV  " or (card.name .. "  ")) .. label,
                    width - 3),
                item.kind == "money_request" and ui.theme.warning
                    or mine and ui.theme.accent or ui.theme.ink)
            row = row + 1
        end
        if #messages == 0 then
            ui.center(target, 9, "No messages yet", ui.theme.muted)
        end
        local scene = ui.scene(target)
        local buttonWidth = math.floor((width - 5) / 3)
        scene:button("say", 2, height - 4, buttonWidth, 3, "WRITE",
            { background = ui.theme.accentDark })
        scene:button("demand", 3 + buttonWidth, height - 4, buttonWidth, 3,
            "ASK FOR MONEY", { background = ui.theme.warning,
                foreground = colors.black })
        scene:button("pay", 4 + buttonWidth * 2, height - 4, buttonWidth, 3,
            "SEND MONEY", { background = ui.theme.success,
                foreground = colors.black })
        scene:button("back", 1, height, 8, 1, "< BACK",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 2 })
        blink = not blink
        if action == "back" or action == "__terminate" then return end
        if action == "say" then
            local body = ui.input(target, "MESSAGE", {
                hint = "To " .. card.name, maxLength = 120,
                allowSpace = true, minLength = 1,
            })
            if body then
                adminRequest("ADMIN_MESSAGE",
                    { account_id = card.account_id, body = body })
            end
        elseif action == "demand" then
            local amount = amountPrompt("ASK FOR MONEY",
                card.name .. " can settle this in the chat")
            if amount then
                local reason = reasonPrompt("WHAT FOR")
                if reason then
                    adminRequest("ADMIN_MESSAGE_DEMAND", {
                        account_id = card.account_id,
                        amount = amount, note = reason,
                    })
                end
            end
        elseif action == "pay" then
            local amount = amountPrompt("SEND MONEY", "Paid to " .. card.name)
            if amount then
                local reason = reasonPrompt("WHAT FOR")
                if reason then
                    adminRequest("ADMIN_MESSAGE_PAY", {
                        account_id = card.account_id,
                        amount = amount, note = reason,
                    })
                end
            end
        end
    end
end

-- Banner, full screen or a message, aimed at everyone or at one account.
local function sendAnnouncement(card)
    local who = card and card.name or "Everyone"
    local title = ui.input(target, "ANNOUNCEMENT", {
        hint = who .. " will see this", maxLength = 36,
        allowSpace = true, minLength = 2,
    })
    if not title then return end
    local body = ui.input(target, "DETAILS", {
        hint = "The line underneath", maxLength = 120,
        allowSpace = true, minLength = 0,
    })
    if not body then return end
    local width, height = target.getSize()
    ui.clear(target)
    ui.header(target, "HOW LOUD?", who .. "  -  " .. title, util.formatClock())
    local scene = ui.scene(target)
    scene:button("banner", 2, 5, width - 2, 4,
        "BANNER\nDrops in, then goes away",
        { background = ui.theme.accentDark })
    scene:button("modal", 2, 10, width - 2, 4,
        "FULL SCREEN\nStays until they press Continue",
        { background = ui.theme.danger })
    if card then
        scene:button("message", 2, 15, width - 2, 3,
            "TEXT MESSAGE\nThey can answer", { background = colors.purple })
    end
    scene:button("back", 1, height, 8, 1, "< BACK",
        { background = ui.theme.panel })
    local action = scene:wait()
    if action == "message" and card then
        if adminRequest("ADMIN_MESSAGE",
            { account_id = card.account_id, body = title
                .. (#body > 0 and (" - " .. body) or "") }) then
            messageThread(card)
        end
        return
    end
    if action ~= "banner" and action ~= "modal" then return end
    if adminRequest("ADMIN_ANNOUNCE", {
        title = title, body = body, mode = action,
        account_id = card and card.account_id or nil,
    }) then
        ui.message(target, "success", "ANNOUNCED", who .. "  -  " .. title, 1.4)
    end
end

local function accountActions(card)
    while running and governmentToken do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, card.name,
            money(card.balance) .. (card.banned and "  BANNED" or ""),
            util.formatClock())
        if card.approved == false then
            ui.text(target, 2, 4, "WAITING FOR APPROVAL", ui.theme.warning)
        end
        if card.tax_demand then
            ui.text(target, 2, 5, "DEMAND " .. money(card.tax_demand.amount),
                ui.theme.warning)
        end
        local scene = ui.scene(target)
        local items = {
            { "credit", "ADD MONEY", ui.theme.success },
            { "debit", "REMOVE MONEY", ui.theme.warning },
            { "demand", "TAX DEMAND", ui.theme.accentDark },
            { "ban", card.banned and "UNBAN" or "BAN", ui.theme.danger },
            { "notify", "ANNOUNCE TO THEM", colors.magenta },
            { "thread", "MESSAGES", colors.purple },
        }
        if card.approved == false then
            items[#items + 1] = { "approve", "APPROVE", ui.theme.success }
        end
        local buttonWidth = math.floor((width - 5) / 2)
        for index, item in ipairs(items) do
            local column = (index - 1) % 2
            local row = math.floor((index - 1) / 2)
            scene:button(item[1], 2 + column * (buttonWidth + 1),
                7 + row * 3, buttonWidth, 2, item[2], {
                    background = item[3],
                    foreground = item[1] == "credit" and colors.black
                        or colors.white,
                })
        end
        scene:button("back", 1, height, 8, 1, "< BACK",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 1 })
        if action == "back" or action == "__terminate" then return end
        local updated
        if action == "credit" then
            local amount = amountPrompt("ADD MONEY", "Credited to " .. card.name)
            if amount then
                local reason = reasonPrompt("REASON")
                if reason then
                    updated = adminRequest("ADMIN_CREDIT", {
                        account_id = card.account_id,
                        amount = amount, reason = reason,
                    })
                end
            end
        elseif action == "debit" then
            local amount = amountPrompt("REMOVE MONEY", "Taken from " .. card.name)
            if amount then
                local reason = reasonPrompt("REASON")
                if reason then
                    updated = adminRequest("ADMIN_DEBIT", {
                        account_id = card.account_id,
                        amount = amount, reason = reason,
                    })
                end
            end
        elseif action == "demand" then
            local amount = amountPrompt("TAX DEMAND", "They must pay this")
            if amount then
                local reason = reasonPrompt("WHAT FOR")
                if reason then
                    updated = adminRequest("ADMIN_TAX_DEMAND", {
                        account_id = card.account_id,
                        amount = amount, reason = reason,
                    })
                end
            end
        elseif action == "ban" then
            local banning = not card.banned
            if ui.confirm(target, banning and "BAN ACCOUNT" or "LIFT BAN",
                (banning and "Ban " or "Unban ") .. card.name .. "?",
                banning and "BAN" or "UNBAN", "CANCEL") then
                updated = adminRequest("ADMIN_BAN", {
                    account_id = card.account_id, banned = banning,
                })
            end
        elseif action == "approve" then
            updated = adminRequest("ADMIN_APPROVE_ACCOUNT", {
                account_id = card.account_id, approve = true,
            })
        elseif action == "notify" then
            sendAnnouncement(card)
        elseif action == "thread" then
            messageThread(card)
        end
        if updated and updated.account then card = updated.account end
    end
end

local function accountBrowser(pendingOnly)
    local query = ""
    if not pendingOnly then
        query = ui.input(target, "FIND ACCOUNT", {
            hint = "Leave blank to list everyone",
            maxLength = 20, allowSpace = true, minLength = 0,
        }) or ""
    end
    local page = 1
    while running and governmentToken do
        local found = adminRequest("ADMIN_ACCOUNTS", {
            query = query, pending_only = pendingOnly,
        })
        if not found then return end
        local accounts = found.accounts
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, pendingOnly and "PENDING APPROVAL" or "ACCOUNTS",
            #accounts .. " found", util.formatClock())
        if #accounts == 0 then
            ui.center(target, 9, "Nobody matched", ui.theme.muted)
        end
        local scene = ui.scene(target)
        local pageItems, actualPage, pages = util.page(accounts, page, 5)
        page = actualPage
        for index, card in ipairs(pageItems) do
            local suffix = card.banned and "  BANNED"
                or card.approved == false and "  PENDING" or ""
            scene:button("open:" .. card.account_id, 2, 4 + (index - 1) * 2,
                width - 2, 2,
                ui.truncate(card.name .. "  " .. money(card.balance) .. suffix,
                    width - 4),
                { background = card.banned and ui.theme.danger
                    or card.approved == false and ui.theme.warning
                    or ui.theme.panel,
                  foreground = card.approved == false and colors.black
                    or colors.white })
        end
        scene:button("back", 1, height, 8, 1, "< BACK",
            { background = ui.theme.panel })
        if pages > 1 then
            scene:button("prev", width - 15, height, 4, 1, "<",
                { background = ui.theme.panel, disabled = page <= 1 })
            scene:button("next", width - 4, height, 4, 1, ">",
                { background = ui.theme.panel, disabled = page >= pages })
        end
        local action = scene:wait({ tickRate = 1 })
        if action == "back" or action == "__terminate" then return
        elseif action == "prev" then page = page - 1
        elseif action == "next" then page = page + 1
        else
            local id = action and action:match("^open:(.+)$")
            for _, card in ipairs(accounts) do
                if card.account_id == id then accountActions(card) end
            end
        end
    end
end

local function announceScreen()
    sendAnnouncement(nil)
end

local function controlsScreen()
    while running and governmentToken do
        local settings = adminRequest("ADMIN_SETTINGS")
        if not settings then return end
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "CONTROLS", "Government settings", util.formatClock())
        ui.text(target, 2, 5, "Account approval: "
            .. (settings.account_approval and "ON" or "OFF"),
            settings.account_approval and ui.theme.success or ui.theme.muted)
        ui.text(target, 2, 6, "Waiting: " .. settings.pending_approvals,
            settings.pending_approvals > 0 and ui.theme.warning or ui.theme.muted)
        local scene = ui.scene(target)
        local buttonWidth = math.floor((width - 5) / 2)
        local items = {
            { "toggle", settings.account_approval
                and "APPROVAL OFF" or "APPROVAL ON", ui.theme.accentDark },
            { "pending", "PENDING " .. settings.pending_approvals,
                ui.theme.warning },
            { "key", "CHANGE KEY", ui.theme.panel },
            { "back", "< BACK", ui.theme.panel },
        }
        for index, item in ipairs(items) do
            local column = (index - 1) % 2
            local row = math.floor((index - 1) / 2)
            scene:button(item[1], 2 + column * (buttonWidth + 1),
                9 + row * 3, buttonWidth, 2, item[2], {
                    background = item[3],
                    foreground = item[1] == "pending" and colors.black
                        or colors.white,
                })
        end
        local action = scene:wait({ tickRate = 1 })
        if action == "back" or action == "__terminate" then return
        elseif action == "toggle" then
            adminRequest("ADMIN_SET_APPROVAL",
                { enabled = not settings.account_approval })
        elseif action == "pending" then
            accountBrowser(true)
        elseif action == "key" then
            local key = ui.input(target, "NEW GOVERNMENT KEY", {
                hint = "At least six characters",
                maxLength = 40, minLength = 6, allowSpace = true,
            })
            if key and ui.confirm(target, "CHANGE KEY",
                "Everyone signing in here will need the new key.",
                "CHANGE", "CANCEL") then
                if adminRequest("ADMIN_SET_KEY", { new_key = key }) then
                    ui.message(target, "success", "KEY CHANGED",
                        "Keep it safe", 1.6)
                end
            end
        end
    end
end

-- Every thread the government is holding, so a reply is not missed.
local function messageInbox()
    local page = 1
    while running and governmentToken do
        local loaded = adminRequest("ADMIN_MESSAGE_THREADS")
        if not loaded then return end
        local threads = loaded.threads
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "GOVERNMENT MESSAGES", #threads .. " threads",
            util.formatClock())
        local scene = ui.scene(target)
        local pageItems, actualPage, pages = util.page(threads, page, 5)
        page = actualPage
        if #threads == 0 then
            ui.center(target, 9, "No threads yet", ui.theme.muted)
            ui.center(target, 11, "Start one from an account", ui.theme.muted)
        end
        for index, thread in ipairs(pageItems) do
            scene:button("open:" .. thread.account_id, 2, 4 + (index - 1) * 3,
                width - 2, 2,
                thread.name .. "\n" .. ui.truncate(thread.last_body, width - 6),
                {
                    background = thread.waiting and ui.theme.warning
                        or ui.theme.panel,
                    foreground = thread.waiting and colors.black or colors.white,
                })
        end
        scene:button("back", 1, height, 8, 1, "< BACK",
            { background = ui.theme.panel })
        if pages > 1 then
            scene:button("prev", width - 11, height, 4, 1, "<",
                { background = ui.theme.panel, disabled = page <= 1 })
            ui.text(target, width - 6, height, page .. "/" .. pages,
                ui.theme.muted)
            scene:button("next", width - 2, height, 2, 1, ">",
                { background = ui.theme.panel, disabled = page >= pages })
        end
        local action = scene:wait({ tickRate = 3 })
        if action == "back" or action == "__terminate" then return
        elseif action == "prev" then page = page - 1
        elseif action == "next" then page = page + 1
        else
            local id = action and action:match("^open:(.+)$")
            for _, thread in ipairs(threads) do
                if thread.account_id == id then
                    messageThread({ account_id = thread.account_id,
                        name = thread.name })
                    break
                end
            end
        end
    end
end

local function dashboard()
    local blink, tick = true, 0
    local stats = request("GOVERNMENT_STATS")
    while running and governmentToken and stats do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "TAX CONTROLLER", "Government administration",
            util.formatClock(blink))
        ui.card(target, 2, 5, width - 2, 3, ui.theme.success)
        ui.text(target, 4, 5, "TAX REVENUE", ui.theme.muted, ui.theme.panel)
        ui.text(target, 4, 6, money(stats.tax_revenue), ui.theme.success, ui.theme.panel)
        ui.text(target, width - 13, 6, stats.accounts .. " citizens",
            ui.theme.muted, ui.theme.panel)

        local scene = ui.scene(target)
        local labels = {
            { "open", "OPEN PERIOD", ui.theme.warning },
            { "rates", "SET RATES", ui.theme.panel },
            { "revenue", "REVENUE", ui.theme.panel },
            { "audit", "AUDIT CO.", ui.theme.panel },
            { "deposit", "STATE DEPOSIT", ui.theme.accentDark },
            { "stats", "BANK STATS", ui.theme.panel },
            { "close", "CLOSE PERIOD", ui.theme.danger },
            { "accounts", "ACCOUNTS", ui.theme.accentDark },
            { "announce", "ANNOUNCE", colors.magenta },
            { "messages", "MESSAGES", colors.purple },
            { "controls", "CONTROLS", ui.theme.panel },
            { "system", "SYSTEM", ui.theme.panel },
        }
        -- Three columns. Two ran the last row off the bottom of a 51x19
        -- Advanced Computer once the list grew past ten entries.
        local buttonWidth = math.floor((width - 6) / 3)
        for index, item in ipairs(labels) do
            local column = (index - 1) % 3
            local row = math.floor((index - 1) / 3)
            scene:button(item[1], 2 + column * (buttonWidth + 1),
                9 + row * 2, buttonWidth, 2, item[2], {
                    background = item[3],
                    foreground = item[1] == "open" and colors.black or colors.white,
                })
        end
        scene:button("lock", 1, height, 7, 1, "LOCK",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 0.5 })
        blink = not blink
        tick = tick + 1
        -- Refresh on a five second cadence and straight after any change,
        -- instead of asking the Bank for statistics twice a second.
        local refresh = false
        if action == "__tick" then
            net.autoUpdate(config, "admin", ROOT, client)
            refresh = tick % 10 == 0
        elseif action == "open" then openPeriod() refresh = true
        elseif action == "rates" then setRates() refresh = true
        elseif action == "revenue" then revenueScreen()
        elseif action == "audit" then auditCompany()
        elseif action == "deposit" then stateDeposit() refresh = true
        elseif action == "stats" then statsScreen()
        elseif action == "close" then closePeriod() refresh = true
        elseif action == "accounts" then accountBrowser(false)
        elseif action == "announce" then announceScreen()
        elseif action == "messages" then messageInbox()
        elseif action == "controls" then controlsScreen()
        elseif action == "system" then systemScreen()
        elseif action == "lock" then governmentToken = nil
        elseif action == "__terminate" then running = false end
        if refresh and governmentToken then
            stats = request("GOVERNMENT_STATS", {}, true) or stats
        end
    end
end

ui.boot(target, "ADMIN TERMINAL", "GOVERNMENT CORE v" .. config.version)
-- Check for a new release at every restart, straight from the public
-- manifest. The Bank Server no longer has to hold a copy for us.
net.autoUpdate(config, "admin", ROOT, client,
    { force = true, programVersion = PROGRAM_VERSION })
if not client:discover() then
    ui.message(target, "error", "BANK OFFLINE", "Check the modem", 1.4)
end

while running do
    if not governmentToken then loginScreen() end
    if governmentToken then dashboard() end
end

ui.clear(target)
print("Admin Terminal closed.")
