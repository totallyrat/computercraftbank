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
            { "system", "SYSTEM", ui.theme.panel },
        }
        local buttonWidth = math.floor((width - 5) / 2)
        for index, item in ipairs(labels) do
            local column = (index - 1) % 2
            local row = math.floor((index - 1) / 2)
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
            net.autoUpdate(config, "tax", ROOT, client)
            refresh = tick % 10 == 0
        elseif action == "open" then openPeriod() refresh = true
        elseif action == "rates" then setRates() refresh = true
        elseif action == "revenue" then revenueScreen()
        elseif action == "audit" then auditCompany()
        elseif action == "deposit" then stateDeposit() refresh = true
        elseif action == "stats" then statsScreen()
        elseif action == "close" then closePeriod() refresh = true
        elseif action == "system" then systemScreen()
        elseif action == "lock" then governmentToken = nil
        elseif action == "__terminate" then running = false end
        if refresh and governmentToken then
            stats = request("GOVERNMENT_STATS", {}, true) or stats
        end
    end
end

ui.boot(target, "TAX CONTROLLER", "GOVERNMENT CORE v" .. config.version)
-- Check for a new release at every restart, straight from the public
-- manifest. The Bank Server no longer has to hold a copy for us.
net.autoUpdate(config, "tax", ROOT, client, { force = true })
if not client:discover() then
    ui.message(target, "error", "BANK OFFLINE", "Check the modem", 1.4)
end

while running do
    if not governmentToken then loginScreen() end
    if governmentToken then dashboard() end
end

ui.clear(target)
print("Tax Controller closed.")
