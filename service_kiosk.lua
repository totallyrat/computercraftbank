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
local kioskFile = fs.combine(ROOT, "service_kiosk_device.dat")
local kiosk = util.loadTable(kioskFile, {})
local kioskState
local running = true
local customerMonitor
local customerMonitorName
local customerView = { mode = "idle", data = {}, frame = 0 }

local function findCustomerMonitor()
    local foundName
    customerMonitor = peripheral.find("monitor",
        function(name, wrapped)
            if not foundName and wrapped.isColor and wrapped.isColor() then
                foundName = name
                return true
            end
            return false
        end)
    customerMonitorName = foundName
    if customerMonitor then
        pcall(customerMonitor.setTextScale, 0.5)
        pcall(customerMonitor.setCursorBlink, false)
    end
end

local function terminalPayload(payload)
    payload = payload or {}
    payload.terminal_id = kiosk.terminal_id
    payload.terminal_token = kiosk.terminal_token
    return payload
end

local function request(action, payload, silent)
    local result, err, code = client:request(action, terminalPayload(payload))
    if not result and not silent then ui.networkError(target, err) end
    return result, err, code
end

local function saveKiosk()
    util.saveTable(kioskFile, kiosk)
end

local function money(value)
    return util.money(value, config.currency)
end

local function monitorColors()
    if customerMonitor and customerMonitor.isColor() then return ui.theme end
    return {
        background = colors.black, panel = colors.black, ink = colors.white,
        muted = colors.white, accent = colors.white, success = colors.white,
        danger = colors.white, warning = colors.white,
    }
end

local function monitorTitle(text, color)
    if not customerMonitor then return end
    local width, height = customerMonitor.getSize()
    ui.fill(customerMonitor, 1, 1, width, math.min(2, height), color)
    ui.center(customerMonitor, 1, ui.truncate(text, math.max(1, width - 2)),
        colors.black, color)
    if height >= 2 then
        ui.fill(customerMonitor, 1, 2, width, 1, color)
    end
end

