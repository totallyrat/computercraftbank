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

local function saveKiosk()
    util.saveTable(kioskFile, kiosk)
end

local function money(value)
    return util.money(value, config.currency)
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

local function merchantName()
    return kioskState and kioskState.company and kioskState.company.name
        or kiosk.name or "Service Kiosk"
end

-- Optional 1x1 customer monitor ---------------------------------------------

local function findCustomerMonitor()
    local foundName
    customerMonitor = peripheral.find("monitor", function(name, wrapped)
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

local function monitorTheme()
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
    ui.center(customerMonitor, 1,
        ui.truncate(text, math.max(1, width - 2)), colors.black, color)
end

local function renderCustomerMonitor()
    if not customerMonitor then return end
    local monitor = customerMonitor
    local width, height = monitor.getSize()
    local theme = monitorTheme()
    local mode = customerView.mode
    local data = customerView.data or {}
    local frame = customerView.frame or 0
    local compact = width < 24 or height < 11
    ui.clear(monitor, theme.background)

    if mode == "idle" then
        monitorTitle("PUMPE CHECKOUT", theme.accent)
        ui.center(monitor, math.min(height, compact and 3 or 4),
            ui.truncate(data.merchant or "SERVICE KIOSK",
                math.max(1, width - 2)), theme.ink)
        ui.center(monitor, math.min(height, compact and 5 or 6),
            compact and "READY" or "READY WHEN YOU ARE", theme.muted)
        local pulseWidth = math.max(2, math.min(width - 2,
            2 + (frame % math.max(2, width - 3))))
        ui.fill(monitor, math.floor((width - pulseWidth) / 2) + 1,
            math.min(height, compact and 7 or 8), pulseWidth, 1, theme.accent)
        if height >= 9 then
            ui.center(monitor, height - 1,
                util.formatClock(frame % 2 == 0), theme.muted)
        end
    elseif mode == "cart" then
        monitorTitle(data.kind == "subscription"
            and "YOUR SUBSCRIPTION" or "YOUR ORDER", theme.accent)
        local items = data.items or {}
        local maxRows = math.max(1, height - 6)
        local first = math.max(1, #items - maxRows + 1)
        local row = 3
        for index = first, #items do
            local item = items[index]
            local priceText = money((item.price or 0) * (item.quantity or 0))
            local priceX = math.max(3, width - #priceText)
            ui.text(monitor, 2, row,
                ui.truncate((item.quantity or 0) .. "x "
                    .. tostring(item.name or "Item"),
                    math.max(1, priceX - 3)), theme.ink)
            ui.text(monitor, priceX, row, priceText, theme.ink)
            row = row + 1
        end
        local dividerY = math.max(3, height - 3)
        ui.fill(monitor, 1, dividerY, width, 1, theme.panel)
        ui.text(monitor, 2, math.min(height, dividerY + 1),
            data.kind == "subscription" and "PER DAY" or "TOTAL", theme.muted)
        local totalText = money(data.total or 0)
        ui.text(monitor, math.max(2, width - #totalText),
            math.min(height, dividerY + 1), totalText, theme.success)
    elseif mode == "code" then
        monitorTitle(data.kind == "withdrawal" and "RECEIVE WITH PUMPE"
            or data.kind == "subscription" and "CONFIRM SUBSCRIPTION"
            or "PAY WITH PUMPE", theme.accent)
        ui.center(monitor, math.min(height, 3), money(data.amount or 0)
            .. (data.kind == "subscription" and "/DAY" or ""), theme.ink)
        local code = tostring(data.code or "------")
        local codeY = compact and 4 or 5
        local codeHeight = compact and 2 or 3
        ui.fill(monitor, 2, codeY, math.max(1, width - 2),
            math.min(codeHeight, height - codeY + 1), colors.white)
        ui.center(monitor, math.min(height,
            codeY + math.floor(codeHeight / 2)),
            code:sub(1, 3) .. " " .. code:sub(4, 6),
            colors.black, colors.white)
        local seconds = math.max(0,
            math.floor((data.expires_in_ms or 0) / 1000))
        ui.center(monitor, math.min(height, compact and 7 or 9),
            string.format("%d:%02d LEFT",
                math.floor(seconds / 60), seconds % 60), theme.muted)
        if height >= 9 then
            ui.center(monitor, height - 1, "PUMPE > PAY"
                .. string.rep(".", frame % 4), theme.accent)
        end
    elseif mode == "success" then
        ui.fill(monitor, 1, 1, width, height, theme.success)
        ui.center(monitor, math.max(2, math.floor(height / 2) - 1),
            data.kind == "subscription" and "ACTIVE" or "PAID",
            colors.black, theme.success)
        ui.center(monitor, math.max(3, math.floor(height / 2) + 1),
            money(data.amount or 0)
                .. (data.kind == "subscription" and "/DAY" or ""),
            colors.black, theme.success)
        if height >= 8 then
            ui.center(monitor, height - 1,
                ui.truncate(data.payer and ("THANK YOU, " .. data.payer)
                    or "THANK YOU", math.max(1, width - 2)),
                colors.black, theme.success)
        end
    elseif mode == "cancelled" then
        monitorTitle("TRANSACTION ENDED", theme.danger)
        ui.center(monitor, math.max(3, math.floor(height / 2)),
            "NOT CHARGED", theme.ink)
        if height >= 7 then
            ui.center(monitor, height - 1,
                compact and "NEW SALE READY" or "READY FOR A NEW SALE",
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
        sleep(delay or 0.07)
    end
end

-- Registration and company linking -----------------------------------------

local function refreshState(silent)
    local result = request("KIOSK_STATE", {}, silent)
    if result then
        result.products = result.products or result.quick_items or {}
        kioskState = result
        if customerView.mode == "idle" then
            customerView.data.merchant = merchantName()
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
        local visible, actualPage, pages = util.page(companies, page, 4)
        page = actualPage
        ui.clear(target)
        ui.header(target, "LINK COMPANY", "Where should sales settle?")
        local scene = ui.scene(target)
        for index, company in ipairs(visible) do
            local y = 5 + (index - 1) * 3
            scene:button("company:" .. company.company_id, 3, y,
                width - 5, 2, company.name .. "\n" .. company.tax_id, {
                    background = ui.theme.panel,
                })
        end
        scene:button("create", 2, height - 1, 13, 1, "+ NEW COMPANY", {
            background = ui.theme.accentDark,
        })
        scene:button("back", 16, height - 1, 8, 1, "BACK", {
            background = ui.theme.panel,
        })
        if pages > 1 then
            scene:button("prev", width - 9, height - 1, 4, 1, "<", {
                background = ui.theme.panel, disabled = page <= 1,
            })
            scene:button("next", width - 4, height - 1, 4, 1, ">", {
                background = ui.theme.panel, disabled = page >= pages,
            })
        end
        local action = scene:wait()
        if action == "back" or action == "__terminate" then return nil, false
        elseif action == "create" then return nil, true
        elseif action == "prev" then page = page - 1
        elseif action == "next" then page = page + 1
        else
            local id = action and action:match("^company:(.+)$")
            if id then return id, false end
        end
    end
end

local function companyOnboarding(force)
    refreshState(true)
    if kioskState and kioskState.company and not force then return true end
    if not force then
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "COMPANY LINK", kiosk.name)
        ui.center(target, 6, "LINK THIS KIOSK", ui.theme.ink)
        ui.center(target, 8, "Sales can settle to a Foxy Account", ui.theme.muted)
        local scene = ui.scene(target)
        scene:button("link", 3, 11, width - 5, 3, "LINK COMPANY", {
            background = ui.theme.accentDark, shadow = true,
        })
        scene:button("skip", 3, 15, width - 5, 2, "RUN UNLINKED", {
            background = ui.theme.panel,
        })
        if scene:wait() ~= "link" then return true end
    end

    local ownerName = ui.input(target, "OWNER SIGN IN", {
        hint = "Foxy Account name",
        maxLength = 20,
        allowSpace = true,
    })
    if not ownerName then return false end
    local pin = ui.pin(target, "OWNER PIN", true)
    if not pin then return false end
    local login, loginError = request("KIOSK_OWNER_LOGIN", {
        name = ownerName, pin = pin,
    }, true)
    if not login then
        ui.message(target, "error", "OWNER LOGIN FAILED", loginError, 1.2)
        return false
    end
    local companyResult, companyError = request("OWNER_COMPANIES", {
        owner_session = login.owner_session,
    }, true)
    if not companyResult then
        ui.message(target, "error", "COULD NOT LOAD", companyError, 1.2)
        return false
    end
    local companyId, create = chooseCompany(companyResult.companies)
    if create then
        local companyName = ui.input(target, "NEW COMPANY", {
            hint = "Official company name",
            maxLength = 28,
            allowSpace = true,
        })
        if companyName then
            local created, createError = request("CREATE_COMPANY", {
                owner_session = login.owner_session,
                company_name = companyName,
            }, true)
            if created then
                companyId = created.company.company_id
            else
                ui.message(target, "error", "CREATE FAILED", createError, 1.1)
            end
        end
    end
    if not companyId then return false end
    local linked, linkError = request("LINK_TERMINAL", {
        owner_session = login.owner_session,
        company_id = companyId,
    }, true)
    if not linked then
        ui.message(target, "error", "LINK FAILED", linkError, 1.1)
        return false
    end
    refreshState(true)
    ui.message(target, "success", "KIOSK LINKED", linked.company.name, 0.9)
    return true
end

-- Sale and subscription codes ----------------------------------------------

local function cartSummary(cart)
    local items, total, kind = {}, 0, nil
    for _, entry in pairs(cart or {}) do
        if (entry.quantity or 0) > 0 then
            items[#items + 1] = {
                item_id = entry.item_id,
                name = entry.name,
                price = entry.price,
                quantity = entry.quantity,
                kind = entry.kind or "one_time",
            }
            total = total + entry.price * entry.quantity
            kind = kind or entry.kind or "one_time"
        end
    end
    table.sort(items, function(a, b) return a.name < b.name end)
    return items, util.roundMoney(total), kind
end

local function choosePurchaseType(title)
    while true do
        local width, height = target.getSize()
        ui.clear(target, colors.white)
        ui.header(target, title or "PURCHASE TYPE",
            "How should the customer pay?")
        local scene = ui.scene(target)
        scene:button("one_time", 3, 6, width - 5, 4,
            "ONE TIME\nCharge the customer once", {
                background = ui.theme.accentDark, shadow = true,
            })
        scene:button("subscription", 3, 11, width - 5, 4,
            "SUBSCRIPTION\nCharge every in-game day", {
                background = colors.purple, shadow = true,
            })
        scene:button("back", 1, height, 8, 1, "< BACK", {
            background = ui.theme.panel,
        })
        local action = scene:wait()
        if action == "one_time" or action == "subscription" then return action end
        if action == "back" or action == "__terminate" then return nil end
    end
end

local function waitForCode(code, amount, kind)
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
        local title = kind == "withdrawal" and "WITHDRAWAL CODE"
            or kind == "subscription" and "SUBSCRIPTION CODE"
            or "PAYMENT CODE"
        ui.header(target, title, merchantName(), util.formatClock(frame % 2 == 0))
        ui.center(target, 5, money(amount)
            .. (kind == "subscription" and " / DAY" or ""), ui.theme.ink)
        ui.fill(target, math.max(2, math.floor(width / 2) - 9),
            7, math.min(19, width - 2), 5, colors.white)
        ui.center(target, 8, kind == "subscription"
            and "CONFIRM IN PUMPE" or "ENTER IN PUMPE",
            colors.gray, colors.white)
        ui.center(target, 10, code:sub(1, 3) .. " " .. code:sub(4, 6),
            colors.black, colors.white)
        local seconds = math.floor(remaining / 1000)
        ui.center(target, 13, string.format("Expires in %d:%02d",
            math.floor(seconds / 60), seconds % 60), ui.theme.muted)
        ui.center(target, 15, "Waiting for customer"
            .. string.rep(".", frame % 4), ui.theme.accent)
        local scene = ui.scene(target)
        scene:button("cancel", 2, height - 1, 12, 1, "CANCEL CODE", {
            background = ui.theme.danger,
        })
        local action = scene:wait({ tickRate = 0.45, flash = false })
        if action == "cancel" or action == "__terminate" then
            request("CANCEL_CODE", { code = code }, true)
            animateCustomer("cancelled", {}, 4)
            sleep(0.35)
            setCustomerView("idle", { merchant = merchantName() })
            return false
        end
        local status, statusError = request("CODE_STATUS", {
            code = code,
        }, true)
        if status and status.status == "paid" then
            local paidKind = status.kind or kind
            animateCustomer("success", {
                amount = amount,
                payer = status.payer or "CUSTOMER",
                kind = paidKind,
            }, 7)
            ui.message(target, "success",
                paidKind == "subscription" and "SUBSCRIPTION ACTIVE"
                    or paidKind == "withdrawal" and "WITHDRAWAL COMPLETE"
                    or "PAYMENT ACCEPTED",
                (status.payer or "Customer") .. "  " .. money(amount)
                    .. (paidKind == "subscription" and "/day" or ""), 1.1)
            refreshState(true)
            sleep(0.45)
            setCustomerView("idle", { merchant = merchantName() })
            return true
        elseif status and (status.status == "expired"
            or status.status == "cancelled") then
            break
        elseif not status and statusError
            and statusError ~= "Bank server timed out" then
            break
        end
    end
    animateCustomer("cancelled", {}, 4)
    ui.message(target, "warning", "CODE EXPIRED", "No payment was taken", 1)
    setCustomerView("idle", { merchant = merchantName() })
    return false
end

local function checkout(cart)
    local items, total, kind = cartSummary(cart)
    if total <= 0 then
        local amountText = ui.input(target, "CUSTOM AMOUNT", {
            hint = "Use the touch keypad",
            mode = "number",
            maxLength = 12,
        })
        total = util.roundMoney(tonumber(amountText))
        if not total or total <= 0 then return false end
        kind = choosePurchaseType("CUSTOM SALE")
        if not kind then return false end
    end
    kind = kind or "one_time"
    local names = {}
    for index, item in ipairs(items) do
        if index <= 3 then names[#names + 1] = item.name end
    end
    local description = #names > 0 and table.concat(names, ", ")
        or (kind == "subscription" and "Custom subscription" or "Custom sale")
    local result, err = request("CREATE_PAY_CODE", {
        amount = total,
        items = items,
        purchase_type = kind,
        description = description,
    }, true)
    if not result then
        ui.message(target, "error", "CODE FAILED", err, 1.1)
        return false
    end
    return waitForCode(result.code, result.amount,
        result.kind or (kind == "subscription" and "subscription" or "sale"))
end

local function addProduct()
    local name = ui.input(target, "NEW PRODUCT", {
        hint = "Product name",
        maxLength = 20,
        allowSpace = true,
    })
    if not name then return false end
    local price = ui.input(target, "PRODUCT PRICE", {
        hint = name,
        mode = "number",
        maxLength = 12,
    })
    if not price then return false end
    local kind = choosePurchaseType("NEW PRODUCT")
    if not kind then return false end
    local result, err = request("ADD_PRODUCT", {
        name = name,
        price = tonumber(price),
        kind = kind,
    }, true)
    if not result then
        ui.message(target, "error", "COULD NOT ADD", err, 1.1)
        return false
    end
    kioskState.products = result.products
    ui.message(target, "success", "PRODUCT ADDED",
        name .. (kind == "subscription" and " / day" or ""), 0.8)
    return true
end

-- Settings ------------------------------------------------------------------

local function directWithdrawal()
    refreshState(true)
    local amountText = ui.input(target, "WITHDRAWAL", {
        hint = "Available " .. money(kioskState.terminal.balance),
        mode = "number",
        maxLength = 12,
    })
    if not amountText then return end
    local result, err = request("CREATE_WITHDRAWAL_CODE", {
        amount = tonumber(amountText),
        description = "Kiosk withdrawal",
    }, true)
    if result then
        waitForCode(result.code, result.amount, "withdrawal")
    else
        ui.message(target, "error", "COULD NOT CREATE", err, 1.1)
    end
end

local function balanceScreen()
    refreshState(true)
    local width, height = target.getSize()
    ui.clear(target)
    ui.header(target, "MERCHANT BALANCE", merchantName(), util.formatClock())
    ui.card(target, 3, 6, width - 5, 7, ui.theme.success)
    ui.text(target, 5, 7, "AVAILABLE", ui.theme.muted, ui.theme.panel)
    ui.text(target, 5, 9, money(kioskState.terminal.balance),
        ui.theme.ink, ui.theme.panel)
    ui.text(target, 5, 11, "LIFETIME SALES  "
        .. money(kioskState.terminal.sales_total), ui.theme.muted, ui.theme.panel)
    local scene = ui.scene(target)
    scene:button("back", 1, height, 8, 1, "< BACK", {
        background = ui.theme.panel,
    })
    scene:wait()
end

local function productManager()
    local page = 1
    while true do
        refreshState(true)
        local products = kioskState.products or {}
        local width, height = target.getSize()
        local visible, actualPage, pages = util.page(products, page, 5)
        page = actualPage
        ui.clear(target)
        ui.header(target, "MANAGE PRODUCTS", #products .. " total",
            util.formatClock())
        local scene = ui.scene(target)
        for index, product in ipairs(visible) do
            local y = 4 + (index - 1) * 3
            ui.card(target, 2, y, width - 2, 2,
                product.kind == "subscription" and colors.purple
                    or ui.theme.accent)
            ui.text(target, 4, y,
                ui.truncate(product.name, width - 20),
                ui.theme.ink, ui.theme.panel)
            ui.text(target, 4, y + 1, money(product.price)
                .. (product.kind == "subscription" and "/day" or ""),
                ui.theme.muted, ui.theme.panel)
            scene:button("delete:" .. product.item_id,
                width - 9, y, 8, 2, "DELETE", {
                    background = ui.theme.danger,
                })
        end
        scene:button("back", 1, height, 8, 1, "< BACK", {
            background = ui.theme.panel,
        })
        if pages > 1 then
            scene:button("prev", width - 9, height, 4, 1, "<", {
                background = ui.theme.panel, disabled = page <= 1,
            })
            scene:button("next", width - 4, height, 4, 1, ">", {
                background = ui.theme.panel, disabled = page >= pages,
            })
        end
        local action = scene:wait()
        if action == "back" or action == "__terminate" then return
        elseif action == "prev" then page = page - 1
        elseif action == "next" then page = page + 1
        else
            local id = action and action:match("^delete:(.+)$")
            if id and ui.confirm(target, "DELETE PRODUCT",
                "Remove this product from the POS?", "DELETE", "KEEP") then
                local result, err = request("REMOVE_PRODUCT", {
                    item_id = id,
                }, true)
                if result then
                    kioskState.products = result.products
                else
                    ui.message(target, "error", "DELETE FAILED", err, 1)
                end
            end
        end
    end
end

local function settingsScreen()
    while true do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "POS SETTINGS", merchantName(), util.formatClock())
        local scene = ui.scene(target)
        local buttonWidth = math.floor((width - 5) / 2)
        local entries = {
            { "balance", "BALANCE", ui.theme.success },
            { "withdraw", "WITHDRAW", ui.theme.accentDark },
            { "products", "MANAGE PRODUCTS", colors.purple },
            { "company", "LINK COMPANY", ui.theme.warning },
            { "display", "RESCAN DISPLAY", ui.theme.panel },
            { "close", "CLOSE KIOSK", ui.theme.danger },
        }
        for index, entry in ipairs(entries) do
            local column = (index - 1) % 2
            local row = math.floor((index - 1) / 2)
            scene:button(entry[1], 2 + column * (buttonWidth + 1),
                5 + row * 4, buttonWidth, 3, entry[2], {
                    background = entry[3],
                    foreground = (entry[1] == "balance"
                        or entry[1] == "company")
                            and colors.black or colors.white,
                    shadow = true,
                })
        end
        ui.text(target, 2, height - 2,
            "Service Kiosk v" .. config.version
                .. "  Display " .. (customerMonitor and "ON" or "OFF"),
            ui.theme.muted)
        scene:button("back", 1, height, 8, 1, "< POS", {
            background = ui.theme.panel,
        })
        local action = scene:wait()
        if action == "back" or action == "__terminate" then return false
        elseif action == "balance" then balanceScreen()
        elseif action == "withdraw" then directWithdrawal()
        elseif action == "products" then productManager()
        elseif action == "company" then companyOnboarding(true)
        elseif action == "display" then
            findCustomerMonitor()
            setCustomerView("idle", { merchant = merchantName() })
            ui.message(target, customerMonitor and "success" or "warning",
                customerMonitor and "DISPLAY CONNECTED" or "NO DISPLAY FOUND",
                customerMonitorName or "Attach an advanced monitor", 0.9)
        elseif action == "close" and ui.confirm(target, "CLOSE KIOSK",
            "End this terminal session?", "CLOSE", "BACK") then
            return true
        end
    end
end

-- Square-style POS ----------------------------------------------------------

local function filteredProducts(products, tab)
    local output = {}
    for _, product in ipairs(products or {}) do
        local kind = product.kind == "subscription"
            and "subscription" or "one_time"
        if (tab == "favorites" and product.favorite)
            or (tab == "all" and kind == "one_time")
            or (tab == "subscriptions" and kind == "subscription") then
            local copy = util.copy(product)
            copy.kind = kind
            output[#output + 1] = copy
        end
    end
    table.sort(output, function(a, b) return a.name < b.name end)
    return output
end

local function posLoop()
    local cart = {}
    local tab, page, frame = "favorites", 1, 0
    setCustomerView("idle", { merchant = merchantName() })
    while running do
        local width, height = target.getSize()
        local receiptWidth = math.max(16, math.min(19, math.floor(width * 0.37)))
        local productX = receiptWidth + 2
        local productWidth = width - productX + 1
        local products = filteredProducts(kioskState.products, tab)
        local visible, actualPage, pages = util.page(products, page, 6)
        page = actualPage
        local cartItems, total, cartKind = cartSummary(cart)
        customerView.data = {
            items = cartItems, total = total, kind = cartKind,
        }
        customerView.mode = #cartItems > 0 and "cart" or "idle"
        if customerView.mode == "idle" then
            customerView.data.merchant = merchantName()
        end
        customerView.frame = frame
        renderCustomerMonitor()

        ui.clear(target, colors.white)
        ui.fill(target, 1, 1, width, 2, colors.black)
        ui.text(target, 2, 1, "PUMPE POS", colors.white, colors.black)
        ui.text(target, 2, 2,
            ui.truncate(merchantName(), math.max(1, width - 15)),
            colors.lightGray, colors.black)
        local scene = ui.scene(target)
        scene:button("add", width - 6, 1, 3, 2, "+", {
            background = ui.theme.accentDark,
        })
        scene:button("settings", width - 2, 1, 3, 2, "S", {
            background = colors.gray,
        })

        ui.fill(target, 1, 3, receiptWidth, height - 2, colors.lightGray)
        ui.text(target, 2, 4, "RECEIPT", colors.gray, colors.lightGray)
        local maxReceiptRows = math.max(1, height - 11)
        local firstReceipt = math.max(1, #cartItems - maxReceiptRows + 1)
        local receiptRow = 6
        for index = firstReceipt, #cartItems do
            local item = cartItems[index]
            local line = item.quantity .. "x " .. item.name
            scene:button("remove:" .. item.item_id, 2, receiptRow,
                receiptWidth - 2, 1,
                ui.truncate(line, receiptWidth - 8), {
                    background = colors.lightGray,
                    foreground = colors.black,
                    flash = false,
                })
            local priceText = money(item.price * item.quantity)
            ui.text(target, math.max(2, receiptWidth - #priceText),
                receiptRow, priceText, colors.gray, colors.lightGray)
            receiptRow = receiptRow + 1
        end
        if #cartItems == 0 then
            ui.text(target, 2, 7, "Tap a product", colors.gray, colors.lightGray)
            ui.text(target, 2, 8, "or press PAY", colors.gray, colors.lightGray)
            ui.text(target, 2, 9, "for custom amount", colors.gray,
                colors.lightGray)
        end
        ui.text(target, 2, height - 6,
            cartKind == "subscription" and "PER DAY" or "TOTAL",
            colors.gray, colors.lightGray)
        local totalText = money(total)
        ui.text(target, math.max(2, receiptWidth - #totalText),
            height - 6, totalText, colors.black, colors.lightGray)
        scene:button("clear", 2, height - 4, receiptWidth - 2, 1,
            "CLEAR", {
                background = colors.gray,
                disabled = #cartItems == 0,
            })
        scene:button("pay", 2, height - 2, receiptWidth - 2, 2,
            total > 0 and ("PAY  " .. money(total)) or "PAY", {
                background = colors.lime,
                foreground = colors.black,
                shadow = true,
            })

        local tabLabels = {
            { "favorites", "Favorited" },
            { "all", "All Products" },
            { "subscriptions", "Subscriptions" },
        }
        local tabWidth = math.max(6, math.floor((productWidth - 1) / 3))
        for index, entry in ipairs(tabLabels) do
            scene:button("tab:" .. entry[1],
                productX + (index - 1) * tabWidth, 3,
                index == 3 and (width - productX
                    - (index - 1) * tabWidth + 1) or tabWidth,
                2, entry[2], {
                    background = tab == entry[1]
                        and colors.black or colors.lightGray,
                    foreground = tab == entry[1]
                        and colors.white or colors.black,
                })
        end

        local navigationWidth = 3
        local cardAreaWidth = math.max(12, productWidth - navigationWidth - 1)
        local cardWidth = math.max(7, math.floor((cardAreaWidth - 1) / 2))
        for index, product in ipairs(visible) do
            local column = (index - 1) % 2
            local row = math.floor((index - 1) / 2)
            local x = productX + column * (cardWidth + 1)
            local y = 6 + row * 4
            local favoriteWidth = math.min(3, math.max(2, cardWidth - 5))
            local mainWidth = math.max(4, cardWidth - favoriteWidth)
            local quantity = cart[product.item_id]
                and cart[product.item_id].quantity or 0
            scene:button("product:" .. product.item_id,
                x, y, mainWidth, 3,
                ui.truncate(product.name, math.max(1, mainWidth - 2))
                    .. "\n" .. money(product.price)
                    .. (product.kind == "subscription" and "/d" or "")
                    .. (quantity > 0 and ("\nx" .. quantity) or ""), {
                    background = quantity > 0
                        and ui.theme.accentDark
                        or product.kind == "subscription"
                            and colors.purple or colors.gray,
                    shadow = true,
                })
            scene:button("favorite:" .. product.item_id,
                x + mainWidth, y, favoriteWidth, 3,
                product.favorite and "F*" or "F", {
                    background = product.favorite
                        and colors.orange or colors.lightGray,
                    foreground = colors.black,
                })
        end
        if #visible == 0 then
            local emptyLabel = tab == "favorites"
                and "Tap F beside a product"
                or tab == "subscriptions"
                    and "Add a subscription with +"
                    or "Add a product with +"
            emptyLabel = ui.truncate(emptyLabel, math.max(1, productWidth - 4))
            ui.text(target, productX + math.max(0,
                math.floor((productWidth - #emptyLabel) / 2)),
                9, emptyLabel, colors.gray, colors.white)
        end
        local navX = width - 2
        scene:button("prev", navX, 7, 3, 3, "^", {
            background = colors.lightGray,
            foreground = colors.black,
            disabled = page <= 1,
        })
        scene:button("next", navX, 12, 3, 3, "v", {
            background = colors.lightGray,
            foreground = colors.black,
            disabled = page >= pages,
        })
        ui.text(target, navX, 16, page .. "/" .. pages, colors.gray, colors.white)

        local action = scene:wait({ tickRate = 0.5, flash = false })
        frame = frame + 1
        if action == "__tick" or action == "__idle" then
            customerView.frame = frame
            renderCustomerMonitor()
            net.autoUpdate(config, "service", ROOT, client)
            if frame % 10 == 0 then refreshState(true) end
        elseif action == "add" then
            addProduct()
            page = 1
        elseif action == "settings" or action == "__terminate" then
            if settingsScreen() then running = false end
        elseif action == "clear" then
            cart = {}
        elseif action == "pay" then
            if checkout(cart) then cart = {} end
        elseif action == "prev" then
            page = math.max(1, page - 1)
        elseif action == "next" then
            page = math.min(pages, page + 1)
        else
            local newTab = action and action:match("^tab:(.+)$")
            local productId = action and action:match("^product:(.+)$")
            local favoriteId = action and action:match("^favorite:(.+)$")
            local removeId = action and action:match("^remove:(.+)$")
            if newTab then
                tab, page = newTab, 1
            elseif removeId and cart[removeId] then
                cart[removeId].quantity = cart[removeId].quantity - 1
                if cart[removeId].quantity <= 0 then cart[removeId] = nil end
            elseif favoriteId then
                for _, product in ipairs(kioskState.products) do
                    if product.item_id == favoriteId then
                        local result, err = request("SET_PRODUCT_FAVORITE", {
                            item_id = favoriteId,
                            favorite = not product.favorite,
                        }, true)
                        if result then kioskState.products = result.products
                        else
                            ui.message(target, "error",
                                "FAVORITE FAILED", err, 0.9)
                        end
                        break
                    end
                end
            elseif productId then
                for _, product in ipairs(kioskState.products) do
                    if product.item_id == productId then
                        local _, _, existingKind = cartSummary(cart)
                        local productKind = product.kind == "subscription"
                            and "subscription" or "one_time"
                        if existingKind and existingKind ~= productKind then
                            if ui.confirm(target, "NEW CART TYPE",
                                "Clear the current cart and switch?",
                                "SWITCH", "KEEP") then
                                cart = {}
                            else
                                break
                            end
                        end
                        cart[productId] = cart[productId] or {
                            item_id = product.item_id,
                            name = product.name,
                            price = product.price,
                            kind = productKind,
                            quantity = 0,
                        }
                        cart[productId].quantity =
                            cart[productId].quantity + 1
                        break
                    end
                end
            end
        end
    end
end

if rawget(_G, "PUMPE_SERVICE_TEST_MODE") == true then
    return {
        cart_summary = cartSummary,
        filtered_products = filteredProducts,
        render_customer_monitor = renderCustomerMonitor,
    }
end

ui.boot(target, "SERVICE KIOSK", "SQUARE-STYLE POS v" .. config.version)
findCustomerMonitor()
if not client:discover() then
    ui.message(target, "error", "BANK OFFLINE", "Check the modem", 1.4)
end

if registerKiosk() then
    companyOnboarding(false)
    if refreshState() then posLoop() end
end

setCustomerView("cancelled", {})
ui.clear(target)
print("Service Kiosk closed safely.")
