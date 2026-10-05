local ROOT = fs.getDir(shell.getRunningProgram())
if ROOT == "" then ROOT = "." end
package.path = package.path .. ";" .. fs.combine(ROOT, "?.lua")
    .. ";" .. fs.combine(ROOT, "?/init.lua")

-- Stamped by tools/build_release_manifest.js. A program running beside a
-- config.lua from a different release means a partial install.
local PROGRAM_VERSION = "15.1.0"
local config = require("config")
local util = require("lib.util")
local net = require("lib.net")
local ui = require("lib.ui")

local target = term.current()
local client = net.client(config)
local sessionToken
local organizer
local running = true
local deviceFile = fs.combine(ROOT, "event_kiosk_device.dat")
local device = util.loadTable(deviceFile, { last_name = "" })
-- 12.0: this kiosk's main colour, orange unless its organizer chose one.
if type(ui.useMainColor) == "function" then ui.useMainColor(ROOT) end

-- 12.0: the bar every page ends with. A kiosk has no home screen to go
-- back to, so it is only its three tabs.
local function tabBar(scene, spec)
    ui.tabBar(scene, target, spec.list, spec.active, nil, { home = false })
end

local function money(value)
    return util.money(value, config.currency)
end

local function request(action, payload, silent)
    payload = payload or {}
    if sessionToken and not payload.session_token then
        payload.session_token = sessionToken
    end
    local result, err, code = client:request(action, payload)
    if not result and not silent then ui.networkError(target, err) end
    if code == "SESSION_EXPIRED" then sessionToken, organizer = nil, nil end
    return result, err, code
end

local function login()
    local name = ui.input(target, "ORGANIZER LOGIN", {
        hint = "Your Foxy Account name",
        initial = device.last_name,
        maxLength = 20,
        allowSpace = true,
    })
    if not name then return false end
    local pin = ui.pin(target, "ACCOUNT PIN", true)
    if not pin then return false end
    local result, err = client:request("LOGIN", { name = name, pin = pin })
    if not result then
        ui.message(target, "error", "LOGIN FAILED", err, 1.1)
        return false
    end
    sessionToken = result.session_token
    organizer = result.account
    device.last_name = organizer.name
    util.saveTable(deviceFile, device)
    ui.message(target, "success", "WELCOME", organizer.name, 0.8)
    -- Setting up a new kiosk: its colour, once.
    if type(ui.hasMainColor) == "function" and not ui.hasMainColor(ROOT) then
        ui.pickMainColor(target, ROOT, "Kiosk colour")
    end
    return true
end

local function loginScreen()
    local width, height = target.getSize()
    while running and not sessionToken do
        ui.clear(target)
        ui.header(target, "EVENT KIOSK", "Organizer terminal", util.formatClock())
        ui.center(target, 6, "CREATE. SELL. ADMIT.", ui.theme.accent)
        ui.center(target, 8, "One terminal for the whole venue", ui.theme.muted)
        local scene = ui.scene(target)
        scene:button("login", 4, 11, width - 7, 3, "ORGANIZER SIGN IN",
            { background = ui.theme.accentDark, shadow = true })
        scene:button("exit", 1, height, 6, 1, "EXIT",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 0.5 })
        if action == "login" then login()
        elseif action == "exit" or action == "__terminate" then running = false end
    end
end

local function addTicketType(event)
    local name = ui.input(target, "TICKET TYPE", {
        hint = "Example: VIP Backstage",
        maxLength = 28,
        allowSpace = true,
    })
    if not name then return false end
    local description = ui.input(target, "TICKET DESCRIPTION", {
        hint = "Perks or access included",
        maxLength = 60,
        allowSpace = true,
    })
    if not description then return false end
    local price = ui.input(target, "TICKET PRICE", {
        hint = name,
        mode = "number", maxLength = 12,
    })
    if not price then return false end
    local quantity = ui.input(target, "TICKET QUANTITY", {
        hint = "Maximum inventory",
        mode = "number", maxLength = 8,
    })
    if not quantity then return false end
    local result, err = request("ADD_TICKET_TYPE", {
        event_id = event.event_id,
        name = name,
        description = description,
        price = tonumber(price),
        quantity = tonumber(quantity),
    }, true)
    if result then
        ui.message(target, "success", "TICKET TYPE ADDED",
            name .. "  " .. money(price), 0.9)
        return true
    end
    ui.message(target, "error", "COULD NOT ADD", err, 1.1)
    return false