local function renderCustomerMonitor()
    if not customerMonitor then return end
    local monitor = customerMonitor
    local width, height = monitor.getSize()
    local theme = monitorColors()
    local mode, data, frame = customerView.mode, customerView.data, customerView.frame
    local compact = width < 24 or height < 11
    ui.clear(monitor, theme.background)

    if mode == "idle" then
        monitorTitle("PUMPE CHECKOUT", theme.accent)
        ui.center(monitor, math.min(height, compact and 3 or 4),
            ui.truncate(data.merchant or "SERVICE KIOSK", math.max(1, width - 2)),
            theme.ink)
        ui.center(monitor, math.min(height, compact and 5 or 6),
            compact and "READY" or "READY WHEN YOU ARE", theme.muted)
        local pulseWidth = math.min(width,
            math.max(3, math.floor(math.max(3, width - 6)
                * ((frame % 8) + 1) / 8)))
        ui.fill(monitor, math.floor((width - pulseWidth) / 2) + 1,
            math.min(height, compact and 7 or 8),
            math.min(width, pulseWidth), 1, theme.accent)
        if height >= 9 then
            ui.center(monitor, height - 1,
                util.formatClock(frame % 2 == 0), theme.muted)
        end
    elseif mode == "cart" then
        monitorTitle("YOUR ORDER", theme.accent)
        local items = data.items or {}
        local maxRows = math.max(1, height - 6)
        local first = math.max(1, #items - maxRows + 1)
        local row = 3
        for index = first, #items do
            local item = items[index]
            local priceText = money((item.price or 0) * (item.quantity or 0))
            local priceX = math.max(3, width - #priceText)
            local itemWidth = math.max(1, priceX - 3)
            local itemText = tostring(item.quantity or 0) .. "x "
                .. tostring(item.name or "Item")
            ui.text(monitor, 2, row, ui.truncate(itemText, itemWidth), theme.ink)
            ui.text(monitor, priceX, row, priceText, theme.ink)
            row = row + 1
        end
        local dividerY = math.max(3, height - 3)
        ui.fill(monitor, 1, dividerY, width, 1, theme.panel)
        ui.text(monitor, 2, math.min(height, dividerY + 1), "TOTAL", theme.muted)
        local totalText = money(data.total or 0)
        ui.text(monitor, math.max(2, width - #totalText),
            math.min(height, dividerY + 1), totalText, theme.success)
        if height >= 8 then
            local footer = #items == 0 and "NO ITEMS YET"
                or (#items .. (#items == 1 and " PRODUCT" or " PRODUCTS"))
            ui.center(monitor, height, ui.truncate(footer, math.max(1, width - 2)),
                theme.muted)
        end
    elseif mode == "code" then
        monitorTitle(data.kind == "withdrawal" and "RECEIVE WITH PUMPE"
            or "PAY WITH PUMPE", theme.accent)
        ui.center(monitor, math.min(height, 3), money(data.amount or 0), theme.ink)
        local code = tostring(data.code or "------")
        local spaced = code:sub(1, 3) .. " " .. code:sub(4, 6)
        local codeY = compact and 4 or 5
        local codeHeight = compact and 2 or 3
        ui.fill(monitor, 2, codeY, math.max(1, width - 2),
            math.min(codeHeight, height - codeY + 1), colors.white)
        ui.center(monitor, math.min(height, codeY + math.floor(codeHeight / 2)),
            spaced, colors.black, colors.white)
        local seconds = math.max(0, math.floor((data.expires_in_ms or 0) / 1000))
        ui.center(monitor, math.min(height, compact and height - 2 or 9),
            string.format("EXPIRES %d:%02d",
            math.floor(seconds / 60), seconds % 60), theme.muted)
        if height >= 8 then
            ui.center(monitor, height - 1,
                (compact and "PUMPE > PAY" or "Open PUMPE > Pay")
                    .. string.rep(".", frame % 4), theme.accent)
        end
    elseif mode == "waiting" then
        monitorTitle("PAYMENT REQUEST", theme.warning)
        ui.center(monitor, math.min(height, compact and 3 or 4),
            ui.truncate(data.customer or "CUSTOMER", math.max(1, width - 2)),
            theme.ink)
        ui.center(monitor, math.min(height, compact and 5 or 6),
            money(data.amount or 0), theme.ink)
        local dots = string.rep(".", frame % 4)
        ui.center(monitor, math.min(height, compact and 7 or 9),
            "WAITING" .. dots, theme.warning)
        if height >= 9 then
            ui.center(monitor, height - 1,
                compact and "APPROVE IN PUMPE" or "Approve on your PUMPE",
                theme.muted)
        end
    elseif mode == "success" then
        ui.fill(monitor, 1, 1, width, height, theme.success)
        local blockWidth = math.min(math.max(1, width - 4),
            math.max(math.min(width, 12), 8 + (frame % 6) * 3))
        local blockY = compact and 2 or 3
        local blockHeight = math.min(compact and 4 or 5, height - blockY + 1)
        ui.fill(monitor, math.floor((width - blockWidth) / 2) + 1,
            blockY, blockWidth, blockHeight, colors.white)
        ui.center(monitor, math.min(height, blockY + 1),
            "PAID", colors.black, colors.white)
        ui.center(monitor, math.min(height, blockY + blockHeight - 1),
            money(data.amount or 0), colors.black, colors.white)
        if height >= 8 then
            local thanks = data.payer and data.payer ~= ""
                and ("THANK YOU, " .. data.payer) or "THANK YOU"
            ui.center(monitor, height - 2,
                ui.truncate(thanks, math.max(1, width - 2)),
                colors.black, theme.success)
        end
    elseif mode == "cancelled" then
        monitorTitle("TRANSACTION ENDED", theme.danger)
        ui.center(monitor, math.max(3, math.floor(height / 2)),
            compact and "NOT CHARGED" or "NO PAYMENT TAKEN", theme.ink)
        if height >= 7 then
            ui.center(monitor, height - 1,
                compact and "REQUEST A NEW CODE" or "Please ask for a new code",
                theme.muted)
        end
    end
end

local function setCustomerView(mode, data)
    customerView = { mode = mode, data = data or {}, frame = 0 }
    renderCustomerMonitor()
end

local function animateCustomer(mode, data, frames, delay)
    setCustomerView(mode, data)
    for frame = 1, frames do
        customerView.frame = frame
        renderCustomerMonitor()
        sleep(delay or 0.08)
    end
end

local function refreshState(silent)
    local result = request("KIOSK_STATE", {}, silent)
    if result then
        kioskState = result
        if customerView.mode == "idle" then
            customerView.data.merchant = result.company and result.company.name
                or result.terminal.name
            renderCustomerMonitor()
        end
    end
    return result
end

local function registerKiosk()
    local payload = {
        terminal_id = kiosk.terminal_id,
        terminal_token = kiosk.terminal_token,
        name = kiosk.name,
    }
    if not kiosk.terminal_id then
        kiosk.name = ui.input(target, "KIOSK SETUP", {
            hint = "Name shown to customers",
            initial = "Service Kiosk",
            maxLength = 24,
            allowSpace = true,
        })
        if not kiosk.name then return false end
        payload.name = kiosk.name
    end
    local result, err = client:request("KIOSK_REGISTER", payload)
    if not result then
        ui.message(target, "error", "SETUP FAILED", err, 1.3)
        return false
    end
    kiosk.terminal_id = result.terminal_id
    kiosk.terminal_token = result.terminal_token
    kiosk.name = result.name
    saveKiosk()
    return true
end

local function chooseCompany(companies)
    local page = 1
    while true do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "LINK A COMPANY", "Where should sales settle?")
        local pageItems, actualPage, pages = util.page(companies, page, 4)
        page = actualPage
        local scene = ui.scene(target)
        for index, company in ipairs(pageItems) do
            local y = 5 + (index - 1) * 3
            scene:button("company:" .. company.company_id, 3, y,
                width - 5, 2, company.name .. "\n" .. company.tax_id,
                { background = ui.theme.panel })
        end
        scene:button("create", 2, height - 1, 12, 1, "+ NEW COMPANY",
            { background = ui.theme.accentDark })
        scene:button("skip", 15, height - 1, 8, 1, "SKIP",
            { background = ui.theme.panel })
        if pages > 1 then
            scene:button("prev", width - 9, height - 1, 4, 1, "<",
                { background = ui.theme.panel, disabled = page <= 1 })
            scene:button("next", width - 4, height - 1, 4, 1, ">",
                { background = ui.theme.panel, disabled = page >= pages })
        end
        local action = scene:wait()
        if action == "skip" or action == "__terminate" then return nil, false
        elseif action == "prev" then page = page - 1
        elseif action == "next" then page = page + 1
        elseif action == "create" then return nil, true
        else
            local id = action and action:match("^company:(.+)$")
            if id then return id, false end
        end
    end
end

local function companyOnboarding()
    refreshState(true)
    if kioskState and kioskState.company then return true end
    local width, height = target.getSize()
    ui.clear(target)
    ui.header(target, "COMPANY LINK", kiosk.name)
    ui.center(target, 6, "LINK THIS KIOSK", ui.theme.ink)
    ui.center(target, 7, "Sales will reach the owner account", ui.theme.muted)
    local scene = ui.scene(target)
    scene:button("link", 3, 10, width - 5, 3, "LINK COMPANY",
        { background = ui.theme.accentDark, shadow = true })
    scene:button("skip", 3, 14, width - 5, 2, "RUN UNLINKED",
        { background = ui.theme.panel })
    local action = scene:wait()
    if action ~= "link" then return true end

    local ownerName = ui.input(target, "OWNER SIGN IN", {
        hint = "PUMPE account name",
        maxLength = 20,
        allowSpace = true,
    })
    if not ownerName then return true end
    local pin = ui.pin(target, "OWNER PIN", true)
    if not pin then return true end
    local loginResult, loginErr = request("KIOSK_OWNER_LOGIN", {
        name = ownerName, pin = pin,
    }, true)
    if not loginResult then
        ui.message(target, "error", "OWNER LOGIN FAILED", loginErr, 1.1)
        return true
    end
    local companiesResult, companiesErr = request("OWNER_COMPANIES", {
        owner_session = loginResult.owner_session,
    }, true)
    if not companiesResult then
        ui.message(target, "error", "COULD NOT LOAD", companiesErr, 1.1)
        return true
    end
    local companyId, create = chooseCompany(companiesResult.companies)
    if create then
        local companyName = ui.input(target, "NEW COMPANY", {
            hint = "Official company name",
            maxLength = 28,
            allowSpace = true,
        })
        if companyName then
            local created, createErr = request("CREATE_COMPANY", {
                owner_session = loginResult.owner_session,
                company_name = companyName,
            }, true)
            if created then companyId = created.company.company_id
            else ui.message(target, "error", "CREATE FAILED", createErr, 1) end
        end
    end
    if companyId then
        local linked, linkErr = request("LINK_TERMINAL", {
            owner_session = loginResult.owner_session,
            company_id = companyId,
        }, true)
        if linked then
            ui.message(target, "success", "KIOSK LINKED", linked.company.name, 1)
            refreshState(true)
        else
            ui.message(target, "error", "LINK FAILED", linkErr, 1.1)
        end
    end
    return true
end

local function cartSummary(cart)
    local lines, total = {}, 0
    for _, entry in pairs(cart) do
        if entry.quantity > 0 then
            lines[#lines + 1] = {
                item_id = entry.item_id,
                name = entry.name,
                price = entry.price,
                quantity = entry.quantity,
            }
            total = total + entry.price * entry.quantity
        end
    end
    table.sort(lines, function(a, b) return a.name < b.name end)
    return lines, util.roundMoney(total)
end

local function waitForCode(code, amount, kind, items)
    local width, height = target.getSize()
    local deadline = util.nowMs() + config.payment_code_ttl_ms
    local frame = 0
    setCustomerView("code", {
        code = code, amount = amount, kind = kind,
        expires_in_ms = deadline - util.nowMs(),
    })
    while util.nowMs() < deadline do
        frame = frame + 1
        local remaining = math.max(0, deadline - util.nowMs())
        customerView.data.expires_in_ms = remaining
        customerView.frame = frame
        renderCustomerMonitor()

        ui.clear(target)
        ui.header(target, kind == "withdrawal" and "WITHDRAWAL CODE" or "PAYMENT CODE",
            kioskState.company and kioskState.company.name or kiosk.name,
            util.formatClock(frame % 2 == 0))
        ui.center(target, 5, money(amount), ui.theme.ink)
        ui.fill(target, math.floor(width / 2) - 9, 7, 19, 5, colors.white)
        ui.center(target, 8, "ENTER IN PUMPE", colors.gray, colors.white)
        ui.center(target, 10, code:sub(1, 3) .. " " .. code:sub(4, 6),
            colors.black, colors.white)
        local seconds = math.floor(remaining / 1000)
        ui.center(target, 13, string.format("Expires in %d:%02d",
            math.floor(seconds / 60), seconds % 60), ui.theme.muted)
        ui.center(target, 15, "Waiting for customer" .. string.rep(".", frame % 4),
            ui.theme.accent)
        local scene = ui.scene(target)
        scene:button("cancel", 2, height - 1, 12, 1, "CANCEL CODE",
            { background = ui.theme.danger })
        local action = scene:wait({ tickRate = 0.45, flash = false })
        if action == "cancel" or action == "__terminate" then
            request("CANCEL_CODE", { code = code }, true)
            animateCustomer("cancelled", {}, 5, 0.08)
            sleep(0.5)
            setCustomerView("idle", {
                merchant = kioskState.company and kioskState.company.name or kiosk.name,
            })
            return false
        end
        local status, err = request("CODE_STATUS", { code = code }, true)
        if status and status.status == "paid" then
            animateCustomer("success", {
                amount = amount,
                payer = status.payer or "",
            }, 8, 0.07)
            ui.message(target, "success", kind == "withdrawal"
                and "WITHDRAWAL COMPLETE" or "PAYMENT ACCEPTED",
                (status.payer or "Customer") .. "  " .. money(amount), 1.2)
            sleep(0.7)
            refreshState(true)
            setCustomerView("idle", {
                merchant = kioskState.company and kioskState.company.name or kiosk.name,
            })
            return true
        elseif status and (status.status == "expired" or status.status == "cancelled") then
            break
        elseif not status and err and err ~= "Bank server timed out" then
            break
        end
    end
    animateCustomer("cancelled", {}, 4, 0.07)
    ui.message(target, "warning", "CODE EXPIRED", "No payment was taken", 1)
    setCustomerView("idle", {
        merchant = kioskState.company and kioskState.company.name or kiosk.name,
    })
    return false
end

local function quickPay()
    if not refreshState() then return end
    local items = kioskState.quick_items or {}
    if #items == 0 then
        ui.message(target, "info", "NO QUICK ITEMS", "Add products under Items", 1.2)
        return
    end
    local cart, page, frame = {}, 1, 0
    setCustomerView("cart", { items = {}, total = 0 })
    while true do
        local width, height = target.getSize()
        local cartItems, total = cartSummary(cart)
        customerView.data = { items = cartItems, total = total }
        customerView.frame = frame
        renderCustomerMonitor()

        ui.clear(target)
        ui.header(target, "QUICK PAY", #cartItems .. " products", util.formatClock(frame % 2 == 0))
        local cartWidth = math.max(17, math.floor(width * 0.36))
        local productWidth = width - cartWidth - 3
        ui.text(target, 2, 4, "PRODUCTS", ui.theme.muted)
        ui.fill(target, productWidth + 3, 4, cartWidth, height - 5, ui.theme.panel)
        ui.text(target, productWidth + 5, 4, "ORDER", ui.theme.muted, ui.theme.panel)

        local perPage = math.max(4, math.floor((height - 7) / 3) * 2)
        local pageItems, actualPage, pages = util.page(items, page, perPage)
        page = actualPage
        local scene = ui.scene(target)
        local buttonWidth = math.floor((productWidth - 3) / 2)
        for index, item in ipairs(pageItems) do
            local column = (index - 1) % 2
            local row = math.floor((index - 1) / 2)
            local x = 2 + column * (buttonWidth + 1)
            local y = 6 + row * 3
            local quantity = cart[item.item_id] and cart[item.item_id].quantity or 0
            local label = ui.truncate(item.name, buttonWidth - 2) .. "\n"
                .. money(item.price) .. (quantity > 0 and ("  x" .. quantity) or "")
            scene:button("add:" .. item.item_id, x, y, buttonWidth, 2, label, {
                background = quantity > 0 and ui.theme.accentDark or ui.theme.panel,
                shadow = true,
            })
        end

        local visibleCart = {}
        for index = math.max(1, #cartItems - math.max(1, height - 11) + 1),
            #cartItems do visibleCart[#visibleCart + 1] = cartItems[index] end
        for index, item in ipairs(visibleCart) do
            local y = 6 + (index - 1)
            local line = item.quantity .. "x " .. item.name
            ui.text(target, productWidth + 5, y,
                ui.truncate(line, cartWidth - 10), ui.theme.ink, ui.theme.panel)
            local priceText = money(item.price * item.quantity)
            ui.text(target, width - #priceText, y, priceText, ui.theme.ink, ui.theme.panel)
        end
        ui.text(target, productWidth + 5, height - 5, "TOTAL", ui.theme.muted,
            ui.theme.panel)
        local totalText = money(total)
        ui.text(target, width - #totalText, height - 5, totalText,
            ui.theme.success, ui.theme.panel)
        scene:button("clear", productWidth + 4, height - 3,
            math.floor((cartWidth - 2) / 2), 2, "CLEAR",
            { background = ui.theme.danger, disabled = total <= 0 })
        scene:button("pay", productWidth + 5 + math.floor((cartWidth - 2) / 2),
            height - 3, math.ceil((cartWidth - 2) / 2), 2, "PAY",
            { background = ui.theme.success, foreground = colors.black,
                disabled = total <= 0 })
        scene:button("back", 1, height, 7, 1, "< BACK",
            { background = ui.theme.panel })
        if pages > 1 then
            scene:button("prev", 10, height, 4, 1, "<",
                { background = ui.theme.panel, disabled = page <= 1 })
            ui.text(target, 15, height, page .. "/" .. pages, ui.theme.muted)
            scene:button("next", 20, height, 4, 1, ">",
                { background = ui.theme.panel, disabled = page >= pages })
        end
        local action = scene:wait({ tickRate = 0.35 })
        frame = frame + 1
        if action == "back" or action == "__terminate" then
            setCustomerView("idle", {
                merchant = kioskState.company and kioskState.company.name or kiosk.name,
            })
            return
        elseif action == "clear" then cart = {}
        elseif action == "prev" then page = page - 1
        elseif action == "next" then page = page + 1
        elseif action == "pay" and total > 0 then
            local result, err = request("CREATE_PAY_CODE", {
                amount = total,
                items = cartItems,
                description = "Quick Pay order",
            }, true)
            if result then
                waitForCode(result.code, result.amount, "sale", cartItems)
                return
            else
                ui.message(target, "error", "CODE FAILED", err, 1)
            end
        else
            local id = action and action:match("^add:(.+)$")
            if id then
                for _, item in ipairs(items) do
                    if item.item_id == id then
                        cart[id] = cart[id] or {
                            item_id = id, name = item.name, price = item.price, quantity = 0,
                        }
                        cart[id].quantity = cart[id].quantity + 1
                        animateCustomer("cart", {
                            items = cartSummary(cart),
                            total = select(2, cartSummary(cart)),
                        }, 2, 0.04)
                        break
                    end
                end
            end
        end
    end
end

local function directCode(kind)
    local title = kind == "withdrawal" and "WITHDRAWAL" or "CODE PAY"
    local amountText = ui.input(target, title, {
        hint = kind == "withdrawal"
            and ("Available " .. money(kioskState.terminal.balance))
            or "Enter transaction amount",
        mode = "number", maxLength = 12,
    })
    if not amountText then return end
    local action = kind == "withdrawal" and "CREATE_WITHDRAWAL_CODE" or "CREATE_PAY_CODE"
    local result, err = request(action, {
        amount = tonumber(amountText),
        description = kind == "withdrawal" and "Kiosk withdrawal" or "Code payment",
    }, true)
    if result then
        waitForCode(result.code, result.amount, kind, {})
    else ui.message(target, "error", "COULD NOT CREATE", err, 1.1) end
end

local function addItem()
    local name = ui.input(target, "NEW QUICK ITEM", {
        hint = "Product name",
        maxLength = 20,
        allowSpace = true,
    })
    if not name then return false end
    local price = ui.input(target, "ITEM PRICE", {
        hint = name,
        mode = "number", maxLength = 12,
    })
    if not price then return false end
    local result, err = request("ADD_QUICK_ITEM", {
        name = name, price = tonumber(price),
    }, true)
    if result then
        ui.message(target, "success", "ITEM ADDED", name .. "  " .. money(price), 0.8)
        return true
    end
    ui.message(target, "error", "COULD NOT ADD", err, 1)
    return false
end

local function itemManager()
    refreshState()
    local items, page = kioskState.quick_items or {}, 1
    while true do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "QUICK ITEMS", #items .. " products", util.formatClock())
        local pageItems, actualPage, pages = util.page(items, page, 5)
        page = actualPage
        local scene = ui.scene(target)
        for index, item in ipairs(pageItems) do
            local y = 4 + (index - 1) * 3
            ui.card(target, 2, y, width - 2, 2, ui.theme.accent)
            ui.text(target, 4, y, ui.truncate(item.name, width - 18),
                ui.theme.ink, ui.theme.panel)
            ui.text(target, 4, y + 1, money(item.price), ui.theme.muted, ui.theme.panel)
            scene:button("delete:" .. item.item_id, width - 9, y, 8, 2, "DELETE",
                { background = ui.theme.danger })
        end
        scene:button("back", 1, height, 7, 1, "< BACK",
            { background = ui.theme.panel })
        scene:button("add", 9, height, 10, 1, "+ ADD ITEM",
            { background = ui.theme.accentDark })
        if pages > 1 then
            scene:button("prev", width - 9, height, 4, 1, "<",
                { background = ui.theme.panel, disabled = page <= 1 })
            scene:button("next", width - 4, height, 4, 1, ">",
                { background = ui.theme.panel, disabled = page >= pages })
        end
        local action = scene:wait()
        if action == "back" or action == "__terminate" then return
        elseif action == "add" then
            if addItem() then
                refreshState(true)
                items = kioskState.quick_items or {}
            end
        elseif action == "prev" then page = page - 1
        elseif action == "next" then page = page + 1
        else
            local id = action and action:match("^delete:(.+)$")
            if id and ui.confirm(target, "DELETE ITEM",
                "Remove this product button?", "DELETE", "KEEP") then
                local result, err = request("REMOVE_QUICK_ITEM", { item_id = id }, true)
                if result then items = result.quick_items
                else ui.message(target, "error", "DELETE FAILED", err, 1) end
            end
        end
    end
end

local function subscriptionCreator()
    local customer = ui.input(target, "NEW SUBSCRIPTION", {
        hint = "Customer PUMPE name",
        maxLength = 20,
        allowSpace = true,
    })
    if not customer then return end
    local description = ui.input(target, "DESCRIPTION", {
        hint = "Example: Daily Coffee Pass",
        maxLength = 40,
        allowSpace = true,
    })
    if not description then return end
    local amount = ui.input(target, "DAILY CHARGE", {
        hint = "Charged once per in-game day",
        mode = "number", maxLength = 12,
    })
    if not amount then return end
    ui.message(target, "info", "CUSTOMER APPROVAL",
        "Ask " .. customer .. " to enter their PIN", 0.9)
    local pin = ui.pin(target, "CUSTOMER PIN", true)
    if not pin then return end
    local result, err = request("CREATE_SUBSCRIPTION", {
        customer_name = customer,
        customer_pin = pin,
        amount = tonumber(amount),
        description = description,
    }, true)
    if result then
        ui.message(target, "success", "SUBSCRIPTION ACTIVE",
            money(amount) .. "/day from tomorrow", 1.1)
    else ui.message(target, "error", "COULD NOT CREATE", err, 1.1) end
end

local function proximityPay()
    if not gps or not gps.locate then
        ui.message(target, "error", "GPS UNAVAILABLE", "A GPS network is required", 1.1)
        return
    end
    local amountText = ui.input(target, "PROXIMITY PAY", {
        hint = "Amount to request",
        mode = "number", maxLength = 12,
    })
    if not amountText then return end
    ui.message(target, "info", "FINDING CUSTOMER", "Looking within 32 blocks", 0.5)
    local x, y, z = gps.locate(2, false)
    if not x then
        ui.message(target, "error", "NO GPS FIX", "Check GPS host computers", 1.1)
        return
    end
    local nearby, nearbyErr = request("PROXIMITY_FIND", {
        x = x, y = y, z = z, radius = 32,
    }, true)
    if not nearby then
        ui.message(target, "error", "NO PUMPE FOUND", nearbyErr, 1.1)
        return
    end
    local amount = tonumber(amountText)
    if not ui.confirm(target, "SEND REQUEST",
        nearby.customer .. "  " .. money(amount), "SEND", "BACK") then return end
    local result, err = request("PROXIMITY_REQUEST", {
        customer_name = nearby.customer,
        amount = amount,
        description = "Proximity payment",
    }, true)
    if not result then
        ui.message(target, "error", "REQUEST FAILED", err, 1)
        return
    end

    local frame = 0
    setCustomerView("waiting", { customer = nearby.customer, amount = amount })
    while frame < 200 do
        frame = frame + 1
        customerView.frame = frame
        renderCustomerMonitor()
        ui.clear(target)
        ui.header(target, "PAYMENT REQUEST", nearby.customer, util.formatClock(frame % 2 == 0))
        ui.center(target, 6, money(amount), ui.theme.ink)
        ui.center(target, 9, "Waiting for approval" .. string.rep(".", frame % 4),
            ui.theme.warning)
        local scene = ui.scene(target)
        local _, screenHeight = target.getSize()
        scene:button("cancel", 2, screenHeight - 1, 10, 1, "CLOSE",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 0.45, flash = false })
        if action == "cancel" or action == "__terminate" then break end
        local status = request("REQUEST_STATUS", { request_id = result.request_id }, true)
        if status and status.status == "paid" then
            animateCustomer("success", {
                amount = amount, payer = nearby.customer,
            }, 8, 0.07)
            ui.message(target, "success", "PAYMENT ACCEPTED",
                nearby.customer .. "  " .. money(amount), 1.1)
            break
        elseif status and (status.status == "declined" or status.status == "expired") then
            ui.message(target, "warning", string.upper(status.status),
                "No payment was taken", 1)
            break
        end
    end
    refreshState(true)
    setCustomerView("idle", {
        merchant = kioskState.company and kioskState.company.name or kiosk.name,
    })
end

local function balanceScreen()
    refreshState()
    local width, height = target.getSize()
    ui.clear(target)
    ui.header(target, "MERCHANT BALANCE",
        kioskState.company and kioskState.company.name or "Unlinked kiosk",
        util.formatClock())
    ui.card(target, 3, 6, width - 5, 7, ui.theme.success)
    ui.text(target, 5, 7, "AVAILABLE", ui.theme.muted, ui.theme.panel)
    ui.text(target, 5, 9, money(kioskState.terminal.balance),
        ui.theme.ink, ui.theme.panel)
    ui.text(target, 5, 11, "LIFETIME SALES  "
        .. money(kioskState.terminal.sales_total), ui.theme.muted, ui.theme.panel)
    local scene = ui.scene(target)
    scene:button("back", 1, height, 7, 1, "< BACK",
        { background = ui.theme.panel })
    scene:wait()
end

local function aboutScreen()
    local width, height = target.getSize()
    ui.clear(target)
    ui.header(target, "SYSTEM", kiosk.name, util.formatClock())
    ui.text(target, 3, 6, "PUMPE Service Kiosk v" .. config.version, ui.theme.ink)
    ui.text(target, 3, 8, "Terminal: " .. kiosk.terminal_id, ui.theme.muted)
    ui.text(target, 3, 10, "Customer display: "
        .. (customerMonitor and ("ONLINE (" .. customerMonitorName .. ")") or "NOT ATTACHED"),
        customerMonitor and ui.theme.success or ui.theme.warning)
    ui.text(target, 3, 12, "Touch UI: ACTIVE", ui.theme.success)
    local scene = ui.scene(target)
    scene:button("rescan", 3, 15, 16, 2, "RESCAN MONITOR",
        { background = ui.theme.accentDark })
    if not kioskState.company then
        scene:button("link", 20, 15, 16, 2, "LINK COMPANY",
            { background = ui.theme.warning, foreground = colors.black })
    end
    scene:button("back", 1, height, 7, 1, "< BACK",
        { background = ui.theme.panel })
    local action = scene:wait()
    if action == "rescan" then
        findCustomerMonitor()
        setCustomerView("idle", {
            merchant = kioskState.company and kioskState.company.name or kiosk.name,
        })
        ui.message(target, customerMonitor and "success" or "warning",
            customerMonitor and "MONITOR CONNECTED" or "NO MONITOR FOUND",
            customerMonitorName or "Attach an advanced monitor", 1)
    elseif action == "link" then
        companyOnboarding()
        refreshState(true)
    end
end

local function dashboard()
    local blink, frame = true, 0
    refreshState()
    setCustomerView("idle", {
        merchant = kioskState.company and kioskState.company.name or kiosk.name,
    })
    while running do
        local width, height = target.getSize()
        ui.clear(target)
        local merchant = kioskState.company and kioskState.company.name or "UNLINKED"
        ui.header(target, "SERVICE KIOSK", merchant, util.formatClock(blink))
        ui.card(target, 2, 5, width - 2, 3,
            kioskState.company and ui.theme.success or ui.theme.warning)
        ui.text(target, 4, 5, "BALANCE", ui.theme.muted, ui.theme.panel)
        ui.text(target, 4, 6, money(kioskState.terminal.balance), ui.theme.ink, ui.theme.panel)
        local monitorLabel = customerMonitor and "DISPLAY ON" or "NO DISPLAY"
        ui.text(target, width - #monitorLabel, 6, monitorLabel,
            customerMonitor and ui.theme.success or ui.theme.warning, ui.theme.panel)

        local scene = ui.scene(target)
        local labels = {
            { "quick", "QUICK PAY", ui.theme.accentDark },
            { "proximity", "PROXIMITY", ui.theme.accentDark },
            { "code", "CODE PAY", ui.theme.panel },
            { "withdraw", "WITHDRAW", ui.theme.panel },
            { "subscription", "SUBSCRIPTION", ui.theme.panel },
            { "balance", "BALANCE", ui.theme.panel },
            { "items", "ITEMS", ui.theme.panel },
            { "system", "SYSTEM", ui.theme.panel },
        }
        local buttonWidth = math.floor((width - 5) / 2)
        for index, item in ipairs(labels) do
            local column = (index - 1) % 2
            local row = math.floor((index - 1) / 2)
            scene:button(item[1], 2 + column * (buttonWidth + 1),
                9 + row * 2, buttonWidth, 2, item[2], {
                    background = item[3],
                })
        end
        scene:button("exit", 1, height, 6, 1, "EXIT",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 0.5 })
        frame = frame + 1
        blink = not blink
        if action == "__tick" then
            customerView.frame = frame
            if customerView.mode == "idle" then renderCustomerMonitor() end
            net.autoUpdate(config, "service", ROOT)
            if frame % 10 == 0 then refreshState(true) end
        elseif action == "quick" then ui.wipe(target, "NEW ORDER"); quickPay()
        elseif action == "proximity" then proximityPay()
        elseif action == "code" then directCode("sale")
        elseif action == "withdraw" then directCode("withdrawal")
        elseif action == "subscription" then subscriptionCreator()
        elseif action == "balance" then balanceScreen()
        elseif action == "items" then itemManager()
        elseif action == "system" then aboutScreen()
        elseif action == "exit" or action == "__terminate" then
            if ui.confirm(target, "CLOSE KIOSK", "End this terminal session?", "CLOSE", "BACK") then
                running = false
            end
        end
        if running then refreshState(true) end
    end
end

ui.boot(target, "SERVICE KIOSK", "TOUCH CHECKOUT v" .. config.version)
findCustomerMonitor()
if not client:discover() then
    ui.message(target, "error", "BANK OFFLINE", "Check the Ender modem", 1.4)
end

if registerKiosk() then
    companyOnboarding()
    if refreshState() then dashboard() end
end

setCustomerView("cancelled", {})
ui.clear(target)
print("Service Kiosk closed.")