end

-- A day and a time, typed as two boxes. Comes back as the day and "HH:MM",
-- or nil if either was cancelled.
local function askMoment(title, what)
    local dayText = ui.input(target, title .. " DAY", {
        hint = what .. " - today is day " .. util.ingameDay(),
        mode = "number", maxLength = 8,
    })
    if not dayText then return nil end
    local timeText = ui.input(target, title .. " TIME", {
        hint = "Four digits, example 1830",
        mode = "number", maxLength = 5,
    })
    if not timeText then return nil end
    if not timeText:match("^%d%d?:%d%d$") then
        local raw = timeText:gsub("[^%d]", "")
        if #raw == 4 then timeText = raw:sub(1, 2) .. ":" .. raw:sub(3, 4) end
    end
    return tonumber(dayText), timeText
end

-- FoxyOS 13: how many tickets one person may buy, 1 to 10.
local function askLimit(current)
    local text = ui.input(target, "PER PERSON", {
        hint = "Most tickets one person may buy, 1-10",
        mode = "number", maxLength = 2, initial = tostring(current or 5),
    })
    return text and tonumber(text) or nil
end

local function createEvent()
    local title = ui.input(target, "CREATE EVENT", {
        hint = "Public event title",
        maxLength = 40,
        allowSpace = true,
    })
    if not title then return end
    local description = ui.input(target, "DESCRIPTION", {
        hint = "What should guests know?",
        maxLength = 100,
        allowSpace = true,
    })
    if not description then return end
    local location = ui.input(target, "LOCATION", {
        hint = "Venue or coordinates",
        maxLength = 50,
        allowSpace = true,
    })
    if not location then return end
    local dayText = ui.input(target, "EVENT DAY", {
        hint = "Today is in-game day " .. util.ingameDay(),
        mode = "number", maxLength = 8,
    })
    if not dayText then return end
    local timeText = ui.input(target, "EVENT TIME", {
        hint = "Four digits, example 1830",
        mode = "number", maxLength = 5,
    })
    if not timeText then return end
    if not timeText:match("^%d%d?:%d%d$") then
        local raw = timeText:gsub("[^%d]", "")
        if #raw == 4 then timeText = raw:sub(1, 2) .. ":" .. raw:sub(3, 4) end
    end

    -- FoxyOS 13: when the tickets go on sale, and how many each.
    local releaseDay, releaseTime
    if not ui.confirm(target, "TICKETS ON SALE", "Straight away, or at a set"
        .. " time with a queue and a waiting room?", "NOW", "LATER") then
        releaseDay, releaseTime = askMoment("ON SALE", "When the sale opens")
        if not releaseDay then return end
    end
    local limit = askLimit(config.max_ticket_quantity)
    if not limit then return end

    local countdown = util.eventCountdown(tonumber(dayText), timeText)
    if not ui.confirm(target, "CREATE EVENT",
        title .. " - in " .. countdown, "CREATE", "BACK") then return end
    local result, err = request("CREATE_EVENT", {
        title = title,
        description = description,
        location = location,
        event_day = tonumber(dayText),
        event_time = timeText,
        release_day = releaseDay,
        release_time = releaseTime,
        limit = limit,
    }, true)
    if not result then
        ui.message(target, "error", "CREATE FAILED", err, 1.2)
        return
    end
    ui.message(target, "success", "EVENT CREATED", result.event.title, 0.9)
    while ui.confirm(target, "ADD TICKET TYPE",
        "Set up another ticket category?", "ADD", "DONE") do
        addTicketType(result.event)
    end
end

-- FoxyOS 13: changing when tickets go on sale, and how many each.
local function saleScreen(event)
    local changes = {}
    if ui.confirm(target, "SALE OPENS", event.release_day
        and ("Day " .. event.release_day .. " " .. event.release_time
            .. ". Change it?") or "On sale now. Set a time?", "CHANGE", "KEEP") then
        changes.release_day, changes.release_time = askMoment("ON SALE",
            "When the sale opens")
        if not changes.release_day then return event end
    end
    changes.limit = askLimit(event.limit)
    if not changes.limit then return event end
    changes.event_id = event.event_id
    local result, err = request("EVENT_SALE", changes, true)
    if not result then
        ui.message(target, "error", "NOT CHANGED", err, 1.6)
        return event
    end
    ui.message(target, "success", "SALE UPDATED", event.title, 0.9)
    for key, value in pairs(result.event) do event[key] = value end
    return event
end

-- The presale and who is invited. Invites go out as FoxMail from the
-- organizer's own address; a tap on a name takes the invite back.
local function presaleScreen(event)
    if not event.presale_day then
        if not event.release_day then
            ui.message(target, "warning", "SET THE SALE FIRST",
                "A presale opens before the general sale", 1.8)
            return event
        end
        local day, time = askMoment("PRESALE", "When the presale opens")
        if not day then return event end
        local result, err = request("EVENT_SALE", { event_id = event.event_id,
            presale_day = day, presale_time = time }, true)
        if not result then
            ui.message(target, "error", "NO PRESALE", err, 1.8)
            return event
        end
        for key, value in pairs(result.event) do event[key] = value end
    end
    local listed = request("EVENT_INVITES", { event_id = event.event_id }, true)
    local invites, page = listed and listed.invites or {}, 1
    while running and sessionToken do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "PRESALE", "Day " .. event.presale_day .. " "
            .. event.presale_time .. "  -  " .. #invites .. " invited",
            util.formatClock())
        local scene = ui.scene(target)
        local per = math.max(1, height - 8)
        local pageItems, actualPage, pages = util.page(invites, page, per)
        page = actualPage
        if #invites == 0 then
            ui.center(target, 7, "Nobody invited yet", ui.theme.muted)
            ui.center(target, 9, "Invite people by FoxMail address or name",
                ui.theme.muted, nil, width - 2)
        end
        for index, invite in ipairs(pageItems) do
            local slot = (page - 1) * per + index
            scene:button("invite:" .. slot, 2, 3 + index, width - 2, 1,
                ui.truncate(invite.name .. "  " .. (invite.address
                    or "no FoxMail, told on their Pocket"), width - 4),
                { background = ui.theme.panel })
        end
        if pages > 1 then
            scene:button("prev", width - 12, height - 2, 4, 1, "<",
                { background = ui.theme.panel, disabled = page <= 1 })
            scene:button("next", width - 4, height - 2, 4, 1, ">",
                { background = ui.theme.panel, disabled = page >= pages })
        end
        scene:button("add", 10, height, 10, 1, "+ INVITE",
            { background = ui.theme.accentDark })
        scene:button("remove", 21, height, 16, 1, "REMOVE PRESALE",
            { background = ui.theme.danger })
        scene:button("back", 1, height, 8, 1, "< BACK",
            { background = ui.theme.panel })
        local action = scene:wait()
        if action == "back" or action == "__terminate" then return event end
        if action == "prev" then page = page - 1
        elseif action == "next" then page = page + 1
        elseif action == "add" then
            local who = ui.input(target, "INVITE", {
                hint = "FoxMail address, or their name",
                maxLength = 32, allowSpace = true, minLength = 2,
            })
            if who then
                local sent, err = request("EVENT_INVITE", { event_id = event.event_id,
                    who = who }, true)
                if sent then
                    invites = sent.invites
                    ui.message(target, "success", sent.invite.mailed
                        and "INVITE MAILED" or "INVITED", sent.invite.name, 1)
                else
                    ui.message(target, "error", "NOT INVITED", err, 1.8)
                end
            end
        elseif action == "remove" then
            if ui.confirm(target, "REMOVE PRESALE", "Everybody buys at the"
                .. " general sale then", "REMOVE", "KEEP") then
                local result, err = request("EVENT_SALE", { event_id = event.event_id,
                    presale = false }, true)
                if result then
                    for key in pairs(event) do
                        if key:match("^presale") then event[key] = nil end
                    end
                    return event
                end
                ui.message(target, "error", "NOT REMOVED", err, 1.6)
            end
        else
            local slot = tonumber(action and action:match("^invite:(%d+)$"))
            local invite = slot and invites[slot]
            if invite and ui.confirm(target, "TAKE BACK INVITE",
                invite.name .. " loses their presale place", "TAKE BACK", "KEEP") then
                local result, err = request("EVENT_UNINVITE", { event_id = event.event_id,
                    account_id = invite.account_id }, true)
                if result then invites = result.invites
                else ui.message(target, "error", "NOT CHANGED", err, 1.4) end
            end
        end
    end
    return event
end

local function analyticsScreen(event)
    local blink, ticks = true, 0
    while true do
        local width, height = target.getSize()
        ui.clear(target)
        local countdown = util.eventCountdown(event.event_day, event.event_time)
        ui.header(target, ui.truncate(event.title, width - 9),
            "Starts in " .. countdown, util.formatClock(blink))
        local sold, capacity, revenue = 0, 0, 0
        for _, ticketType in ipairs(event.ticket_types or {}) do
            sold = sold + ticketType.sold_quantity
            capacity = capacity + ticketType.total_quantity
            revenue = revenue + ticketType.sold_quantity * ticketType.price
        end
        ui.card(target, 2, 5, width - 2, 3, ui.theme.success)
        ui.text(target, 4, 5, sold .. "/" .. capacity .. " SOLD",
            ui.theme.ink, ui.theme.panel)
        ui.text(target, width - #money(revenue), 5, money(revenue),
            ui.theme.success, ui.theme.panel)
        ui.progress(target, 4, 7, width - 6, sold, math.max(1, capacity),
            ui.theme.success, colors.gray)
        -- FoxyOS 13: where the sale stands, and the queue.
        local phase = event.phase or "general"
        local saleLine = phase == "general" and "ON SALE"
            or phase == "presale" and "PRESALE OPEN"
            or ("ON SALE DAY " .. tostring(event.release_day) .. " "
                .. tostring(event.release_time))
        if event.presale_day and phase == "soon" then
            saleLine = saleLine .. "  PRESALE DAY " .. event.presale_day
                .. " " .. event.presale_time
        end
        ui.text(target, 2, 9, ui.truncate(saleLine, width - 2),
            phase == "soon" and colors.yellow or ui.theme.success)
        ui.text(target, 2, 10, ui.truncate((event.waiting or 0) .. " in line  "
            .. (event.shopping or 0) .. " choosing  " .. (event.limit or "?")
            .. " per person  " .. (event.invited_count or 0) .. " invited",
            width - 2), ui.theme.muted)

        local scene = ui.scene(target)
        local visible = math.max(1, height - 14)
        for index = 1, math.min(#(event.ticket_types or {}), visible) do
            local ticketType = event.ticket_types[index]
            local y = 12 + index - 1
            local percentage = ticketType.total_quantity > 0
                and math.floor(ticketType.sold_quantity / ticketType.total_quantity * 100)
                or 0
            local soldOut = ticketType.sold_quantity >= ticketType.total_quantity
            ui.text(target, 2, y, ui.truncate(ticketType.name, width - 22),
                soldOut and ui.theme.danger or ui.theme.ink)
            local detail = string.format("%d/%d  %d%%",
                ticketType.sold_quantity, ticketType.total_quantity, percentage)
            ui.text(target, width - #detail, y, detail,
                soldOut and ui.theme.danger or ui.theme.muted)
        end
        local addWidth = width >= 45 and 15 or 8
        scene:button("add", 10, height, addWidth, 1,
            width >= 45 and "+ TICKET TYPE" or "+ TYPE",
            { background = ui.theme.accentDark })
        scene:button("sale", 11 + addWidth, height, 6, 1, "SALE",
            { background = ui.theme.panel })
        scene:button("presale", 18 + addWidth, height, 9, 1, "PRESALE",
            { background = colors.magenta })
        scene:button("back", 1, height, 8, 1, "< BACK",
            { background = ui.theme.panel })
        local action = scene:wait({ tickRate = 0.5 })
        blink = not blink
        if action == "back" or action == "__terminate" then return end
        local changed = false
        if action == "add" then
            changed = addTicketType(event)
        elseif action == "sale" then
            saleScreen(event)
            changed = true
        elseif action == "presale" then
            presaleScreen(event)
            changed = true
        elseif action == "__tick" then
            -- The queue moves on its own; a look every few seconds.
            ticks = ticks + 1
            changed = ticks % 10 == 0
        end
        if changed then
            local refreshed = request("MY_EVENTS", {}, true)
            if refreshed then
                for _, candidate in ipairs(refreshed.events) do
                    if candidate.event_id == event.event_id then
                        event = candidate
                        break
                    end
                end
            end
        end
    end
end

-- 12.0: the Events tab. What it lists is paged above the tab bar.
local function myEvents(spec)
    local result = request("MY_EVENTS")
    if not result then return "tab:home" end
    local events, page, blink = result.events, 1, true
    while running and sessionToken do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "MY EVENTS", #events .. " total", util.formatClock(blink))
        local per = math.max(1, math.floor((ui.contentBottom(target) - 4) / 3))
        local pageItems, actualPage, pages = util.page(events, page, per)
        page = actualPage
        local scene = ui.scene(target)
        if #events == 0 then ui.center(target, 9, "No events yet", ui.theme.muted) end
        for index, event in ipairs(pageItems) do
            local y = 4 + (index - 1) * 3
            local countdown = util.eventCountdown(event.event_day, event.event_time)
            scene:button("event:" .. event.event_id, 2, y, width - 2, 2,
                ui.truncate(event.title, width - 8) .. "\nIN "
                    .. string.upper(countdown), {
                    background = event.status == "active" and ui.theme.panel or colors.gray,
                })
        end
        if pages > 1 then
            scene:button("prev", width - 12, 2, 4, 1, "<",
                { background = ui.theme.panel, disabled = page <= 1 })
            ui.text(target, width - 7, 2, page .. "/" .. pages, ui.theme.muted)
            scene:button("next", width - 3, 2, 3, 1, ">",
                { background = ui.theme.panel, disabled = page >= pages })
        end
        tabBar(scene, spec)
        local action = scene:wait({ tickRate = 0.5 })
        blink = not blink
        if action == "__terminate" then running = false return nil end
        if action and action:match("^tab:") then return action end
        if action == "__tick" then
            net.autoUpdate(config, "event", ROOT, client)
        elseif action == "prev" then page = page - 1
        elseif action == "next" then page = page + 1
        else
            local id = action and action:match("^event:(.+)$")
            if id then
                for _, event in ipairs(events) do
                    if event.event_id == id then
                        ui.wipe(target, "SALES ANALYTICS")
                        analyticsScreen(event)
                        result = request("MY_EVENTS", {}, true) or result
                        events = result.events
                        break
                    end
                end
            end
        end
    end
    return nil
end

local function ticketResultScreen(result)
    local width, height = target.getSize()
    local ticket, event, ticketType = result.ticket, result.event, result.ticket_type
    ui.clear(target)
    ui.header(target, result.valid and "VALID TICKET" or "TICKET BLOCKED",
        ticket.qr_code, util.formatClock())
    local accent = result.valid and ui.theme.success or ui.theme.danger
    ui.card(target, 3, 5, width - 5, 9, accent)
    ui.text(target, 5, 6, ui.truncate(event.title, width - 10),
        ui.theme.ink, ui.theme.panel)
    ui.text(target, 5, 8, ticketType.name, accent, ui.theme.panel)
    ui.text(target, 5, 10, "Holder: " .. result.holder,
        ui.theme.ink, ui.theme.panel)
    ui.text(target, 5, 12, ticket.used
        and ("USED Day " .. tostring(ticket.used_day) .. " " .. tostring(ticket.used_time))
        or "READY TO ADMIT", accent, ui.theme.panel)
    local scene = ui.scene(target)
    if result.valid then
        scene:button("admit", 3, 16, width - 5, 2, "MARK USED + ADMIT",
            { background = ui.theme.success, foreground = colors.black })
    else
        scene:button("back", 3, 16, width - 5, 2,
            ticket.used and "ALREADY USED - BACK" or "INVALID - BACK",
            { background = ui.theme.danger })
    end
    scene:button("cancel", 1, height, 8, 1, "< BACK",
        { background = ui.theme.panel })
    local action = scene:wait()
    if action == "admit" then
        local used, err = request("MARK_TICKET_USED", {
            ticket_id = ticket.ticket_id,
        }, true)
        if used then
            ui.message(target, "success", "GUEST ADMITTED",
                result.holder .. " - " .. ticketType.name, 1.2)
        else ui.message(target, "error", "COULD NOT ADMIT", err, 1.1) end
    end
end

local function verifyTicket()
    local code = ui.input(target, "VERIFY TICKET", {
        hint = "Eight-character entry code",
        mode = "code", maxLength = 8, minLength = 8,
    })
    if not code then return end
    local result, err = request("VERIFY_TICKET", { code = code }, true)
    if result then ticketResultScreen(result)
    else ui.message(target, "error", "TICKET REJECTED", err, 1.2) end
end

-- Proximity ticket scanning. Turn it on at the door and the Bank asks
-- whoever is nearest with a ticket for this event on their screen. Nobody
-- reads out an eight character code.
local function pickScanEvent()
    local result = request("MY_EVENTS")
    if not result then return nil end
    local open = {}
    for _, event in ipairs(result.events) do
        if event.status == "active" then open[#open + 1] = event end
    end
    if #open == 0 then
        ui.message(target, "info", "NO OPEN EVENTS",
            "Create an event first", 1.4)
        return nil
    end
    if #open == 1 then return open[1] end
    local page = 1
    while running do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "SCAN WHICH EVENT", #open .. " open",
            util.formatClock())
        local pageItems, actualPage, pages = util.page(open, page, 4)
        page = actualPage
        local scene = ui.scene(target)
        for index, event in ipairs(pageItems) do
            scene:button("event:" .. event.event_id, 2, 4 + (index - 1) * 3,
                width - 2, 2, ui.truncate(event.title, width - 6),
                { background = ui.theme.panel })
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
        local action = scene:wait({ tickRate = 1 })
        if action == "back" or action == "__terminate" then return nil
        elseif action == "prev" then page = page - 1
        elseif action == "next" then page = page + 1
        else
            local id = action and action:match("^event:(.+)$")
            for _, event in ipairs(open) do
                if event.event_id == id then return event end
            end
        end
    end
end

local function proximityScan()
    local event = pickScanEvent()
    if not event then return end
    local requestId, status, detail, blink = nil, "STARTING", "", true
    local admitted = {}

    local function stop()
        if requestId then
            request("TICKET_SCAN_CANCEL", { request_id = requestId }, true)
            requestId = nil
        end
    end

    local function beginScan()
        local started, err = request("TICKET_SCAN", {
            event_id = event.event_id,
            position = net.locate(1),
        }, true)
        if not started then
            requestId, status, detail = nil, "NOT SCANNING", err or "Try again"
            return
        end
        requestId = started.scan.request_id
        status = started.scan.status == "offered" and "ASKING" or "SEARCHING"
        detail = started.scan.target_name or "Nobody nearby yet"
    end

    beginScan()
    while running and sessionToken do
        local width, height = target.getSize()
        ui.clear(target)
        ui.header(target, "PROXIMITY SCAN",
            ui.truncate(event.title, width - 4), util.formatClock(blink))
        local accent = status == "ADMITTED" and ui.theme.success
            or status == "REFUSED" and ui.theme.danger
            or status == "ASKING" and ui.theme.accent
            or ui.theme.panel
        ui.card(target, 2, 5, width - 2, 5, accent)
        ui.text(target, 4, 6, status, accent, ui.theme.panel, width - 6)
        ui.wrappedText(target, 4, 7, detail, width - 6, 2,
            ui.theme.ink, ui.theme.panel)
        ui.text(target, 2, 11, "ADMITTED  " .. #admitted, ui.theme.muted)
        for index = 1, math.min(#admitted, height - 15) do
            ui.text(target, 2, 11 + index,
                ui.truncate(admitted[index], width - 3), ui.theme.ink)
        end
        local scene = ui.scene(target)
        scene:button("stop", 2, height - 2, width - 2, 2, "STOP SCANNING",
            { background = ui.theme.danger })
        local action = scene:wait({ tickRate = 1 })
        blink = not blink
        if action == "stop" or action == "__terminate" then
            stop()
            return
        end
        if action == "__tick" then
            if not requestId then
                beginScan()
            else
                local polled = request("TICKET_SCAN_STATUS",
                    { request_id = requestId }, true)
                local scan = polled and polled.scan
                if not scan then
                    requestId = nil
                elseif scan.status == "accepted" then
                    status, detail = "ADMITTED", scan.result or "Guest admitted"
                    table.insert(admitted, 1, scan.result or "Guest")
                    while #admitted > 6 do table.remove(admitted) end
                    requestId = nil
                elseif scan.status == "rejected" then
                    status, detail = "REFUSED", scan.result or "Ticket refused"
                    requestId = nil
                elseif scan.status == "nobody_nearby" then
                    status, detail = "SEARCHING",
                        "Nobody nearby has a ticket up"
                    requestId = nil
                else
                    status = "ASKING"
                    detail = (scan.target_name or "Someone")
                        .. (scan.distance and ("  " .. scan.distance
                            .. " blocks") or "")
                end
            end
        end
    end
    stop()
end

-- 12.0: three tabs -- Home, Events, Door -- with everything on one of them.
local function dashboard()
    local stats = request("EVENT_DASHBOARD")
    if not stats then return end
    local function homePage(spec)
        local blink, tick = true, 0
        while running and sessionToken do
            local width, height = target.getSize()
            ui.clear(target)
            ui.header(target, "EVENT DASHBOARD", organizer.name, util.formatClock(blink))
            local cardWidth = math.floor((width - 5) / 3)
            local cards = {
                { "ACTIVE", stats.active_events, ui.theme.accent },
                { "SOLD", stats.tickets_sold, colors.magenta },
                { "REVENUE", money(stats.revenue), ui.theme.success },
            }
            for index, card in ipairs(cards) do
                local x = 2 + (index - 1) * (cardWidth + 1)
                ui.card(target, x, 5, cardWidth, 4, card[3])
                ui.text(target, x + 2, 6, card[1], ui.theme.muted, ui.theme.panel)
                ui.text(target, x + 2, 7, tostring(card[2]), ui.theme.ink,
                    ui.theme.panel, cardWidth - 3)
            end
            local scene = ui.scene(target)
            -- 12.0 Final: the kiosk itself sits under Create, rather than
            -- behind More. A short screen gets one-row buttons.
            local bottom = ui.contentBottom(target)
            local roomy = bottom >= 16
            -- FoxyOS 15.1: Beta Updates, beside Create.
            local betaOn = util.betaJoined(ROOT)
            local createY, createH = roomy and 11 or bottom - 2, roomy and 3 or 1
            scene:button("create", 2, createY, width - 11, createH, "CREATE EVENT",
                { background = ui.theme.accent, foreground = ui.theme.accentInk,
                  shadow = roomy })
            scene:button("beta", width - 8, createY, 8, createH, "BETA",
                { background = betaOn and ui.theme.success or ui.theme.panel,
                  foreground = betaOn and colors.black or ui.theme.ink })
            local third = math.floor((width - 4) / 3)
            local rowY, rowH = roomy and bottom - 1 or bottom, roomy and 2 or 1
            scene:button("color", 2, rowY, third, rowH, "COLOUR",
                { background = ui.theme.panel })
            scene:button("logout", 3 + third, rowY, third, rowH, "LOG OUT",
                { background = ui.theme.panel })
            scene:button("exit", 4 + third * 2, rowY, width - 3 - third * 2, rowH, "CLOSE",
                { background = ui.theme.danger, foreground = ui.inkOn(ui.theme.danger) })
            tabBar(scene, spec)
            local action = scene:wait({ tickRate = 0.5 })
            tick = tick + 1
            blink = not blink
            -- The clock blinks twice a second; the Bank is asked for fresh
            -- numbers every five seconds, or right after they changed.
            local refresh = false
            if action == "__terminate" then running = false return nil end
            if action and action:match("^tab:") then return action end
            if action == "__tick" then
                net.autoUpdate(config, "event", ROOT, client)
                refresh = tick % 10 == 0
            elseif action == "create" then
                createEvent()
                refresh = true
            elseif action == "color" then
                ui.pickMainColor(target, ROOT, "Kiosk colour")
            elseif action == "beta" then
                ui.betaUpdates(target, ROOT, { kind = "kiosk", version = config.version })
            elseif action == "logout" then
                if ui.confirm(target, "LOG OUT", "End organizer session?", "LOG OUT",
                    "BACK") then
                    sessionToken, organizer = nil, nil
                    return nil
                end
            elseif action == "exit" then
                running = false
                return nil
            end
            if refresh and sessionToken then
                stats = request("EVENT_DASHBOARD", {}, true) or stats
            end
        end
    end
    local function doorPage(spec)
        while running and sessionToken do
            local width = target.getSize()
            ui.clear(target)
            ui.header(target, "AT THE DOOR", organizer.name, util.formatClock())
            local scene = ui.scene(target)
            -- Two big buttons, as tall as the screen allows.
            local tall = math.max(2, math.min(4,
                math.floor((ui.contentBottom(target) - 7) / 2)))
            scene:button("verify", 2, 5, width - 2, tall,
                "VERIFY TICKET\nType the guest's entry code",
                { background = ui.theme.success, foreground = colors.black,
                  shadow = true })
            scene:button("scan", 2, 6 + tall, width - 2, tall,
                "PROXIMITY SCAN\nAsk whoever walks up",
                { background = colors.purple, shadow = true })
            -- FoxyOS 12: somebody says their MyID Code at the door.
            if 7 + tall * 2 <= ui.contentBottom(target) then
                scene:button("myid", 2, 7 + tall * 2, width - 2, 1, "MYID VERIFIER",
                    { background = colors.lightBlue, foreground = colors.black })
            end
            tabBar(scene, spec)
            local action = scene:wait({ tickRate = 1 })
            if action == "__terminate" then running = false return nil end
            if action and action:match("^tab:") then return action end
            if action == "verify" then
                verifyTicket()
            elseif action == "scan" then
                ui.wipe(target)
                proximityScan()
            elseif action == "myid" then
                ui.myIdVerifier(target, function(code)
                    return request("MYID_VERIFY", { code = code }, true)
                end)
            elseif action == "__tick" then
                net.autoUpdate(config, "event", ROOT, client)
            end
        end
    end
    ui.runTabs({
        target = target, title = "Event Kiosk", subtitle = "Everything here",
        list = { { id = "home", label = "Home" }, { id = "events", label = "Events" },
            { id = "door", label = "Door" } },
        pages = { home = homePage, events = myEvents, door = doorPage },
        running = function() return running and sessionToken ~= nil end,
    })
end

ui.boot(target, "EVENT KIOSK", (ui.osLabel and ui.osLabel(config) or "FoxyOS"))
-- Check for a new release at every restart, straight from the public
-- manifest. The Bank Server no longer has to hold a copy for us.
net.autoUpdate(config, "event", ROOT, client,
    { force = true, programVersion = PROGRAM_VERSION })
if not client:discover() then
    ui.message(target, "error", "BANK OFFLINE", "Check the modem", 1.4)
end

while running do
    if not sessionToken then loginScreen() end
    if sessionToken then dashboard() end
end

ui.clear(target)
print("Event Kiosk closed.")
